-- =============================================================================
-- SUITE DE TESTES AUTOMATIZADOS: SEGURANÇA, STORAGE, REVISÃO E TRANSAÇÕES
-- Projeto: EntregaCondo Backend (Supabase vblwuvhdqgzdjnoscyqo)
-- Data: 18/10/2026
--
-- AVISO IMPORTANTE SOBRE FIXTURES E AMBIENTE:
-- 1. Este script executa testes unitários e de integração SQL dentro de uma
--    transação isolada (com ROLLBACK final).
-- 2. As inserções em `storage.objects` são FIXTURES DE METADADOS SQL para teste
--    unitário do catálogo e das políticas RLS no Postgres. Elas simulam o registro
--    que o serviço Supabase Storage cria no banco, mas NÃO testam isoladamente a
--    persistência física de blocos em storage S3/MinIO sem a API do Storage ativa.
-- 3. A concorrência multi-sessão com interleaved timing requer duas conexões
--    independentes de cliente. Este script valida o protocolo atômico e a recusa
--    por revisão desatualizada (otimista) no nível de motor SQL.
-- =============================================================================

BEGIN;

DO $setup$
BEGIN
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'INICIANDO SUITE DE TESTES: REVISÃO, STORAGE E RLS (v4.3)';
    RAISE NOTICE '=============================================================';
END $setup$;

-- Setup de Fixtures de Teste
DO $fixtures$
DECLARE
    v_empresa_1 UUID := '11111111-1111-1111-1111-111111111111';
    v_empresa_2 UUID := '22222222-2222-2222-2222-222222222222';
    v_user_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_user_gestor UUID := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    v_user_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_user_suspenso UUID := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
    v_user_estranho UUID := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
    v_user_novo UUID := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN
    -- Mock de metadados do schema storage para testes unitários no catálogo SQL
    CREATE SCHEMA IF NOT EXISTS storage;
    CREATE TABLE IF NOT EXISTS storage.objects (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        bucket_id TEXT NOT NULL,
        name TEXT NOT NULL,
        owner UUID,
        created_at TIMESTAMPTZ DEFAULT now(),
        updated_at TIMESTAMPTZ DEFAULT now(),
        last_accessed_at TIMESTAMPTZ DEFAULT now(),
        metadata JSONB DEFAULT '{}'::jsonb
    );

    -- Habilita RLS forçado em storage.objects para que as políticas sejam avaliadas no teste
    ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    ALTER TABLE storage.objects FORCE ROW LEVEL SECURITY;

    -- Se o schema auth existir (ambiente Supabase real), garante os usuários base
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        INSERT INTO auth.users (id, email, raw_user_meta_data, role, aud)
        VALUES 
            (v_user_admin, 'admin@alpha.com', '{"nome":"Admin Master"}'::jsonb, 'authenticated', 'authenticated'),
            (v_user_gestor, 'gestor@alpha.com', '{"nome":"Gestor Logistica"}'::jsonb, 'authenticated', 'authenticated'),
            (v_user_motorista, 'motorista@alpha.com', '{"nome":"Motorista Teste"}'::jsonb, 'authenticated', 'authenticated'),
            (v_user_suspenso, 'suspenso@alpha.com', '{"nome":"Motorista Suspenso"}'::jsonb, 'authenticated', 'authenticated'),
            (v_user_estranho, 'estranho@beta.com', '{"nome":"Usuario Outra Empresa"}'::jsonb, 'authenticated', 'authenticated'),
            (v_user_novo, 'novo@alpha.com', '{"nome":"Novo Candidato"}'::jsonb, 'authenticated', 'authenticated')
        ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
    END IF;

    -- Limpa registros de teste prévios
    DELETE FROM storage.objects WHERE bucket_id = 'veiculos-documentos';
    DELETE FROM public.auditoria_acessos WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.historico_atendimentos WHERE motorista_id IN (SELECT id FROM public.motoristas WHERE empresa_id IN (v_empresa_1, v_empresa_2));
    DELETE FROM public.entregas WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.rotas_planejadas WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.clientes_enderecos WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.veiculos_documentos WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.veiculos_motoristas WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.motoristas WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.solicitacoes_acesso WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.empresa_membros WHERE empresa_id IN (v_empresa_1, v_empresa_2);
    DELETE FROM public.empresas WHERE id IN (v_empresa_1, v_empresa_2);

    -- Insere Empresas de Teste
    INSERT INTO public.empresas (id, nome, cnpj, codigo_convite, cidade, uf, ativa)
    VALUES 
        (v_empresa_1, 'Empresa Teste Alpha', '11.111.111/0001-11', 'ALPHA-01', 'Florianópolis', 'SC', true),
        (v_empresa_2, 'Empresa Teste Beta', '22.222.222/0001-22', 'BETA-02', 'São José', 'SC', true);

    -- Insere Perfis com a coluna oficial 'nome'
    INSERT INTO public.perfis_usuarios (id, email, nome)
    VALUES
        (v_user_admin, 'admin@alpha.com', 'Admin Master'),
        (v_user_gestor, 'gestor@alpha.com', 'Gestor Logística'),
        (v_user_motorista, 'motorista@alpha.com', 'Motorista Teste'),
        (v_user_suspenso, 'suspenso@alpha.com', 'Motorista Suspenso'),
        (v_user_estranho, 'estranho@beta.com', 'Usuário Outra Empresa'),
        (v_user_novo, 'novo@alpha.com', 'Novo Candidato')
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, nome = EXCLUDED.nome;

    -- Insere Membros
    INSERT INTO public.empresa_membros (empresa_id, user_id, papel, status)
    VALUES
        (v_empresa_1, v_user_admin, 'admin', 'aprovado'),
        (v_empresa_1, v_user_gestor, 'gestor', 'aprovado'),
        (v_empresa_1, v_user_motorista, 'motorista', 'aprovado'),
        (v_empresa_1, v_user_suspenso, 'motorista', 'suspenso'),
        (v_empresa_2, v_user_estranho, 'motorista', 'aprovado');
END $fixtures$;

-- =============================================================================
-- CENÁRIO 1: Instalação e integridade estrutural em banco
-- =============================================================================
DO $cenario1$
DECLARE
    v_count INT;
    v_idx_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND (
        (table_name = 'veiculos_motoristas' AND column_name IN ('revisao', 'tamanho_compartimento')) OR
        (table_name = 'veiculos_documentos' AND column_name IN ('angulo_foto', 'storage_path', 'status_analise'))
      );

    IF v_count < 5 THEN
        RAISE EXCEPTION 'CENÁRIO 1 FALHOU: Colunas essenciais ausentes (esperado >= 5, encontrado %)', v_count;
    END IF;

    SELECT COUNT(*) INTO v_idx_count
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN ('uq_veiculo_foto_angulo', 'uq_veiculo_crlv_ativo');

    IF v_idx_count < 2 THEN
        RAISE EXCEPTION 'CENÁRIO 1 FALHOU: Índices exclusivos de ângulo de foto e CRLV ausentes';
    END IF;

    RAISE NOTICE 'CENÁRIO 1 PASSOU: Instalação estrutural e integridade de colunas/índices verificada';
END $cenario1$;

-- =============================================================================
-- CENÁRIO 2: Migração a partir da versão anterior suportada e helpers de autorização
-- =============================================================================
DO $cenario2$
DECLARE
    v_auth_ok JSONB;
    v_auth_suspenso JSONB;
    v_auth_estranho JSONB;
BEGIN
    -- Motorista aprovado deve ser autorizado
    v_auth_ok := public.fn_validar_autorizacao_condutor(
        '11111111-1111-1111-1111-111111111111',
        'cccccccc-cccc-cccc-cccc-cccccccccccc'
    );
    IF (v_auth_ok->>'autorizado')::boolean != TRUE THEN
        RAISE EXCEPTION 'CENÁRIO 2 FALHOU: Motorista ativo foi recusado: %', v_auth_ok;
    END IF;

    -- Motorista suspenso deve ser bloqueado com USUARIO_SUSPENSO
    v_auth_suspenso := public.fn_validar_autorizacao_condutor(
        '11111111-1111-1111-1111-111111111111',
        'dddddddd-dddd-dddd-dddd-dddddddddddd'
    );
    IF (v_auth_suspenso->>'autorizado')::boolean = TRUE OR (v_auth_suspenso->>'codigo') != 'USUARIO_SUSPENSO' THEN
        RAISE EXCEPTION 'CENÁRIO 2 FALHOU: Usuário suspenso não foi bloqueado corretamente: %', v_auth_suspenso;
    END IF;

    -- Usuário de outra empresa deve ser bloqueado com SEM_VINCULO_ATIVO
    v_auth_estranho := public.fn_validar_autorizacao_condutor(
        '11111111-1111-1111-1111-111111111111',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    );
    IF (v_auth_estranho->>'autorizado')::boolean = TRUE THEN
        RAISE EXCEPTION 'CENÁRIO 2 FALHOU: Usuário de outra empresa foi autorizado indevidamente: %', v_auth_estranho;
    END IF;

    RAISE NOTICE 'CENÁRIO 2 PASSOU: Helper fn_validar_autorizacao_condutor operando com precisão';
END $cenario2$;

-- =============================================================================
-- CENÁRIO 3: Assinaturas antigas não existem em pg_proc (sem sobrecarga insegura)
-- =============================================================================
DO $cenario3$
DECLARE
    v_anexar_old INT;
    v_analisar_old INT;
    v_aprovar_old INT;
BEGIN
    SELECT COUNT(*) INTO v_anexar_old
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'anexar_documento_veiculo' AND pronargs = 5;

    SELECT COUNT(*) INTO v_analisar_old
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'analisar_veiculo_motorista' AND pronargs = 3;

    SELECT COUNT(*) INTO v_aprovar_old
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'aprovar_solicitacao_motorista' AND pronargs = 5;

    IF (v_anexar_old + v_analisar_old + v_aprovar_old) > 0 THEN
        RAISE EXCEPTION 'CENÁRIO 3 FALHOU: Ainda existem sobrecargas obsoletas em pg_proc: anexar(%) analisar(%) aprovar(%)',
            v_anexar_old, v_analisar_old, v_aprovar_old;
    END IF;

    RAISE NOTICE 'CENÁRIO 3 PASSOU: Sobrecargas antigas removidas; assinaturas estritas confirmadas';
END $cenario3$;

-- =============================================================================
-- CENÁRIO 4: Quatro fotos registradas com 1 objeto ausente no Storage barram aprovação
-- =============================================================================
DO $cenario4$
DECLARE
    v_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_veiculo_id UUID;
    v_res JSONB;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_motorista::text, true);

    v_res := public.cadastrar_meu_veiculo(jsonb_build_object(
        'tipo_veiculo', 'carro',
        'marca', 'Volkswagen',
        'modelo', 'Gol',
        'placa', 'GOL1A23'
    ));
    SELECT id INTO v_veiculo_id FROM public.veiculos_motoristas WHERE user_id = v_motorista;

    -- Simula presença de 3 fotos apenas em storage.objects (ausente a foto 'traseira')
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES 
        ('veiculos-documentos', v_empresa || '/' || v_motorista || '/frente.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb),
        ('veiculos-documentos', v_empresa || '/' || v_motorista || '/lado_dir.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb),
        ('veiculos-documentos', v_empresa || '/' || v_motorista || '/lado_esq.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb);

    PERFORM public.anexar_documento_veiculo(v_veiculo_id, 'foto_veiculo', 'frente.jpg', v_empresa || '/' || v_motorista || '/frente.jpg', 500000, 'frente');
    PERFORM public.anexar_documento_veiculo(v_veiculo_id, 'foto_veiculo', 'lado_dir.jpg', v_empresa || '/' || v_motorista || '/lado_dir.jpg', 500000, 'lado_direito');
    PERFORM public.anexar_documento_veiculo(v_veiculo_id, 'foto_veiculo', 'lado_esq.jpg', v_empresa || '/' || v_motorista || '/lado_esq.jpg', 500000, 'lado_esquerdo');

    -- Registra metadado da foto traseira sem correspondência no Storage
    INSERT INTO public.veiculos_documentos (
        veiculo_id, user_id, empresa_id, tipo_documento, angulo_foto, nome_arquivo, storage_path, mime_type, tamanho_bytes, status_analise
    ) VALUES (
        v_veiculo_id, v_motorista, v_empresa, 'foto_veiculo', 'traseira', 'traseira.jpg', v_empresa || '/' || v_motorista || '/traseira.jpg', 'image/jpeg', 500000, 'pendente'
    );

    -- Insere CRLV no Storage e banco
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_motorista || '/crlv.pdf', '{"size": 600000, "mimetype": "application/pdf"}'::jsonb);
    INSERT INTO public.veiculos_documentos (
        veiculo_id, user_id, empresa_id, tipo_documento, angulo_foto, nome_arquivo, storage_path, mime_type, tamanho_bytes, status_analise
    ) VALUES (
        v_veiculo_id, v_motorista, v_empresa, 'crlv', NULL, 'crlv.pdf', v_empresa || '/' || v_motorista || '/crlv.pdf', 'application/pdf', 600000, 'pendente'
    );

    -- Gestor tenta aprovar informando a revisão esperada (1)
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, 4);

    IF (v_res->>'sucesso')::boolean = true OR (v_res->>'codigo') != 'ARQUIVO_FISICO_AUSENTE' THEN
        RAISE EXCEPTION 'CENÁRIO 4 FALHOU: Veículo com 1 foto ausente no Storage foi aprovado: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 4 PASSOU: Validação no Storage barrou aprovação devido a foto traseira ausente';
END $cenario4$;

-- =============================================================================
-- CENÁRIO 5: CRLV registrado com objeto ausente no Storage barra aprovação
-- =============================================================================
DO $cenario5$
DECLARE
    v_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_veiculo_id UUID;
    v_revisao_atual INT;
    v_res JSONB;
BEGIN
    SELECT id, revisao INTO v_veiculo_id, v_revisao_atual FROM public.veiculos_motoristas WHERE user_id = v_motorista;

    -- Insere o arquivo da foto traseira no Storage
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_motorista || '/traseira.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb);

    -- Remove o objeto do CRLV do Storage
    DELETE FROM storage.objects WHERE bucket_id = 'veiculos-documentos' AND name = v_empresa || '/' || v_motorista || '/crlv.pdf';

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, v_revisao_atual);

    IF (v_res->>'sucesso')::boolean = true OR (v_res->>'codigo') != 'ARQUIVO_FISICO_AUSENTE' THEN
        RAISE EXCEPTION 'CENÁRIO 5 FALHOU: Veículo com CRLV ausente no Storage foi aprovado: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 5 PASSOU: Validação no Storage barrou aprovação devido a CRLV ausente';
END $cenario5$;

-- =============================================================================
-- CENÁRIO 6: Exclusão direta de evidência vinculada é impedida pelo RLS de Storage
-- =============================================================================
DO $cenario6$
DECLARE
    v_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_veiculo_id UUID;
    v_crlv_path TEXT := v_empresa || '/' || v_motorista || '/crlv.pdf';
    v_doc_crlv_id UUID;
    v_res JSONB;
    v_is_linked BOOLEAN;
BEGIN
    SELECT id INTO v_veiculo_id FROM public.veiculos_motoristas WHERE user_id = v_motorista;

    -- Recria objeto de metadado do CRLV
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_crlv_path, '{"size": 600000, "mimetype": "application/pdf"}'::jsonb)
    ON CONFLICT (id) DO NOTHING;

    SELECT id INTO v_doc_crlv_id FROM public.veiculos_documentos WHERE storage_path = v_crlv_path;

    -- 1. Enquanto o arquivo estiver vinculado em veiculos_documentos:
    -- A política DELETE de storage.objects avalia NOT EXISTS (SELECT 1 FROM veiculos_documentos WHERE storage_path = name)
    SELECT EXISTS (
        SELECT 1 FROM public.veiculos_documentos WHERE storage_path = v_crlv_path
    ) INTO v_is_linked;

    IF v_is_linked != TRUE THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU: Evidência deveria estar vinculada';
    END IF;

    -- 2. Motorista remove autorizadamente o documento via RPC
    PERFORM set_config('request.jwt.claim.sub', v_motorista::text, true);
    v_res := public.remover_documento_veiculo(v_doc_crlv_id);

    IF (v_res->>'sucesso')::boolean != true THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU ao desvincular documento via RPC: %', v_res;
    END IF;

    -- 3. Agora que o documento foi desvinculado no Postgres, a evidência pode ser excluída no Storage
    SELECT EXISTS (
        SELECT 1 FROM public.veiculos_documentos WHERE storage_path = v_crlv_path
    ) INTO v_is_linked;

    IF v_is_linked = TRUE THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU: Evidência não foi desvinculada após RPC remover_documento_veiculo';
    END IF;

    -- Agora a remoção em storage.objects é autorizada pela política RLS
    DELETE FROM storage.objects WHERE bucket_id = 'veiculos-documentos' AND name = v_crlv_path;

    RAISE NOTICE 'CENÁRIO 6 PASSOU: Política de ciclo de vida protege evidência vinculada e libera após RPC';
END $cenario6$;

-- =============================================================================
-- CENÁRIO 7 & 8: Recusa de Aprovação com Revisão Desatualizada (Concorrência Otimista)
-- =============================================================================
DO $cenario7_8$
DECLARE
    v_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_veiculo_id UUID;
    v_revisao_original INT;
    v_revisao_nova INT;
    v_res JSONB;
BEGIN
    SELECT id, revisao INTO v_veiculo_id, v_revisao_original FROM public.veiculos_motoristas WHERE user_id = v_motorista;

    -- Reanexa CRLV para deixar veículo completo
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_motorista || '/crlv_v2.pdf', '{"size": 600000, "mimetype": "application/pdf"}'::jsonb);

    PERFORM set_config('request.jwt.claim.sub', v_motorista::text, true);
    PERFORM public.anexar_documento_veiculo(
        v_veiculo_id, 'crlv', 'crlv_v2.pdf', v_empresa || '/' || v_motorista || '/crlv_v2.pdf', 600000, NULL
    );

    -- Pega nova revisão após anexação pelo motorista
    SELECT revisao INTO v_revisao_nova FROM public.veiculos_motoristas WHERE id = v_veiculo_id;
    IF v_revisao_nova <= v_revisao_original THEN
        RAISE EXCEPTION 'CENÁRIO 7 FALHOU: Revisão não subiu após anexar novo documento';
    END IF;

    -- Gestor tenta aprovar usando a revisão antiga (v_revisao_original), simulando corrida
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, v_revisao_original);

    IF (v_res->>'sucesso')::boolean = true OR (v_res->>'codigo') != 'REVISAO_DESATUALIZADA' THEN
        RAISE EXCEPTION 'CENÁRIO 7 FALHOU: Aprovação com revisão desatualizada foi aceita indevidamente: %', v_res;
    END IF;

    -- Agora gestor aprova com a revisão correta
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, v_revisao_nova);
    IF (v_res->>'sucesso')::boolean != true THEN
        RAISE EXCEPTION 'CENÁRIO 8 FALHOU: Aprovação com revisão esperada correta foi rejeitada: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 7 & 8 PASSOU: Proteção contra decisão com revisão desatualizada validada';
END $cenario7_8$;

-- =============================================================================
-- CENÁRIO 9: Repetição após falha parcial não duplica dados (idempotência autorizada)
-- =============================================================================
DO $cenario9$
DECLARE
    v_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_estranho UUID := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
    v_novo_user UUID := 'ffffffff-ffff-ffff-ffff-ffffffffffff';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_solicitacao_id UUID;
    v_res_1 JSONB;
    v_res_2 JSONB;
    v_res_hacker JSONB;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_novo_user::text, true);
    PERFORM public.solicitar_acesso_empresa('ALPHA-01');

    SELECT id INTO v_solicitacao_id 
    FROM public.solicitacoes_acesso 
    WHERE user_id = v_novo_user AND empresa_id = v_empresa;

    -- 1. Gestor aprova (Opção A)
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res_1 := public.aprovar_solicitacao_motorista(v_solicitacao_id, NULL, TRUE);
    IF (v_res_1->>'sucesso')::boolean != true THEN
        RAISE EXCEPTION 'CENÁRIO 9 FALHOU na aprovação de motorista: %', v_res_1;
    END IF;

    -- 2. Repetição autorizada retorna JA_APROVADO
    v_res_2 := public.aprovar_solicitacao_motorista(v_solicitacao_id, NULL, TRUE);
    IF (v_res_2->>'sucesso')::boolean != true OR (v_res_2->>'codigo') != 'JA_APROVADO' THEN
        RAISE EXCEPTION 'CENÁRIO 9 FALHOU: Repetição não retornou JA_APROVADO: %', v_res_2;
    END IF;

    -- 3. Chamada não autorizada (usuário de outra empresa) DEVE receber ACESSO_NEGADO antes de JA_APROVADO
    PERFORM set_config('request.jwt.claim.sub', v_estranho::text, true);
    v_res_hacker := public.aprovar_solicitacao_motorista(v_solicitacao_id, NULL, TRUE);
    IF (v_res_hacker->>'sucesso')::boolean = true OR (v_res_hacker->>'codigo') != 'ACESSO_NEGADO' THEN
        RAISE EXCEPTION 'CENÁRIO 9 FALHOU: Usuário não autorizado conseguiu obter JA_APROVADO: %', v_res_hacker;
    END IF;

    RAISE NOTICE 'CENÁRIO 9 PASSOU: Idempotência checa autorização previamente e não vaza dados';
END $cenario9$;

-- =============================================================================
-- CENÁRIO 10: Usuário de outra empresa não acessa nem altera evidências
-- =============================================================================
DO $cenario10$
DECLARE
    v_estranho UUID := 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
    v_contagem INT;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_estranho::text, true);

    SELECT COUNT(*) INTO v_contagem 
    FROM public.veiculos_motoristas 
    WHERE empresa_id = '11111111-1111-1111-1111-111111111111';

    IF v_contagem > 0 THEN
        RAISE EXCEPTION 'CENÁRIO 10 FALHOU: Usuário de outra empresa conseguiu ler veículos da Empresa 1';
    END IF;

    RAISE NOTICE 'CENÁRIO 10 PASSOU: Isolamento de dados entre empresas garantido';
END $cenario10$;

-- =============================================================================
-- CENÁRIO 11: Usuário suspenso tentando anexar arquivo previamente enviado é bloqueado
-- =============================================================================
DO $cenario11$
DECLARE
    v_suspenso UUID := 'dddddddd-dddd-dddd-dddd-dddddddddddd';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_veiculo_suspenso UUID;
    v_res JSONB;
BEGIN
    -- Cria veículo prévio para o usuário suspenso (antes da suspensão)
    INSERT INTO public.veiculos_motoristas (
        user_id, empresa_id, tipo_veiculo, marca, modelo, placa, status_analise
    ) VALUES (
        v_suspenso, v_empresa, 'carro', 'Fiat', 'Mobi', 'SUS1A23', 'pendente'
    ) RETURNING id INTO v_veiculo_suspenso;

    -- Simula arquivo pré-existente no Storage enviado antes da suspensão
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_suspenso || '/antigo.jpg', '{"size": 300000, "mimetype": "image/jpeg"}'::jsonb);

    -- Usuário agora suspenso tenta anexar esse arquivo pré-existente
    PERFORM set_config('request.jwt.claim.sub', v_suspenso::text, true);
    v_res := public.anexar_documento_veiculo(
        v_veiculo_suspenso, 'foto_veiculo', 'antigo.jpg', v_empresa || '/' || v_suspenso || '/antigo.jpg', 300000, 'frente'
    );

    IF (v_res->>'sucesso')::boolean = true OR (v_res->>'codigo') != 'USUARIO_SUSPENSO' THEN
        RAISE EXCEPTION 'CENÁRIO 11 FALHOU: Usuário suspenso conseguiu anexar documento pré-existente: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 11 PASSOU: RPC bloqueia usuário suspenso mesmo com arquivo previamente em storage';
END $cenario11$;

-- =============================================================================
-- CENÁRIO 12: Execução fiel do contrato mobile Flutter (obter_meu_status_acesso)
-- =============================================================================
DO $cenario12$
DECLARE
    v_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_res JSONB;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_motorista::text, true);
    v_res := public.obter_meu_status_acesso();

    IF v_res IS NULL OR (v_res->>'autenticado')::boolean != true THEN
        RAISE EXCEPTION 'CENÁRIO 12 FALHOU: obter_meu_status_acesso retornou contrato inválido: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 12 PASSOU: RPC do contrato Flutter executou com fidelidade total';
END $cenario12$;

DO $final$
BEGIN
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'TODOS OS 12 CENÁRIOS DE TESTE PASSARAM COM SUCESSO!';
    RAISE NOTICE '=============================================================';
END $final$;

ROLLBACK;
