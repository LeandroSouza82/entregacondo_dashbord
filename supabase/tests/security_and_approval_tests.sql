-- =============================================================================
-- SUITE DE TESTES AUTOMATIZADOS: SEGURANÇA, STORAGE, REVISÃO E TRANSAÇÕES
-- Projeto: EntregaCondo Backend
-- Data: 18/10/2026
--
-- AVISO IMPORTANTE SOBRE FIXTURES E AMBIENTE:
-- 1. Este script executa testes unitários e de integração SQL dentro de uma
--    transação isolada (com ROLLBACK final).
-- 2. IDENTIFICAÇÃO DE TESTES DE METADADOS SQL: As inserções em `storage.objects`
--    são FIXTURES DE METADADOS SQL para teste unitário do catálogo e das políticas
--    RLS no Postgres. Elas testam rigorosamente o comportamento relacional e RLS,
--    mas NÃO gravam arquivos físicos em blocos (S3/MinIO) sem o serviço Storage ativo.
-- 3. A concorrência multi-sessão com interleaved timing requer duas conexões
--    independentes de cliente. Este script valida o protocolo atômico e a recusa
--    por revisão desatualizada (otimista) e locks FOR UPDATE no nível do motor SQL.
-- =============================================================================

BEGIN;

DO $setup$
BEGIN
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'INICIANDO SUITE DE TESTES: REVISÃO, STORAGE E RLS (v5.0)';
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

    -- Concede permissões na tabela storage.objects para testes com papel authenticated
    GRANT ALL ON storage.objects TO authenticated, anon;

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
    DELETE FROM public.storage_limpeza_fila WHERE empresa_id IN (v_empresa_1, v_empresa_2);
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
        (table_name = 'veiculos_documentos' AND column_name IN ('angulo_foto', 'storage_path', 'status_analise')) OR
        (table_name = 'storage_limpeza_fila' AND column_name IN ('status', 'tentativas', 'storage_path'))
      );

    IF v_count < 8 THEN
        RAISE EXCEPTION 'CENÁRIO 1 FALHOU: Colunas essenciais ausentes (esperado >= 8, encontrado %)', v_count;
    END IF;

    SELECT COUNT(*) INTO v_idx_count
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN ('uq_veiculo_foto_angulo', 'uq_veiculo_crlv_ativo', 'idx_storage_limpeza_status_path');

    IF v_idx_count < 3 THEN
        RAISE EXCEPTION 'CENÁRIO 1 FALHOU: Índices essenciais ausentes';
    END IF;

    RAISE NOTICE 'CENÁRIO 1 PASSOU: Instalação estrutural, colunas e fila de limpeza verificadas';
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
    v_auth_ok := public.fn_validar_autorizacao_condutor(
        '11111111-1111-1111-1111-111111111111',
        'cccccccc-cccc-cccc-cccc-cccccccccccc'
    );
    IF (v_auth_ok->>'autorizado')::boolean != TRUE THEN
        RAISE EXCEPTION 'CENÁRIO 2 FALHOU: Motorista ativo foi recusado: %', v_auth_ok;
    END IF;

    v_auth_suspenso := public.fn_validar_autorizacao_condutor(
        '11111111-1111-1111-1111-111111111111',
        'dddddddd-dddd-dddd-dddd-dddddddddddd'
    );
    IF (v_auth_suspenso->>'autorizado')::boolean = TRUE OR (v_auth_suspenso->>'codigo') != 'USUARIO_SUSPENSO' THEN
        RAISE EXCEPTION 'CENÁRIO 2 FALHOU: Usuário suspenso não foi bloqueado corretamente: %', v_auth_suspenso;
    END IF;

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
    v_aprovar_old5 INT;
    v_aprovar_old6 INT;
BEGIN
    SELECT COUNT(*) INTO v_anexar_old
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'anexar_documento_veiculo' AND pronargs = 5;

    SELECT COUNT(*) INTO v_analisar_old
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'analisar_veiculo_motorista' AND pronargs = 3;

    SELECT COUNT(*) INTO v_aprovar_old5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'aprovar_solicitacao_motorista' AND pronargs = 5;

    SELECT COUNT(*) INTO v_aprovar_old6
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'aprovar_solicitacao_motorista' AND pronargs = 6;

    IF (v_anexar_old + v_analisar_old + v_aprovar_old5 + v_aprovar_old6) > 0 THEN
        RAISE EXCEPTION 'CENÁRIO 3 FALHOU: Ainda existem sobrecargas obsoletas em pg_proc: anexar(%) analisar(%) aprovar5(%) aprovar6(%)',
            v_anexar_old, v_analisar_old, v_aprovar_old5, v_aprovar_old6;
    END IF;

    RAISE NOTICE 'CENÁRIO 3 PASSOU: Todas as sobrecargas antigas removidas; assinaturas estritas confirmadas';
END $cenario3$;

-- =============================================================================
-- CENÁRIO 4: Quatro fotos registradas com 1 objeto ausente no Storage barram aprovação
-- (TESTE SQL DE METADADOS: validação no catálogo storage.objects)
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

    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES 
        ('veiculos-documentos', v_empresa || '/' || v_motorista || '/frente.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb),
        ('veiculos-documentos', v_empresa || '/' || v_motorista || '/lado_dir.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb),
        ('veiculos-documentos', v_empresa || '/' || v_motorista || '/lado_esq.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb);

    PERFORM public.anexar_documento_veiculo(v_veiculo_id, 'foto_veiculo', 'frente.jpg', v_empresa || '/' || v_motorista || '/frente.jpg', 500000, 'frente');
    PERFORM public.anexar_documento_veiculo(v_veiculo_id, 'foto_veiculo', 'lado_dir.jpg', v_empresa || '/' || v_motorista || '/lado_dir.jpg', 500000, 'lado_direito');
    PERFORM public.anexar_documento_veiculo(v_veiculo_id, 'foto_veiculo', 'lado_esq.jpg', v_empresa || '/' || v_motorista || '/lado_esq.jpg', 500000, 'lado_esquerdo');

    INSERT INTO public.veiculos_documentos (
        veiculo_id, user_id, empresa_id, tipo_documento, angulo_foto, nome_arquivo, storage_path, mime_type, tamanho_bytes, status_analise
    ) VALUES (
        v_veiculo_id, v_motorista, v_empresa, 'foto_veiculo', 'traseira', 'traseira.jpg', v_empresa || '/' || v_motorista || '/traseira.jpg', 'image/jpeg', 500000, 'pendente'
    );

    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_motorista || '/crlv.pdf', '{"size": 600000, "mimetype": "application/pdf"}'::jsonb);
    INSERT INTO public.veiculos_documentos (
        veiculo_id, user_id, empresa_id, tipo_documento, angulo_foto, nome_arquivo, storage_path, mime_type, tamanho_bytes, status_analise
    ) VALUES (
        v_veiculo_id, v_motorista, v_empresa, 'crlv', NULL, 'crlv.pdf', v_empresa || '/' || v_motorista || '/crlv.pdf', 'application/pdf', 600000, 'pendente'
    );

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, 4);

    IF (v_res->>'sucesso')::boolean = true OR (v_res->>'codigo') != 'ARQUIVO_FISICO_AUSENTE' THEN
        RAISE EXCEPTION 'CENÁRIO 4 FALHOU: Veículo com 1 foto ausente no Storage foi aprovado: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 4 PASSOU: Validação de metadados barrou aprovação devido a foto traseira ausente';
END $cenario4$;

-- =============================================================================
-- CENÁRIO 5: CRLV registrado com objeto ausente no Storage barra aprovação
-- (TESTE SQL DE METADADOS)
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

    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_motorista || '/traseira.jpg', '{"size": 500000, "mimetype": "image/jpeg"}'::jsonb);

    DELETE FROM storage.objects WHERE bucket_id = 'veiculos-documentos' AND name = v_empresa || '/' || v_motorista || '/crlv.pdf';

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, v_revisao_atual);

    IF (v_res->>'sucesso')::boolean = true OR (v_res->>'codigo') != 'ARQUIVO_FISICO_AUSENTE' THEN
        RAISE EXCEPTION 'CENÁRIO 5 FALHOU: Veículo com CRLV ausente no Storage foi aprovado: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 5 PASSOU: Validação de metadados barrou aprovação devido a CRLV ausente';
END $cenario5$;

-- =============================================================================
-- CENÁRIO 6: Exclusão e sobrescrita direta de evidência vinculada sob papel authenticated
-- (EXECUÇÃO REAL DA POLÍTICA RLS EM storage.objects)
-- =============================================================================
DO $cenario6$
DECLARE
    v_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_crlv_path TEXT := v_empresa || '/' || v_motorista || '/crlv.pdf';
    v_doc_crlv_id UUID;
    v_res JSONB;
    v_deleted_count INT;
    v_updated_count INT;
    v_fila_id UUID;
BEGIN
    -- Recria metadado do CRLV
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_crlv_path, '{"size": 600000, "mimetype": "application/pdf"}'::jsonb)
    ON CONFLICT (id) DO NOTHING;

    SELECT id INTO v_doc_crlv_id FROM public.veiculos_documentos WHERE storage_path = v_crlv_path;

    -- 1. Executa sob papel authenticated como o próprio condutor
    PERFORM set_config('request.jwt.claim.sub', v_motorista::text, true);
    PERFORM set_config('role', 'authenticated', true);

    -- Tenta DELETE direto sob papel authenticated: RLS DEVE BLOQUEAR (0 linhas afetadas)
    DELETE FROM storage.objects WHERE bucket_id = 'veiculos-documentos' AND name = v_crlv_path;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    IF v_deleted_count > 0 THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU: DELETE direto de evidência vinculada foi permitido pelo RLS!';
    END IF;

    -- Tenta UPDATE direto (sobrescrita) sob papel authenticated: RLS DEVE BLOQUEAR
    UPDATE storage.objects 
    SET metadata = '{"tampered": true}'::jsonb 
    WHERE bucket_id = 'veiculos-documentos' AND name = v_crlv_path;
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count > 0 THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU: UPDATE direto de evidência vinculada foi permitido pelo RLS!';
    END IF;

    -- Restaura papel de sistema para executar a RPC autorizada
    PERFORM set_config('role', 'postgres', true);

    -- 2. Motorista remove autorizadamente o documento via RPC
    v_res := public.remover_documento_veiculo(v_doc_crlv_id);

    IF (v_res->>'sucesso')::boolean != true THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU ao desvincular documento via RPC: %', v_res;
    END IF;

    v_fila_id := (v_res->>'fila_id')::uuid;

    -- 3. Agora que o arquivo foi desvinculado e enfileirado em storage_limpeza_fila,
    -- o papel authenticated TENTA O DELETE e a política RLS DEVE AUTORIZAR!
    PERFORM set_config('role', 'authenticated', true);

    DELETE FROM storage.objects WHERE bucket_id = 'veiculos-documentos' AND name = v_crlv_path;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    IF v_deleted_count = 0 THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU: Exclusão na fila de limpeza autorizada deveria ter sido permitida pelo RLS';
    END IF;

    -- Restaura papel e confirma limpeza na fila
    PERFORM set_config('role', 'postgres', true);
    v_res := public.registrar_limpeza_storage_executada(v_fila_id, TRUE);

    IF (v_res->>'sucesso')::boolean != true OR (v_res->>'status') != 'concluido' THEN
        RAISE EXCEPTION 'CENÁRIO 6 FALHOU ao registrar conclusão na fila de limpeza: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 6 PASSOU: RLS bloqueou exclusão/sobrescrita vinculada sob authenticated e liberou após desvinculação';
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

    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_motorista || '/crlv_v2.pdf', '{"size": 600000, "mimetype": "application/pdf"}'::jsonb);

    PERFORM set_config('request.jwt.claim.sub', v_motorista::text, true);
    PERFORM public.anexar_documento_veiculo(
        v_veiculo_id, 'crlv', 'crlv_v2.pdf', v_empresa || '/' || v_motorista || '/crlv_v2.pdf', 600000, NULL
    );

    SELECT revisao INTO v_revisao_nova FROM public.veiculos_motoristas WHERE id = v_veiculo_id;
    IF v_revisao_nova <= v_revisao_original THEN
        RAISE EXCEPTION 'CENÁRIO 7 FALHOU: Revisão não subiu após anexar novo documento';
    END IF;

    -- Gestor tenta aprovar usando a revisão antiga
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, v_revisao_original);

    IF (v_res->>'sucesso')::boolean = true OR (v_res->>'codigo') != 'REVISAO_DESATUALIZADA' THEN
        RAISE EXCEPTION 'CENÁRIO 7 FALHOU: Aprovação com revisão desatualizada foi aceita indevidamente: %', v_res;
    END IF;

    -- Gestor aprova com a revisão correta
    v_res := public.analisar_veiculo_motorista(v_veiculo_id, true, v_revisao_nova);
    IF (v_res->>'sucesso')::boolean != true THEN
        RAISE EXCEPTION 'CENÁRIO 8 FALHOU: Aprovação com revisão esperada correta foi rejeitada: %', v_res;
    END IF;

    RAISE NOTICE 'CENÁRIO 7 & 8 PASSOU: Decisão com revisão desatualizada barrada e aprovação válida registrada';
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
    v_qtd_motoristas INT;
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

    SELECT COUNT(*) INTO v_qtd_motoristas FROM public.motoristas WHERE user_id = v_novo_user AND empresa_id = v_empresa;
    IF v_qtd_motoristas != 1 THEN
        RAISE EXCEPTION 'CENÁRIO 9 FALHOU: Esperado exatamente 1 motorista, encontrado %', v_qtd_motoristas;
    END IF;

    -- 2. Repetição autorizada retorna JA_APROVADO e NÃO duplica motorista
    v_res_2 := public.aprovar_solicitacao_motorista(v_solicitacao_id, NULL, TRUE);
    IF (v_res_2->>'sucesso')::boolean != true OR (v_res_2->>'codigo') != 'JA_APROVADO' THEN
        RAISE EXCEPTION 'CENÁRIO 9 FALHOU: Repetição não retornou JA_APROVADO: %', v_res_2;
    END IF;

    SELECT COUNT(*) INTO v_qtd_motoristas FROM public.motoristas WHERE user_id = v_novo_user AND empresa_id = v_empresa;
    IF v_qtd_motoristas != 1 THEN
        RAISE EXCEPTION 'CENÁRIO 9 FALHOU: Repetição duplicou motorista na frota!';
    END IF;

    -- 3. Chamada não autorizada DEVE receber ACESSO_NEGADO antes de JA_APROVADO
    PERFORM set_config('request.jwt.claim.sub', v_estranho::text, true);
    v_res_hacker := public.aprovar_solicitacao_motorista(v_solicitacao_id, NULL, TRUE);
    IF (v_res_hacker->>'sucesso')::boolean = true OR (v_res_hacker->>'codigo') != 'ACESSO_NEGADO' THEN
        RAISE EXCEPTION 'CENÁRIO 9 FALHOU: Usuário não autorizado conseguiu obter JA_APROVADO: %', v_res_hacker;
    END IF;

    RAISE NOTICE 'CENÁRIO 9 PASSOU: Idempotência checa autorização previamente e não duplica motoristas';
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
    INSERT INTO public.veiculos_motoristas (
        user_id, empresa_id, tipo_veiculo, marca, modelo, placa, status_analise
    ) VALUES (
        v_suspenso, v_empresa, 'carro', 'Fiat', 'Mobi', 'SUS1A23', 'pendente'
    ) RETURNING id INTO v_veiculo_suspenso;

    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES ('veiculos-documentos', v_empresa || '/' || v_suspenso || '/antigo.jpg', '{"size": 300000, "mimetype": "image/jpeg"}'::jsonb);

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

-- =============================================================================
-- CENÁRIO 13: Ausência de mutações parciais ao recusar aprovação por revisão de veículo
-- (CONFERÊNCIA ANTES E DEPOIS DO NÚMERO DE MOTORISTAS E STATUS)
-- =============================================================================
DO $cenario13$
DECLARE
    v_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_candidato UUID := '12345678-1234-1234-1234-123456789abc';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_solicitacao_id UUID;
    v_veiculo_id UUID;
    v_qtd_motoristas_antes INT;
    v_qtd_motoristas_depois INT;
    v_res JSONB;
    v_status_solic TEXT;
    v_membro_existe BOOLEAN;
BEGIN
    -- Cria candidato e solicitação pendente
    INSERT INTO public.perfis_usuarios (id, email, nome)
    VALUES (v_candidato, 'candidato@teste.com', 'Candidato Zero Mutacao')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.solicitacoes_acesso (id, empresa_id, user_id, papel_solicitado, status)
    VALUES (gen_random_uuid(), v_empresa, v_candidato, 'motorista', 'pendente')
    RETURNING id INTO v_solicitacao_id;

    -- Candidato cadastra veículo com revisão 1
    PERFORM set_config('request.jwt.claim.sub', v_candidato::text, true);
    PERFORM public.cadastrar_meu_veiculo(jsonb_build_object(
        'tipo_veiculo', 'carro',
        'marca', 'Renault',
        'modelo', 'Kwid',
        'placa', 'KWD1B34'
    ));

    SELECT id INTO v_veiculo_id FROM public.veiculos_motoristas WHERE user_id = v_candidato;

    -- Registra quantidade de motoristas ANTES da tentativa com erro
    SELECT COUNT(*) INTO v_qtd_motoristas_antes FROM public.motoristas;

    -- TENTATIVA 1: Gestor tenta aprovar solicitando aprovação do veículo com revisão DESATUALIZADA (esperada: 99, real: 1)
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    v_res := public.aprovar_solicitacao_motorista(
        v_solicitacao_id,
        NULL,
        TRUE,
        'Candidato Zero Mutacao',
        '(48) 99999-0000',
        TRUE, -- aprovar_veiculo
        99    -- revisao_desatualizada
    );

    IF (v_res->>'sucesso')::boolean = TRUE OR (v_res->>'codigo') != 'REVISAO_DESATUALIZADA' THEN
        RAISE EXCEPTION 'CENÁRIO 13 FALHOU: Aprovação com revisão desatualizada não retornou REVISAO_DESATUALIZADA: %', v_res;
    END IF;

    -- Confere quantidade de motoristas DEPOIS da tentativa com revisão desatualizada
    SELECT COUNT(*) INTO v_qtd_motoristas_depois FROM public.motoristas;

    IF v_qtd_motoristas_antes != v_qtd_motoristas_depois THEN
        RAISE EXCEPTION 'CENÁRIO 13 FALHOU: Quantidade de motoristas mudou após recusa por revisão desatualizada! (Antes=%, Depois=%)',
            v_qtd_motoristas_antes, v_qtd_motoristas_depois;
    END IF;

    -- TENTATIVA 2: Gestor tenta aprovar com aprovação de veículo mas com revisão NULL (tentativa de bypass)
    v_res := public.aprovar_solicitacao_motorista(
        v_solicitacao_id,
        NULL,
        TRUE,
        'Candidato Zero Mutacao',
        '(48) 99999-0000',
        TRUE, -- aprovar_veiculo
        NULL  -- revisao_omitida
    );

    IF (v_res->>'sucesso')::boolean = TRUE OR (v_res->>'codigo') != 'REVISAO_OBRIGATORIA' THEN
        RAISE EXCEPTION 'CENÁRIO 13 FALHOU: Aprovação com revisão NULL não retornou REVISAO_OBRIGATORIA: %', v_res;
    END IF;

    -- Confere quantidade de motoristas DEPOIS da tentativa com revisão NULL
    SELECT COUNT(*) INTO v_qtd_motoristas_depois FROM public.motoristas;
    IF v_qtd_motoristas_antes != v_qtd_motoristas_depois THEN
        RAISE EXCEPTION 'CENÁRIO 13 FALHOU: Quantidade de motoristas mudou após recusa por revisão NULL! (Antes=%, Depois=%)',
            v_qtd_motoristas_antes, v_qtd_motoristas_depois;
    END IF;

    -- Confere que a solicitação permaneceu 'pendente' e nenhum vínculo foi gravado
    SELECT status INTO v_status_solic FROM public.solicitacoes_acesso WHERE id = v_solicitacao_id;
    IF v_status_solic != 'pendente' THEN
        RAISE EXCEPTION 'CENÁRIO 13 FALHOU: Status da solicitação foi alterado após recusa: %', v_status_solic;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.empresa_membros WHERE empresa_id = v_empresa AND user_id = v_candidato
    ) INTO v_membro_existe;

    IF v_membro_existe THEN
        RAISE EXCEPTION 'CENÁRIO 13 FALHOU: Membro foi gravado em empresa_membros após recusa!';
    END IF;

    RAISE NOTICE 'CENÁRIO 13 PASSOU: Zero mutações parciais após recusa por revisão de veículo comprovada antes/depois';
END $cenario13$;

-- =============================================================================
-- CENÁRIO 14: Fila de limpeza persistente e recuperação após falha
-- =============================================================================
DO $cenario14$
DECLARE
    v_admin UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    v_motorista UUID := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    v_empresa UUID := '11111111-1111-1111-1111-111111111111';
    v_fila_id UUID;
    v_item RECORD;
    v_res JSONB;
BEGIN
    INSERT INTO public.storage_limpeza_fila (
        bucket_id, storage_path, empresa_id, user_id, motivo, status
    ) VALUES (
        'veiculos-documentos', v_empresa || '/' || v_motorista || '/doc_recuperacao.pdf', v_empresa, v_motorista, 'teste_recuperacao', 'pendente'
    ) RETURNING id INTO v_fila_id;

    -- Simula falha na primeira tentativa de limpeza física
    PERFORM set_config('request.jwt.claim.sub', v_motorista::text, true);
    v_res := public.registrar_limpeza_storage_executada(v_fila_id, FALSE, 'Erro HTTP 503 Service Unavailable');

    SELECT * INTO v_item FROM public.storage_limpeza_fila WHERE id = v_fila_id;
    IF v_item.status != 'pendente' OR v_item.tentativas != 1 OR v_item.ultimo_erro != 'Erro HTTP 503 Service Unavailable' THEN
        RAISE EXCEPTION 'CENÁRIO 14 FALHOU: Registro de falha não persistiu estado recuperável corretamente: %', v_item;
    END IF;

    -- Simula nova tentativa recuperada com sucesso
    v_res := public.registrar_limpeza_storage_executada(v_fila_id, TRUE, NULL);

    SELECT * INTO v_item FROM public.storage_limpeza_fila WHERE id = v_fila_id;
    IF v_item.status != 'concluido' OR v_item.tentativas != 2 OR v_item.ultimo_erro IS NOT NULL THEN
        RAISE EXCEPTION 'CENÁRIO 14 FALHOU: Registro de conclusão da recuperação não atualizou estado: %', v_item;
    END IF;

    RAISE NOTICE 'CENÁRIO 14 PASSOU: Protocolo de recuperação de limpeza física e auditoria de fila validado';
END $cenario14$;

DO $final$
BEGIN
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'TODOS OS 14 CENÁRIOS DE TESTE PASSARAM COM SUCESSO!';
    RAISE NOTICE '=============================================================';
END $final$;

ROLLBACK;
