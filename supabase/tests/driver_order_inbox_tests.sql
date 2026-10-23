BEGIN;
DO $$
DECLARE company uuid:='11111111-1111-1111-1111-111111111111'; driver uuid:='c1000000-0000-0000-0000-000000000001';
 active uuid; batch uuid; addr uuid; oldtask uuid; delivery uuid; collection uuid; other uuid; r jsonb; blocked boolean:=false;
 car uuid; angle text; reservation jsonb; storage_path_value text; rev int; payload jsonb; offered uuid;
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
 INSERT INTO public.clientes_enderecos(empresa_id,nome_identificador,endereco_completo,numero,bairro,cidade,cep,latitude,longitude)
 VALUES(company,'Teste pedidos','Rua de teste','1','Centro','Florianópolis','88000000',-27.59,-48.54) RETURNING id INTO addr;
 INSERT INTO public.rotas_planejadas(empresa_id,motorista_id,status,idempotency_key,distancia_original_km,tempo_original_minutos,distancia_otimizada_km,tempo_otimizado_minutos,percentual_economia_km,percentual_economia_tempo,ordem_paradas_json) VALUES(company,driver,'em_execucao','inbox-active',10,20,10,20,0,0,'[]') RETURNING id INTO active;
 INSERT INTO public.rotas_planejadas(empresa_id,motorista_id,status,idempotency_key,distancia_original_km,tempo_original_minutos,distancia_otimizada_km,tempo_otimizado_minutos,percentual_economia_km,percentual_economia_tempo,ordem_paradas_json) VALUES(company,driver,'planejada','inbox-batch',10,20,10,20,0,0,'[]') RETURNING id INTO batch;
 INSERT INTO public.entregas(empresa_id,motorista_id,rota_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,status,ordem_na_rota)
 VALUES(company,driver,active,addr,'OLD-TEST','Antigo','em_transito',1) RETURNING id INTO oldtask;
 INSERT INTO public.entregas(empresa_id,motorista_id,rota_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,status,tipo_tarefa,ordem_na_rota,observacoes_gestor)
 VALUES(company,driver,batch,addr,'DEL-TEST','Entrega','atribuida','entrega',1,'Entregar ao zelador') RETURNING id INTO delivery;
 INSERT INTO public.entregas(empresa_id,motorista_id,rota_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,status,tipo_tarefa,ordem_na_rota)
 VALUES(company,driver,batch,addr,'COL-TEST','Coleta','atribuida','coleta',2) RETURNING id INTO collection;
 INSERT INTO public.entregas(empresa_id,motorista_id,rota_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,status,tipo_tarefa,ordem_na_rota)
 VALUES(company,driver,batch,addr,'OTH-TEST','Outros','atribuida','outros',3) RETURNING id INTO other;
 INSERT INTO public.pedidos_fluxo(entrega_id,empresa_id,motorista_id,lote_id) SELECT unnest(ARRAY[delivery,collection,other]),company,driver,batch;
 PERFORM set_config('request.jwt.claim.sub','ffffffff-ffff-ffff-ffff-ffffffffffff',true);
 BEGIN PERFORM public.aceitar_pedidos_motorista(ARRAY[delivery]); EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Outro motorista aceitou'; END IF;
 PERFORM set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',true);
 r:=public.aceitar_pedidos_motorista(ARRAY[delivery,collection,other]);
 IF r->>'rota_id'<>active::text THEN RAISE EXCEPTION 'Não juntou ao trabalho ativo'; END IF;
 IF (SELECT count(*) FROM public.entregas WHERE rota_id=active)<>4 THEN RAISE EXCEPTION 'Perdeu pedidos'; END IF;
 IF (SELECT etapa FROM public.pedidos_fluxo WHERE entrega_id=delivery)<>'aguardando_retirada' THEN RAISE EXCEPTION 'Entrega liberada cedo'; END IF;
 IF EXISTS(SELECT 1 FROM public.pedidos_fluxo WHERE entrega_id=ANY(ARRAY[collection,other]) AND etapa<>'liberado') THEN RAISE EXCEPTION 'Bloqueou coleta ou outros'; END IF;
 blocked:=false;
 BEGIN UPDATE public.entregas SET chegada_em=now() WHERE id=delivery; EXCEPTION WHEN OTHERS THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Atendeu sem retirar'; END IF;
 UPDATE public.entregas SET chegada_em=now() WHERE id=oldtask;
 PERFORM public.confirmar_retirada_pedidos(ARRAY[delivery]);
 UPDATE public.entregas SET chegada_em=now() WHERE id=delivery;
 IF (SELECT observacoes_gestor FROM public.entregas WHERE id=delivery)<>'Entregar ao zelador' THEN RAISE EXCEPTION 'Perdeu observação'; END IF;
 r:=public.aceitar_pedidos_motorista(ARRAY[delivery]);
 IF (SELECT etapa FROM public.pedidos_fluxo WHERE entrega_id=delivery)<>'liberado' THEN RAISE EXCEPTION 'Retentativa bloqueou entrega'; END IF;
 IF (SELECT count(*) FROM public.entregas WHERE rota_id=active)<>4 THEN RAISE EXCEPTION 'Retentativa duplicou'; END IF;
 PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
 payload:=jsonb_build_object('empresa_id',company,'motorista_id',driver,'idempotency_key','inbox-send',
 'distancia_original_km',10,'tempo_original_minutos',20,'distancia_otimizada_km',10,'tempo_otimizado_minutos',20,
 'percentual_economia_km',0,'percentual_economia_tempo',0,'ordem_paradas_json','[]'::jsonb,
 'paradas',jsonb_build_array(jsonb_build_object('cliente_endereco_id',addr,'destinatario_nome','Nova oferta','tipo_tarefa','entrega','observacoes_gestor','Avisar na portaria')));
 r:=public.enviar_pedidos_motorista(payload);
 IF r->>'sucesso' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Envio falhou: %',r; END IF;
 offered:=(r->>'nova_rota_id')::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f JOIN public.entregas e ON e.id=f.entrega_id WHERE e.rota_id=offered AND f.etapa='ofertado' AND e.observacoes_gestor='Avisar na portaria') THEN RAISE EXCEPTION 'Envio perdeu oferta ou observação'; END IF;
 r:=public.enviar_pedidos_motorista(payload);
 IF r->>'idempotente' IS DISTINCT FROM 'true' OR r->>'nova_rota_id'<>offered::text THEN RAISE EXCEPTION 'Envio repetido duplicou'; END IF;
 IF has_function_privilege('anon','public.aceitar_pedidos_motorista(uuid[])','EXECUTE') OR has_table_privilege('authenticated','public.pedidos_fluxo','UPDATE') THEN RAISE EXCEPTION 'Permissões excessivas'; END IF;
END $$;
ROLLBACK;
SELECT 10 AS inbox_passed;
