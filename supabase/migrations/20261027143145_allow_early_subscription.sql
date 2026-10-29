-- Allow contracting during the trial without shortening it or charging early.
ALTER TABLE ec_private.checkouts_assinatura
 ADD COLUMN IF NOT EXISTS inicio_cobranca timestamptz,
 ADD COLUMN IF NOT EXISTS estado_provedor text NOT NULL DEFAULT 'pending',
 ADD COLUMN IF NOT EXISTS atualizado_provedor_em timestamptz,
 ADD COLUMN IF NOT EXISTS proxima_cobranca timestamptz,
 ADD COLUMN IF NOT EXISTS ativo boolean NOT NULL DEFAULT true;
ALTER TABLE ec_private.checkouts_assinatura DROP CONSTRAINT IF EXISTS checkouts_assinatura_empresa_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS checkout_ativo_empresa ON ec_private.checkouts_assinatura(empresa_id) WHERE ativo;

CREATE OR REPLACE FUNCTION public.preparar_checkout_assinatura(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a ec_private.assinaturas_empresas%ROWTYPE; c ec_private.checkouts_assinatura%ROWTYPE; email text;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(p_empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esta empresa não possui uma assinatura comercial.' USING ERRCODE='22023'; END IF;
 IF a.suspensa THEN RAISE EXCEPTION 'Assinatura suspensa. Consulte o suporte.' USING ERRCODE='42501'; END IF;
 IF a.pago_ate>now() THEN RAISE EXCEPTION 'Sua assinatura paga já está ativa.' USING ERRCODE='22023'; END IF;
 SELECT u.email INTO email FROM auth.users u WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL;
 IF email IS NULL THEN RAISE EXCEPTION 'Confirme seu e-mail.' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE empresa_id=p_empresa_id AND ativo;
 IF FOUND AND c.estado_provedor='cancelled' THEN
  UPDATE ec_private.checkouts_assinatura SET ativo=false WHERE id=c.id;
  c:=NULL;
 END IF;
 IF c.id IS NULL THEN
  INSERT INTO ec_private.checkouts_assinatura(empresa_id,inicio_cobranca)
  VALUES(p_empresa_id,CASE WHEN a.teste_fim>now() THEN a.teste_fim ELSE NULL END)
  RETURNING * INTO c;
 END IF;
 RETURN jsonb_build_object('id',c.id,'email',email,'url',c.url,'preapproval_id',c.preapproval_id,
  'valor',a.valor_mensal,'ambiente',a.ambiente_pagamento,'inicio_cobranca',c.inicio_cobranca,
  'estado_provedor',c.estado_provedor,'servidor_em',now());
END;
$$;

CREATE OR REPLACE FUNCTION public.vincular_checkout_assinatura(p_checkout_id uuid,p_preapproval_id text,p_url text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 IF p_checkout_id IS NULL OR p_preapproval_id IS NULL OR p_url IS NULL OR p_preapproval_id !~ '^[A-Za-z0-9_-]{1,100}$' OR p_url !~ '^https://(www\.)?mercadopago\.com\.br/' THEN
  RAISE EXCEPTION 'Resposta de checkout inválida.' USING ERRCODE='22023'; END IF;
 UPDATE ec_private.checkouts_assinatura SET preapproval_id=p_preapproval_id,url=p_url
 WHERE id=p_checkout_id AND ativo AND (preapproval_id IS NULL OR preapproval_id=p_preapproval_id);
 RETURN FOUND;
END;
$$;

-- Status never grants paid coverage. Only a verified approved payment can do so.
CREATE OR REPLACE FUNCTION public.sincronizar_assinatura_provedor(
 p_checkout_id uuid,p_preapproval_id text,p_status text,p_atualizado_em timestamptz,
 p_inicio_cobranca timestamptz,p_proxima_cobranca timestamptz,p_ambiente text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c ec_private.checkouts_assinatura%ROWTYPE; a ec_private.assinaturas_empresas%ROWTYPE;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 IF p_status IS NULL OR p_status NOT IN ('pending','authorized','paused','cancelled')
 OR p_atualizado_em IS NULL OR p_atualizado_em>now()+interval '5 minutes' THEN
  RAISE EXCEPTION 'Estado da assinatura inválido.' USING ERRCODE='22023'; END IF;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE id=p_checkout_id;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=c.empresa_id FOR UPDATE;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE id=p_checkout_id FOR UPDATE;
 IF c.preapproval_id IS DISTINCT FROM p_preapproval_id OR a.ambiente_pagamento IS DISTINCT FROM p_ambiente THEN
  RAISE EXCEPTION 'Assinatura não vinculada a esta empresa.' USING ERRCODE='42501'; END IF;
 IF c.inicio_cobranca IS NOT NULL AND (p_inicio_cobranca IS NULL OR p_inicio_cobranca<c.inicio_cobranca-interval '1 second') THEN
  RAISE EXCEPTION 'A cobrança não pode antecipar o fim do teste.' USING ERRCODE='22023'; END IF;
 IF c.atualizado_provedor_em IS NOT NULL AND c.atualizado_provedor_em>=p_atualizado_em THEN RETURN true; END IF;
 UPDATE ec_private.checkouts_assinatura SET estado_provedor=p_status,
  atualizado_provedor_em=p_atualizado_em,proxima_cobranca=p_proxima_cobranca WHERE id=c.id;
 RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.preparar_checkout_assinatura(uuid),public.vincular_checkout_assinatura(uuid,text,text),
 public.sincronizar_assinatura_provedor(uuid,text,text,timestamptz,timestamptz,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.preparar_checkout_assinatura(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vincular_checkout_assinatura(uuid,text,text),
 public.sincronizar_assinatura_provedor(uuid,text,text,timestamptz,timestamptz,timestamptz,text) TO service_role;

CREATE OR REPLACE FUNCTION public.obter_minha_assinatura(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a ec_private.assinaturas_empresas%ROWTYPE; c ec_private.checkouts_assinatura%ROWTYPE; used integer; active_drivers integer;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.empresa_membros m WHERE m.empresa_id=p_empresa_id
  AND m.user_id=auth.uid() AND m.status='aprovado') THEN
  RAISE EXCEPTION 'Acesso negado a esta empresa.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=p_empresa_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('legado',true,'operacional',true,'servidor_em',now()); END IF;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE empresa_id=p_empresa_id AND ativo;
 SELECT coalesce(atendimentos,0) INTO used FROM ec_private.uso_plano
 WHERE empresa_id=p_empresa_id AND mes=date_trunc('month',now() AT TIME ZONE 'America/Sao_Paulo')::date;
 SELECT count(*) INTO active_drivers FROM public.motoristas WHERE empresa_id=p_empresa_id AND ativo;
 RETURN jsonb_build_object('legado',false,'operacional',ec_private.empresa_assinatura_liberada(p_empresa_id),
  'estado',CASE WHEN a.suspensa THEN 'suspensa' WHEN a.pago_ate>now() THEN 'ativa' WHEN a.teste_fim>now() THEN 'teste' ELSE 'expirada' END,
  'teste_fim',a.teste_fim,'pago_ate',a.pago_ate,'servidor_em',now(),
  'dias_restantes',greatest(0,ceil(extract(epoch FROM (greatest(a.teste_fim,a.pago_ate)-now()))/86400)),
  'valor_mensal',a.valor_mensal,'limite_motoristas',a.limite_motoristas,'limite_atendimentos',a.limite_atendimentos,
  'atendimentos_mes',coalesce(used,0),'motoristas_ativos',active_drivers,
  'checkout_estado',c.estado_provedor,'checkout_pendente',c.preapproval_id IS NOT NULL AND c.estado_provedor='pending',
  'cobranca_inicio',c.inicio_cobranca,'proxima_cobranca',c.proxima_cobranca);
END;
$$;
REVOKE ALL ON FUNCTION public.obter_minha_assinatura(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_minha_assinatura(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.consultar_checkout_assinatura(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c ec_private.checkouts_assinatura%ROWTYPE; a ec_private.assinaturas_empresas%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(p_empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=p_empresa_id;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE empresa_id=p_empresa_id AND ativo;
 IF NOT FOUND THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('id',c.id,'preapproval_id',c.preapproval_id,'ambiente',a.ambiente_pagamento);
END;
$$;
REVOKE ALL ON FUNCTION public.consultar_checkout_assinatura(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consultar_checkout_assinatura(uuid) TO authenticated;
