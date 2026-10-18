-- ==============================================================================
-- MIGRATION: 20261018010000_auth_approval_workflow.sql
-- Módulo: Gestão de Empresas, Perfis, Vínculos, Aprovações, Despacho Transacional e Auditoria
-- EntregaCondo - Dashboard & Mobile Integration
-- ==============================================================================

-- 1. Habilitar extensões
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 2. TABELA: empresas
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.empresas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome VARCHAR(255) NOT NULL,
    cnpj VARCHAR(30) UNIQUE,
    codigo_convite VARCHAR(50) NOT NULL UNIQUE,
    cidade VARCHAR(100),
    uf VARCHAR(2),
    ativa BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- 3. TABELA: perfis_usuarios
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.perfis_usuarios (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    nome VARCHAR(255) NOT NULL,
    telefone VARCHAR(30),
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- 4. TABELA: motoristas
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.motoristas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    nome VARCHAR(255) NOT NULL,
    telefone VARCHAR(30) NOT NULL,
    email VARCHAR(255),
    veiculo_modelo VARCHAR(100) NOT NULL,
    veiculo_placa VARCHAR(20) NOT NULL UNIQUE,
    status VARCHAR(30) NOT NULL DEFAULT 'disponivel' 
        CHECK (status IN ('disponivel', 'em_rota', 'pausado', 'offline')),
    latitude_atual NUMERIC(10, 7),
    longitude_atual NUMERIC(10, 7),
    capacidade_max_pacotes INT NOT NULL DEFAULT 60,
    avaliacao_media NUMERIC(3, 2) NOT NULL DEFAULT 5.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Colunas complementares para tabelas preexistentes
ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE;
ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS ativo BOOLEAN NOT NULL DEFAULT TRUE;

-- ------------------------------------------------------------------------------
-- 5. TABELA: empresa_membros
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.empresa_membros (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    papel VARCHAR(30) NOT NULL DEFAULT 'motorista' CHECK (papel IN ('admin', 'gestor', 'motorista')),
    status VARCHAR(30) NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'aprovado', 'rejeitado', 'suspenso')),
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    motivo_decisao TEXT,
    aprovado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    aprovado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_empresa_membro UNIQUE (empresa_id, user_id)
);

-- ------------------------------------------------------------------------------
-- 6. TABELA: solicitacoes_acesso
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.solicitacoes_acesso (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    papel_solicitado VARCHAR(30) NOT NULL DEFAULT 'motorista' CHECK (papel_solicitado IN ('motorista')),
    status VARCHAR(30) NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'aprovado', 'rejeitado', 'suspenso')),
    motorista_vinculado_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    motivo_decisao TEXT,
    decidido_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    decidido_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_solicitacao_empresa_user UNIQUE (empresa_id, user_id)
);

-- ------------------------------------------------------------------------------
-- 7. TABELA: auditoria_acessos
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.auditoria_acessos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    acao VARCHAR(50) NOT NULL,
    status_anterior VARCHAR(30),
    novo_status VARCHAR(30) NOT NULL,
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    motivo TEXT,
    executado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    detalhes JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- 8. TABELA: clientes_enderecos
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.clientes_enderecos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE,
    nome_identificador VARCHAR(255) NOT NULL,
    destinatario_padrao VARCHAR(255),
    endereco_completo TEXT NOT NULL,
    numero VARCHAR(50) NOT NULL,
    bairro VARCHAR(100) NOT NULL,
    cidade VARCHAR(100) NOT NULL,
    cep VARCHAR(20) NOT NULL,
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    tempo_medio_minutos NUMERIC(5, 2) NOT NULL DEFAULT 10.00,
    total_entregas_realizadas INT NOT NULL DEFAULT 0,
    tipo_local VARCHAR(50) NOT NULL DEFAULT 'condominio_horizontal'
        CHECK (tipo_local IN ('condominio_horizontal', 'edificio_vertical', 'comercial', 'casa_rua')),
    observacoes_acesso TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.clientes_enderecos ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE;

-- ------------------------------------------------------------------------------
-- 9. TABELA: rotas_planejadas
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rotas_planejadas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE,
    motorista_id UUID NOT NULL REFERENCES public.motoristas(id) ON DELETE CASCADE,
    status VARCHAR(30) NOT NULL DEFAULT 'planejada'
        CHECK (status IN ('planejada', 'em_execucao', 'concluida', 'cancelada')),
    distancia_original_km NUMERIC(7, 2) NOT NULL,
    tempo_original_minutos NUMERIC(7, 2) NOT NULL,
    distancia_otimizada_km NUMERIC(7, 2) NOT NULL,
    tempo_otimizado_minutos NUMERIC(7, 2) NOT NULL,
    percentual_economia_km NUMERIC(5, 2) NOT NULL,
    percentual_economia_tempo NUMERIC(5, 2) NOT NULL,
    ordem_paradas_json JSONB NOT NULL,
    iniciada_em TIMESTAMPTZ,
    concluida_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE;

-- ------------------------------------------------------------------------------
-- 10. TABELA: entregas
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.entregas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE,
    codigo_rastreio VARCHAR(50) NOT NULL UNIQUE,
    cliente_endereco_id UUID NOT NULL REFERENCES public.clientes_enderecos(id) ON DELETE RESTRICT,
    destinatario_nome VARCHAR(255) NOT NULL,
    destinatario_telefone VARCHAR(30),
    unidade_apartamento VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'atribuida', 'em_transito', 'entregue', 'tentativa_falha', 'cancelada')),
    prioridade VARCHAR(20) NOT NULL DEFAULT 'normal'
        CHECK (prioridade IN ('baixa', 'normal', 'alta', 'urgente')),
    tipo_tarefa VARCHAR(30) NOT NULL DEFAULT 'entrega'
        CHECK (tipo_tarefa IN ('entrega', 'coleta', 'outros')),
    descricao_outro VARCHAR(255),
    peso_kg NUMERIC(6, 2),
    volumes_qtd INT NOT NULL DEFAULT 1,
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    rota_id UUID REFERENCES public.rotas_planejadas(id) ON DELETE SET NULL,
    ordem_na_rota INT,
    observacoes_gestor TEXT,
    data_hora_entrega TIMESTAMPTZ,
    janela_inicio TIME,
    janela_fim TIME,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES public.empresas(id) ON DELETE CASCADE;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS observacoes_gestor TEXT;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS data_hora_entrega TIMESTAMPTZ;

-- ------------------------------------------------------------------------------
-- 11. TABELA: historico_atendimentos
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.historico_atendimentos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entrega_id UUID NOT NULL REFERENCES public.entregas(id) ON DELETE CASCADE,
    cliente_endereco_id UUID NOT NULL REFERENCES public.clientes_enderecos(id) ON DELETE CASCADE,
    motorista_id UUID NOT NULL REFERENCES public.motoristas(id) ON DELETE CASCADE,
    tempo_portaria_espera_minutos NUMERIC(5, 2) NOT NULL DEFAULT 0.00,
    tempo_deslocamento_interno_minutos NUMERIC(5, 2) NOT NULL DEFAULT 0.00,
    tempo_total_minutos NUMERIC(5, 2) NOT NULL,
    data_hora_chegada TIMESTAMPTZ NOT NULL,
    data_hora_conclusao TIMESTAMPTZ NOT NULL,
    sucesso BOOLEAN NOT NULL DEFAULT TRUE,
    motivo_falha TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- 12. ÍNDICES DE PERFORMANCE
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_membros_empresa_status ON public.empresa_membros(empresa_id, status);
CREATE INDEX IF NOT EXISTS idx_membros_user ON public.empresa_membros(user_id);
CREATE INDEX IF NOT EXISTS idx_solicitacoes_empresa_status ON public.solicitacoes_acesso(empresa_id, status);
CREATE INDEX IF NOT EXISTS idx_solicitacoes_user ON public.solicitacoes_acesso(user_id);
CREATE INDEX IF NOT EXISTS idx_motoristas_user ON public.motoristas(user_id);
CREATE INDEX IF NOT EXISTS idx_motoristas_empresa ON public.motoristas(empresa_id);
CREATE INDEX IF NOT EXISTS idx_entregas_empresa_motorista ON public.entregas(empresa_id, motorista_id);
CREATE INDEX IF NOT EXISTS idx_entregas_rota ON public.entregas(rota_id, ordem_na_rota);
CREATE INDEX IF NOT EXISTS idx_rotas_empresa_motorista ON public.rotas_planejadas(empresa_id, motorista_id);
CREATE INDEX IF NOT EXISTS idx_clientes_coords ON public.clientes_enderecos(latitude, longitude);

-- ------------------------------------------------------------------------------
-- 13. TRIGGERS
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_recalcular_tempo_medio_condominio()
RETURNS TRIGGER AS $$
DECLARE
    v_media NUMERIC(5, 2);
    v_total INT;
BEGIN
    SELECT 
        ROUND(AVG(tempo_total_minutos), 2),
        COUNT(*)
    INTO 
        v_media,
        v_total
    FROM public.historico_atendimentos
    WHERE cliente_endereco_id = NEW.cliente_endereco_id
      AND sucesso = TRUE;

    IF v_media IS NOT NULL THEN
        UPDATE public.clientes_enderecos
        SET 
            tempo_medio_minutos = v_media,
            total_entregas_realizadas = v_total,
            updated_at = timezone('utc'::text, now())
        WHERE id = NEW.cliente_endereco_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_atualiza_tempo_medio_condominio ON public.historico_atendimentos;
CREATE TRIGGER trg_atualiza_tempo_medio_condominio
AFTER INSERT ON public.historico_atendimentos
FOR EACH ROW
EXECUTE FUNCTION public.fn_recalcular_tempo_medio_condominio();

CREATE OR REPLACE FUNCTION public.fn_trg_on_auth_user_created()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.perfis_usuarios (id, email, nome, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.email, 'sem-email@entregacondo.com.br'),
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(COALESCE(NEW.email, 'Motorista'), '@', 1)),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        nome = CASE WHEN public.perfis_usuarios.nome = '' OR public.perfis_usuarios.nome IS NULL THEN EXCLUDED.nome ELSE public.perfis_usuarios.nome END,
        avatar_url = COALESCE(EXCLUDED.avatar_url, public.perfis_usuarios.avatar_url),
        updated_at = timezone('utc'::text, now());

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.fn_trg_on_auth_user_created();

-- ------------------------------------------------------------------------------
-- 14. FUNÇÕES RPC (APROVAÇÃO, DESPACHO TRANSACIONAL, AUDITORIA)
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sincronizar_meu_perfil()
RETURNS JSONB AS $$
DECLARE
    v_user RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_AUTORIZADO', 'mensagem', 'Usuário não autenticado.');
    END IF;

    SELECT id, email, raw_user_meta_data INTO v_user
    FROM auth.users
    WHERE id = auth.uid();

    IF v_user IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'USUARIO_NAO_ENCONTRADO', 'mensagem', 'Usuário não localizado.');
    END IF;

    INSERT INTO public.perfis_usuarios (id, email, nome, avatar_url)
    VALUES (
        v_user.id,
        COALESCE(v_user.email, 'sem-email@entregacondo.com.br'),
        COALESCE(v_user.raw_user_meta_data->>'full_name', v_user.raw_user_meta_data->>'name', split_part(COALESCE(v_user.email, 'Motorista'), '@', 1)),
        v_user.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        nome = CASE WHEN public.perfis_usuarios.nome = '' OR public.perfis_usuarios.nome IS NULL THEN EXCLUDED.nome ELSE public.perfis_usuarios.nome END,
        avatar_url = COALESCE(EXCLUDED.avatar_url, public.perfis_usuarios.avatar_url),
        updated_at = timezone('utc'::text, now());

    RETURN jsonb_build_object('sucesso', true, 'codigo', 'SUCESSO', 'mensagem', 'Perfil sincronizado.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.obter_meu_status_acesso()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_membro RECORD;
    v_solicitacao RECORD;
    v_motorista RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'autenticado', false,
            'status', 'sem_vinculo',
            'papel', NULL,
            'empresa_id', NULL,
            'empresa_nome', NULL,
            'motorista_id', NULL,
            'motivo', NULL,
            'mensagem', 'Usuário não autenticado no Supabase Auth.'
        );
    END IF;

    PERFORM public.sincronizar_meu_perfil();

    SELECT em.*, e.nome AS empresa_nome, e.codigo_convite
    INTO v_membro
    FROM public.empresa_membros em
    JOIN public.empresas e ON e.id = em.empresa_id
    WHERE em.user_id = v_user_id;

    IF v_membro IS NULL THEN
        SELECT sa.*, e.nome AS empresa_nome
        INTO v_solicitacao
        FROM public.solicitacoes_acesso sa
        JOIN public.empresas e ON e.id = sa.empresa_id
        WHERE sa.user_id = v_user_id;

        IF v_solicitacao IS NOT NULL THEN
            RETURN jsonb_build_object(
                'autenticado', true,
                'user_id', v_user_id,
                'status', v_solicitacao.status,
                'papel', v_solicitacao.papel_solicitado,
                'empresa_id', v_solicitacao.empresa_id,
                'empresa_nome', v_solicitacao.empresa_nome,
                'motorista_id', NULL,
                'motivo', v_solicitacao.motivo_decisao,
                'solicitacao_id', v_solicitacao.id,
                'created_at', v_solicitacao.created_at,
                'decidido_em', v_solicitacao.decidido_em,
                'mensagem', 'Solicitação pendente de aprovação pela gestão da empresa.'
            );
        END IF;

        RETURN jsonb_build_object(
            'autenticado', true,
            'user_id', v_user_id,
            'status', 'sem_vinculo',
            'papel', NULL,
            'empresa_id', NULL,
            'empresa_nome', NULL,
            'motorista_id', NULL,
            'motivo', NULL,
            'solicitacao_id', NULL,
            'created_at', NULL,
            'decidido_em', NULL,
            'mensagem', 'Conta autenticada sem vínculo de empresa. Digite o código de convite da sua transportadora.'
        );
    END IF;

    IF v_membro.status = 'pendente' THEN
        RETURN jsonb_build_object(
            'autenticado', true,
            'user_id', v_user_id,
            'status', 'pendente',
            'papel', v_membro.papel,
            'empresa_id', v_membro.empresa_id,
            'empresa_nome', v_membro.empresa_nome,
            'motorista_id', NULL,
            'motivo', NULL,
            'mensagem', 'Solicitação recebida. Aguardando vinculação operacional pelo gestor.'
        );
    END IF;

    IF v_membro.status = 'rejeitado' THEN
        RETURN jsonb_build_object(
            'autenticado', true,
            'user_id', v_user_id,
            'status', 'rejeitado',
            'papel', v_membro.papel,
            'empresa_id', v_membro.empresa_id,
            'empresa_nome', v_membro.empresa_nome,
            'motorista_id', NULL,
            'motivo', COALESCE(v_membro.motivo_decisao, 'Solicitação não aprovada pela gestão.'),
            'mensagem', 'Seu pedido de vinculação foi rejeitado pela empresa.'
        );
    END IF;

    IF v_membro.status = 'suspenso' THEN
        RETURN jsonb_build_object(
            'autenticado', true,
            'user_id', v_user_id,
            'status', 'suspenso',
            'papel', v_membro.papel,
            'empresa_id', v_membro.empresa_id,
            'empresa_nome', v_membro.empresa_nome,
            'motorista_id', NULL,
            'motivo', COALESCE(v_membro.motivo_decisao, 'Acesso suspenso preventivamente pela gestão.'),
            'mensagem', 'Seu acesso operacional está suspenso. Procure a gestão da sua empresa.'
        );
    END IF;

    IF v_membro.papel = 'motorista' THEN
        SELECT * INTO v_motorista 
        FROM public.motoristas 
        WHERE id = v_membro.motorista_id
          AND empresa_id = v_membro.empresa_id;

        IF v_motorista IS NULL THEN
            RETURN jsonb_build_object(
                'autenticado', true,
                'user_id', v_user_id,
                'status', 'aprovado_sem_cadastro',
                'papel', 'motorista',
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'motorista_id', NULL,
                'motivo', 'Vínculo aprovado, mas nenhum cadastro de veículo/motorista atribuído.',
                'mensagem', 'Aguardando atribuição de cadastro veicular pela gestão.'
            );
        END IF;

        RETURN jsonb_build_object(
            'autenticado', true,
            'user_id', v_user_id,
            'status', 'aprovado',
            'papel', 'motorista',
            'empresa_id', v_membro.empresa_id,
            'empresa_nome', v_membro.empresa_nome,
            'motorista_id', v_membro.motorista_id,
            'motorista_nome', v_motorista.nome,
            'veiculo', v_motorista.veiculo_modelo || ' (' || v_motorista.veiculo_placa || ')',
            'motivo', NULL,
            'mensagem', 'Acesso operacional liberado com sucesso.'
        );
    ELSE
        RETURN jsonb_build_object(
            'autenticado', true,
            'user_id', v_user_id,
            'status', 'aprovado',
            'papel', v_membro.papel,
            'empresa_id', v_membro.empresa_id,
            'empresa_nome', v_membro.empresa_nome,
            'motorista_id', NULL,
            'motivo', NULL,
            'mensagem', 'Acesso administrativo autorizado.'
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.fn_usuario_e_gestor_empresa(p_empresa_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 
        FROM public.empresa_membros 
        WHERE empresa_id = p_empresa_id 
          AND user_id = auth.uid() 
          AND papel IN ('admin', 'gestor') 
          AND status = 'aprovado'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Solicitar Acesso à Empresa (PÚBLICO - ESTRITAMENTE MOTORISTA, SEM ELEVAÇÃO DE PRIVILÉGIOS)
CREATE OR REPLACE FUNCTION public.solicitar_acesso_empresa(
    p_codigo_convite TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_empresa RECORD;
    v_membro_existente RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', false,
            'codigo', 'NAO_AUTORIZADO',
            'mensagem', 'Não autorizado. Autentique-se primeiro no aplicativo.'
        );
    END IF;

    PERFORM public.sincronizar_meu_perfil();

    SELECT * INTO v_empresa
    FROM public.empresas
    WHERE UPPER(TRIM(codigo_convite)) = UPPER(TRIM(p_codigo_convite))
      AND ativa = TRUE;

    IF v_empresa IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', false,
            'codigo', 'EMPRESA_NAO_ENCONTRADA',
            'mensagem', 'Código de convite da empresa não encontrado ou inativo.'
        );
    END IF;

    SELECT * INTO v_membro_existente
    FROM public.empresa_membros
    WHERE user_id = v_user_id;

    IF v_membro_existente IS NOT NULL THEN
        IF v_membro_existente.status = 'aprovado' THEN
            RETURN jsonb_build_object(
                'sucesso', true,
                'codigo', 'JA_APROVADO',
                'status', 'aprovado',
                'empresa_id', v_membro_existente.empresa_id,
                'papel', v_membro_existente.papel,
                'mensagem', 'Usuário já possui vínculo ativo e aprovado nesta ou em outra empresa.'
            );
        END IF;

        IF v_membro_existente.status = 'suspenso' THEN
            RETURN jsonb_build_object(
                'sucesso', false,
                'codigo', 'USUARIO_SUSPENSO',
                'status', 'suspenso',
                'empresa_id', v_membro_existente.empresa_id,
                'motivo', v_membro_existente.motivo_decisao,
                'mensagem', 'Seu acesso foi suspenso pela gestão. Procure a administração para reativação.'
            );
        END IF;

        IF v_membro_existente.status = 'pendente' AND v_membro_existente.empresa_id = v_empresa.id THEN
            RETURN jsonb_build_object(
                'sucesso', true,
                'codigo', 'SOLICITACAO_EXISTENTE',
                'status', 'pendente',
                'empresa_id', v_empresa.id,
                'empresa_nome', v_empresa.nome,
                'mensagem', 'Sua solicitação de acesso já está pendente de análise pela gestão.'
            );
        END IF;

        UPDATE public.empresa_membros
        SET empresa_id = v_empresa.id,
            papel = 'motorista',
            status = 'pendente',
            motorista_id = NULL,
            motivo_decisao = 'Solicitação reenviada via código ' || p_codigo_convite,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_membro_existente.id;

        INSERT INTO public.solicitacoes_acesso (
            empresa_id, user_id, papel_solicitado, status, motivo_decisao
        )
        VALUES (
            v_empresa.id, v_user_id, 'motorista', 'pendente', 'Solicitação reenviada via código ' || p_codigo_convite
        )
        ON CONFLICT (empresa_id, user_id) DO UPDATE SET
            papel_solicitado = 'motorista',
            status = 'pendente',
            motivo_decisao = 'Solicitação reenviada via código ' || p_codigo_convite,
            decidido_por = NULL,
            decidido_em = NULL,
            updated_at = timezone('utc'::text, now());

        INSERT INTO public.auditoria_acessos (
            empresa_id, user_id, acao, status_anterior, novo_status, motivo, executado_por
        )
        VALUES (
            v_empresa.id, v_user_id, 'solicitacao_acesso_reenviada', v_membro_existente.status, 'pendente',
            'Solicitação de acesso enviada via código ' || p_codigo_convite, v_user_id
        );

        RETURN jsonb_build_object(
            'sucesso', true,
            'codigo', 'SOLICITACAO_REGISTRADA',
            'status', 'pendente',
            'empresa_id', v_empresa.id,
            'empresa_nome', v_empresa.nome,
            'mensagem', 'Solicitação vinculada à empresa com sucesso. Aguardando aprovação.'
        );
    END IF;

    INSERT INTO public.empresa_membros (
        empresa_id, user_id, papel, status, motivo_decisao
    )
    VALUES (
        v_empresa.id, v_user_id, 'motorista', 'pendente', 'Solicitação enviada via código ' || p_codigo_convite
    );

    INSERT INTO public.solicitacoes_acesso (
        empresa_id, user_id, papel_solicitado, status, motivo_decisao
    )
    VALUES (
        v_empresa.id, v_user_id, 'motorista', 'pendente', 'Solicitação via código ' || p_codigo_convite
    );

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motivo, executado_por
    )
    VALUES (
        v_empresa.id, v_user_id, 'solicitacao_acesso_enviada', NULL, 'pendente',
        'Solicitação de acesso enviada via código ' || p_codigo_convite, v_user_id
    );

    RETURN jsonb_build_object(
        'sucesso', true,
        'codigo', 'SOLICITACAO_REGISTRADA',
        'status', 'pendente',
        'empresa_id', v_empresa.id,
        'empresa_nome', v_empresa.nome,
        'mensagem', 'Solicitação vinculada à empresa com sucesso. Aguardando aprovação.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.aprovar_solicitacao_motorista(
    p_solicitacao_id UUID,
    p_motorista_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_gestor_id UUID;
    v_solicitacao RECORD;
    v_motorista RECORD;
    v_outro_vinculo RECORD;
BEGIN
    v_gestor_id := auth.uid();
    IF v_gestor_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado. Autentique-se.';
    END IF;

    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE id = p_solicitacao_id;

    IF v_solicitacao IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'SOLICITACAO_NAO_ENCONTRADA', 'mensagem', 'Solicitação não encontrada.');
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'PERMISSAO_NEGADA', 'mensagem', 'Ação negada: você não é gestor autorizado desta empresa.');
    END IF;

    SELECT * INTO v_motorista
    FROM public.motoristas
    WHERE id = p_motorista_id;

    IF v_motorista IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'MOTORISTA_NAO_ENCONTRADO', 'mensagem', 'Cadastro de motorista não encontrado.');
    END IF;

    IF v_motorista.empresa_id IS NOT NULL AND v_motorista.empresa_id != v_solicitacao.empresa_id THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'EMPRESA_DIVERGENTE', 'mensagem', 'O motorista informado pertence a outra empresa.');
    END IF;

    IF v_motorista.user_id IS NOT NULL AND v_motorista.user_id != v_solicitacao.user_id THEN
        SELECT email INTO v_outro_vinculo FROM public.perfis_usuarios WHERE id = v_motorista.user_id;
        RETURN jsonb_build_object(
            'sucesso', false, 
            'codigo', 'MOTORISTA_JA_VINCULADO',
            'mensagem', 'Este cadastro de motorista já está vinculado a outro usuário (' || COALESCE(v_outro_vinculo.email, 'outro e-mail') || ').'
        );
    END IF;

    UPDATE public.motoristas
    SET 
        empresa_id = v_solicitacao.empresa_id,
        user_id = v_solicitacao.user_id,
        ativo = TRUE,
        status = 'disponivel',
        updated_at = timezone('utc'::text, now())
    WHERE id = p_motorista_id;

    UPDATE public.solicitacoes_acesso
    SET 
        status = 'aprovado',
        motorista_vinculado_id = p_motorista_id,
        decidido_por = v_gestor_id,
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = p_solicitacao_id;

    UPDATE public.empresa_membros
    SET 
        status = 'aprovado',
        papel = 'motorista',
        motorista_id = p_motorista_id,
        aprovado_por = v_gestor_id,
        aprovado_em = timezone('utc'::text, now()),
        motivo_decisao = 'Aprovado pelo gestor',
        updated_at = timezone('utc'::text, now())
    WHERE empresa_id = v_solicitacao.empresa_id AND user_id = v_solicitacao.user_id;

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motorista_id, motivo, executado_por
    )
    VALUES (
        v_solicitacao.empresa_id, v_solicitacao.user_id, 'aprovado_motorista',
        v_solicitacao.status, 'aprovado', p_motorista_id, 'Motorista vinculado: ' || v_motorista.nome, v_gestor_id
    );

    RETURN jsonb_build_object(
        'sucesso', true,
        'codigo', 'SUCESSO',
        'mensagem', 'Motorista ' || v_motorista.nome || ' aprovado e vinculado com sucesso!',
        'solicitacao_id', p_solicitacao_id,
        'motorista_id', p_motorista_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.rejeitar_solicitacao_acesso(
    p_solicitacao_id UUID,
    p_motivo TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_gestor_id UUID;
    v_solicitacao RECORD;
BEGIN
    v_gestor_id := auth.uid();
    IF v_gestor_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado.';
    END IF;

    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'MOTIVO_OBRIGATORIO', 'mensagem', 'O motivo da rejeição é obrigatório.');
    END IF;

    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE id = p_solicitacao_id;

    IF v_solicitacao IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'SOLICITACAO_NAO_ENCONTRADA', 'mensagem', 'Solicitação não encontrada.');
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'PERMISSAO_NEGADA', 'mensagem', 'Ação negada: você não é gestor autorizado desta empresa.');
    END IF;

    UPDATE public.solicitacoes_acesso
    SET 
        status = 'rejeitado',
        motivo_decisao = p_motivo,
        decidido_por = v_gestor_id,
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = p_solicitacao_id;

    UPDATE public.empresa_membros
    SET 
        status = 'rejeitado',
        motivo_decisao = p_motivo,
        updated_at = timezone('utc'::text, now())
    WHERE empresa_id = v_solicitacao.empresa_id AND user_id = v_solicitacao.user_id;

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motivo, executado_por
    )
    VALUES (
        v_solicitacao.empresa_id, v_solicitacao.user_id, 'rejeitado',
        v_solicitacao.status, 'rejeitado', p_motivo, v_gestor_id
    );

    RETURN jsonb_build_object('sucesso', true, 'codigo', 'SUCESSO', 'mensagem', 'Solicitação rejeitada com sucesso.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.suspender_acesso_membro(
    p_membro_id UUID,
    p_motivo TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_gestor_id UUID;
    v_membro RECORD;
BEGIN
    v_gestor_id := auth.uid();
    IF v_gestor_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado.';
    END IF;

    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'MOTIVO_OBRIGATORIO', 'mensagem', 'A justificativa de suspensão é obrigatória.');
    END IF;

    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE id = p_membro_id
       OR user_id = p_membro_id
       OR id = (SELECT em.id FROM public.empresa_membros em JOIN public.solicitacoes_acesso sa ON sa.user_id = em.user_id AND sa.empresa_id = em.empresa_id WHERE sa.id = p_membro_id LIMIT 1);

    IF v_membro IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'MEMBRO_NAO_ENCONTRADO', 'mensagem', 'Membro não encontrado.');
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'PERMISSAO_NEGADA', 'mensagem', 'Permissão negada.');
    END IF;

    UPDATE public.empresa_membros
    SET status = 'suspenso', motivo_decisao = p_motivo, updated_at = timezone('utc'::text, now())
    WHERE id = v_membro.id;

    UPDATE public.solicitacoes_acesso
    SET status = 'suspenso', motivo_decisao = p_motivo, updated_at = timezone('utc'::text, now())
    WHERE empresa_id = v_membro.empresa_id AND user_id = v_membro.user_id;

    IF v_membro.motorista_id IS NOT NULL THEN
        UPDATE public.motoristas
        SET status = 'offline', updated_at = timezone('utc'::text, now())
        WHERE id = v_membro.motorista_id;
    END IF;

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motorista_id, motivo, executado_por
    )
    VALUES (
        v_membro.empresa_id, v_membro.user_id, 'suspenso', v_membro.status,
        'suspenso', v_membro.motorista_id, p_motivo, v_gestor_id
    );

    RETURN jsonb_build_object('sucesso', true, 'codigo', 'SUCESSO', 'mensagem', 'Acesso operacional suspenso.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.reativar_acesso_membro(
    p_membro_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_gestor_id UUID;
    v_membro RECORD;
    v_motorista RECORD;
    v_outro_membro RECORD;
BEGIN
    v_gestor_id := auth.uid();
    IF v_gestor_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado.';
    END IF;

    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE id = p_membro_id
       OR user_id = p_membro_id
       OR id = (SELECT em.id FROM public.empresa_membros em JOIN public.solicitacoes_acesso sa ON sa.user_id = em.user_id AND sa.empresa_id = em.empresa_id WHERE sa.id = p_membro_id LIMIT 1);

    IF v_membro IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'MEMBRO_NAO_ENCONTRADO', 'mensagem', 'Membro não encontrado.');
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'PERMISSAO_NEGADA', 'mensagem', 'Permissão negada.');
    END IF;

    IF v_membro.status != 'suspenso' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'STATUS_INVALIDO', 'mensagem', 'Apenas membros suspensos podem ser reativados.');
    END IF;

    IF v_membro.papel = 'motorista' THEN
        IF v_membro.motorista_id IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', false,
                'codigo', 'SEM_MOTORISTA_VINCULADO',
                'mensagem', 'Não é possível reativar sem um cadastro de motorista válido associado. Realize a aprovação e vinculação novamente.'
            );
        END IF;

        SELECT * INTO v_motorista FROM public.motoristas WHERE id = v_membro.motorista_id;
        IF v_motorista IS NULL OR v_motorista.empresa_id != v_membro.empresa_id THEN
            RETURN jsonb_build_object(
                'sucesso', false,
                'codigo', 'MOTORISTA_INVALIDO',
                'mensagem', 'O cadastro de motorista associado não pertence mais a esta empresa.'
            );
        END IF;

        IF v_motorista.user_id IS NOT NULL AND v_motorista.user_id != v_membro.user_id THEN
            SELECT email INTO v_outro_membro FROM public.perfis_usuarios WHERE id = v_motorista.user_id;
            RETURN jsonb_build_object(
                'sucesso', false,
                'codigo', 'CONFLITO_VINCULO',
                'mensagem', 'O cadastro deste motorista foi associado a outro usuário (' || COALESCE(v_outro_membro.email, 'outro e-mail') || ') durante a suspensão. Reatribua manualmente.'
            );
        END IF;

        UPDATE public.motoristas
        SET user_id = v_membro.user_id,
            ativo = TRUE,
            status = 'disponivel',
            updated_at = timezone('utc'::text, now())
        WHERE id = v_membro.motorista_id;
    END IF;

    UPDATE public.empresa_membros
    SET status = 'aprovado',
        motivo_decisao = 'Reativado pelo gestor',
        updated_at = timezone('utc'::text, now())
    WHERE id = p_membro_id;

    UPDATE public.solicitacoes_acesso
    SET status = 'aprovado',
        motivo_decisao = 'Reativado pelo gestor',
        updated_at = timezone('utc'::text, now())
    WHERE empresa_id = v_membro.empresa_id AND user_id = v_membro.user_id;

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motorista_id, motivo, executado_por
    )
    VALUES (
        v_membro.empresa_id, v_membro.user_id, 'reativado', 'suspenso',
        'aprovado', v_membro.motorista_id, 'Acesso reativado pelo gestor', v_gestor_id
    );

    RETURN jsonb_build_object('sucesso', true, 'codigo', 'SUCESSO', 'mensagem', 'Acesso operacional reativado com sucesso.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.alterar_papel_membro(
    p_membro_id UUID,
    p_novo_papel TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_admin_id UUID;
    v_membro RECORD;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_AUTORIZADO', 'mensagem', 'Não autorizado.');
    END IF;

    IF p_novo_papel NOT IN ('admin', 'gestor', 'motorista') THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'PAPEL_INVALIDO', 'mensagem', 'Papel inválido. Opções: admin, gestor, motorista.');
    END IF;

    SELECT * INTO v_membro FROM public.empresa_membros WHERE id = p_membro_id;
    IF v_membro IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'MEMBRO_NAO_ENCONTRADO', 'mensagem', 'Membro não encontrado.');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.empresa_membros 
        WHERE empresa_id = v_membro.empresa_id 
          AND user_id = v_admin_id 
          AND papel = 'admin' 
          AND status = 'aprovado'
    ) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'PERMISSAO_NEGADA', 'mensagem', 'Apenas administradores aprovados podem alterar o papel de membros.');
    END IF;

    UPDATE public.empresa_membros
    SET papel = p_novo_papel,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_membro_id;

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motivo, executado_por, detalhes
    )
    VALUES (
        v_membro.empresa_id, v_membro.user_id, 'alteracao_papel_membro', v_membro.status, v_membro.status,
        'Papel alterado de ' || v_membro.papel || ' para ' || p_novo_papel, v_admin_id,
        jsonb_build_object('papel_anterior', v_membro.papel, 'novo_papel', p_novo_papel)
    );

    RETURN jsonb_build_object('sucesso', true, 'codigo', 'SUCESSO', 'mensagem', 'Papel alterado com sucesso para ' || p_novo_papel);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.despachar_rota_transacional(
    p_dados JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_gestor_id UUID;
    v_empresa_id UUID;
    v_motorista_id UUID;
    v_idempotency_key TEXT;
    v_rota_existente RECORD;
    v_motorista RECORD;
    v_nova_rota_id UUID;
    v_parada JSONB;
    v_idx INT;
    v_cliente_endereco_id UUID;
    v_lat NUMERIC(10, 7);
    v_lng NUMERIC(10, 7);
    v_endereco_obj JSONB;
    v_codigo_rastreio TEXT;
    v_paradas_inseridas INT := 0;
BEGIN
    v_gestor_id := auth.uid();
    IF v_gestor_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado. Autentique-se primeiro.';
    END IF;

    v_empresa_id := (p_dados->>'empresa_id')::UUID;
    v_motorista_id := (p_dados->>'motorista_id')::UUID;
    v_idempotency_key := p_dados->>'idempotency_key';

    IF v_empresa_id IS NULL OR v_motorista_id IS NULL THEN
        RAISE EXCEPTION 'Parâmetros obrigatórios ausentes: empresa_id e motorista_id.';
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_empresa_id) THEN
        RAISE EXCEPTION 'Ação negada: usuário não é gestor aprovado desta empresa.';
    END IF;

    IF v_idempotency_key IS NOT NULL AND TRIM(v_idempotency_key) != '' THEN
        SELECT id, status, motorista_id INTO v_rota_existente
        FROM public.rotas_planejadas
        WHERE empresa_id = v_empresa_id
          AND ordem_paradas_json->>'idempotency_key' = v_idempotency_key;

        IF v_rota_existente IS NOT NULL THEN
            RETURN jsonb_build_object(
                'sucesso', true,
                'codigo', 'ROTA_JA_EXISTENTE',
                'rota_id', v_rota_existente.id,
                'status', v_rota_existente.status,
                'motorista_id', v_rota_existente.motorista_id,
                'mensagem', 'Rota já processada anteriormente (retorno idempotente).'
            );
        END IF;
    END IF;

    SELECT * INTO v_motorista
    FROM public.motoristas
    WHERE id = v_motorista_id
      AND empresa_id = v_empresa_id
      AND ativo = TRUE
    FOR UPDATE;

    IF v_motorista IS NULL THEN
        RAISE EXCEPTION 'Motorista não encontrado, inativo ou pertencente a outra empresa.';
    END IF;

    IF v_motorista.user_id IS NULL THEN
        RAISE EXCEPTION 'O motorista % ainda não possui conta de aplicativo vinculada.', v_motorista.nome;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.empresa_membros
        WHERE empresa_id = v_empresa_id
          AND user_id = v_motorista.user_id
          AND papel = 'motorista'
          AND status = 'aprovado'
    ) THEN
        RAISE EXCEPTION 'O acesso do motorista % não está aprovado ou está suspenso.', v_motorista.nome;
    END IF;

    v_nova_rota_id := gen_random_uuid();

    INSERT INTO public.rotas_planejadas (
        id,
        empresa_id,
        motorista_id,
        status,
        distancia_original_km,
        tempo_original_minutos,
        distancia_otimizada_km,
        tempo_otimizado_minutos,
        percentual_economia_km,
        percentual_economia_tempo,
        ordem_paradas_json
    )
    VALUES (
        v_nova_rota_id,
        v_empresa_id,
        v_motorista_id,
        'planejada',
        COALESCE((p_dados->>'distancia_original_km')::NUMERIC, 0),
        COALESCE((p_dados->>'tempo_original_minutos')::NUMERIC, 0),
        COALESCE((p_dados->>'distancia_otimizada_km')::NUMERIC, 0),
        COALESCE((p_dados->>'tempo_otimizado_minutos')::NUMERIC, 0),
        COALESCE((p_dados->>'percentual_economia_km')::NUMERIC, 0),
        COALESCE((p_dados->>'percentual_economia_tempo')::NUMERIC, 0),
        jsonb_set(
            COALESCE(p_dados->'paradas', '[]'::jsonb),
            '{idempotency_key}',
            to_jsonb(COALESCE(v_idempotency_key, v_nova_rota_id::TEXT))
        )
    );

    v_idx := 0;
    FOR v_parada IN SELECT * FROM jsonb_array_elements(p_dados->'paradas')
    LOOP
        v_idx := v_idx + 1;
        v_endereco_obj := v_parada->'endereco';

        IF v_endereco_obj IS NULL THEN
            RAISE EXCEPTION 'Parada % não possui informações de endereço.', v_idx;
        END IF;

        v_lat := (v_endereco_obj->>'latitude')::NUMERIC;
        v_lng := (v_endereco_obj->>'longitude')::NUMERIC;

        IF v_lat IS NULL OR v_lng IS NULL OR (v_lat = 0 AND v_lng = 0) OR v_lat < -90 OR v_lat > 90 OR v_lng < -180 OR v_lng > 180 THEN
            RAISE EXCEPTION 'Parada % possui coordenadas inválidas ou ausentes. Geocodificação real obrigatória.', v_idx;
        END IF;

        IF v_endereco_obj->>'id' IS NOT NULL AND EXISTS (SELECT 1 FROM public.clientes_enderecos WHERE id = (v_endereco_obj->>'id')::UUID) THEN
            v_cliente_endereco_id := (v_endereco_obj->>'id')::UUID;
        ELSE
            INSERT INTO public.clientes_enderecos (
                empresa_id,
                nome_identificador,
                destinatario_padrao,
                endereco_completo,
                numero,
                bairro,
                cidade,
                cep,
                latitude,
                longitude,
                tipo_local,
                observacoes_acesso
            )
            VALUES (
                v_empresa_id,
                COALESCE(v_endereco_obj->>'nome_identificador', v_parada->>'unidade_apartamento', 'Ponto de Entrega'),
                v_parada->>'destinatario_nome',
                COALESCE(v_endereco_obj->>'endereco_completo', 'Endereço sem logradouro'),
                COALESCE(v_endereco_obj->>'numero', 'S/N'),
                COALESCE(v_endereco_obj->>'bairro', 'Bairro'),
                COALESCE(v_endereco_obj->>'cidade', 'Cidade'),
                COALESCE(v_endereco_obj->>'cep', '00000-000'),
                v_lat,
                v_lng,
                COALESCE(v_endereco_obj->>'tipo_local', 'condominio_horizontal'),
                v_endereco_obj->>'observacoes_acesso'
            )
            RETURNING id INTO v_cliente_endereco_id;
        END IF;

        v_codigo_rastreio := COALESCE(v_parada->>'codigo_rastreio', 'EC-' || floor(100000 + random() * 900000)::TEXT);

        INSERT INTO public.entregas (
            empresa_id,
            codigo_rastreio,
            cliente_endereco_id,
            destinatario_nome,
            destinatario_telefone,
            unidade_apartamento,
            status,
            prioridade,
            tipo_tarefa,
            descricao_outro,
            volumes_qtd,
            motorista_id,
            rota_id,
            ordem_na_rota,
            observacoes_gestor
        )
        VALUES (
            v_empresa_id,
            v_codigo_rastreio,
            v_cliente_endereco_id,
            COALESCE(v_parada->>'destinatario_nome', 'Destinatário'),
            v_parada->>'destinatario_telefone',
            v_parada->>'unidade_apartamento',
            'atribuida',
            COALESCE(v_parada->>'prioridade', 'normal'),
            COALESCE(v_parada->>'tipo_tarefa', 'entrega'),
            v_parada->>'descricao_outro',
            COALESCE((v_parada->>'volumes_qtd')::INT, 1),
            v_motorista_id,
            v_nova_rota_id,
            v_idx,
            v_parada->>'observacoes_gestor'
        );

        v_paradas_inseridas := v_paradas_inseridas + 1;
    END LOOP;

    UPDATE public.motoristas
    SET status = 'em_rota', updated_at = timezone('utc'::text, now())
    WHERE id = v_motorista_id;

    RETURN jsonb_build_object(
        'sucesso', true,
        'codigo', 'SUCESSO',
        'rota_id', v_nova_rota_id,
        'motorista_id', v_motorista_id,
        'motorista_nome', v_motorista.nome,
        'total_paradas', v_paradas_inseridas,
        'mensagem', 'Rota despachada e paradas gravadas com sucesso de forma transacional.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.registrar_conclusao_entrega(
    p_entrega_id UUID,
    p_sucesso BOOLEAN,
    p_motivo_falha TEXT DEFAULT NULL,
    p_tempo_portaria NUMERIC DEFAULT 0,
    p_tempo_deslocamento NUMERIC DEFAULT 0,
    p_data_hora_chegada TIMESTAMPTZ DEFAULT NULL,
    p_data_hora_conclusao TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_entrega RECORD;
    v_motorista RECORD;
    v_tempo_total NUMERIC(5, 2);
    v_chegada TIMESTAMPTZ;
    v_conclusao TIMESTAMPTZ;
    v_novo_status TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado. Autentique-se.';
    END IF;

    SELECT * INTO v_entrega
    FROM public.entregas
    WHERE id = p_entrega_id;

    IF v_entrega IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ENTREGA_NAO_ENCONTRADA', 'mensagem', 'Entrega não encontrada.');
    END IF;

    SELECT m.* INTO v_motorista
    FROM public.motoristas m
    JOIN public.empresa_membros em ON em.user_id = v_user_id AND em.motorista_id = m.id AND em.status = 'aprovado'
    WHERE m.id = v_entrega.motorista_id
      AND m.user_id = v_user_id;

    IF v_motorista IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Você não é o motorista atribuído a esta entrega ou seu acesso não está ativo.');
    END IF;

    v_chegada := COALESCE(p_data_hora_chegada, timezone('utc'::text, now()) - INTERVAL '10 minutes');
    v_conclusao := COALESCE(p_data_hora_conclusao, timezone('utc'::text, now()));
    v_tempo_total := COALESCE(p_tempo_portaria, 0) + COALESCE(p_tempo_deslocamento, 0);
    IF v_tempo_total <= 0 THEN
        v_tempo_total := GREATEST(1, ROUND(EXTRACT(EPOCH FROM (v_conclusao - v_chegada)) / 60, 2));
    END IF;

    v_novo_status := CASE WHEN p_sucesso THEN 'entregue' ELSE 'tentativa_falha' END;

    UPDATE public.entregas
    SET status = v_novo_status,
        data_hora_entrega = v_conclusao,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_entrega_id;

    INSERT INTO public.historico_atendimentos (
        entrega_id,
        cliente_endereco_id,
        motorista_id,
        tempo_portaria_espera_minutos,
        tempo_deslocamento_interno_minutos,
        tempo_total_minutos,
        data_hora_chegada,
        data_hora_conclusao,
        sucesso,
        motivo_falha
    )
    VALUES (
        p_entrega_id,
        v_entrega.cliente_endereco_id,
        v_motorista.id,
        COALESCE(p_tempo_portaria, 0),
        COALESCE(p_tempo_deslocamento, 0),
        v_tempo_total,
        v_chegada,
        v_conclusao,
        p_sucesso,
        p_motivo_falha
    );

    RETURN jsonb_build_object(
        'sucesso', true,
        'codigo', 'SUCESSO',
        'status', v_novo_status,
        'data_hora_entrega', v_conclusao,
        'mensagem', CASE WHEN p_sucesso THEN 'Entrega concluída com sucesso!' ELSE 'Ocorrência de entrega registrada com sucesso.' END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.bootstrap_primeiro_gestor(
    p_email_gestor TEXT,
    p_codigo_convite TEXT,
    p_nome_empresa TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_empresa RECORD;
    v_membro RECORD;
BEGIN
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE LOWER(TRIM(email)) = LOWER(TRIM(p_email_gestor));

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Conta de usuário com e-mail % não encontrada em auth.users. O usuário deve realizar cadastro/login prévio.', p_email_gestor;
    END IF;

    SELECT * INTO v_empresa
    FROM public.empresas
    WHERE UPPER(TRIM(codigo_convite)) = UPPER(TRIM(p_codigo_convite));

    IF v_empresa IS NULL THEN
        IF p_nome_empresa IS NULL THEN
            p_nome_empresa := 'Empresa ' || UPPER(TRIM(p_codigo_convite));
        END IF;

        INSERT INTO public.empresas (nome, codigo_convite, ativa)
        VALUES (p_nome_empresa, UPPER(TRIM(p_codigo_convite)), TRUE)
        RETURNING * INTO v_empresa;
    END IF;

    INSERT INTO public.perfis_usuarios (id, email, nome)
    VALUES (v_user_id, LOWER(TRIM(p_email_gestor)), COALESCE((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = v_user_id), 'Administrador'))
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        updated_at = timezone('utc'::text, now());

    INSERT INTO public.empresa_membros (
        empresa_id, user_id, papel, status, motivo_decisao, aprovado_em
    )
    VALUES (
        v_empresa.id, v_user_id, 'admin', 'aprovado', 'Bootstrap administrativo de primeiro gestor', timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel = 'admin',
        status = 'aprovado',
        motivo_decisao = 'Bootstrap administrativo de primeiro gestor',
        aprovado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    RETURNING * INTO v_membro;

    INSERT INTO public.solicitacoes_acesso (
        empresa_id, user_id, papel_solicitado, status, motivo_decisao, decidido_em
    )
    VALUES (
        v_empresa.id, v_user_id, 'motorista', 'aprovado', 'Aprovado via bootstrap administrativo como gestor', timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        status = 'aprovado',
        motivo_decisao = 'Aprovado via bootstrap administrativo como gestor',
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now());

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motivo, executado_por
    )
    VALUES (
        v_empresa.id, v_user_id, 'bootstrap_primeiro_gestor', NULL, 'aprovado',
        'Primeiro administrador/gestor ativado para a empresa ' || v_empresa.nome, v_user_id
    );

    RETURN jsonb_build_object(
        'sucesso', true,
        'codigo', 'SUCESSO',
        'user_id', v_user_id,
        'email', p_email_gestor,
        'empresa_id', v_empresa.id,
        'empresa_nome', v_empresa.nome,
        'papel', 'admin',
        'status', 'aprovado',
        'mensagem', 'Primeiro gestor configurado com sucesso.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.bootstrap_primeiro_gestor(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bootstrap_primeiro_gestor(TEXT, TEXT, TEXT) TO service_role;

-- ------------------------------------------------------------------------------
-- 15. ROW LEVEL SECURITY (RLS) ESTRITO
-- ------------------------------------------------------------------------------
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfis_usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.empresa_membros ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.solicitacoes_acesso ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_acessos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes_enderecos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rotas_planejadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historico_atendimentos ENABLE ROW LEVEL SECURITY;

-- Limpeza de políticas anteriores para idempotência
DROP POLICY IF EXISTS "Membros visualizam sua empresa" ON public.empresas;
DROP POLICY IF EXISTS "Usuario gerencia seu perfil" ON public.perfis_usuarios;
DROP POLICY IF EXISTS "Gestores visualizam perfis de solicitantes da sua empresa" ON public.perfis_usuarios;
DROP POLICY IF EXISTS "Gestores visualizam perfis de membros da sua empresa" ON public.perfis_usuarios;
DROP POLICY IF EXISTS "Usuario visualiza sua propria solicitacao" ON public.solicitacoes_acesso;
DROP POLICY IF EXISTS "Gestores gerenciam solicitacoes de sua empresa" ON public.solicitacoes_acesso;
DROP POLICY IF EXISTS "Usuario visualiza seu vinculo" ON public.empresa_membros;
DROP POLICY IF EXISTS "Gestores gerenciam membros da empresa" ON public.empresa_membros;
DROP POLICY IF EXISTS "Gestores visualizam auditoria de sua empresa" ON public.auditoria_acessos;
DROP POLICY IF EXISTS "Apenas gestores visualizam auditoria de sua empresa" ON public.auditoria_acessos;
DROP POLICY IF EXISTS "Gestores gerenciam motoristas da sua empresa" ON public.motoristas;
DROP POLICY IF EXISTS "Motorista aprovado consulta seu proprio cadastro" ON public.motoristas;
DROP POLICY IF EXISTS "Gestores gerenciam clientes da empresa" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Motoristas aprovados leem enderecos de entregas ativas" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Motoristas aprovados leem enderecos de entregas atribuidas" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Gestores gerenciam rotas da empresa" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Motorista aprovado consulta apenas suas rotas" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Motorista aprovado atualiza status de suas rotas" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Motorista aprovado atualiza apenas suas rotas" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Gestores gerenciam entregas da empresa" ON public.entregas;
DROP POLICY IF EXISTS "Motorista aprovado consulta apenas suas entregas" ON public.entregas;
DROP POLICY IF EXISTS "Motorista aprovado atualiza status de suas entregas" ON public.entregas;
DROP POLICY IF EXISTS "Gestores gerenciam historico" ON public.historico_atendimentos;
DROP POLICY IF EXISTS "Motoristas inserem historico de suas entregas" ON public.historico_atendimentos;
DROP POLICY IF EXISTS "Motoristas aprovados inserem historico de suas entregas" ON public.historico_atendimentos;

-- Recriação das políticas seguras
CREATE POLICY "Membros visualizam sua empresa" ON public.empresas
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros
        WHERE empresa_id = public.empresas.id
          AND user_id = auth.uid()
    )
);

CREATE POLICY "Usuario gerencia seu perfil" ON public.perfis_usuarios
FOR ALL TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

CREATE POLICY "Gestores visualizam perfis de membros da sua empresa" ON public.perfis_usuarios
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em_alvo
        JOIN public.empresa_membros em_gestor ON em_gestor.empresa_id = em_alvo.empresa_id
        WHERE em_alvo.user_id = public.perfis_usuarios.id
          AND em_gestor.user_id = auth.uid()
          AND em_gestor.papel IN ('admin', 'gestor')
          AND em_gestor.status = 'aprovado'
    )
);

CREATE POLICY "Usuario visualiza sua propria solicitacao" ON public.solicitacoes_acesso
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Gestores gerenciam solicitacoes de sua empresa" ON public.solicitacoes_acesso
FOR ALL TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Usuario visualiza seu vinculo" ON public.empresa_membros
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Gestores gerenciam membros da empresa" ON public.empresa_membros
FOR ALL TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Apenas gestores visualizam auditoria de sua empresa" ON public.auditoria_acessos
FOR SELECT TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Gestores gerenciam motoristas da sua empresa" ON public.motoristas
FOR ALL TO authenticated
USING (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Motorista aprovado consulta seu proprio cadastro" ON public.motoristas
FOR SELECT TO authenticated
USING (
    user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM public.empresa_membros em
        WHERE em.user_id = auth.uid()
          AND em.motorista_id = public.motoristas.id
          AND em.status = 'aprovado'
    )
);

CREATE POLICY "Gestores gerenciam clientes da empresa" ON public.clientes_enderecos
FOR ALL TO authenticated
USING (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Motoristas aprovados leem enderecos de entregas atribuidas" ON public.clientes_enderecos
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.entregas e
        JOIN public.empresa_membros em ON em.user_id = auth.uid() AND em.motorista_id = e.motorista_id AND em.status = 'aprovado'
        WHERE e.cliente_endereco_id = public.clientes_enderecos.id
          AND e.status IN ('atribuida', 'em_transito')
    )
);

CREATE POLICY "Gestores gerenciam rotas da empresa" ON public.rotas_planejadas
FOR ALL TO authenticated
USING (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Motorista aprovado consulta apenas suas rotas" ON public.rotas_planejadas
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        JOIN public.motoristas m ON m.id = em.motorista_id
        WHERE em.user_id = auth.uid()
          AND em.status = 'aprovado'
          AND em.papel = 'motorista'
          AND m.id = public.rotas_planejadas.motorista_id
          AND m.user_id = auth.uid()
    )
);

CREATE POLICY "Motorista aprovado atualiza apenas suas rotas" ON public.rotas_planejadas
FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        JOIN public.motoristas m ON m.id = em.motorista_id
        WHERE em.user_id = auth.uid()
          AND em.status = 'aprovado'
          AND em.papel = 'motorista'
          AND m.id = public.rotas_planejadas.motorista_id
          AND m.user_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        JOIN public.motoristas m ON m.id = em.motorista_id
        WHERE em.user_id = auth.uid()
          AND em.status = 'aprovado'
          AND em.papel = 'motorista'
          AND m.id = public.rotas_planejadas.motorista_id
          AND m.user_id = auth.uid()
    )
);

CREATE POLICY "Gestores gerenciam entregas da empresa" ON public.entregas
FOR ALL TO authenticated
USING (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Motorista aprovado consulta apenas suas entregas" ON public.entregas
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        JOIN public.motoristas m ON m.id = em.motorista_id
        WHERE em.user_id = auth.uid()
          AND em.status = 'aprovado'
          AND em.papel = 'motorista'
          AND m.id = public.entregas.motorista_id
          AND m.user_id = auth.uid()
    )
);

CREATE POLICY "Motorista aprovado atualiza status de suas entregas" ON public.entregas
FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        JOIN public.motoristas m ON m.id = em.motorista_id
        WHERE em.user_id = auth.uid()
          AND em.status = 'aprovado'
          AND em.papel = 'motorista'
          AND m.id = public.entregas.motorista_id
          AND m.user_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        JOIN public.motoristas m ON m.id = em.motorista_id
        WHERE em.user_id = auth.uid()
          AND em.status = 'aprovado'
          AND em.papel = 'motorista'
          AND m.id = public.entregas.motorista_id
          AND m.user_id = auth.uid()
    )
);

CREATE POLICY "Gestores gerenciam historico" ON public.historico_atendimentos
FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.entregas e
        WHERE e.id = public.historico_atendimentos.entrega_id
          AND (e.empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(e.empresa_id))
    )
);

CREATE POLICY "Motoristas aprovados inserem historico de suas entregas" ON public.historico_atendimentos
FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.motoristas m
        JOIN public.empresa_membros em ON em.user_id = auth.uid() AND em.motorista_id = m.id AND em.status = 'aprovado'
        WHERE m.id = public.historico_atendimentos.motorista_id
          AND m.user_id = auth.uid()
    )
);

-- ------------------------------------------------------------------------------
-- 16. CONFIGURAÇÃO DE SUPABASE REALTIME
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.empresa_membros;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.solicitacoes_acesso;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.rotas_planejadas;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.entregas;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;
