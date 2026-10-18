-- Dados sintéticos para um PostgreSQL temporário. Nunca executar em produção.
INSERT INTO public.empresas(id,nome,cnpj,codigo_convite,ativa) VALUES
('11111111-1111-1111-1111-111111111111','Empresa teste A','TEST-A','TEST-A',true),
('22222222-2222-2222-2222-222222222222','Empresa teste B','TEST-B','TEST-B',true)
ON CONFLICT(id) DO UPDATE SET ativa=true;
INSERT INTO auth.users(id,email,raw_user_meta_data,role,aud) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','gestor-a@example.test','{"nome":"Gestor A"}','authenticated','authenticated'),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','gestor-b@example.test','{"nome":"Gestor B"}','authenticated','authenticated'),
('cccccccc-cccc-cccc-cccc-cccccccccccc','motorista-a@example.test','{"nome":"Condutor A"}','authenticated','authenticated'),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','sem-vinculo@example.test','{"nome":"Sem vínculo"}','authenticated','authenticated'),
('ffffffff-ffff-ffff-ffff-ffffffffffff','motorista-b@example.test','{"nome":"Condutor B"}','authenticated','authenticated'),
('99999999-9999-9999-9999-999999999999','candidato@example.test','{"nome":"Candidato"}','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.perfis_usuarios(id,email,nome)
SELECT id,email,raw_user_meta_data->>'nome' FROM auth.users
WHERE email LIKE '%@example.test' ON CONFLICT(id) DO NOTHING;
INSERT INTO public.motoristas(id,empresa_id,user_id,nome,telefone,veiculo_modelo,veiculo_placa,ativo) VALUES
('c1000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','cccccccc-cccc-cccc-cccc-cccccccccccc','Condutor A','000000000','Fiat Uno','ABC1D23',true),
('f1000000-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','ffffffff-ffff-ffff-ffff-ffffffffffff','Condutor B','000000000','Fiat Mobi','ABC1D24',true);
INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status,motorista_id) VALUES
('11111111-1111-1111-1111-111111111111','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','gestor','aprovado',null),
('22222222-2222-2222-2222-222222222222','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','gestor','aprovado',null),
('11111111-1111-1111-1111-111111111111','cccccccc-cccc-cccc-cccc-cccccccccccc','motorista','aprovado','c1000000-0000-0000-0000-000000000001'),
('22222222-2222-2222-2222-222222222222','ffffffff-ffff-ffff-ffff-ffffffffffff','motorista','aprovado','f1000000-0000-0000-0000-000000000001'),
('11111111-1111-1111-1111-111111111111','99999999-9999-9999-9999-999999999999','motorista','pendente',null);
INSERT INTO public.solicitacoes_acesso(empresa_id,user_id,papel_solicitado,status) VALUES ('11111111-1111-1111-1111-111111111111','99999999-9999-9999-9999-999999999999','motorista','pendente');
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',false);
SELECT public.cadastrar_meu_veiculo('{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo_veiculo":"carro","marca":"Fiat","modelo":"Uno","placa":"ABC1D23"}');
SELECT set_config('request.jwt.claim.sub','99999999-9999-9999-9999-999999999999',false);
SELECT public.cadastrar_meu_veiculo('{"empresa_id":"11111111-1111-1111-1111-111111111111","tipo_veiculo":"carro","marca":"Fiat","modelo":"Mobi","placa":"ABC1D25"}');
SELECT set_config('request.jwt.claim.sub','',false);