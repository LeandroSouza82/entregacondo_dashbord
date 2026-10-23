-- Private FCM devices and transactional per-device notification outbox.
CREATE TABLE IF NOT EXISTS public.push_dispositivos (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 empresa_id uuid NOT NULL REFERENCES public.empresas(id), token text UNIQUE,
 plataforma text NOT NULL DEFAULT 'android' CHECK(plataforma='android'),
 ativo boolean NOT NULL DEFAULT true, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.push_envios (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 user_id uuid NOT NULL REFERENCES auth.users(id), dispositivo_id uuid NOT NULL REFERENCES public.push_dispositivos(id),
 rota_id uuid NOT NULL REFERENCES public.rotas_planejadas(id), evento text NOT NULL,
 tipo text NOT NULL CHECK(tipo IN ('nova_rota','nova_coleta')), quantidade int NOT NULL CHECK(quantidade>0),
 status text NOT NULL DEFAULT 'pendente' CHECK(status IN ('pendente','processando','aceito_fcm','cancelado','expirado','falhou')),
 tentativas int NOT NULL DEFAULT 0, proxima_tentativa timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '24 hours',
 claim_token uuid, lease_expires_at timestamptz, token_enviado text, ultimo_erro text,
 created_at timestamptz NOT NULL DEFAULT now(), enviado_em timestamptz,
 UNIQUE(evento,dispositivo_id)
);
ALTER TABLE public.push_dispositivos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_envios ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_dispositivos,public.push_envios FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.push_dispositivos,public.push_envios TO service_role;
CREATE INDEX IF NOT EXISTS idx_push_pendentes ON public.push_envios(proxima_tentativa) WHERE status IN ('pendente','processando');
CREATE OR REPLACE FUNCTION public.registrar_dispositivo_push(p_id uuid,p_empresa_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE owner_id uuid;
BEGIN
 IF auth.uid() IS NULL OR p_id IS NULL OR p_token IS NULL OR length(p_token) NOT BETWEEN 20 AND 4096
 OR NOT EXISTS(SELECT 1 FROM public.empresa_membros em JOIN public.empresas e ON e.id=em.empresa_id AND e.ativa
 JOIN public.motoristas m ON m.id=em.motorista_id AND m.user_id=em.user_id AND m.empresa_id=em.empresa_id AND m.ativo
 WHERE em.empresa_id=p_empresa_id AND em.user_id=auth.uid() AND em.status='aprovado' AND em.papel='motorista') THEN
  RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso de motorista aprovado necessário para ativar avisos.');
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('push-token:'||p_token,0));
 SELECT user_id INTO owner_id FROM public.push_dispositivos WHERE id=p_id FOR UPDATE;
 IF FOUND AND owner_id<>auth.uid() THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Dispositivo indisponível.'); END IF;
 -- Token possession transfers this installation to the currently authenticated account.
 UPDATE public.push_dispositivos SET token=NULL,ativo=false,updated_at=now() WHERE token=p_token AND id<>p_id;
 INSERT INTO public.push_dispositivos(id,user_id,empresa_id,token) VALUES(p_id,auth.uid(),p_empresa_id,p_token)
 ON CONFLICT(id) DO UPDATE SET empresa_id=excluded.empresa_id,token=excluded.token,ativo=true,updated_at=now();
 RETURN jsonb_build_object('sucesso',true);
END $$;
CREATE OR REPLACE FUNCTION public.desativar_dispositivo_push(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('sucesso',false); END IF;
 UPDATE public.push_dispositivos SET ativo=false,updated_at=now() WHERE id=p_id AND user_id=auth.uid();
 RETURN jsonb_build_object('sucesso',true);
END $$;
REVOKE ALL ON FUNCTION public.registrar_dispositivo_push(uuid,uuid,text),public.desativar_dispositivo_push(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_dispositivo_push(uuid,uuid,text),public.desativar_dispositivo_push(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_enfileirar_push_servicos()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE route_id uuid; kind text; amount int; target record;
BEGIN
 FOR target IN SELECT (NEW.resultado->>'rota_ativa_id')::uuid AS id,'nova_coleta'::text AS tipo,COALESCE((NEW.resultado->>'coletas_adicionadas')::int,0) AS qtd
 UNION ALL SELECT (NEW.resultado->>'nova_rota_id')::uuid,'nova_rota',0 LOOP
  route_id:=target.id;kind:=target.tipo;amount:=target.qtd;
  IF route_id IS NULL THEN CONTINUE; END IF;
  IF kind='nova_rota' THEN SELECT count(*) INTO amount FROM public.entregas WHERE rota_id=route_id AND empresa_id=NEW.empresa_id; END IF;
  IF amount<=0 THEN CONTINUE; END IF;
  INSERT INTO public.push_envios(empresa_id,user_id,dispositivo_id,rota_id,evento,tipo,quantidade)
  SELECT NEW.empresa_id,m.user_id,d.id,r.id,NEW.chave||':'||r.id::text,kind,amount
  FROM public.rotas_planejadas r JOIN public.motoristas m ON m.id=r.motorista_id AND m.empresa_id=r.empresa_id AND m.ativo
  JOIN public.push_dispositivos d ON d.user_id=m.user_id AND d.empresa_id=r.empresa_id AND d.ativo AND d.token IS NOT NULL
  JOIN public.empresa_membros em ON em.empresa_id=r.empresa_id AND em.user_id=m.user_id AND em.motorista_id=m.id AND em.papel='motorista' AND em.status='aprovado'
  WHERE r.id=route_id AND r.empresa_id=NEW.empresa_id AND r.status IN ('planejada','em_execucao')
  ON CONFLICT(evento,dispositivo_id) DO NOTHING;
 END LOOP;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.fn_enfileirar_push_servicos() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS push_servicos_confirmados ON public.operacoes_envio_motorista;
CREATE TRIGGER push_servicos_confirmados AFTER INSERT ON public.operacoes_envio_motorista FOR EACH ROW EXECUTE FUNCTION public.fn_enfileirar_push_servicos();
CREATE OR REPLACE FUNCTION public.reivindicar_push_envios(p_limite int DEFAULT 10)
RETURNS TABLE(id uuid,claim_token uuid,token text,rota_id uuid,tipo text,quantidade int,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 UPDATE public.push_envios j SET status=CASE WHEN j.expires_at<=now() THEN 'expirado' ELSE 'cancelado' END,claim_token=NULL,lease_expires_at=NULL
 WHERE j.status IN ('pendente','processando') AND (j.expires_at<=now() OR NOT EXISTS(
 SELECT 1 FROM public.push_dispositivos d JOIN public.rotas_planejadas r ON r.id=j.rota_id AND r.empresa_id=j.empresa_id
 JOIN public.motoristas m ON m.id=r.motorista_id AND m.empresa_id=r.empresa_id AND m.user_id=j.user_id AND m.ativo
 JOIN public.empresas e ON e.id=r.empresa_id AND e.ativa
 JOIN public.empresa_membros em ON em.empresa_id=r.empresa_id AND em.user_id=m.user_id AND em.motorista_id=m.id AND em.status='aprovado' AND em.papel='motorista'
 WHERE d.id=j.dispositivo_id AND d.user_id=j.user_id AND d.empresa_id=j.empresa_id AND d.ativo AND d.token IS NOT NULL AND r.status IN ('planejada','em_execucao')));
 RETURN QUERY WITH chosen AS (
 SELECT j.id FROM public.push_envios j WHERE (j.status='pendente' OR (j.status='processando' AND j.lease_expires_at<now())) AND j.proxima_tentativa<=now() AND j.tentativas<8
 ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT greatest(1,least(COALESCE(p_limite,10),25))
 ), claimed AS (
 UPDATE public.push_envios j SET status='processando',claim_token=gen_random_uuid(),lease_expires_at=now()+interval '2 minutes',tentativas=j.tentativas+1,
 token_enviado=d.token FROM chosen c,public.push_dispositivos d WHERE j.id=c.id AND d.id=j.dispositivo_id RETURNING j.*
 ) SELECT c.id,c.claim_token,c.token_enviado,c.rota_id,c.tipo,c.quantidade,c.expires_at FROM claimed c;
END $$;
CREATE OR REPLACE FUNCTION public.finalizar_push_envio(p_id uuid,p_claim uuid,p_resultado text,p_erro text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE job public.push_envios%ROWTYPE;
BEGIN
 SELECT * INTO job FROM public.push_envios WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR job.status<>'processando' OR job.claim_token IS DISTINCT FROM p_claim OR job.lease_expires_at<=now() THEN RETURN false; END IF;
 IF p_resultado NOT IN ('aceito','repetir','invalido','falhou') OR p_resultado IS NULL THEN RETURN false; END IF;
 IF p_resultado='invalido' THEN UPDATE public.push_dispositivos SET ativo=false WHERE id=job.dispositivo_id AND token=job.token_enviado; END IF;
 UPDATE public.push_envios SET status=CASE WHEN p_resultado='aceito' THEN 'aceito_fcm' WHEN p_resultado='repetir' AND tentativas<8 AND expires_at>now() THEN 'pendente' ELSE 'falhou' END,
 proxima_tentativa=now()+make_interval(secs=>least(3600,10*power(2,tentativas))::int),
 enviado_em=CASE WHEN p_resultado='aceito' THEN now() ELSE NULL END,ultimo_erro=left(p_erro,200),claim_token=NULL,lease_expires_at=NULL,token_enviado=NULL WHERE public.push_envios.id=job.id;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.reivindicar_push_envios(int),public.finalizar_push_envio(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reivindicar_push_envios(int),public.finalizar_push_envio(uuid,uuid,text,text) TO service_role;

-- Waking is best effort; the private outbox survives a network/configuration failure.
CREATE OR REPLACE FUNCTION public.fn_acordar_push_worker()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE secret text;
BEGIN
 IF to_regclass('vault.decrypted_secrets') IS NULL OR to_regnamespace('net') IS NULL THEN RETURN; END IF;
 EXECUTE 'SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name=$1 LIMIT 1' INTO secret USING 'entregacondo_push_worker';
 IF secret IS NULL OR length(secret)<32 THEN RETURN; END IF;
 EXECUTE 'SELECT net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 5000)'
 USING 'https://vblwuvhdqgzdjnoscyqo.supabase.co/functions/v1/push-servicos',jsonb_build_object('Content-Type','application/json','x-push-worker-secret',secret),'{}'::jsonb;
EXCEPTION WHEN OTHERS THEN
 RAISE WARNING 'O envio push aguardará a próxima tentativa agendada.';
END $$;
CREATE OR REPLACE FUNCTION public.fn_acordar_push_apos_fila()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN PERFORM public.fn_acordar_push_worker(); RETURN NULL; END $$;
REVOKE ALL ON FUNCTION public.fn_acordar_push_worker(),public.fn_acordar_push_apos_fila() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_acordar_push_worker() TO service_role;
DROP TRIGGER IF EXISTS acordar_push_fila ON public.push_envios;
CREATE TRIGGER acordar_push_fila AFTER INSERT ON public.push_envios FOR EACH STATEMENT EXECUTE FUNCTION public.fn_acordar_push_apos_fila();
