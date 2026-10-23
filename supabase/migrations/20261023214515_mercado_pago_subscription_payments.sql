CREATE TABLE IF NOT EXISTS ec_private.checkouts_assinatura (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL UNIQUE REFERENCES ec_private.assinaturas_empresas(empresa_id) ON DELETE CASCADE,
 preapproval_id text UNIQUE, url text, criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS ec_private.pagamentos_assinatura (
 pagamento_id text PRIMARY KEY,
 checkout_id uuid NOT NULL REFERENCES ec_private.checkouts_assinatura(id),
 status text NOT NULL, aprovado_em timestamptz, atualizado_em timestamptz NOT NULL,
 cobertura_ate timestamptz, valor numeric(10,2) NOT NULL CHECK(valor=149.90)
);
ALTER TABLE ec_private.checkouts_assinatura ENABLE ROW LEVEL SECURITY;
ALTER TABLE ec_private.pagamentos_assinatura ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.checkouts_assinatura,ec_private.pagamentos_assinatura FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.preparar_checkout_assinatura(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a ec_private.assinaturas_empresas%ROWTYPE; c ec_private.checkouts_assinatura%ROWTYPE; email text;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(p_empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esta empresa não possui uma assinatura comercial.' USING ERRCODE='22023'; END IF;
 IF a.teste_fim>now() OR a.pago_ate>now() THEN RAISE EXCEPTION 'Seu período de acesso ainda está ativo.' USING ERRCODE='22023'; END IF;
 SELECT u.email INTO email FROM auth.users u WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL;
 IF email IS NULL THEN RAISE EXCEPTION 'Confirme seu e-mail.' USING ERRCODE='42501'; END IF;
 INSERT INTO ec_private.checkouts_assinatura(empresa_id) VALUES(p_empresa_id) ON CONFLICT(empresa_id) DO NOTHING;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',c.id,'email',email,'url',c.url,'preapproval_id',c.preapproval_id,'valor',a.valor_mensal,'ambiente',a.ambiente_pagamento);
END;
$$;
CREATE OR REPLACE FUNCTION public.vincular_checkout_assinatura(p_checkout_id uuid,p_preapproval_id text,p_url text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 IF p_checkout_id IS NULL OR p_preapproval_id IS NULL OR p_url IS NULL OR p_preapproval_id !~ '^[A-Za-z0-9_-]{1,100}$' OR p_url !~ '^https://(www\.)?mercadopago\.com\.br/' THEN
  RAISE EXCEPTION 'Resposta de checkout inválida.' USING ERRCODE='22023'; END IF;
 UPDATE ec_private.checkouts_assinatura SET preapproval_id=p_preapproval_id,url=p_url
 WHERE id=p_checkout_id AND (preapproval_id IS NULL OR preapproval_id=p_preapproval_id);
 RETURN FOUND;
END;
$$;
CREATE OR REPLACE FUNCTION public.registrar_pagamento_assinatura(
 p_checkout_id uuid,p_preapproval_id text,p_pagamento_id text,p_status text,p_valor numeric,
 p_moeda text,p_aprovado_em timestamptz,p_atualizado_em timestamptz,p_ambiente text DEFAULT 'production')
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c ec_private.checkouts_assinatura%ROWTYPE; a ec_private.assinaturas_empresas%ROWTYPE;
 payment ec_private.pagamentos_assinatura%ROWTYPE; coverage timestamptz;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 IF p_valor IS DISTINCT FROM 149.90 OR p_moeda IS DISTINCT FROM 'BRL'
  OR p_pagamento_id IS NULL OR p_pagamento_id !~ '^[0-9]{1,30}$'
  OR p_status IS NULL OR p_status NOT IN ('approved','pending','in_process','rejected','cancelled','refunded','charged_back')
  OR p_atualizado_em IS NULL OR p_atualizado_em>now()+interval '5 minutes' THEN
  RAISE EXCEPTION 'Pagamento incompatível com o plano.' USING ERRCODE='22023'; END IF;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE id=p_checkout_id AND preapproval_id=p_preapproval_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Assinatura não vinculada a esta empresa.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=c.empresa_id FOR UPDATE;
 IF p_ambiente IS DISTINCT FROM a.ambiente_pagamento THEN
  RAISE EXCEPTION 'O ambiente do pagamento não corresponde ao cadastro.' USING ERRCODE='42501'; END IF;
 SELECT * INTO payment FROM ec_private.pagamentos_assinatura WHERE pagamento_id=p_pagamento_id;
 IF FOUND THEN
  IF payment.checkout_id<>c.id THEN RAISE EXCEPTION 'Pagamento já vinculado a outro cadastro.' USING ERRCODE='42501'; END IF;
  IF payment.atualizado_em>=p_atualizado_em THEN RETURN true; END IF;
  coverage:=payment.cobertura_ate;
 END IF;
 IF p_status='approved' THEN
  IF p_aprovado_em IS NULL OR p_aprovado_em>now()+interval '5 minutes' THEN
   RAISE EXCEPTION 'Confirmação de pagamento inválida.' USING ERRCODE='22023'; END IF;
  IF coverage IS NULL THEN coverage:=greatest(p_aprovado_em,a.pago_ate,a.teste_fim)+interval '1 month'; END IF;
 END IF;
 INSERT INTO ec_private.pagamentos_assinatura(pagamento_id,checkout_id,status,aprovado_em,atualizado_em,cobertura_ate,valor)
 VALUES(p_pagamento_id,c.id,p_status,p_aprovado_em,p_atualizado_em,coverage,p_valor)
 ON CONFLICT(pagamento_id) DO UPDATE SET status=excluded.status,aprovado_em=excluded.aprovado_em,
  atualizado_em=excluded.atualizado_em,cobertura_ate=excluded.cobertura_ate;
 UPDATE ec_private.assinaturas_empresas SET
  pago_ate=(SELECT max(p.cobertura_ate) FROM ec_private.pagamentos_assinatura p
   JOIN ec_private.checkouts_assinatura x ON x.id=p.checkout_id WHERE x.empresa_id=c.empresa_id AND p.status='approved'),
  suspensa=EXISTS(SELECT 1 FROM ec_private.pagamentos_assinatura p JOIN ec_private.checkouts_assinatura x ON x.id=p.checkout_id
   WHERE x.empresa_id=c.empresa_id AND p.status='charged_back')
 WHERE empresa_id=c.empresa_id;
 RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.preparar_checkout_assinatura(uuid),public.vincular_checkout_assinatura(uuid,text,text),
 public.registrar_pagamento_assinatura(uuid,text,text,text,numeric,text,timestamptz,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.preparar_checkout_assinatura(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vincular_checkout_assinatura(uuid,text,text),
 public.registrar_pagamento_assinatura(uuid,text,text,text,numeric,text,timestamptz,timestamptz,text) TO service_role;

CREATE OR REPLACE FUNCTION public.obter_contexto_pagamento_assinatura(p_pagamento_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('checkout_id',c.id,'preapproval_id',c.preapproval_id) INTO result
 FROM ec_private.pagamentos_assinatura p JOIN ec_private.checkouts_assinatura c ON c.id=p.checkout_id WHERE p.pagamento_id=p_pagamento_id;
 RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.obter_contexto_pagamento_assinatura(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_contexto_pagamento_assinatura(text) TO service_role;
