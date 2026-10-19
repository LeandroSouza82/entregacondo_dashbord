-- Testes relacionais de metadados: não criam binários nem usam a API HTTP do Storage.
-- Executar somente em Supabase local/staging isolado, ou via npm run test:db.
BEGIN;
CREATE TEMP TABLE regression_results(name text NOT NULL);
CREATE FUNCTION pg_temp.check_result(ok boolean, message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'REGRESSÃO: %',message; END IF;
    INSERT INTO regression_results VALUES(message);
END $$;
DO $tests$
DECLARE
    company_a uuid := '11111111-1111-1111-1111-111111111111';
    company_b uuid := '22222222-2222-2222-2222-222222222222';
    driver_a uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    admin_a uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    admin_b uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    outsider uuid := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
    candidate uuid := '99999999-9999-9999-9999-999999999999';
    car_id uuid; candidate_car uuid; doc_id uuid; front_id uuid;
    fila_id uuid; request_id uuid; addr_id uuid; route_id uuid; delivery_id uuid;
    reservation jsonb; result jsonb; claim record; claim2 record;
    angle text; storage_path_value text; count_before bigint; count_after bigint; revision int;
    expected_denial boolean; n int;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
    result := public.salvar_cliente_endereco(jsonb_build_object('empresa_id',company_a,'nome_identificador','Novo cliente','endereco_completo','Endereço informado','latitude',-27.5,'longitude',-48.5));
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'gestor salva endereço pelo RPC');
    result := public.salvar_cliente_endereco(jsonb_build_object('empresa_id',company_b,'nome_identificador','Outra empresa','endereco_completo','Endereço informado','latitude',-27.5,'longitude',-48.5));
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean=false,'gestor não grava cliente de outra empresa');
    PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
    result := public.salvar_cliente_endereco(jsonb_build_object('empresa_id',company_a,'nome_identificador','Sem vínculo','endereco_completo','Endereço informado','latitude',-27.5,'longitude',-48.5));
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean=false,'conta sem vínculo não grava cliente');
    PERFORM set_config('request.jwt.claim.sub',driver_a::text,true);
    SELECT id INTO car_id FROM public.veiculos_motoristas WHERE user_id=driver_a;
    PERFORM pg_temp.check_result(car_id IS NOT NULL,'cadastro funciona após instalação/atualização');
    PERFORM pg_temp.check_result(
        NOT has_function_privilege('anon','public.iniciar_rota(uuid)','EXECUTE')
        AND NOT has_function_privilege('anon','public.concluir_rota(uuid)','EXECUTE')
        AND NOT has_function_privilege('anon','public.registrar_limpeza_storage_executada(uuid,uuid,boolean,text)','EXECUTE'),
        'anon não executa RPCs sensíveis');
    PERFORM pg_temp.check_result(
        to_regprocedure('public.registrar_limpeza_storage_executada(uuid,boolean,text)') IS NULL
        AND to_regprocedure('public.reivindicar_itens_limpeza_storage(integer)') IS NULL,
        'assinaturas antigas de limpeza foram removidas');

    PERFORM pg_temp.check_result(NOT has_function_privilege('anon','public.bootstrap_primeiro_gestor(text,text,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public.bootstrap_primeiro_gestor(text,text,text)','EXECUTE'),
        'bootstrap administrativo restrito à service_role');
    PERFORM pg_temp.check_result(to_regprocedure('public.aprovar_solicitacao_motorista(uuid,uuid)') IS NULL,
        'aprovação legada de dois argumentos não pode contornar o contrato');

    PERFORM set_config('request.jwt.claim.sub',driver_a::text,true);
    FOREACH angle IN ARRAY ARRAY['frente','lado_direito','lado_esquerdo','traseira'] LOOP
        reservation:=public.reservar_upload_evidencia(company_a,'foto_veiculo',angle||'.jpg',angle);
        PERFORM pg_temp.check_result((reservation->>'sucesso')::boolean,'reserva de foto '||angle);
        storage_path_value:=reservation->>'storage_path';
        -- Fixture SQL de metadados sob o papel real da política.
        PERFORM set_config('role','authenticated',true);
        INSERT INTO storage.objects(bucket_id,name,metadata)
        VALUES('veiculos-documentos',storage_path_value,'{"size":500,"mimetype":"image/jpeg"}');
        PERFORM set_config('role','postgres',true);
        result:=public.anexar_documento_veiculo(car_id,'foto_veiculo',angle||'.jpg',storage_path_value,500,angle);
        PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'anexação reservada '||angle);
        IF angle='frente' THEN front_id:=(result->>'documento_id')::uuid; END IF;
    END LOOP;
    reservation:=public.reservar_upload_evidencia(company_a,'crlv','crlv.pdf');
    storage_path_value:=reservation->>'storage_path';
    INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('veiculos-documentos',storage_path_value,'{"size":500,"mimetype":"application/pdf"}');
    result:=public.anexar_documento_veiculo(car_id,'crlv','crlv.pdf',storage_path_value,500);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'CRLV reservado vinculado');
    doc_id:=(result->>'documento_id')::uuid;
    PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
    SELECT revisao INTO revision FROM public.veiculos_motoristas WHERE id=car_id;
    result:=public.analisar_veiculo_motorista(car_id,true,revision-1);
    PERFORM pg_temp.check_result(result->>'codigo'='REVISAO_DESATUALIZADA','aprovação recusa revisão antiga');
    result:=public.analisar_veiculo_motorista(car_id,true,revision);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'veículo completo pode ser aprovado');

    -- Uma confirmação não pode mudar uma reserva nem um arquivo vinculado.
    PERFORM set_config('request.jwt.claim.sub',driver_a::text,true);
    SELECT id INTO fila_id FROM public.storage_limpeza_fila WHERE storage_path=storage_path_value;
    result:=public.registrar_limpeza_storage_executada(fila_id,gen_random_uuid(),true);
    PERFORM pg_temp.check_result(result->>'codigo'='CLAIM_INVALIDO'
        AND (SELECT status='vinculado' FROM public.storage_limpeza_fila WHERE id=fila_id),
        'confirmação não altera evidência vinculada');
    reservation:=public.reservar_upload_evidencia(company_a,'complementar','reserva.pdf');
    result:=public.registrar_limpeza_storage_executada((reservation->>'fila_id')::uuid,gen_random_uuid(),false);
    PERFORM pg_temp.check_result(result->>'codigo'='CLAIM_INVALIDO','confirmação não altera reserva');

    PERFORM set_config('role','authenticated',true);
    DELETE FROM storage.objects WHERE name=storage_path_value AND bucket_id='veiculos-documentos';
    GET DIAGNOSTICS n=ROW_COUNT;
    PERFORM set_config('role','postgres',true);
    PERFORM pg_temp.check_result(n=0,'RLS bloqueia DELETE de evidência vinculada');
    PERFORM set_config('role','authenticated',true);
    UPDATE storage.objects SET metadata='{"size":1}' WHERE name=storage_path_value;
    GET DIAGNOSTICS n=ROW_COUNT;
    PERFORM set_config('role','postgres',true);
    PERFORM pg_temp.check_result(n=0,'RLS bloqueia sobrescrita');

    result:=public.remover_documento_veiculo(doc_id);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean
        AND (SELECT status_analise='pendente' FROM public.veiculos_motoristas WHERE id=car_id),
        'desvincular CRLV invalida aprovação');
    fila_id:=(result->>'fila_id')::uuid;
    result:=public.remover_documento_veiculo(doc_id);
    PERFORM pg_temp.check_result(result->>'codigo'='DOCUMENTO_NAO_ENCONTRADO','remoção repetida não reabre fila');
    PERFORM set_config('role','authenticated',true);
    DELETE FROM storage.objects WHERE name=storage_path_value;
    GET DIAGNOSTICS n=ROW_COUNT;
    PERFORM set_config('role','postgres',true);
    PERFORM pg_temp.check_result(n=0,'DELETE exige reivindicação prévia');
    SELECT * INTO claim FROM public.reivindicar_itens_limpeza_storage(1,fila_id);
    PERFORM pg_temp.check_result(claim.claim_token IS NOT NULL AND claim.tentativas=1,'claim identifica e conta tentativa');
    result:=public.registrar_limpeza_storage_executada(fila_id,claim.claim_token,true);
    PERFORM pg_temp.check_result(result->>'codigo'='OBJETO_AINDA_PRESENTE','não confirma remoção enquanto metadado existe');
    PERFORM set_config('role','authenticated',true);
    DELETE FROM storage.objects WHERE name=storage_path_value;
    GET DIAGNOSTICS n=ROW_COUNT;
    PERFORM set_config('role','postgres',true);
    PERFORM pg_temp.check_result(n=1,'RLS permite DELETE pelo responsável durante lease');
    result:=public.registrar_limpeza_storage_executada(fila_id,claim.claim_token,true);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean AND result->>'status'='concluido','confirma remoção com token atual');
    result:=public.registrar_limpeza_storage_executada(fila_id,claim.claim_token,false,'resposta repetida');
    PERFORM pg_temp.check_result(result->>'codigo'='JA_CONCLUIDO'
        AND (SELECT tentativas=1 FROM public.storage_limpeza_fila WHERE id=fila_id),
        'repetição não reabre concluído nem conta outra tentativa');

    reservation:=public.reservar_upload_evidencia(company_a,'complementar','falha.pdf');
    fila_id:=(reservation->>'fila_id')::uuid;
    result:=public.descartar_evidencia_temporaria(reservation->>'storage_path');
    UPDATE public.storage_limpeza_fila SET max_tentativas=2 WHERE id=fila_id;
    SELECT * INTO claim FROM public.reivindicar_itens_limpeza_storage(1,fila_id);
    UPDATE public.storage_limpeza_fila SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE id=fila_id;
    SELECT * INTO claim2 FROM public.reivindicar_itens_limpeza_storage(1,fila_id);
    result:=public.registrar_limpeza_storage_executada(fila_id,claim.claim_token,false,'retorno antigo');
    PERFORM pg_temp.check_result(result->>'codigo'='CLAIM_INVALIDO'
        AND (SELECT claim_token=claim2.claim_token AND status='em_processamento' FROM public.storage_limpeza_fila WHERE id=fila_id),
        'token antigo não altera tentativa recuperada');
    result:=public.registrar_limpeza_storage_executada(fila_id,claim2.claim_token,false,'HTTP indisponível');
    PERFORM pg_temp.check_result(result->>'status'='falhou','interrupção e falha consomem limite');
    result:=public.anexar_documento_veiculo(car_id,'complementar','falha.pdf',reservation->>'storage_path',500);
    PERFORM pg_temp.check_result(result->>'codigo'='ARQUIVO_DESCARTADO','falhou não permite reutilizar caminho');
    result:=public.retomar_limpeza_falha(fila_id);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean
        AND (SELECT claim_token IS NULL AND tentativas=0 FROM public.storage_limpeza_fila WHERE id=fila_id),
        'retomada invalida token anterior e preserva auditoria');
    PERFORM pg_temp.check_result((SELECT count(*)>=3 FROM public.auditoria_acessos WHERE detalhes->>'fila_id'=fila_id::text),'tentativas e retomada possuem auditoria');

    reservation:=public.reservar_upload_evidencia(company_a,'complementar','descartado.pdf');
    result:=public.descartar_evidencia_temporaria(reservation->>'storage_path');
    result:=public.anexar_documento_veiculo(car_id,'complementar','descartado.pdf',reservation->>'storage_path',500);
    PERFORM pg_temp.check_result(result->>'codigo'='ARQUIVO_EM_LIMPEZA','descarte impede vinculação posterior');

    -- Isolamento e preservação dos documentos na troca de empresa.
    INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status) VALUES(company_b,driver_a,'motorista','pendente');
    INSERT INTO public.solicitacoes_acesso(empresa_id,user_id,papel_solicitado,status) VALUES(company_b,driver_a,'motorista','pendente');
    result:=public.cadastrar_meu_veiculo(jsonb_build_object('empresa_id',company_b,'tipo_veiculo','carro','marca','X','modelo','Y','placa','ABC1D23'));
    PERFORM pg_temp.check_result(result->>'codigo'='VEICULO_OUTRA_EMPRESA'
        AND (SELECT empresa_id=company_a FROM public.veiculos_motoristas WHERE id=car_id)
        AND (SELECT count(*)=4 FROM public.veiculos_documentos WHERE veiculo_id=car_id AND empresa_id=company_a),
        'troca de empresa recusa e preserva veículo e quatro fotos');
    result:=public.cadastrar_meu_veiculo('{"tipo_veiculo":"carro","marca":"X","modelo":"Y","placa":"ABC1D23"}');
    PERFORM pg_temp.check_result(result->>'codigo'='EMPRESA_OBRIGATORIA','vários vínculos exigem empresa explícita');

    -- Recusa de aprovação não deixa cadastro parcial.
    SELECT id INTO candidate_car FROM public.veiculos_motoristas WHERE user_id=candidate;
    INSERT INTO public.solicitacoes_acesso(empresa_id,user_id,papel_solicitado,status)
    VALUES(company_a,candidate,'motorista','pendente') ON CONFLICT(empresa_id,user_id) DO UPDATE SET status='pendente' RETURNING id INTO request_id;
    SELECT count(*) INTO count_before FROM public.motoristas;
    PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
    result:=public.aprovar_solicitacao_motorista(request_id,null,true,'Candidato','000',true,99);
    SELECT count(*) INTO count_after FROM public.motoristas;
    PERFORM pg_temp.check_result(result->>'codigo'='REVISAO_DESATUALIZADA' AND count_before=count_after,'aprovação recusada não cria motorista');
    result:=public.aprovar_solicitacao_motorista(request_id,null,true,'Candidato','000',true,null);
    PERFORM pg_temp.check_result(result->>'codigo'='REVISAO_OBRIGATORIA','aprovação do veículo exige revisão');
    INSERT INTO public.solicitacoes_acesso(empresa_id,user_id,papel_solicitado,status)
    VALUES(company_b,candidate,'motorista','pendente') RETURNING id INTO request_id;
    PERFORM set_config('request.jwt.claim.sub',admin_b::text,true);
    result:=public.aprovar_solicitacao_motorista(request_id,null,true,'Candidato','000',true,1);
    PERFORM pg_temp.check_result(result->>'codigo'='VEICULO_OUTRA_EMPRESA','gestor B não aprova veículo de A');

    -- Rotas: usuário sem motorista, gestor de outra empresa e veículo pendente.
    INSERT INTO public.clientes_enderecos(empresa_id,nome_identificador,endereco_completo,numero,bairro,cidade,cep,latitude,longitude)
    VALUES(company_a,'Condomínio teste','Rua teste','1','Centro','Cidade teste','00000000',0,0) RETURNING id INTO addr_id;
    INSERT INTO public.rotas_planejadas(empresa_id,motorista_id,idempotency_key,distancia_original_km,tempo_original_minutos,distancia_otimizada_km,tempo_otimizado_minutos,percentual_economia_km,percentual_economia_tempo,ordem_paradas_json)
    VALUES(company_a,'c1000000-0000-0000-0000-000000000001','regression',1,1,1,1,0,0,'[]') RETURNING id INTO route_id;
    INSERT INTO public.entregas(empresa_id,codigo_rastreio,cliente_endereco_id,destinatario_nome,motorista_id,rota_id,status)
    VALUES(company_a,'TEST-1',addr_id,'Teste','c1000000-0000-0000-0000-000000000001',route_id,'atribuida') RETURNING id INTO delivery_id;
    PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
    result:=public.iniciar_rota(route_id);
    PERFORM pg_temp.check_result(result->>'codigo'='ACESSO_NEGADO','usuário sem motorista não inicia rota');
    result:=public.concluir_rota(route_id);
    PERFORM pg_temp.check_result(result->>'codigo'='ACESSO_NEGADO','usuário sem motorista não conclui rota');
    result:=public.registrar_conclusao_entrega(delivery_id,true);
    PERFORM pg_temp.check_result(result->>'codigo'='ACESSO_NEGADO','usuário sem motorista não baixa entrega');
    PERFORM set_config('request.jwt.claim.sub',admin_b::text,true);
    result:=public.iniciar_rota(route_id);
    PERFORM pg_temp.check_result(result->>'codigo'='ACESSO_NEGADO','gestor de outra empresa não opera rota');
    PERFORM set_config('request.jwt.claim.sub',driver_a::text,true);
    result:=public.iniciar_rota(route_id);
    PERFORM pg_temp.check_result(result->>'codigo'='ACESSO_NEGADO','veículo pendente não é liberado para operar');

    -- Recompor o CRLV por nova reserva e aprovar; o motorista correto passa.
    reservation:=public.reservar_upload_evidencia(company_a,'crlv','novo-crlv.pdf');
    storage_path_value:=reservation->>'storage_path';
    INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('veiculos-documentos',storage_path_value,'{"size":500,"mimetype":"application/pdf"}');
    result:=public.anexar_documento_veiculo(car_id,'crlv','novo-crlv.pdf',storage_path_value,500);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'novo CRLV usa caminho novo');
    SELECT revisao INTO revision FROM public.veiculos_motoristas WHERE id=car_id;
    PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
    result:=public.analisar_veiculo_motorista(car_id,true,revision);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'reaprovação após recomposição do CRLV');
    PERFORM set_config('request.jwt.claim.sub',driver_a::text,true);
    PERFORM set_config('role','authenticated',true);
    result:=public.iniciar_rota(route_id);
    PERFORM set_config('role','postgres',true);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'motorista atribuído e veículo aprovado inicia rota');
    -- Reorder security and stale-edit protection, using the approved test driver.
    DECLARE
      extra_id uuid; done_id uuid; expected uuid[]; reordered uuid[];
    BEGIN
      UPDATE public.entregas SET ordem_na_rota=1 WHERE id=delivery_id;
      INSERT INTO public.entregas(empresa_id,codigo_rastreio,cliente_endereco_id,destinatario_nome,motorista_id,rota_id,status,ordem_na_rota)
      VALUES(company_a,'REORDER-2',addr_id,'Second','c1000000-0000-0000-0000-000000000001',route_id,'atribuida',2) RETURNING id INTO extra_id;
      INSERT INTO public.entregas(empresa_id,codigo_rastreio,cliente_endereco_id,destinatario_nome,motorista_id,rota_id,status,ordem_na_rota)
      VALUES(company_a,'REORDER-DONE',addr_id,'Done','c1000000-0000-0000-0000-000000000001',route_id,'entregue',3) RETURNING id INTO done_id;
      expected:=ARRAY[delivery_id,extra_id]; reordered:=ARRAY[extra_id,delivery_id];
      PERFORM set_config('request.jwt.claim.sub',admin_b::text,true);
      result:=public.reordenar_paradas_rota(route_id,reordered,expected);
      PERFORM pg_temp.check_result(result->>'sucesso'='false','other company cannot reorder route');
      PERFORM set_config('request.jwt.claim.sub',driver_a::text,true);
      result:=public.reordenar_paradas_rota(route_id,ARRAY[delivery_id,delivery_id],expected);
      PERFORM pg_temp.check_result(result->>'sucesso'='false','duplicate or missing stop rejected');
      result:=public.reordenar_paradas_rota(route_id,reordered,expected,'{"latitude":-27.5,"longitude":-48.5,"retornar_ao_inicio":true,"metodo":"circuito_2opt"}');
      PERFORM pg_temp.check_result((SELECT configuracao_navegacao->>'metodo'='circuito_2opt' FROM public.rotas_planejadas WHERE id=route_id),'driver origin persisted with route order');
      PERFORM pg_temp.check_result(result->>'sucesso'='true' AND (SELECT ordem_na_rota=1 FROM public.entregas WHERE id=extra_id),'assigned driver persists new order');
      result:=public.reordenar_paradas_rota(route_id,expected,expected);
      PERFORM pg_temp.check_result(result->>'codigo'='ORDEM_DESATUALIZADA','stale reorder cannot overwrite current order');
      PERFORM pg_temp.check_result((SELECT ordem_na_rota=3 FROM public.entregas WHERE id=done_id),'completed stop position preserved');
      PERFORM pg_temp.check_result((SELECT ordem_paradas_json->0->>'id'=extra_id::text FROM public.rotas_planejadas WHERE id=route_id),'route snapshot agrees with delivery order');
      PERFORM pg_temp.check_result(NOT has_function_privilege('anon','public.reordenar_paradas_rota(uuid,uuid[],uuid[],jsonb)','EXECUTE'),'anonymous reorder blocked');
      result:=public.reordenar_paradas_rota(route_id,reordered,reordered,'{"latitude":-27.5,"longitude":-48.5,"retornar_ao_inicio":true,"metodo":"circuito_2opt","metricas":{"fonte":"mapbox_directions_restante","distancia_km":32.5,"tempo_minutos":130}}');
      PERFORM pg_temp.check_result(result->>'sucesso'='true' AND (SELECT metricas_fonte='mapbox_directions_restante' AND distancia_otimizada_km=32.5 AND metricas_atualizadas_em IS NOT NULL FROM public.rotas_planejadas WHERE id=route_id),'reorder persists new verified road metrics atomically');
      result:=public.reordenar_paradas_rota(route_id,reordered,reordered);
      PERFORM pg_temp.check_result((SELECT metricas_fonte IS NULL AND metricas_atualizadas_em IS NULL FROM public.rotas_planejadas WHERE id=route_id),'reorder without calculation invalidates old estimates');
      UPDATE public.entregas SET status='entregue' WHERE id=extra_id;
    END;
    UPDATE public.empresa_membros SET status='suspenso' WHERE user_id=driver_a AND empresa_id=company_a;
    result:=public.registrar_conclusao_entrega(delivery_id,true);
    PERFORM pg_temp.check_result(result->>'codigo'='ACESSO_NEGADO','suspensão impede baixa de entrega');
    UPDATE public.empresa_membros SET status='aprovado' WHERE user_id=driver_a AND empresa_id=company_a;
    result:=public.registrar_conclusao_entrega(delivery_id,true);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'motorista autorizado registra entrega');
    DECLARE
      failure_id uuid; hist_before integer; count_before integer; mean_before numeric;
    BEGIN
      SELECT count(*) INTO hist_before FROM public.historico_atendimentos WHERE entrega_id=delivery_id;
      SELECT total_entregas_realizadas,tempo_medio_minutos INTO count_before,mean_before FROM public.clientes_enderecos WHERE id=addr_id;
      PERFORM set_config('role','authenticated',true);
      result:=public.registrar_conclusao_entrega(delivery_id,true);
      PERFORM set_config('role','postgres',true);
      PERFORM pg_temp.check_result(result->>'codigo'='ENTREGA_JA_REGISTRADA' AND (SELECT count(*)=hist_before FROM public.historico_atendimentos WHERE entrega_id=delivery_id),'authenticated retry does not duplicate history');
      PERFORM pg_temp.check_result((SELECT total_entregas_realizadas=count_before AND tempo_medio_minutos=mean_before FROM public.clientes_enderecos WHERE id=addr_id),'retry preserves count and mean');
      result:=public.registrar_conclusao_entrega(delivery_id,false,'ausente');
      PERFORM pg_temp.check_result(result->>'codigo'='TRANSICAO_INVALIDA','conflicting completion outcome rejected');
      INSERT INTO public.entregas(empresa_id,codigo_rastreio,cliente_endereco_id,destinatario_nome,motorista_id,rota_id,status)
      VALUES(company_a,'COMPLETION-FAILURE',addr_id,'Failure','c1000000-0000-0000-0000-000000000001',route_id,'em_transito') RETURNING id INTO failure_id;
      result:=public.registrar_conclusao_entrega(failure_id,false,'  ');
      PERFORM pg_temp.check_result(result->>'codigo'='MOTIVO_OBRIGATORIO','blank failure reason rejected');
      result:=public.registrar_conclusao_entrega(failure_id,false,'ausente',0,0,now(),now()-interval '1 minute');
      PERFORM pg_temp.check_result(result->>'codigo'='HORARIO_INVALIDO','reversed arrival and completion rejected');
      PERFORM set_config('role','authenticated',true);
      result:=public.registrar_conclusao_entrega(failure_id,false,'Cliente ausente',0,0,now()-interval '5 minutes',now());
      PERFORM set_config('role','postgres',true);
      PERFORM pg_temp.check_result(result->>'sucesso'='true' AND (SELECT status='tentativa_falha' FROM public.entregas WHERE id=failure_id),'authenticated driver records failed attempt');
      PERFORM pg_temp.check_result((SELECT count(*)=1 AND bool_and(motivo_falha='Cliente ausente' AND NOT sucesso) FROM public.historico_atendimentos WHERE entrega_id=failure_id),'failure stores written reason exactly once');
    END;
    DECLARE
      proof_id uuid; t timestamptz:=now()-interval '95 seconds'; photo text; receipt jsonb;
    BEGIN
      INSERT INTO public.entregas(empresa_id,codigo_rastreio,cliente_endereco_id,destinatario_nome,motorista_id,rota_id,status)
      VALUES(company_a,'RECEIPT-TEST',addr_id,'Receipt','c1000000-0000-0000-0000-000000000001',route_id,'em_transito') RETURNING id INTO proof_id;
      result:=public.iniciar_atendimento_entrega(proof_id,t);
      PERFORM pg_temp.check_result(result->>'sucesso'='true','explicit arrival persisted');
      result:=public.iniciar_atendimento_entrega(proof_id,now());
      PERFORM pg_temp.check_result((result->>'chegada_em')::timestamptz=t,'arrival retry never resets timer');
      result:=public.concluir_atendimento_entrega(proof_id,true,t,now(),'{}');
      PERFORM pg_temp.check_result(result->>'sucesso'='false' AND (SELECT status='em_transito' FROM public.entregas WHERE id=proof_id),'receiver required before success');
      photo:=company_a::text||'/'||driver_a::text||'/'||proof_id::text||'/photo.jpg';
      receipt:=jsonb_build_object('recebedor_tipo','zelador','recebedor_nome','Pessoa de teste','foto_path',photo);
      result:=public.concluir_atendimento_entrega(proof_id,true,t,now(),receipt);
      PERFORM pg_temp.check_result(result->>'sucesso'='false','missing photo object rejected');
      INSERT INTO storage.objects(bucket_id,name) VALUES('entregas-comprovantes',photo);
      PERFORM set_config('role','authenticated',true);
      result:=public.concluir_atendimento_entrega(proof_id,true,t,now(),receipt);
      PERFORM set_config('role','postgres',true);
      PERFORM pg_temp.check_result(result->>'sucesso'='true' AND (SELECT duracao_segundos=95 AND recebedor_tipo='zelador' AND foto_path=photo FROM public.entrega_comprovantes WHERE entrega_id=proof_id),'receipt and exact elapsed seconds committed');
      result:=public.concluir_atendimento_entrega(proof_id,true,t,now(),jsonb_build_object('recebedor_tipo','vizinho'));
      PERFORM pg_temp.check_result(result->>'codigo'='ENTREGA_JA_REGISTRADA' AND (SELECT count(*)=1 FROM public.historico_atendimentos WHERE entrega_id=proof_id) AND (SELECT recebedor_tipo='zelador' FROM public.entrega_comprovantes WHERE entrega_id=proof_id),'receipt retry is immutable and idempotent');
      PERFORM set_config('request.jwt.claim.sub',admin_b::text,true);
      result:=public.iniciar_atendimento_entrega(proof_id,t);
      PERFORM pg_temp.check_result(result->>'sucesso'='false','foreign company cannot start attendance');
      PERFORM set_config('request.jwt.claim.sub',driver_a::text,true);
    END;
    result:=public.concluir_rota(route_id);
    PERFORM pg_temp.check_result((result->>'sucesso')::boolean,'motorista autorizado conclui rota atendida');
END $tests$;
SELECT count(*)::int AS passed, array_agg(name ORDER BY name) AS cases FROM regression_results;
ROLLBACK;