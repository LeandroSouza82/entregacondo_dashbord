BEGIN;
CREATE TEMP TABLE planning_checks (name text);
CREATE FUNCTION pg_temp.check_rule(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Regra opcional: %',label; END IF;
 INSERT INTO planning_checks VALUES(label);
END $$;
CREATE FUNCTION pg_temp.reject_rule(statement text, expected text, label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE blocked boolean:=false;
BEGIN
 BEGIN
  EXECUTE statement;
  SET CONSTRAINTS ALL IMMEDIATE;
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM !~* expected THEN RAISE EXCEPTION 'Erro inesperado em %: %',label,SQLERRM; END IF;
  blocked:=true;
 END;
 PERFORM pg_temp.check_rule(blocked,label);
END $$;
DO $$
DECLARE company uuid:='11111111-1111-1111-1111-111111111111'; driver uuid:='c1000000-0000-0000-0000-000000000001';
 addr uuid; pickup uuid:=gen_random_uuid(); delivery uuid:=gen_random_uuid(); route uuid; other uuid; oldtask uuid;
 car uuid; angle text; reservation jsonb; storage_path_value text; rev int; r jsonb; payload jsonb; bad_payload jsonb; second_pickup uuid; second_delivery uuid; active uuid; agenda jsonb; config jsonb; tomorrow date:=(now() AT TIME ZONE 'America/Sao_Paulo')::date+1; departure timestamptz;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',true);
 SELECT id INTO car FROM public.veiculos_motoristas WHERE user_id=auth.uid();
 FOREACH angle IN ARRAY ARRAY['frente','lado_direito','lado_esquerdo','traseira'] LOOP
  reservation:=public.reservar_upload_evidencia(company,'foto_veiculo',angle||'.jpg',angle);
  storage_path_value:=reservation->>'storage_path';
  INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('veiculos-documentos',storage_path_value,'{"size":500,"mimetype":"image/jpeg"}');
  PERFORM public.anexar_documento_veiculo(car,'foto_veiculo',angle||'.jpg',storage_path_value,500,angle);
 END LOOP;
 reservation:=public.reservar_upload_evidencia(company,'crlv','crlv.pdf');
 storage_path_value:=reservation->>'storage_path';
 INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('veiculos-documentos',storage_path_value,'{"size":500,"mimetype":"application/pdf"}');
 PERFORM public.anexar_documento_veiculo(car,'crlv','crlv.pdf',storage_path_value,500);
 PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
 SELECT revisao INTO rev FROM public.veiculos_motoristas WHERE id=car;
 PERFORM public.analisar_veiculo_motorista(car,true,rev);
 PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
 PERFORM pg_temp.check_rule(public.obter_capacidades_rotas()->>'regras_opcionais'='1','capability version');
 INSERT INTO public.clientes_enderecos(empresa_id,nome_identificador,endereco_completo,numero,bairro,cidade,cep,latitude,longitude)
 VALUES(company,'Local teste regras','Rua teste','1','Centro','Palhoça','88132292',-27.63,-48.68) RETURNING id INTO addr;
 departure:=(tomorrow+time '08:30') AT TIME ZONE 'America/Sao_Paulo';
 agenda:=jsonb_build_array(jsonb_build_object('entrega_id',pickup,'inicio_em',departure+interval '30 minutes','fim_em',departure+interval '35 minutes'),
   jsonb_build_object('entrega_id',delivery,'inicio_em',departure+interval '60 minutes','fim_em',departure+interval '70 minutes'));
 payload:=jsonb_build_object('empresa_id',company,'motorista_id',driver,'idempotency_key','planning-optional',
  'distancia_original_km',10,'tempo_original_minutos',20,'distancia_otimizada_km',10,'tempo_otimizado_minutos',20,
  'percentual_economia_km',0,'percentual_economia_tempo',0,'ordem_paradas_json','[]'::jsonb,
  'planejamento_saida_em',departure,'agenda',agenda,'paradas',jsonb_build_array(
   jsonb_build_object('id',pickup,'cliente_endereco_id',addr,'destinatario_nome','Coleta teste','tipo_tarefa','coleta','ordem_na_rota',1,
    'janela_data',tomorrow,'janela_inicio','09:00','janela_fim','12:00','tempo_atendimento_previsto_min',5),
   jsonb_build_object('id',delivery,'cliente_endereco_id',addr,'destinatario_nome','Entrega teste','tipo_tarefa','entrega','ordem_na_rota',2,
    'coleta_origem_id',pickup,'janela_data',tomorrow,'janela_inicio','09:00','janela_fim','12:00','tempo_atendimento_previsto_min',10)));
 second_pickup:=gen_random_uuid();
 bad_payload:=payload||jsonb_build_object('idempotency_key','planning-invalid-agenda','agenda',NULL,
   'paradas',jsonb_build_array(payload->'paradas'->0||jsonb_build_object('id',second_pickup)));
 PERFORM pg_temp.reject_rule(format('SELECT public.enviar_pedidos_motorista(%L::jsonb)',bad_payload),'Recalcule','invalid dispatch agenda fails atomically');
 PERFORM pg_temp.check_rule(NOT EXISTS(SELECT FROM public.entregas WHERE id=second_pickup)
   AND NOT EXISTS(SELECT FROM public.rotas_planejadas WHERE idempotency_key='planning-invalid-agenda')
   AND NOT EXISTS(SELECT FROM public.operacoes_envio_motorista WHERE chave='planning-invalid-agenda'),'failed dispatch leaves no partial order route or journal');
 r:=public.enviar_pedidos_motorista(payload); route:=(r->>'nova_rota_id')::uuid;
 SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
 PERFORM pg_temp.check_rule(r->>'sucesso'='true' AND route IS NOT NULL,'dispatch with both optional rules');
 PERFORM pg_temp.check_rule((SELECT count(*)=2 FROM public.entregas WHERE id=ANY(ARRAY[pickup,delivery]) AND rota_id=route),'stable stop ids preserved');
 PERFORM pg_temp.check_rule((SELECT janela_inicio_em=(tomorrow+time '09:00') AT TIME ZONE 'America/Sao_Paulo' FROM public.entregas WHERE id=pickup),'generated Brasília timestamp');
 PERFORM pg_temp.check_rule((SELECT tempo_atendimento_previsto_min=10 AND coleta_origem_id=pickup FROM public.entregas WHERE id=delivery),'duration and dependency persisted');
 r:=public.enviar_pedidos_motorista(payload);
 PERFORM pg_temp.check_rule(r->>'idempotente'='true' AND (SELECT count(*)=2 FROM public.entregas WHERE rota_id=route),'dispatch retry creates no duplicates');
 r:=public.enviar_servicos_motorista(payload);
 PERFORM pg_temp.check_rule(r->>'codigo'='USE_ENVIO_PEDIDOS','legacy dispatch rejects silent rule loss');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET janela_fim=%L WHERE id=%L','08:00',pickup),'janela_planejada|não cabe','reversed window rejected');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET janela_data=NULL WHERE id=%L',pickup),'Informe a data','partial window rejected');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET tempo_atendimento_previsto_min=241 WHERE id=%L',pickup),'atendimento_previsto|não cabe','invalid service duration rejected');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET tipo_tarefa=%L WHERE id=%L','outros',pickup),'mesma empresa','wrong pickup type rejected at deferred constraint');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET coleta_origem_id=id WHERE id=%L',delivery),'mesma empresa','self dependency rejected');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET motorista_id=%L WHERE id=%L','f1000000-0000-0000-0000-000000000001',pickup),'mesma empresa','parent driver change cannot break dependency');
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO public.clientes_enderecos(empresa_id,nome_identificador,endereco_completo,numero,bairro,cidade,cep,latitude,longitude)
 VALUES('22222222-2222-2222-2222-222222222222','Outro','Rua teste','1','Centro','Palhoça','88132292',-27.63,-48.68) RETURNING id INTO other;
 INSERT INTO public.entregas(empresa_id,motorista_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,tipo_tarefa)
 VALUES('22222222-2222-2222-2222-222222222222','f1000000-0000-0000-0000-000000000001',other,'PL-CROSS','Outra coleta','coleta') RETURNING id INTO other;
 PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET coleta_origem_id=%L WHERE id=%L',other,delivery),'mesma empresa|coleta_origem_fk','cross company reference rejected');
 PERFORM pg_temp.reject_rule(format('SELECT ec_private.validar_agenda(ARRAY[%L,%L]::uuid[],NULL,%L,false)',pickup,delivery,departure),'Recalcule','missing agenda rejected');
 PERFORM pg_temp.reject_rule(format('SELECT ec_private.validar_agenda(ARRAY[%L,%L]::uuid[],%L::jsonb,%L,false)',pickup,delivery,agenda,now()-interval '1 hour'),'Recalcule','outdated departure rejected');
 PERFORM pg_temp.reject_rule(format('SELECT ec_private.validar_agenda(ARRAY[%L,%L]::uuid[],%L::jsonb,%L,false)',delivery,pickup,agenda,departure),'não corresponde','wrong agenda order rejected');
 PERFORM pg_temp.reject_rule(format('SELECT ec_private.validar_agenda(ARRAY[%L,%L]::uuid[],%L::jsonb,%L,false)',pickup,delivery,jsonb_set(agenda,'{1,fim_em}',to_jsonb(departure+interval '61 minutes')),departure),'não cabe','agenda must include whole service duration');
 PERFORM set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',true);
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET janela_fim=%L WHERE id=%L','13:00',pickup),'Somente a gestão','driver cannot change optional rules');
 r:=public.aceitar_pedidos_motorista(ARRAY[delivery]);
 SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
 PERFORM pg_temp.check_rule(r->>'sucesso'='true' AND (SELECT etapa='liberado' FROM public.pedidos_fluxo WHERE entrega_id=delivery),'dependent delivery may be accepted separately');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET chegada_em=now() WHERE id=%L',delivery),'Conclua a coleta','unaccepted pickup does not release arrival');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET status=%L WHERE id=%L','entregue',delivery),'Conclua a coleta','direct success cannot bypass pickup');
 r:=public.aceitar_pedidos_motorista(ARRAY[pickup]);
 UPDATE public.rotas_planejadas SET status='em_execucao' WHERE id=route;
 SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
 PERFORM pg_temp.check_rule((SELECT p.ordem_na_rota<d.ordem_na_rota FROM public.entregas p,public.entregas d WHERE p.id=pickup AND d.id=delivery),'partial acceptance preserves pickup before delivery');
 r:=public.reordenar_paradas_rota(route,ARRAY[delivery,pickup],ARRAY[pickup,delivery]);
 PERFORM pg_temp.check_rule(r->>'sucesso'='false' AND r->>'mensagem' LIKE '%coleta%','RPC refuses reversed dependency');
 PERFORM pg_temp.check_rule(ec_private.tracking_active(delivery,route,driver)=false,'tracking does not expose blocked delivery');
 UPDATE public.entregas SET status='tentativa_falha' WHERE id=pickup;
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET chegada_em=now() WHERE id=%L',delivery),'Conclua a coleta','failed pickup does not release delivery');
 UPDATE public.entregas SET status='entregue' WHERE id=pickup;
 PERFORM pg_temp.check_rule(ec_private.tracking_active(delivery,route,driver),'confirmed pickup releases only next tracking');
 UPDATE public.entregas SET chegada_em=now() WHERE id=delivery;
 PERFORM pg_temp.check_rule((SELECT chegada_em IS NOT NULL FROM public.entregas WHERE id=delivery),'confirmed pickup permits arrival even outside planned time');
 PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET janela_fim=%L WHERE id=%L','13:00',delivery),'iniciado','started service conditions immutable');
 UPDATE public.entregas SET status='entregue' WHERE id=delivery;
 PERFORM pg_temp.check_rule((SELECT status='entregue' FROM public.entregas WHERE id=delivery),'real outcome never blocked by lateness');
 PERFORM pg_temp.check_rule(NOT ec_private.tracking_active(delivery,route,driver),'completed delivery tracking ends');
 -- A failed dependency still permits recording the real failure of the delivery.
 UPDATE public.entregas SET status='tentativa_falha' WHERE id=pickup;
 UPDATE public.entregas SET status='tentativa_falha' WHERE id=delivery;
 PERFORM pg_temp.check_rule((SELECT status='tentativa_falha' FROM public.entregas WHERE id=delivery),'failure remains recordable after failed pickup');
 INSERT INTO public.entregas(empresa_id,motorista_id,cliente_endereco_id,codigo_rastreio,destinatario_nome)
 VALUES(company,driver,addr,'PL-LEGACY','Sem condições') RETURNING id INTO oldtask;
 PERFORM pg_temp.check_rule((SELECT janela_data IS NULL AND coleta_origem_id IS NULL AND tempo_atendimento_previsto_min=0 FROM public.entregas WHERE id=oldtask),'old no-rule insert unchanged');

 -- Merge a child first and its pickup later into an active route with a service in progress.
 UPDATE public.rotas_planejadas SET status='concluida' WHERE id=route;
 INSERT INTO public.rotas_planejadas(empresa_id,motorista_id,status,idempotency_key,distancia_original_km,tempo_original_minutos,distancia_otimizada_km,tempo_otimizado_minutos,percentual_economia_km,percentual_economia_tempo,ordem_paradas_json)
 VALUES(company,driver,'em_execucao','planning-active-merge',10,20,10,20,0,0,'[]') RETURNING id INTO active;
 UPDATE public.entregas SET rota_id=active,ordem_na_rota=1,chegada_em=now() WHERE id=oldtask;
 second_pickup:=gen_random_uuid();second_delivery:=gen_random_uuid();
 bad_payload:=payload||jsonb_build_object('idempotency_key','planning-partial-merge','agenda',NULL,'paradas',jsonb_build_array(
  jsonb_build_object('id',second_pickup,'cliente_endereco_id',addr,'destinatario_nome','Segunda coleta','tipo_tarefa','coleta','ordem_na_rota',1),
  jsonb_build_object('id',second_delivery,'cliente_endereco_id',addr,'destinatario_nome','Segunda entrega','tipo_tarefa','entrega','ordem_na_rota',2,'coleta_origem_id',second_pickup)));
 r:=public.enviar_pedidos_motorista(bad_payload);
 PERFORM pg_temp.check_rule(r->>'sucesso'='true','dependency-only dispatch requires no time fields');
 PERFORM set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',true);
 r:=public.aceitar_pedidos_motorista(ARRAY[second_delivery]);
 SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
 PERFORM pg_temp.check_rule(r->>'rota_id'=active::text,'dependent child merges into current work');
 PERFORM pg_temp.reject_rule(format('UPDATE public.entregas SET chegada_em=now() WHERE id=%L',second_delivery),'Conclua a coleta','external offered pickup still blocks arrival');
 r:=public.aceitar_pedidos_motorista(ARRAY[second_pickup]);
 SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
 PERFORM pg_temp.check_rule((SELECT array_agg(id ORDER BY ordem_na_rota)=ARRAY[oldtask,second_pickup,second_delivery] FROM public.entregas WHERE rota_id=active),'late parent acceptance preserves started service and precedes child');
 r:=public.reordenar_paradas_rota(active,ARRAY[second_pickup,oldtask,second_delivery],ARRAY[oldtask,second_pickup,second_delivery]);
 PERFORM pg_temp.check_rule(r->>'sucesso'='false' AND r->>'mensagem' LIKE '%andamento%','started service cannot be displaced by manual reorder');
 r:=public.aceitar_pedidos_motorista(ARRAY[second_pickup,second_delivery]);
 PERFORM pg_temp.check_rule((SELECT count(*)=3 FROM public.entregas WHERE rota_id=active),'partial acceptance retries preserve all work without duplicates');
 PERFORM pg_temp.check_rule(NOT has_function_privilege('anon','public.obter_capacidades_rotas()','EXECUTE') AND NOT has_schema_privilege('authenticated','ec_private','USAGE'),'no new public access to private helpers');
 PERFORM pg_temp.check_rule(EXISTS(SELECT FROM pg_indexes WHERE schemaname='public' AND indexname='entregas_coleta_origem_idx'),'foreign key lookup indexed');
 SET CONSTRAINTS ALL IMMEDIATE;
END $$;
SELECT count(*) AS planning_passed FROM planning_checks;
ROLLBACK;
