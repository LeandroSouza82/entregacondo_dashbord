-- Run only on the new EntregaCondo project after the two incremental migrations.
-- Fixtures and changes to statistics are invisible outside this transaction and rolled back.
BEGIN;
DO $validation$
DECLARE
  base public.entregas%ROWTYPE;
  driver_user uuid;
  good uuid:=gen_random_uuid(); bad uuid:=gen_random_uuid();
  result jsonb; before_count integer; after_count integer; after_mean numeric;
BEGIN
  SELECT e.* INTO base FROM public.entregas e
  JOIN public.empresas c ON c.id=e.empresa_id
  JOIN public.motoristas m ON m.id=e.motorista_id AND m.empresa_id=e.empresa_id
  WHERE c.codigo_convite='EC-ENTREGA-01' AND m.ativo=true
    AND EXISTS(SELECT 1 FROM public.clientes_enderecos a WHERE a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id)
  ORDER BY e.created_at LIMIT 1;
  IF base.id IS NULL THEN RAISE EXCEPTION 'Nenhuma tarefa com motorista/endereço válidos para validação'; END IF;
  SELECT user_id INTO driver_user FROM public.motoristas WHERE id=base.motorista_id;
  INSERT INTO public.entregas SELECT (jsonb_populate_record(NULL::public.entregas,to_jsonb(base)||jsonb_build_object('id',good,'rota_id',NULL,'status','em_transito','codigo_rastreio','REG-'||good,'data_hora_entrega',NULL))).*;
  INSERT INTO public.entregas SELECT (jsonb_populate_record(NULL::public.entregas,to_jsonb(base)||jsonb_build_object('id',bad,'rota_id',NULL,'status','em_transito','codigo_rastreio','REG-'||bad,'data_hora_entrega',NULL))).*;
  SELECT total_entregas_realizadas INTO before_count FROM public.clientes_enderecos WHERE id=base.cliente_endereco_id;
  PERFORM set_config('request.jwt.claim.sub',driver_user::text,true);
  PERFORM set_config('role','authenticated',true);
  result:=public.registrar_conclusao_entrega(good,true,NULL,0,0,now()-interval '5 minutes',now());
  PERFORM set_config('role','postgres',true);
  IF result->>'sucesso' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Conclusão falhou: %',result; END IF;
  SELECT total_entregas_realizadas,tempo_medio_minutos INTO after_count,after_mean FROM public.clientes_enderecos WHERE id=base.cliente_endereco_id;
  IF after_count<>before_count+1 THEN RAISE EXCEPTION 'Contagem não atualizada'; END IF;
  PERFORM set_config('role','authenticated',true);
  result:=public.registrar_conclusao_entrega(good,true,NULL,0,0,now()-interval '5 minutes',now());
  PERFORM set_config('role','postgres',true);
  IF result->>'codigo' IS DISTINCT FROM 'ENTREGA_JA_REGISTRADA' OR (SELECT count(*) FROM public.historico_atendimentos WHERE entrega_id=good)<>1 OR (SELECT tempo_medio_minutos FROM public.clientes_enderecos WHERE id=base.cliente_endereco_id)<>after_mean OR (SELECT total_entregas_realizadas FROM public.clientes_enderecos WHERE id=base.cliente_endereco_id)<>after_count THEN RAISE EXCEPTION 'Reenvio duplicou histórico/estatísticas'; END IF;
  PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  PERFORM set_config('role','authenticated',true);
  result:=public.registrar_conclusao_entrega(bad,true);
  PERFORM set_config('role','postgres',true);
  IF result->>'codigo' IS DISTINCT FROM 'ACESSO_NEGADO' THEN RAISE EXCEPTION 'Usuário sem autorização não foi bloqueado'; END IF;
  PERFORM set_config('request.jwt.claim.sub',driver_user::text,true);
  PERFORM set_config('role','authenticated',true);
  result:=public.registrar_conclusao_entrega(bad,false,'  ');
  PERFORM set_config('role','postgres',true);
  IF result->>'codigo' IS DISTINCT FROM 'MOTIVO_OBRIGATORIO' THEN RAISE EXCEPTION 'Motivo vazio aceito'; END IF;
  PERFORM set_config('role','authenticated',true);
  result:=public.registrar_conclusao_entrega(bad,false,'Validação: cliente ausente',0,0,now()-interval '3 minutes',now());
  PERFORM set_config('role','postgres',true);
  IF result->>'sucesso' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM public.historico_atendimentos WHERE entrega_id=bad AND NOT sucesso AND motivo_falha='Validação: cliente ausente') THEN RAISE EXCEPTION 'Falha ou motivo não registrados: %',result; END IF;
  IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='registrar_conclusao_entrega' AND has_function_privilege('anon',p.oid,'EXECUTE')) THEN RAISE EXCEPTION 'RPC exposta a anon'; END IF;
END $validation$;
ROLLBACK;
SELECT 'PASS: conclusão, falha com motivo, reenvio idempotente, média/contagem preservadas e negativa de autorização. Testes revertidos.' AS validacao;
