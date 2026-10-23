BEGIN;
INSERT INTO public.clientes_enderecos(id,empresa_id,nome_identificador,endereco_completo,numero,bairro,cidade,cep,latitude,longitude) VALUES
('db100000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','Release fixture A','Rua teste A','1','Centro','Teste','00000000',-27.6,-48.6),
('db200000-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','Release fixture B','Rua teste B','1','Centro','Teste','00000000',-27.7,-48.7);
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM pg_class WHERE oid='public.saved_addresses'::regclass AND 'security_invoker=true'=ANY(reloptions)) THEN RAISE EXCEPTION 'saved_addresses bypasses caller RLS';END IF;
 IF has_table_privilege('anon','public.saved_addresses','SELECT') THEN RAISE EXCEPTION 'Guest can select saved address view';END IF;
 IF NOT EXISTS(SELECT FROM pg_proc p,unnest(p.proconfig) setting WHERE p.oid='public.fn_safe_uuid(text)'::regprocedure AND setting LIKE 'search_path=%') THEN RAISE EXCEPTION 'UUID helper has mutable search path';END IF;
 IF public.fn_safe_uuid('not-a-uuid') IS NOT NULL OR public.fn_safe_uuid('11111111-1111-1111-1111-111111111111')<>'11111111-1111-1111-1111-111111111111'::uuid THEN RAISE EXCEPTION 'UUID conversion changed';END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM public.saved_addresses WHERE id='db100000-0000-0000-0000-000000000001') OR EXISTS(SELECT FROM public.saved_addresses WHERE id='db200000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'Saved view crosses companies for manager A';END IF;
END $$;
DO $$
DECLARE payload jsonb := '{"empresa_id":"11111111-1111-1111-1111-111111111111","nome_identificador":"No fabricated point","endereco_completo":"Rua teste, Palhoça"}'; result jsonb; coords jsonb;
BEGIN
 FOREACH coords IN ARRAY ARRAY['{}'::jsonb,'{"latitude":0,"longitude":0}'::jsonb,'{"latitude":91,"longitude":-48.6}'::jsonb,'{"latitude":"bad","longitude":-48.6}'::jsonb,'{"latitude":"NaN","longitude":-48.6}'::jsonb] LOOP
  result:=public.salvar_cliente_endereco(payload||coords);
  IF result->>'codigo' IS DISTINCT FROM 'COORDENADAS_INVALIDAS' THEN RAISE EXCEPTION 'Invalid coordinates invented a point: %',result;END IF;
 END LOOP;
 result:=public.salvar_cliente_endereco(payload||'{"latitude":-27.63,"longitude":-48.68}'::jsonb);
 IF result->>'sucesso' IS DISTINCT FROM 'true' OR result->'cliente'->>'cidade' IS DISTINCT FROM '' OR result->'cliente'->>'cep' IS DISTINCT FROM '' THEN RAISE EXCEPTION 'Invented address metadata: %',result;END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM public.saved_addresses WHERE id='db200000-0000-0000-0000-000000000001') OR EXISTS(SELECT FROM public.saved_addresses WHERE id='db100000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'Saved view crosses companies for manager B';END IF;
END $$;
RESET ROLE;
SELECT 12 AS release_compatibility_passed;
ROLLBACK;
