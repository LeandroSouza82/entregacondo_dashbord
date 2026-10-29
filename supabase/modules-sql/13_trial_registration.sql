-- Private registration data is never copied into auth metadata or public companies.
-- The document ledger intentionally survives account/company deletion.
CREATE TABLE IF NOT EXISTS ec_private.documentos_teste (
 tipo_pessoa text NOT NULL CHECK(tipo_pessoa IN ('pf','pj')),
 documento text NOT NULL,
 empresa_id uuid REFERENCES public.empresas(id) ON DELETE SET NULL,
 titular_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 teste_inicio timestamptz NOT NULL DEFAULT now(),
 teste_fim timestamptz NOT NULL DEFAULT (now()+interval '30 days'),
 PRIMARY KEY(tipo_pessoa,documento),
 CHECK(teste_fim=teste_inicio+interval '30 days')
);
CREATE TABLE IF NOT EXISTS ec_private.cadastros_empresas (
 empresa_id uuid PRIMARY KEY REFERENCES public.empresas(id) ON DELETE CASCADE,
 tipo_pessoa text NOT NULL,
 documento text NOT NULL,
 nome_responsavel text NOT NULL CHECK(length(nome_responsavel) BETWEEN 3 AND 120),
 razao_social text,
 nome_fantasia text,
 celular text NOT NULL CHECK(celular ~ '^[1-9][0-9]9[0-9]{8}$'),
 email text NOT NULL,
 cadastrado_em timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tipo_pessoa,documento) REFERENCES ec_private.documentos_teste(tipo_pessoa,documento),
 CHECK(tipo_pessoa='pf' OR length(razao_social) BETWEEN 2 AND 120)
);
ALTER TABLE ec_private.documentos_teste ENABLE ROW LEVEL SECURITY;
ALTER TABLE ec_private.cadastros_empresas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.documentos_teste,ec_private.cadastros_empresas FROM PUBLIC,anon,authenticated;

-- CPF and numeric/alphanumeric CNPJ check digits. This validates format, NOT ownership.
CREATE OR REPLACE FUNCTION ec_private.documento_valido(p_tipo text,p_documento text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE doc text:=upper(regexp_replace(coalesce(p_documento,''),'[./[:space:]-]','','g'));
 total integer; digit integer; i integer; pass integer; base integer; weights integer[];
BEGIN
 IF doc ~ '^(.)\1+$' THEN RETURN false; END IF;
 IF p_tipo='pf' THEN
  IF doc !~ '^[0-9]{11}$' THEN RETURN false; END IF;
  FOR pass IN 1..2 LOOP
   total:=0; base:=8+pass;
   FOR i IN 1..base LOOP total:=total+substr(doc,i,1)::integer*(base+2-i); END LOOP;
   digit:=(total*10)%11; IF digit=10 THEN digit:=0; END IF;
   IF digit<>substr(doc,base+1,1)::integer THEN RETURN false; END IF;
  END LOOP;
 ELSIF p_tipo='pj' THEN
  IF doc !~ '^[A-Z0-9]{12}[0-9]{2}$' THEN RETURN false; END IF;
  FOR pass IN 1..2 LOOP
   weights:=CASE WHEN pass=1 THEN ARRAY[5,4,3,2,9,8,7,6,5,4,3,2] ELSE ARRAY[6,5,4,3,2,9,8,7,6,5,4,3,2] END;
   total:=0; base:=11+pass;
   FOR i IN 1..base LOOP total:=total+(ascii(substr(doc,i,1))-48)*weights[i]; END LOOP;
   digit:=CASE WHEN total%11<2 THEN 0 ELSE 11-total%11 END;
   IF digit<>substr(doc,base+1,1)::integer THEN RETURN false; END IF;
  END LOOP;
 ELSE RETURN false;
 END IF;
 RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION ec_private.documento_valido(text,text) FROM PUBLIC,anon,authenticated;

-- Keep the old RPC only as an idempotent lookup for existing managers.
-- Older frontends and direct RPC calls cannot create a trial without registration.
CREATE OR REPLACE FUNCTION public.iniciar_teste_empresa(p_nome_empresa text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m public.empresa_membros%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT * INTO m FROM public.empresa_membros WHERE user_id=auth.uid() ORDER BY created_at DESC,id LIMIT 1;
 IF FOUND AND m.status='aprovado' AND m.papel IN ('admin','gestor') THEN
  RETURN jsonb_build_object('sucesso',true,'empresa_id',m.empresa_id,'existente',true);
 END IF;
 RAISE EXCEPTION 'Complete o cadastro de pessoa física ou jurídica para iniciar o teste.' USING ERRCODE='42501';
END;
$$;
REVOKE ALL ON FUNCTION public.iniciar_teste_empresa(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iniciar_teste_empresa(text) TO authenticated;

-- Definer is required to atomically provision membership and write private tables.
-- Identity comes only from auth.uid(); client-supplied dates, IDs and roles are ignored.
CREATE OR REPLACE FUNCTION public.registrar_teste_empresa(p_cadastro jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u auth.users%ROWTYPE; m public.empresa_membros%ROWTYPE; company uuid;
 kind text:=p_cadastro->>'tipo_pessoa';
 doc text:=upper(regexp_replace(coalesce(p_cadastro->>'documento',''),'[./[:space:]-]','','g'));
 person text:=btrim(coalesce(p_cadastro->>'nome_responsavel',''));
 legal_name text:=btrim(coalesce(p_cadastro->>'razao_social',''));
 trade_name text:=btrim(coalesce(p_cadastro->>'nome_fantasia',''));
 phone text:=regexp_replace(coalesce(p_cadastro->>'celular',''),'[()[:space:]-]','','g');
 company_name text; claimed integer;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT * INTO u FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 IF NOT FOUND OR u.email_confirmed_at IS NULL OR coalesce(u.is_anonymous,false) THEN
  RAISE EXCEPTION 'Confirme seu e-mail para iniciar o teste grátis.' USING ERRCODE='42501'; END IF;
 SELECT * INTO m FROM public.empresa_membros WHERE user_id=u.id ORDER BY created_at DESC,id LIMIT 1;
 IF FOUND THEN
  IF m.status<>'aprovado' OR m.papel NOT IN ('admin','gestor') THEN
   RAISE EXCEPTION 'Sua conta já possui um vínculo empresarial. Consulte a gestão.' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('sucesso',true,'empresa_id',m.empresa_id,'existente',true);
 END IF;
 IF EXISTS(SELECT 1 FROM public.solicitacoes_acesso WHERE user_id=u.id)
 OR EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas WHERE titular_id=u.id)
 OR EXISTS(SELECT 1 FROM ec_private.documentos_teste WHERE titular_id=u.id) THEN
  RAISE EXCEPTION 'Esta conta já possui cadastro. Entre na conta original ou contate o suporte para recuperar o acesso.' USING ERRCODE='42501'; END IF;
 IF NOT ec_private.documento_valido(kind,doc) THEN
  RAISE EXCEPTION 'Informe um CPF ou CNPJ válido para o tipo de cadastro selecionado.' USING ERRCODE='22023'; END IF;
 IF length(person) NOT BETWEEN 3 AND 120 OR length(trade_name)>120
 OR (kind='pj' AND length(legal_name) NOT BETWEEN 2 AND 120)
 OR phone !~ '^[1-9][0-9]9[0-9]{8}$' THEN
  RAISE EXCEPTION 'Confira o nome, os dados da empresa e o celular com DDD.' USING ERRCODE='22023'; END IF;
 -- Unique index serializes simultaneous registrations, including different accounts.
 -- Avoid returning a constraint error containing the document value.
 INSERT INTO ec_private.documentos_teste(tipo_pessoa,documento,titular_id)
 VALUES(kind,doc,u.id) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS claimed=ROW_COUNT;
 IF claimed=0 THEN
  RAISE EXCEPTION 'Não foi possível liberar um novo teste com este documento. Entre na conta original ou contate o suporte para recuperar o acesso.' USING ERRCODE='42501'; END IF;
 company_name:=coalesce(nullif(trade_name,''),CASE WHEN kind='pj' THEN legal_name ELSE person END);
 INSERT INTO public.empresas(nome,codigo_convite,ativa)
 VALUES(company_name,'EC-'||upper(replace(gen_random_uuid()::text,'-','')),true) RETURNING id INTO company;
 INSERT INTO public.perfis_usuarios(id,email,nome) VALUES(u.id,u.email,person)
 ON CONFLICT(id) DO UPDATE SET nome=excluded.nome,email=excluded.email;
 INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status,aprovado_em)
 VALUES(company,u.id,'admin','aprovado',now());
 INSERT INTO ec_private.assinaturas_empresas(empresa_id,titular_id) VALUES(company,u.id);
 UPDATE ec_private.documentos_teste SET empresa_id=company WHERE tipo_pessoa=kind AND documento=doc;
 INSERT INTO ec_private.cadastros_empresas(empresa_id,tipo_pessoa,documento,nome_responsavel,razao_social,nome_fantasia,celular,email)
 VALUES(company,kind,doc,person,CASE WHEN kind='pj' THEN legal_name ELSE NULL END,nullif(trade_name,''),phone,u.email);
 RETURN jsonb_build_object('sucesso',true,'empresa_id',company,'existente',false,'teste_fim',now()+interval '30 days');
END;
$$;
REVOKE ALL ON FUNCTION public.registrar_teste_empresa(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_teste_empresa(jsonb) TO authenticated;
