-- Company provisioning is atomic. Subscription dates and limits are server-owned.
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS ec_private.assinaturas_empresas (
 empresa_id uuid PRIMARY KEY REFERENCES public.empresas(id) ON DELETE CASCADE,
 titular_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
 teste_inicio timestamptz NOT NULL DEFAULT now(),
 teste_fim timestamptz NOT NULL DEFAULT (now()+interval '30 days'),
 pago_ate timestamptz,
 suspensa boolean NOT NULL DEFAULT false,
 ambiente_pagamento text NOT NULL DEFAULT 'production' CHECK(ambiente_pagamento IN ('test','production')),
 valor_mensal numeric(10,2) NOT NULL DEFAULT 149.90 CHECK(valor_mensal=149.90),
 limite_motoristas integer NOT NULL DEFAULT 3 CHECK(limite_motoristas=3),
 limite_atendimentos integer NOT NULL DEFAULT 1000 CHECK(limite_atendimentos=1000),
 CHECK(teste_fim=teste_inicio+interval '30 days')
);
CREATE TABLE IF NOT EXISTS ec_private.uso_plano (
 empresa_id uuid NOT NULL REFERENCES ec_private.assinaturas_empresas(empresa_id) ON DELETE CASCADE,
 mes date NOT NULL, atendimentos integer NOT NULL DEFAULT 0 CHECK(atendimentos>=0),
 PRIMARY KEY(empresa_id,mes)
);
ALTER TABLE ec_private.assinaturas_empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE ec_private.uso_plano ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.assinaturas_empresas,ec_private.uso_plano FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION ec_private.empresa_assinatura_liberada(p_empresa_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT NOT EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas a WHERE a.empresa_id=p_empresa_id)
 OR EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas a WHERE a.empresa_id=p_empresa_id
  AND NOT a.suspensa AND greatest(a.teste_fim,a.pago_ate)>now());
$$;
REVOKE ALL ON FUNCTION ec_private.empresa_assinatura_liberada(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.iniciar_teste_empresa(p_nome_empresa text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u auth.users%ROWTYPE; m public.empresa_membros%ROWTYPE; company uuid; company_name text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT * INTO u FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 IF NOT FOUND OR u.email_confirmed_at IS NULL OR coalesce(u.is_anonymous,false) THEN
  RAISE EXCEPTION 'Confirme seu e-mail para iniciar o teste grátis.' USING ERRCODE='42501'; END IF;
 -- The auth.users row lock serializes retries and simultaneous first logins.
 SELECT * INTO m FROM public.empresa_membros WHERE user_id=u.id ORDER BY created_at DESC,id LIMIT 1;
 IF FOUND THEN
  IF m.status<>'aprovado' OR m.papel NOT IN ('admin','gestor') THEN
   RAISE EXCEPTION 'Sua conta já possui um vínculo empresarial. Consulte a gestão.' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('sucesso',true,'empresa_id',m.empresa_id,'existente',true);
 END IF;
 IF EXISTS(SELECT 1 FROM public.solicitacoes_acesso WHERE user_id=u.id) THEN
  RAISE EXCEPTION 'Sua conta já possui uma solicitação de acesso. Consulte a gestão.' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas WHERE titular_id=u.id) THEN
  RAISE EXCEPTION 'O teste desta conta já foi utilizado.' USING ERRCODE='42501'; END IF;
 -- User metadata supplies display text only; never a role, company id or validity.
 company_name:=btrim(coalesce(p_nome_empresa,u.raw_user_meta_data->>'empresa_nome',''));
 IF length(company_name) NOT BETWEEN 2 AND 120 THEN
  RAISE EXCEPTION 'Informe o nome da empresa entre 2 e 120 caracteres.' USING ERRCODE='22023'; END IF;
 INSERT INTO public.empresas(nome,codigo_convite,ativa)
 VALUES(company_name,'EC-'||upper(replace(gen_random_uuid()::text,'-','')),true) RETURNING id INTO company;
 INSERT INTO public.perfis_usuarios(id,email,nome)
 VALUES(u.id,u.email,coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'),''),nullif(btrim(u.raw_user_meta_data->>'name'),''),'Gestor'))
 ON CONFLICT(id) DO NOTHING;
 INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status,aprovado_em)
 VALUES(company,u.id,'admin','aprovado',now());
 INSERT INTO ec_private.assinaturas_empresas(empresa_id,titular_id) VALUES(company,u.id);
 RETURN jsonb_build_object('sucesso',true,'empresa_id',company,'existente',false,'teste_fim',now()+interval '30 days');
END;
$$;
REVOKE ALL ON FUNCTION public.iniciar_teste_empresa(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iniciar_teste_empresa(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obter_minha_assinatura(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a ec_private.assinaturas_empresas%ROWTYPE; used integer; active_drivers integer;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.empresa_membros m WHERE m.empresa_id=p_empresa_id
  AND m.user_id=auth.uid() AND m.status='aprovado') THEN
  RAISE EXCEPTION 'Acesso negado a esta empresa.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=p_empresa_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('legado',true,'operacional',true,'servidor_em',now()); END IF;
 SELECT coalesce(atendimentos,0) INTO used FROM ec_private.uso_plano
 WHERE empresa_id=p_empresa_id AND mes=date_trunc('month',now() AT TIME ZONE 'America/Sao_Paulo')::date;
 SELECT count(*) INTO active_drivers FROM public.motoristas WHERE empresa_id=p_empresa_id AND ativo;
 RETURN jsonb_build_object('legado',false,'operacional',ec_private.empresa_assinatura_liberada(p_empresa_id),
  'estado',CASE WHEN a.suspensa THEN 'suspensa' WHEN a.pago_ate>now() THEN 'ativa' WHEN a.teste_fim>now() THEN 'teste' ELSE 'expirada' END,
  'teste_fim',a.teste_fim,'pago_ate',a.pago_ate,'servidor_em',now(),
  'dias_restantes',greatest(0,ceil(extract(epoch FROM (greatest(a.teste_fim,a.pago_ate)-now()))/86400)),
  'valor_mensal',a.valor_mensal,'limite_motoristas',a.limite_motoristas,'limite_atendimentos',a.limite_atendimentos,
  'atendimentos_mes',coalesce(used,0),'motoristas_ativos',active_drivers);
END;
$$;
REVOKE ALL ON FUNCTION public.obter_minha_assinatura(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_minha_assinatura(uuid) TO authenticated;

-- A trigger also guards SECURITY DEFINER RPCs, so an old APK cannot bypass expiry.
CREATE OR REPLACE FUNCTION ec_private.proteger_operacao_assinatura()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company uuid; a ec_private.assinaturas_empresas%ROWTYPE; current_count integer;
BEGIN
 IF TG_TABLE_NAME='historico_atendimentos' THEN
  SELECT empresa_id INTO company FROM public.entregas WHERE id=coalesce(to_jsonb(NEW)->>'entrega_id',to_jsonb(OLD)->>'entrega_id')::uuid;
 ELSE
  company:=coalesce(to_jsonb(NEW)->>'empresa_id',to_jsonb(OLD)->>'empresa_id')::uuid;
 END IF;
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)->>'empresa_id') IS DISTINCT FROM (to_jsonb(OLD)->>'empresa_id') THEN
  RAISE EXCEPTION 'Não é permitido transferir registros entre empresas.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=company FOR UPDATE;
 -- Existing companies retain their current operation; no retroactive trial or reset.
 IF NOT FOUND OR auth.uid() IS NULL THEN
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
 END IF;
 IF NOT ec_private.empresa_assinatura_liberada(company) THEN
  RAISE EXCEPTION 'Seu período de acesso terminou. Assine o plano para continuar operando.' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='motoristas' AND TG_OP<>'DELETE' THEN
  IF NEW.ativo THEN
  SELECT count(*) INTO current_count FROM public.motoristas WHERE empresa_id=company AND ativo AND id<>NEW.id;
  IF current_count>=a.limite_motoristas THEN
   RAISE EXCEPTION 'O plano permite até 3 motoristas ativos.' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
CREATE OR REPLACE FUNCTION ec_private.contar_atendimento_plano()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE cap integer; total integer;
BEGIN
 SELECT limite_atendimentos INTO cap FROM ec_private.assinaturas_empresas WHERE empresa_id=NEW.empresa_id FOR UPDATE;
 IF FOUND THEN
  INSERT INTO ec_private.uso_plano(empresa_id,mes,atendimentos)
  VALUES(NEW.empresa_id,date_trunc('month',now() AT TIME ZONE 'America/Sao_Paulo')::date,1)
  ON CONFLICT(empresa_id,mes) DO UPDATE SET atendimentos=ec_private.uso_plano.atendimentos+1
  RETURNING atendimentos INTO total;
  IF total>cap THEN RAISE EXCEPTION 'O plano permite até 1.000 atendimentos por mês.' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION ec_private.proteger_operacao_assinatura(),ec_private.contar_atendimento_plano() FROM PUBLIC,anon,authenticated;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['motoristas','clientes_enderecos','rotas_planejadas','entregas','entrega_comprovantes','pedidos_fluxo','empresa_membros','veiculos_motoristas','veiculos_documentos','historico_atendimentos'] LOOP
  EXECUTE format('DROP TRIGGER IF EXISTS assinatura_operacional ON public.%I',t);
  EXECUTE format('CREATE TRIGGER assinatura_operacional BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION ec_private.proteger_operacao_assinatura()',t);
 END LOOP;
END $$;
DROP TRIGGER IF EXISTS assinatura_cota_atendimentos ON public.entregas;
CREATE TRIGGER assinatura_cota_atendimentos AFTER INSERT ON public.entregas FOR EACH ROW EXECUTE FUNCTION ec_private.contar_atendimento_plano();

-- Remove legacy permissive policies: a permissive USING(true) defeats other RLS.
DROP POLICY IF EXISTS "Acesso empresas" ON public.empresas;
DROP POLICY IF EXISTS "Acesso membros" ON public.empresa_membros;
DROP POLICY IF EXISTS "Acesso perfis" ON public.perfis_usuarios;
DROP POLICY IF EXISTS "Acesso total a motoristas para membros da empresa" ON public.motoristas;
DROP POLICY IF EXISTS "Acesso a entregas para autenticados" ON public.entregas;
DROP POLICY IF EXISTS "Acesso a rotas para autenticados" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Acesso a clientes enderecos para autenticados" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Permitir exclusao de enderecos" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Usuarios visualizam empresas das quais sao membros" ON public.empresas;
CREATE POLICY "Usuarios visualizam empresas das quais sao membros" ON public.empresas FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public.empresa_membros m WHERE m.empresa_id=empresas.id AND m.user_id=(SELECT auth.uid())));
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['empresas','perfis_usuarios','empresa_membros','solicitacoes_acesso','auditoria_acessos','motoristas','veiculos_motoristas','veiculos_documentos','clientes_enderecos','rotas_planejadas','entregas','historico_atendimentos','storage_limpeza_fila'] LOOP
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
  EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
 END LOOP;
END $$;
GRANT UPDATE(nome,telefone,avatar_url) ON public.perfis_usuarios TO authenticated;
-- Keep the existing headquarters-city preference writable by its own manager.
GRANT UPDATE(cidade) ON public.empresas TO authenticated;
DROP POLICY IF EXISTS "Gestao configura cidade da propria empresa" ON public.empresas;
CREATE POLICY "Gestao configura cidade da propria empresa" ON public.empresas FOR UPDATE TO authenticated
USING(public.fn_usuario_e_gestor_empresa(id,auth.uid()))
WITH CHECK(public.fn_usuario_e_gestor_empresa(id,auth.uid()));
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon',p.oid,'EXECUTE')
   AND p.proname NOT IN ('obter_acompanhamento_cliente','obter_comprovante_compartilhado') LOOP
  EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC,anon',f.signature);
  IF f.proname NOT IN ('rls_auto_enable','bootstrap_primeiro_gestor') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.signature); END IF;
 END LOOP;
END $$;

-- The old manual bootstrap is maintenance-only; it can self-approve an admin.
REVOKE ALL ON FUNCTION public.bootstrap_primeiro_gestor(text,text,text) FROM PUBLIC,anon,authenticated;

-- Operational driver RPCs stop when the trial ends, including public tracking.
CREATE OR REPLACE FUNCTION public.fn_usuario_pode_operar_motorista(
    p_empresa_id UUID, p_motorista_id UUID
)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
    SELECT auth.uid() IS NOT NULL AND ec_private.empresa_assinatura_liberada(p_empresa_id) AND EXISTS (
        SELECT 1 FROM public.motoristas m
        JOIN public.empresas e ON e.id = m.empresa_id AND e.ativa = TRUE
        JOIN public.veiculos_motoristas vm ON vm.user_id = m.user_id AND vm.empresa_id = m.empresa_id
        WHERE m.id = p_motorista_id AND m.empresa_id = p_empresa_id AND m.ativo = TRUE
          AND vm.status_analise = 'aprovado'
          AND (public.fn_validar_completude_veiculo(vm.id)->>'valido')::boolean IS TRUE
          AND (public.fn_usuario_e_gestor_empresa(p_empresa_id, auth.uid()) IS TRUE OR (
              m.user_id = auth.uid() AND EXISTS (
                  SELECT 1 FROM public.empresa_membros em
                  WHERE em.empresa_id = p_empresa_id AND em.user_id = auth.uid()
                    AND em.motorista_id = m.id AND em.papel = 'motorista' AND em.status = 'aprovado'
              )
          ))
    );
$$;
