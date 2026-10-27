BEGIN;
CREATE TEMP TABLE trial_results(name text);
CREATE FUNCTION pg_temp.trial_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'TRIAL: %',label; END IF; INSERT INTO trial_results VALUES(label); END $$;
GRANT INSERT ON trial_results TO authenticated,service_role;
INSERT INTO auth.users(id,email,email_confirmed_at,raw_user_meta_data) VALUES
('ab000000-0000-0000-0000-000000000001','trial-a@example.test',now(),'{"full_name":"Trial A","empresa_nome":"Essenza Teste","papel":"admin","empresa_id":"22222222-2222-2222-2222-222222222222","teste_fim":"2099-01-01"}'),
('ab000000-0000-0000-0000-000000000002','trial-b@example.test',now(),'{"empresa_nome":"Outra Empresa"}'),
('ab000000-0000-0000-0000-000000000003','unconfirmed@example.test',null,'{"empresa_nome":"Não confirmada"}');
SELECT pg_temp.trial_check(NOT has_function_privilege('anon','public.iniciar_teste_empresa(text)','EXECUTE'),'anonymous cannot provision');
SELECT pg_temp.trial_check(NOT has_table_privilege('authenticated','ec_private.assinaturas_empresas','UPDATE'),'browser cannot extend subscription');
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT set_config('trial.a',(public.iniciar_teste_empresa()->>'empresa_id'),true);
SELECT pg_temp.trial_check(public.iniciar_teste_empresa('Another name')->>'empresa_id'=current_setting('trial.a'),'retry returns same company');
SELECT pg_temp.trial_check((SELECT count(*)=1 FROM public.empresas),'company A sees only its own company');
RESET ROLE;
SELECT pg_temp.trial_check(current_setting('trial.a')<>'22222222-2222-2222-2222-222222222222','metadata cannot select existing company');
SELECT pg_temp.trial_check((SELECT teste_fim=teste_inicio+interval '30 days' AND teste_fim<now()+interval '31 days' FROM ec_private.assinaturas_empresas WHERE empresa_id=current_setting('trial.a')::uuid),'server owns fixed 30-day validity');
SELECT pg_temp.trial_check((SELECT nome='Essenza Teste' AND cidade IS NULL FROM public.empresas WHERE id=current_setting('trial.a')::uuid),'display name saved without fabricated city');
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000002',true);
SET LOCAL ROLE authenticated;
SELECT set_config('trial.b',(public.iniciar_teste_empresa()->>'empresa_id'),true);
SELECT pg_temp.trial_check((SELECT count(*)=1 FROM public.empresas),'company B sees only its own company');
SELECT pg_temp.trial_check((SELECT count(*)=0 FROM public.empresas WHERE id=current_setting('trial.a')::uuid),'company B cannot read company A');
DO $$ BEGIN
 BEGIN PERFORM public.obter_minha_assinatura(current_setting('trial.a')::uuid); RAISE EXCEPTION 'Unexpected access';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.trial_check(true,'company B cannot read company A subscription'); END;
 BEGIN INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status) VALUES(current_setting('trial.a')::uuid,auth.uid(),'admin','aprovado'); RAISE EXCEPTION 'Unexpected insert';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.trial_check(true,'browser cannot self-approve foreign membership'); END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000003',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.iniciar_teste_empresa(); RAISE EXCEPTION 'Unexpected unconfirmed signup';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.trial_check(true,'unconfirmed e-mail cannot start trial'); END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','99999999-9999-9999-9999-999999999999',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.iniciar_teste_empresa('Escalation'); RAISE EXCEPTION 'Unexpected driver promotion';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.trial_check(true,'pending driver cannot become admin by onboarding'); END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.trial_check(public.obter_minha_assinatura(current_setting('trial.a')::uuid)->>'estado'='teste','new company starts in trial');
SELECT set_config('trial.address',(public.salvar_cliente_endereco(jsonb_build_object('empresa_id',current_setting('trial.a'),'nome','Cliente','endereco','Rua Teste 1','latitude',-27.5,'longitude',-48.5))->>'id'),true);
RESET ROLE;

-- Early subscription keeps the original trial date and does not grant paid access.
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000002',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.trial_check(public.consultar_checkout_assinatura(current_setting('trial.b')::uuid) IS NULL,'status lookup creates no checkout');
SELECT set_config('early.checkout',(public.preparar_checkout_assinatura(current_setting('trial.b')::uuid)->>'id'),true);
SELECT pg_temp.trial_check(public.preparar_checkout_assinatura(current_setting('trial.b')::uuid)->>'id'=current_setting('early.checkout'),'early retries reuse same checkout');
RESET ROLE;
SELECT pg_temp.trial_check((SELECT c.inicio_cobranca=a.teste_fim FROM ec_private.checkouts_assinatura c JOIN ec_private.assinaturas_empresas a USING(empresa_id) WHERE c.id=current_setting('early.checkout')::uuid),'first charge preserves exact trial end');
SELECT pg_temp.trial_check(NOT has_function_privilege('authenticated','public.sincronizar_assinatura_provedor(uuid,text,text,timestamptz,timestamptz,timestamptz,text)','EXECUTE'),'browser cannot confirm recurring contract');
SELECT set_config('early.end',(SELECT teste_fim::text FROM ec_private.assinaturas_empresas WHERE empresa_id=current_setting('trial.b')::uuid),true);
SELECT set_config('request.jwt.claim.role','service_role',true);
SET LOCAL ROLE service_role;
SELECT public.vincular_checkout_assinatura(current_setting('early.checkout')::uuid,'early-sub','https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=early-sub');
SELECT public.sincronizar_assinatura_provedor(current_setting('early.checkout')::uuid,'early-sub','authorized',now(),current_setting('early.end')::timestamptz,NULL,'production');
RESET ROLE;
SELECT pg_temp.trial_check((SELECT pago_ate IS NULL FROM ec_private.assinaturas_empresas WHERE empresa_id=current_setting('trial.b')::uuid),'authorization alone grants no paid coverage');
SET LOCAL ROLE authenticated;
SELECT pg_temp.trial_check(public.obter_minha_assinatura(current_setting('trial.b')::uuid)->>'checkout_estado'='authorized','manager sees confirmed contract during trial');
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.sincronizar_assinatura_provedor(current_setting('early.checkout')::uuid,'early-sub','authorized',now()+interval '1 second',now(),NULL,'production'); RAISE EXCEPTION 'Unexpected early charge';
 EXCEPTION WHEN invalid_parameter_value THEN PERFORM pg_temp.trial_check(true,'provider cannot shorten trial'); END;
END $$;
SELECT public.sincronizar_assinatura_provedor(current_setting('early.checkout')::uuid,'early-sub','cancelled',now()+interval '2 seconds',current_setting('early.end')::timestamptz,NULL,'production');
SELECT public.sincronizar_assinatura_provedor(current_setting('early.checkout')::uuid,'early-sub','authorized',now()+interval '1 second',current_setting('early.end')::timestamptz,NULL,'production');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.trial_check(public.obter_minha_assinatura(current_setting('trial.b')::uuid)->>'checkout_estado'='cancelled','old webhook cannot restore cancelled contract');
SELECT pg_temp.trial_check(public.preparar_checkout_assinatura(current_setting('trial.b')::uuid)->>'id'<>current_setting('early.checkout'),'cancelled contract can be replaced without deleting payment history');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);

-- Privileged fixtures retain JWT context to exercise triggers beneath definer RPCs.
INSERT INTO public.motoristas(empresa_id,nome,telefone,veiculo_modelo,veiculo_placa)
SELECT current_setting('trial.a')::uuid,'Driver '||g,'000000000','Teste','TRIAL'||g FROM generate_series(1,3) g;
DO $$ BEGIN
 BEGIN INSERT INTO public.motoristas(empresa_id,nome,telefone,veiculo_modelo,veiculo_placa) VALUES(current_setting('trial.a')::uuid,'Fourth','000','Teste','FOURTH'); RAISE EXCEPTION 'Unexpected fourth driver';
 EXCEPTION WHEN check_violation THEN PERFORM pg_temp.trial_check(true,'fourth active driver denied below RPC layer'); END;
END $$;
INSERT INTO public.entregas(empresa_id,codigo_rastreio,cliente_endereco_id,destinatario_nome)
SELECT current_setting('trial.a')::uuid,'TRIAL-'||g,current_setting('trial.address')::uuid,'Cliente' FROM generate_series(1,1000) g;
DO $$ BEGIN
 BEGIN INSERT INTO public.entregas(empresa_id,codigo_rastreio,cliente_endereco_id,destinatario_nome) VALUES(current_setting('trial.a')::uuid,'OVER',current_setting('trial.address')::uuid,'Cliente'); RAISE EXCEPTION 'Unexpected quota excess';
 EXCEPTION WHEN check_violation THEN PERFORM pg_temp.trial_check(true,'1001st monthly attendance denied atomically'); END;
END $$;
DELETE FROM public.entregas WHERE empresa_id=current_setting('trial.a')::uuid AND codigo_rastreio='TRIAL-1';
SELECT pg_temp.trial_check((SELECT atendimentos=1000 FROM ec_private.uso_plano WHERE empresa_id=current_setting('trial.a')::uuid),'deleting attendance does not reset usage');
UPDATE ec_private.assinaturas_empresas SET teste_inicio=now()-interval '31 days',teste_fim=now()-interval '1 day' WHERE empresa_id=current_setting('trial.a')::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.trial_check(public.obter_minha_assinatura(current_setting('trial.a')::uuid)->>'operacional'='false','server detects expiration without scheduled job');
SELECT pg_temp.trial_check((SELECT count(*)=1 FROM public.clientes_enderecos WHERE id=current_setting('trial.address')::uuid),'read access remains after expiration');
DO $$ BEGIN
 BEGIN PERFORM public.salvar_cliente_endereco(jsonb_build_object('empresa_id',current_setting('trial.a'),'nome','Blocked','endereco','Rua Teste 2','latitude',-27.5,'longitude',-48.5)); RAISE EXCEPTION 'Unexpected expired operation';
 EXCEPTION WHEN insufficient_privilege THEN PERFORM pg_temp.trial_check(true,'old RPC cannot operate after trial expires'); END;
END $$;
SELECT pg_temp.trial_check(public.iniciar_teste_empresa()->>'empresa_id'=current_setting('trial.a'),'expired account cannot restart trial by provisioning again');
RESET ROLE;
SELECT pg_temp.trial_check(NOT has_function_privilege('authenticated','public.registrar_pagamento_assinatura(uuid,text,text,text,numeric,text,timestamptz,timestamptz,text)','EXECUTE'),'browser cannot activate paid access');
SET LOCAL ROLE authenticated;
SELECT set_config('trial.checkout',(public.preparar_checkout_assinatura(current_setting('trial.a')::uuid)->>'id'),true);
SELECT pg_temp.trial_check(public.preparar_checkout_assinatura(current_setting('trial.a')::uuid)->>'id'=current_setting('trial.checkout'),'checkout retries share the same idempotency key');
RESET ROLE;
SELECT set_config('request.jwt.claim.role','service_role',true);
SET LOCAL ROLE service_role;
SELECT public.vincular_checkout_assinatura(current_setting('trial.checkout')::uuid,'test-preapproval','https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=test-preapproval');
SELECT public.registrar_pagamento_assinatura(current_setting('trial.checkout')::uuid,'test-preapproval','12345','pending',149.90,'BRL',null,now());
RESET ROLE;
SELECT pg_temp.trial_check(NOT ec_private.empresa_assinatura_liberada(current_setting('trial.a')::uuid),'pending checkout does not activate access');
SET LOCAL ROLE service_role;
SELECT public.registrar_pagamento_assinatura(current_setting('trial.checkout')::uuid,'test-preapproval','12345','approved',149.90,'BRL',now(),now()+interval '1 second');
RESET ROLE;
SELECT pg_temp.trial_check(ec_private.empresa_assinatura_liberada(current_setting('trial.a')::uuid),'confirmed payment activates expired company');
SELECT set_config('trial.coverage',(SELECT pago_ate::text FROM ec_private.assinaturas_empresas WHERE empresa_id=current_setting('trial.a')::uuid),true);
SET LOCAL ROLE service_role;
SELECT public.registrar_pagamento_assinatura(current_setting('trial.checkout')::uuid,'test-preapproval','12345','approved',149.90,'BRL',now(),now()+interval '1 second');
RESET ROLE;
SELECT pg_temp.trial_check((SELECT pago_ate=current_setting('trial.coverage')::timestamptz FROM ec_private.assinaturas_empresas WHERE empresa_id=current_setting('trial.a')::uuid),'duplicate notification never extends another month');
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.registrar_pagamento_assinatura(current_setting('trial.checkout')::uuid,'test-preapproval','777','approved',1,'BRL',now(),now()); RAISE EXCEPTION 'Unexpected wrong amount';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_pagamento_assinatura(current_setting('trial.checkout')::uuid,'foreign-subscription','778','approved',149.90,'BRL',now(),now()); RAISE EXCEPTION 'Unexpected foreign subscription';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT public.registrar_pagamento_assinatura(current_setting('trial.checkout')::uuid,'test-preapproval','12345','refunded',149.90,'BRL',now(),now()+interval '2 seconds');
SELECT public.registrar_pagamento_assinatura(current_setting('trial.checkout')::uuid,'test-preapproval','12345','approved',149.90,'BRL',now(),now()+interval '1 second');
RESET ROLE;
SELECT pg_temp.trial_check(NOT ec_private.empresa_assinatura_liberada(current_setting('trial.a')::uuid),'refund removes access and old notification cannot restore it');
SELECT pg_temp.trial_check((SELECT count(*)=1 FROM ec_private.pagamentos_assinatura),'invalid amount and foreign subscription are never credited');
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.trial_check(public.obter_minha_assinatura('11111111-1111-1111-1111-111111111111')->>'legado'='true','existing company retains access without forced trial');
RESET ROLE;
SELECT count(*)::integer AS trial_passed FROM trial_results;
ROLLBACK;
