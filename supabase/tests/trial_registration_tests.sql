BEGIN;
CREATE TEMP TABLE registration_results(label text);
CREATE FUNCTION pg_temp.registration_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'registration: %',label; END IF; INSERT INTO registration_results VALUES(label); END $$;
GRANT INSERT ON registration_results TO authenticated;
SELECT pg_temp.registration_check(ec_private.documento_valido('pf','529.982.247-25'),'formatted CPF');
SELECT pg_temp.registration_check(ec_private.documento_valido('pj','11.222.333/0001-81'),'formatted CNPJ');
SELECT pg_temp.registration_check(ec_private.documento_valido('pj','00.000.000/E08G-12'),'alphanumeric CNPJ');
SELECT pg_temp.registration_check(NOT ec_private.documento_valido('pf','11111111111'),'repeated digits');
SELECT pg_temp.registration_check(NOT ec_private.documento_valido('pf','52998224724'),'bad CPF digit');
SELECT pg_temp.registration_check(NOT ec_private.documento_valido('pj','11222333000182'),'bad CNPJ digit');
SELECT pg_temp.registration_check(NOT ec_private.documento_valido('pf','52998224725<script>'),'invalid characters are not stripped');
SELECT pg_temp.registration_check(NOT ec_private.documento_valido('pj',null),'missing document');
SELECT pg_temp.registration_check(NOT has_function_privilege('anon','public.registrar_teste_empresa(jsonb)','EXECUTE'),'anonymous registration denied');
SELECT pg_temp.registration_check(NOT has_table_privilege('authenticated','ec_private.documentos_teste','SELECT'),'document registry private');
SELECT pg_temp.registration_check(NOT has_table_privilege('authenticated','ec_private.cadastros_empresas','SELECT'),'contact data private');
SELECT pg_temp.registration_check(NOT has_table_privilege('authenticated','ec_private.documentos_teste','DELETE'),'cannot erase trial usage');
INSERT INTO auth.users(id,email,email_confirmed_at,raw_user_meta_data) VALUES
('ac000000-0000-0000-0000-000000000001','registration1@example.test',now(),'{"empresa_nome":"Fake","tipo_pessoa":"pf","documento":"52998224725"}'),
('ac000000-0000-0000-0000-000000000002','registration2@example.test',now(),'{}'),
('ac000000-0000-0000-0000-000000000003','registration3@example.test',now(),'{}'),
('ac000000-0000-0000-0000-000000000004','unconfirmed-registration@example.test',null,'{}');
SELECT set_config('request.jwt.claim.sub','ac000000-0000-0000-0000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.iniciar_teste_empresa('Bypass'); RAISE EXCEPTION 'old RPC provisioned'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.registrar_teste_empresa('{}'); RAISE EXCEPTION 'metadata bypass'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_teste_empresa('{"tipo_pessoa":"pf","documento":"52998224724","nome_responsavel":"Test","celular":"48999999999"}'); RAISE EXCEPTION 'bad CPF'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_teste_empresa('{"tipo_pessoa":"pj","documento":"11222333000181","nome_responsavel":"Test","celular":"48999999999"}'); RAISE EXCEPTION 'missing legal name'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
SELECT set_config('registration.a',(public.registrar_teste_empresa('{"tipo_pessoa":"pf","documento":"529.982.247-25","nome_responsavel":"Pessoa Teste","celular":"(48) 99999-9999","teste_fim":"2099-01-01","empresa_id":"11111111-1111-1111-1111-111111111111"}')->>'empresa_id'),true);
SELECT pg_temp.registration_check(public.registrar_teste_empresa('{}')->>'empresa_id'=current_setting('registration.a'),'same account retry idempotent');
RESET ROLE;
SELECT pg_temp.registration_check((SELECT nome='Pessoa Teste' AND cnpj IS NULL FROM public.empresas WHERE id=current_setting('registration.a')::uuid),'personal document never exposed in public company');
SELECT pg_temp.registration_check((SELECT documento='52998224725' AND celular='48999999999' AND email='registration1@example.test' FROM ec_private.cadastros_empresas WHERE empresa_id=current_setting('registration.a')::uuid),'normalized private registration');
SELECT pg_temp.registration_check((SELECT teste_fim=teste_inicio+interval '30 days' AND teste_fim<now()+interval '31 days' FROM ec_private.documentos_teste WHERE empresa_id=current_setting('registration.a')::uuid),'caller cannot choose dates');
SELECT set_config('request.jwt.claim.sub','ac000000-0000-0000-0000-000000000002',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.registrar_teste_empresa('{"tipo_pessoa":"pf","documento":"52998224725","nome_responsavel":"Other Name","celular":"48999999998"}'); RAISE EXCEPTION 'duplicate trial'; EXCEPTION WHEN insufficient_privilege THEN
 IF SQLERRM LIKE '%registration1%' OR SQLERRM LIKE '%52998224725%' THEN RAISE EXCEPTION 'document/account leaked'; END IF;
 END;
END $$;
RESET ROLE;
SELECT pg_temp.registration_check(NOT EXISTS(SELECT 1 FROM public.empresa_membros WHERE user_id='ac000000-0000-0000-0000-000000000002'),'duplicate cannot join victim company');
SELECT pg_temp.registration_check(NOT EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas WHERE titular_id='ac000000-0000-0000-0000-000000000002'),'duplicate has no new company');
-- Clear JWT context for privileged fixture deletion; ledger survives both deletions.
SELECT set_config('request.jwt.claim.sub','',true);
DELETE FROM public.empresas WHERE id=current_setting('registration.a')::uuid;
DELETE FROM auth.users WHERE id='ac000000-0000-0000-0000-000000000001';
SELECT pg_temp.registration_check((SELECT empresa_id IS NULL AND titular_id IS NULL FROM ec_private.documentos_teste WHERE documento='52998224725'),'ledger survives company and account deletion');
SELECT set_config('request.jwt.claim.sub','ac000000-0000-0000-0000-000000000002',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.registrar_teste_empresa('{"tipo_pessoa":"pf","documento":"529.982.247-25","nome_responsavel":"Other Name","celular":"48999999998"}'); RAISE EXCEPTION 'trial restarted after deletion'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('registration.b',(public.registrar_teste_empresa('{"tipo_pessoa":"pj","documento":"00.000.000/e08g-12","nome_responsavel":"Responsável Teste","razao_social":"Empresa Teste Ltda","nome_fantasia":"Nome Público","celular":"48999999998"}')->>'empresa_id'),true);
RESET ROLE;
SELECT pg_temp.registration_check((SELECT nome='Nome Público' AND cnpj IS NULL FROM public.empresas WHERE id=current_setting('registration.b')::uuid),'business uses display name without exposing document');
SELECT set_config('request.jwt.claim.sub','ac000000-0000-0000-0000-000000000003',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.registrar_teste_empresa('{"tipo_pessoa":"pj","documento":"00000000E08G12","nome_responsavel":"Another User","razao_social":"Outra Empresa","celular":"48999999998"}'); RAISE EXCEPTION 'duplicate CNPJ'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','ac000000-0000-0000-0000-000000000004',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.registrar_teste_empresa('{"tipo_pessoa":"pf","documento":"11144477735","nome_responsavel":"Unconfirmed User","celular":"48999999998"}'); RAISE EXCEPTION 'unconfirmed trial'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.registration_check(NOT EXISTS(SELECT 1 FROM ec_private.documentos_teste WHERE documento='11144477735'),'unconfirmed email does not consume document');
SELECT count(*)::integer AS registration_passed FROM registration_results;
ROLLBACK;
