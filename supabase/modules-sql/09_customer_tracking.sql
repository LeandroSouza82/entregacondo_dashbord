-- Customer arrival tracking. Tokens are bearer secrets; only their SHA-256 is stored.
-- No direct access to the private table, including authenticated dashboard users.
ALTER TABLE public.clientes_enderecos ADD COLUMN IF NOT EXISTS whatsapp_cliente varchar(30);
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS ec_private.customer_tracking (
 entrega_id uuid PRIMARY KEY REFERENCES public.entregas(id) ON DELETE CASCADE,
 rota_id uuid NOT NULL, motorista_id uuid NOT NULL, token_hash bytea NOT NULL UNIQUE,
 cliente_endereco_id uuid NOT NULL, recipient_phone text NOT NULL,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '8 hours',
 latitude double precision, longitude double precision, observed_at timestamptz,
 eta_at timestamptz, eta_observed_at timestamptz
);
ALTER TABLE ec_private.customer_tracking ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.customer_tracking FROM PUBLIC, anon, authenticated;

-- Also rechecked on EVERY public read: terminal status, reassignment, departure to
-- another stop, membership suspension or route closure immediately hide all GPS.
CREATE OR REPLACE FUNCTION ec_private.tracking_active(p_entrega uuid,p_rota uuid,p_motorista uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT EXISTS(
  SELECT 1 FROM public.entregas e
  JOIN public.rotas_planejadas r ON r.id=e.rota_id AND r.empresa_id=e.empresa_id AND r.motorista_id=e.motorista_id
  JOIN public.motoristas m ON m.id=e.motorista_id AND m.empresa_id=e.empresa_id AND m.ativo
  JOIN public.empresas c ON c.id=e.empresa_id AND c.ativa
  JOIN public.empresa_membros em ON em.empresa_id=e.empresa_id AND em.user_id=m.user_id AND em.motorista_id=m.id AND em.status='aprovado' AND em.papel='motorista'
  WHERE e.id=p_entrega AND e.rota_id=p_rota AND e.motorista_id=p_motorista
   AND r.status='em_execucao' AND e.status NOT IN ('entregue','tentativa_falha','cancelada')
   AND (e.coleta_origem_id IS NULL OR EXISTS(SELECT 1 FROM public.entregas p WHERE p.id=e.coleta_origem_id AND p.empresa_id=e.empresa_id AND p.status='entregue'))
   AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=e.id AND f.etapa<>'liberado')
   AND e.id=(SELECT x.id FROM public.entregas x WHERE x.rota_id=r.id AND x.empresa_id=r.empresa_id
    AND x.status NOT IN ('entregue','tentativa_falha','cancelada')
    AND (x.coleta_origem_id IS NULL OR EXISTS(SELECT 1 FROM public.entregas p WHERE p.id=x.coleta_origem_id AND p.empresa_id=x.empresa_id AND p.status='entregue'))
    AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=x.id AND f.etapa<>'liberado')
    ORDER BY (x.chegada_em IS NOT NULL) DESC,x.ordem_na_rota NULLS LAST,x.id LIMIT 1)
 );
$$;
REVOKE ALL ON FUNCTION ec_private.tracking_active(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.configurar_nome_empresa(p_empresa_id uuid,p_nome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(p_empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório nesta empresa.' USING ERRCODE='42501'; END IF;
 IF p_nome IS NULL OR length(btrim(p_nome)) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'Informe um nome entre 2 e 120 caracteres.'; END IF;
 UPDATE public.empresas SET nome=btrim(p_nome) WHERE id=p_empresa_id;
 RETURN jsonb_build_object('sucesso',true);
END $$;

CREATE OR REPLACE FUNCTION public.preparar_aviso_cliente(p_entrega_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.entregas%ROWTYPE; h bytea; t ec_private.customer_tracking%ROWTYPE; result jsonb;
BEGIN
 SELECT * INTO e FROM public.entregas WHERE id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE
  OR NOT EXISTS(SELECT 1 FROM public.motoristas m WHERE m.id=e.motorista_id AND m.user_id=auth.uid())
  OR ec_private.tracking_active(e.id,e.rota_id,e.motorista_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Avise somente o próximo atendimento liberado da sua rota ativa.' USING ERRCODE='42501'; END IF;
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Token inválido.'; END IF;
 IF e.destinatario_telefone IS NULL OR e.destinatario_telefone !~ '^[1-9][0-9]{9,14}$' THEN RAISE EXCEPTION 'WhatsApp do cliente não cadastrado ou inválido.'; END IF;
 h:=sha256(convert_to(p_token,'UTF8'));
 SELECT * INTO t FROM ec_private.customer_tracking WHERE entrega_id=e.id;
 IF t.token_hash=h AND (t.expires_at<=now() OR t.cliente_endereco_id IS DISTINCT FROM e.cliente_endereco_id OR t.recipient_phone IS DISTINCT FROM e.destinatario_telefone) THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','EXPIRADO','mensagem','Gere um novo link.'); END IF;
 -- Repeated taps reuse the same valid link; a new device/token revokes the old one.
 INSERT INTO ec_private.customer_tracking(entrega_id,rota_id,motorista_id,token_hash,cliente_endereco_id,recipient_phone)
 VALUES(e.id,e.rota_id,e.motorista_id,h,e.cliente_endereco_id,e.destinatario_telefone)
 ON CONFLICT(entrega_id) DO UPDATE SET rota_id=EXCLUDED.rota_id,motorista_id=EXCLUDED.motorista_id,
 token_hash=EXCLUDED.token_hash,cliente_endereco_id=EXCLUDED.cliente_endereco_id,recipient_phone=EXCLUDED.recipient_phone,expires_at=now()+interval '8 hours',latitude=NULL,longitude=NULL,observed_at=NULL,eta_at=NULL,eta_observed_at=NULL
 WHERE customer_tracking.token_hash<>EXCLUDED.token_hash OR customer_tracking.rota_id<>EXCLUDED.rota_id OR customer_tracking.motorista_id<>EXCLUDED.motorista_id OR customer_tracking.cliente_endereco_id<>EXCLUDED.cliente_endereco_id OR customer_tracking.recipient_phone<>EXCLUDED.recipient_phone;
 SELECT jsonb_build_object('sucesso',true,'empresa_nome',c.nome,'motorista_nome',COALESCE(NULLIF(btrim(p.nome),''),m.nome),
  'telefone',e.destinatario_telefone,'tipo_tarefa',e.tipo_tarefa,'descricao_outro',e.descricao_outro)
 INTO result FROM public.empresas c JOIN public.motoristas m ON m.id=e.motorista_id LEFT JOIN public.perfis_usuarios p ON p.id=m.user_id WHERE c.id=e.empresa_id;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.obter_meu_acompanhamento(p_rota_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE((SELECT jsonb_build_object('sucesso',true,'entrega_id',t.entrega_id,'latitude',a.latitude,'longitude',a.longitude)
 FROM ec_private.customer_tracking t JOIN public.entregas e ON e.id=t.entrega_id
 JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id
 JOIN public.motoristas m ON m.id=t.motorista_id
 WHERE t.rota_id=p_rota_id AND m.user_id=auth.uid() AND t.expires_at>now()
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id)
 AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone
 AND ec_private.tracking_active(e.id,t.rota_id,t.motorista_id) LIMIT 1),'{"sucesso":false}'::jsonb);
$$;

CREATE OR REPLACE FUNCTION public.publicar_localizacao_acompanhamento(p_entrega_id uuid,p_latitude double precision,p_longitude double precision,p_observada_em timestamptz,p_previsao_chegada_em timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR p_latitude IS NULL OR p_longitude IS NULL
 OR NOT(p_latitude BETWEEN -90 AND 90) OR NOT(p_longitude BETWEEN -180 AND 180)
 OR p_observada_em IS NULL OR p_observada_em NOT BETWEEN now()-interval '2 minutes' AND now()+interval '30 seconds'
 OR (p_previsao_chegada_em IS NOT NULL AND p_previsao_chegada_em NOT BETWEEN p_observada_em AND p_observada_em+interval '24 hours') THEN
 RETURN jsonb_build_object('sucesso',false); END IF;
 UPDATE ec_private.customer_tracking t SET latitude=p_latitude,longitude=p_longitude,observed_at=p_observada_em,
 eta_at=COALESCE(p_previsao_chegada_em,t.eta_at),eta_observed_at=CASE WHEN p_previsao_chegada_em IS NULL THEN t.eta_observed_at ELSE p_observada_em END
 FROM public.entregas e,public.motoristas m WHERE t.entrega_id=p_entrega_id AND e.id=t.entrega_id AND m.id=e.motorista_id AND m.user_id=auth.uid()
 AND t.expires_at>now() AND (t.observed_at IS NULL OR p_observada_em>t.observed_at)
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id)
 AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone
 AND ec_private.tracking_active(e.id,t.rota_id,t.motorista_id);
 RETURN jsonb_build_object('sucesso',FOUND);
END $$;

CREATE OR REPLACE FUNCTION public.obter_acompanhamento_cliente(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE t ec_private.customer_tracking%ROWTYPE; result jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('estado','indisponivel'); END IF;
 SELECT * INTO t FROM ec_private.customer_tracking WHERE token_hash=sha256(convert_to(p_token,'UTF8'));
 IF NOT FOUND THEN RETURN jsonb_build_object('estado','indisponivel'); END IF;
 IF t.expires_at<=now() OR ec_private.tracking_active(t.entrega_id,t.rota_id,t.motorista_id) IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=t.entrega_id AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone) THEN
  RETURN jsonb_build_object('estado','encerrado'); END IF;
 SELECT jsonb_build_object('estado','ativo','empresa',c.nome,'tipo_tarefa',e.tipo_tarefa,
  'destino',jsonb_build_object('latitude',a.latitude,'longitude',a.longitude),
  'posicao',CASE WHEN t.observed_at IS NULL THEN NULL ELSE jsonb_build_object('latitude',t.latitude,'longitude',t.longitude) END,
  'atualizada_em',t.observed_at,'previsao_chegada_em',t.eta_at,'previsao_atualizada_em',t.eta_observed_at,'servidor_em',now())
 INTO result FROM public.entregas e JOIN public.empresas c ON c.id=e.empresa_id
 JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id WHERE e.id=t.entrega_id;
 RETURN COALESCE(result,jsonb_build_object('estado','indisponivel'));
END $$;
REVOKE ALL ON FUNCTION public.configurar_nome_empresa(uuid,text),public.preparar_aviso_cliente(uuid,text),public.obter_meu_acompanhamento(uuid),public.publicar_localizacao_acompanhamento(uuid,double precision,double precision,timestamptz,timestamptz),public.obter_acompanhamento_cliente(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configurar_nome_empresa(uuid,text),public.preparar_aviso_cliente(uuid,text),public.obter_meu_acompanhamento(uuid),public.publicar_localizacao_acompanhamento(uuid,double precision,double precision,timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_acompanhamento_cliente(text) TO anon,authenticated;
