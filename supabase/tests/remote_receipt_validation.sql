BEGIN;
DO $test$
DECLARE base public.entregas%ROWTYPE; uid uuid; task uuid:=gen_random_uuid(); result jsonb; start_at timestamptz:=now()-interval '95 seconds';
BEGIN
 SELECT e.* INTO base FROM public.entregas e JOIN public.empresas c ON c.id=e.empresa_id JOIN public.motoristas m ON m.id=e.motorista_id
 WHERE c.codigo_convite='EC-ENTREGA-01' AND m.ativo AND e.cliente_endereco_id IS NOT NULL ORDER BY e.created_at LIMIT 1;
 IF base.id IS NULL THEN RAISE EXCEPTION 'Tarefa de referência não encontrada'; END IF;
 SELECT user_id INTO uid FROM public.motoristas WHERE id=base.motorista_id;
 INSERT INTO public.entregas SELECT (jsonb_populate_record(NULL::public.entregas,to_jsonb(base)||jsonb_build_object('id',task,'rota_id',NULL,'status','em_transito','codigo_rastreio','RECEIPT-'||task,'data_hora_entrega',NULL,'chegada_em',NULL))).*;
 PERFORM set_config('request.jwt.claim.sub',uid::text,true);PERFORM set_config('role','authenticated',true);
 result:=public.iniciar_atendimento_entrega(task,start_at);
 IF result->>'sucesso' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Chegada falhou: %',result; END IF;
 result:=public.iniciar_atendimento_entrega(task,now());
 IF (result->>'chegada_em')::timestamptz<>start_at THEN RAISE EXCEPTION 'Relógio foi reiniciado'; END IF;
 result:=public.concluir_atendimento_entrega(task,true,start_at,now(),'{}');
 IF result->>'sucesso' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Recebedor vazio aceito'; END IF;
 result:=public.concluir_atendimento_entrega(task,true,start_at,now(),jsonb_build_object('recebedor_tipo','zelador','recebedor_nome','Teste transacional'));
 IF result->>'sucesso' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Conclusão falhou: %',result; END IF;
 PERFORM set_config('role','postgres',true);
 IF NOT EXISTS(SELECT 1 FROM public.entrega_comprovantes WHERE entrega_id=task AND duracao_segundos=95 AND recebedor_tipo='zelador') THEN RAISE EXCEPTION 'Tempo/comprovante divergente'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.historico_atendimentos WHERE entrega_id=task AND tempo_total_minutos=1.58) THEN RAISE EXCEPTION 'Tempo não chegou ao histórico estatístico'; END IF;
 PERFORM set_config('role','authenticated',true);
 result:=public.concluir_atendimento_entrega(task,true,start_at,now(),jsonb_build_object('recebedor_tipo','vizinho'));
 IF result->>'codigo' IS DISTINCT FROM 'ENTREGA_JA_REGISTRADA' THEN RAISE EXCEPTION 'Reenvio não idempotente'; END IF;
 PERFORM set_config('role','postgres',true);
 IF (SELECT count(*) FROM public.historico_atendimentos WHERE entrega_id=task)<>1 THEN RAISE EXCEPTION 'Histórico duplicado'; END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);PERFORM set_config('role','authenticated',true);
 result:=public.iniciar_atendimento_entrega(task,start_at);
 IF result->>'sucesso' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Usuário não autorizado aceito'; END IF;
 PERFORM set_config('role','postgres',true);
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='entregas-comprovantes' AND NOT public) THEN RAISE EXCEPTION 'Bucket não privado'; END IF;
 IF has_table_privilege('anon','public.entrega_comprovantes','SELECT') OR has_function_privilege('anon','public.concluir_atendimento_entrega(uuid,boolean,timestamptz,timestamptz,jsonb,text)','EXECUTE') THEN RAISE EXCEPTION 'Acesso anônimo indevido'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: chegada explícita, cronômetro sem reset, 95 segundos no histórico, recebedor obrigatório, idempotência e acesso restrito. Fixtures revertidas.' AS validacao;
