BEGIN;
DO $test$
DECLARE base public.rotas_planejadas%ROWTYPE; uid uuid; rid uuid:=gen_random_uuid(); result jsonb;
BEGIN
 SELECT r.* INTO base FROM public.rotas_planejadas r JOIN public.motoristas m ON m.id=r.motorista_id WHERE m.user_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.veiculos_motoristas v WHERE v.user_id=m.user_id AND v.empresa_id=m.empresa_id AND v.status_analise='aprovado') ORDER BY r.created_at DESC LIMIT 1;
 IF base.id IS NULL THEN RAISE EXCEPTION 'Rota de referência autorizada não encontrada'; END IF;
 SELECT user_id INTO uid FROM public.motoristas WHERE id=base.motorista_id;
 INSERT INTO public.rotas_planejadas SELECT (jsonb_populate_record(NULL::public.rotas_planejadas,to_jsonb(base)||jsonb_build_object('id',rid,'status','em_execucao','idempotency_key',rid::text,'distancia_registrada_km',0))).*;
 PERFORM set_config('request.jwt.claim.sub',uid::text,true); PERFORM set_config('role','authenticated',true);
 result:=public.atualizar_localizacao_motorista(rid,-27.6,-48.5,3.5);
 IF result->>'sucesso' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'GPS autorizado falhou: %',result; END IF;
 result:=public.atualizar_localizacao_motorista(rid,-27.6,-48.5,2);
 IF NOT EXISTS(SELECT 1 FROM public.rotas_planejadas WHERE id=rid AND distancia_registrada_km=3.5) THEN RAISE EXCEPTION 'Distância retrocedeu'; END IF;
 result:=public.atualizar_localizacao_motorista(rid,91,-48.5,4);
 IF result->>'sucesso' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Coordenada inválida aceita'; END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 result:=public.atualizar_localizacao_motorista(rid,-27.6,-48.5,4);
 IF result->>'sucesso' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'GPS de terceiro aceito'; END IF;
 IF EXISTS(SELECT 1 FROM public.motoristas WHERE id=base.motorista_id) THEN RAISE EXCEPTION 'Terceiro consegue ler posição'; END IF;
 PERFORM set_config('role','postgres',true);
 IF has_function_privilege('anon','public.atualizar_localizacao_motorista(uuid,double precision,double precision,numeric)','EXECUTE') OR has_table_privilege('authenticated','public.empresa_membros','UPDATE') THEN RAISE EXCEPTION 'Privilégio indevido'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: GPS restrito ao motorista ativo, leitura de terceiros bloqueada, coordenadas validadas, distância sem retrocesso. Todos os dados de teste revertidos.' AS validacao;
