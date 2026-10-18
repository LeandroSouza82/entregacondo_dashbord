-- ==============================================================================
-- ENTREGA CONDO - MODELAGEM DE DADOS DO BANCO SUPABASE (GERADO DETERMINISTICAMENTE)
-- Gerado por: scripts/build_schema.js
-- Fonte: supabase/modules-sql/ e supabase/functions-sql/
-- Não edite este arquivo manualmente. Edite os módulos individuais correspondentes.
-- ==============================================================================


-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/01_tables_core.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 01_tables_core.sql
-- Tabelas estruturais: empresas, perfis_usuarios, empresa_membros,
-- solicitacoes_acesso, auditoria_acessos, motoristas.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. TABELA: empresas
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

-- 2. TABELA: perfis_usuarios
CREATE TABLE IF NOT EXISTS public.perfis_usuarios (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    nome VARCHAR(255) NOT NULL,
    telefone VARCHAR(30),
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. TABELA: motoristas
-- Cadastro operacional de frota da empresa. empresa_id é NOT NULL.
CREATE TABLE IF NOT EXISTS public.motoristas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    nome VARCHAR(255) NOT NULL,
    telefone VARCHAR(30) NOT NULL,
    email VARCHAR(255),
    veiculo_modelo VARCHAR(100) NOT NULL,
    veiculo_placa VARCHAR(20) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'disponivel'
        CHECK (status IN ('disponivel', 'em_rota', 'pausado', 'offline')),
    latitude_atual NUMERIC(10, 7),
    longitude_atual NUMERIC(10, 7),
    capacidade_max_pacotes INT NOT NULL DEFAULT 60,
    avaliacao_media NUMERIC(3, 2) NOT NULL DEFAULT 5.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_motorista_empresa_placa UNIQUE (empresa_id, veiculo_placa)
);

-- 4. TABELA: empresa_membros
-- Vinculo formal de autorização e controle de papéis.
CREATE TABLE IF NOT EXISTS public.empresa_membros (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    papel VARCHAR(30) NOT NULL DEFAULT 'motorista'
        CHECK (papel IN ('admin', 'gestor', 'motorista')),
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'aprovado', 'rejeitado', 'suspenso')),
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    motivo_decisao TEXT,
    aprovado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    aprovado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_empresa_membro UNIQUE (empresa_id, user_id)
);

-- 5. TABELA: solicitacoes_acesso
-- Fila de solicitações de entrada de motoristas.
CREATE TABLE IF NOT EXISTS public.solicitacoes_acesso (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    papel_solicitado VARCHAR(30) NOT NULL DEFAULT 'motorista'
        CHECK (papel_solicitado = 'motorista'),
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'aprovado', 'rejeitado', 'suspenso')),
    motorista_vinculado_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    motivo_decisao TEXT,
    decidido_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    decidido_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_solicitacao_ativa UNIQUE (empresa_id, user_id)
);

-- 6. TABELA: auditoria_acessos
-- Trilha imutável de decisões de acesso e papéis.
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
    detalhes JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/01b_helpers.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 01b_helpers.sql
-- Funções auxiliares de autorização, contexto e validação de segurança.
-- DEFINIDAS ANTES de RPCs, Políticas de Storage e Políticas RLS.
-- ==============================================================================

-- 1. Helper para conversão segura de texto para UUID (evita crash em paths inválidos de storage)
CREATE OR REPLACE FUNCTION public.fn_safe_uuid(p_val TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_val IS NULL OR p_val !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN NULL;
    END IF;
    RETURN p_val::uuid;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- 2. Verifica se o usuário pertence a uma empresa com status aprovado
CREATE OR REPLACE FUNCTION public.fn_usuario_pertence_empresa(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros
        WHERE empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND status = 'aprovado'
    );
$$;

-- 3. Verifica se o usuário é gestor ou admin aprovado de uma empresa
CREATE OR REPLACE FUNCTION public.fn_usuario_e_gestor_empresa(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros
        WHERE empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND papel IN ('admin', 'gestor')
          AND status = 'aprovado'
    );
$$;

-- 4. Verifica se o usuário é administrador master aprovado de uma empresa
CREATE OR REPLACE FUNCTION public.fn_usuario_e_admin_empresa(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros
        WHERE empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND papel = 'admin'
          AND status = 'aprovado'
    );
$$;

-- 5. Verifica se o usuário é motorista aprovado e ativo da empresa
CREATE OR REPLACE FUNCTION public.fn_usuario_e_motorista_ativo(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros
        WHERE empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND papel = 'motorista'
          AND status = 'aprovado'
    );
$$;

-- 6. Retorna o motorista_id vinculado ao usuário aprovado
CREATE OR REPLACE FUNCTION public.fn_motorista_id_do_usuario(p_user_id UUID DEFAULT auth.uid())
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT em.motorista_id
    FROM public.empresa_membros em
    JOIN public.empresas e ON e.id = em.empresa_id
    WHERE em.user_id = p_user_id
      AND em.status = 'aprovado'
      AND em.motorista_id IS NOT NULL
      AND e.ativa = TRUE
    LIMIT 1;
$$;

-- 7. Validação centralizada de autorização de condutor para operações de veículos/documentos
CREATE OR REPLACE FUNCTION public.fn_validar_autorizacao_condutor(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
    v_solicitacao RECORD;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'autorizado', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    IF p_empresa_id IS NULL THEN
        RETURN jsonb_build_object(
            'autorizado', FALSE,
            'codigo', 'EMPRESA_INVALIDA',
            'mensagem', 'Identificador de empresa inválido.'
        );
    END IF;

    -- 1. Verifica status em empresa_membros
    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE empresa_id = p_empresa_id
      AND user_id = p_user_id;

    IF FOUND THEN
        IF v_membro.status = 'suspenso' THEN
            RETURN jsonb_build_object(
                'autorizado', FALSE,
                'codigo', 'USUARIO_SUSPENSO',
                'mensagem', 'Acesso suspenso pela gestão da empresa.'
            );
        END IF;

        IF v_membro.status = 'aprovado' THEN
            RETURN jsonb_build_object(
                'autorizado', TRUE,
                'codigo', 'MEMBRO_APROVADO',
                'papel', v_membro.papel
            );
        END IF;

        RETURN jsonb_build_object(
            'autorizado', FALSE,
            'codigo', 'ACESSO_NAO_AUTORIZADO',
            'mensagem', 'Vínculo com a empresa não está ativo.'
        );
    END IF;

    -- 2. Se não é membro, verifica se possui solicitação de acesso ativa para cadastro inicial
    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE empresa_id = p_empresa_id
      AND user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF FOUND THEN
        IF v_solicitacao.status = 'pendente' THEN
            RETURN jsonb_build_object(
                'autorizado', TRUE,
                'codigo', 'SOLICITACAO_PENDENTE',
                'papel', 'candidato'
            );
        END IF;

        IF v_solicitacao.status = 'rejeitado' THEN
            RETURN jsonb_build_object(
                'autorizado', FALSE,
                'codigo', 'SOLICITACAO_REJEITADA',
                'mensagem', 'Sua solicitação de acesso a esta empresa foi rejeitada.'
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'autorizado', FALSE,
        'codigo', 'SEM_VINCULO_ATIVO',
        'mensagem', 'Nenhum vínculo ou solicitação pendente encontrada para esta empresa.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/02_tables_vehicles.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 02_tables_vehicles.sql
-- Cadastro de veículos e metadados de documentos/evidências
-- Alinhado estritamente com VEICULO_MOBILE.md (Motos, Carros e 4 Fotos por Ângulo)
-- ==============================================================================

-- 1. TABELA: veiculos_motoristas
CREATE TABLE IF NOT EXISTS public.veiculos_motoristas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    tipo_veiculo VARCHAR(20) NOT NULL CHECK (tipo_veiculo IN ('moto', 'carro')),
    marca VARCHAR(100) NOT NULL,
    modelo VARCHAR(100) NOT NULL,
    placa VARCHAR(20) NOT NULL,
    
    -- Campos exclusivos de MOTO
    compartimento VARCHAR(20) CHECK (compartimento IN ('bau', 'mochila', 'bag')),
    volume_litros NUMERIC(6, 2),
    tamanho_compartimento VARCHAR(20) CHECK (tamanho_compartimento IN ('pequeno', 'medio', 'grande')),
    capacidade_kg NUMERIC(6, 2),

    -- Ciclo de auditoria e aprovação
    status_analise VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status_analise IN ('pendente', 'aprovado', 'rejeitado')),
    motivo_rejeicao TEXT,
    revisao INT NOT NULL DEFAULT 1,
    analisado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    analisado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT uq_veiculo_usuario UNIQUE (user_id),

    -- CONSTRAINT RIGOROSA: Regras de negócio alinhadas a VEICULO_MOBILE.md
    CONSTRAINT chk_veiculo_contrato_mobile CHECK (
        (
            -- REGRA CARRO: Somente marca, modelo e placa. Sem carga, volume ou compartimento.
            tipo_veiculo = 'carro' AND
            compartimento IS NULL AND
            volume_litros IS NULL AND
            tamanho_compartimento IS NULL AND
            capacidade_kg IS NULL
        )
        OR
        (
            -- REGRA MOTO COM BAÚ: volume_litros obrigatório e positivo; sem tamanho categórico.
            tipo_veiculo = 'moto' AND
            compartimento = 'bau' AND
            volume_litros IS NOT NULL AND volume_litros > 0 AND
            tamanho_compartimento IS NULL AND
            capacidade_kg IS NOT NULL AND capacidade_kg > 0
        )
        OR
        (
            -- REGRA MOTO COM MOCHILA OU BAG: tamanho_compartimento obrigatório; sem litros.
            tipo_veiculo = 'moto' AND
            compartimento IN ('mochila', 'bag') AND
            tamanho_compartimento IS NOT NULL AND
            volume_litros IS NULL AND
            capacidade_kg IS NOT NULL AND capacidade_kg > 0
        )
    )
);

-- 2. TABELA: veiculos_documentos
-- Metadados das fotos e documentos veiculares (4 fotos por ângulo, CRLV e complementares).
-- Armazenamento físico dos binários ocorre no bucket privado 'veiculos-documentos'.
CREATE TABLE IF NOT EXISTS public.veiculos_documentos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    veiculo_id UUID NOT NULL REFERENCES public.veiculos_motoristas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    tipo_documento VARCHAR(30) NOT NULL CHECK (tipo_documento IN ('foto_veiculo', 'crlv', 'complementar')),
    angulo_foto VARCHAR(30) CHECK (angulo_foto IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira')),
    nome_arquivo VARCHAR(255) NOT NULL,
    storage_path TEXT NOT NULL,
    mime_type VARCHAR(100) NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'application/pdf')),
    tamanho_bytes INT NOT NULL CHECK (tamanho_bytes > 0 AND tamanho_bytes <= 10485760), -- Max 10 MB
    status_analise VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status_analise IN ('pendente', 'aprovado', 'rejeitado')),
    motivo_rejeicao TEXT,
    analisado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    analisado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    -- Validação: Foto do veículo aceita apenas JPG/PNG (não aceita PDF)
    CONSTRAINT chk_foto_formato CHECK (
        tipo_documento != 'foto_veiculo' OR mime_type IN ('image/jpeg', 'image/png')
    ),

    -- Validação de coerência do ângulo: documentos não possuem ângulo de veículo
    CONSTRAINT chk_angulo_coerencia CHECK (
        (tipo_documento = 'foto_veiculo') OR
        (tipo_documento IN ('crlv', 'complementar') AND angulo_foto IS NULL)
    )
);

-- Índices Únicos Condicionais:
-- 1. Garante exatamente uma foto ativa por ângulo para cada veículo
CREATE UNIQUE INDEX IF NOT EXISTS uq_veiculo_foto_angulo 
ON public.veiculos_documentos (veiculo_id, angulo_foto) 
WHERE tipo_documento = 'foto_veiculo' AND angulo_foto IS NOT NULL;

-- 2. Garante um único CRLV ativo por veículo
CREATE UNIQUE INDEX IF NOT EXISTS uq_veiculo_crlv_ativo 
ON public.veiculos_documentos (veiculo_id) 
WHERE tipo_documento = 'crlv';

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/03_tables_logistics.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 03_tables_logistics.sql
-- Tabelas operacionais: clientes_enderecos, rotas_planejadas, entregas,
-- historico_atendimentos. Todos com empresa_id NOT NULL e constraints estritas.
-- ==============================================================================

-- 1. TABELA: clientes_enderecos
CREATE TABLE IF NOT EXISTS public.clientes_enderecos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    nome_identificador VARCHAR(255) NOT NULL,
    destinatario_padrao VARCHAR(255),
    endereco_completo TEXT NOT NULL,
    numero VARCHAR(50) NOT NULL,
    bairro VARCHAR(100) NOT NULL,
    cidade VARCHAR(100) NOT NULL,
    cep VARCHAR(20) NOT NULL,
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    tempo_medio_minutos NUMERIC(5, 2) NOT NULL DEFAULT 15.00,
    total_entregas_realizadas INT NOT NULL DEFAULT 0,
    tipo_local VARCHAR(50) NOT NULL DEFAULT 'condominio_horizontal'
        CHECK (tipo_local IN ('condominio_horizontal', 'edificio_vertical', 'comercial', 'casa_rua')),
    observacoes_acesso TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2. TABELA: rotas_planejadas
CREATE TABLE IF NOT EXISTS public.rotas_planejadas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    motorista_id UUID NOT NULL REFERENCES public.motoristas(id) ON DELETE RESTRICT,
    idempotency_key VARCHAR(100) NOT NULL,
    payload_hash VARCHAR(64),
    status VARCHAR(30) NOT NULL DEFAULT 'planejada'
        CHECK (status IN ('planejada', 'em_execucao', 'concluida', 'cancelada')),
    distancia_original_km NUMERIC(8, 2) NOT NULL,
    tempo_original_minutos NUMERIC(8, 2) NOT NULL,
    distancia_otimizada_km NUMERIC(8, 2) NOT NULL,
    tempo_otimizado_minutos NUMERIC(8, 2) NOT NULL,
    percentual_economia_km NUMERIC(5, 2) NOT NULL,
    percentual_economia_tempo NUMERIC(5, 2) NOT NULL,
    ordem_paradas_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    iniciada_em TIMESTAMPTZ,
    concluida_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_rota_empresa_idempotency UNIQUE (empresa_id, idempotency_key)
);

-- 3. TABELA: entregas
CREATE TABLE IF NOT EXISTS public.entregas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    codigo_rastreio VARCHAR(50) NOT NULL,
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
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_entrega_codigo UNIQUE (empresa_id, codigo_rastreio)
);

-- 4. TABELA: historico_atendimentos
CREATE TABLE IF NOT EXISTS public.historico_atendimentos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entrega_id UUID NOT NULL REFERENCES public.entregas(id) ON DELETE CASCADE,
    cliente_endereco_id UUID NOT NULL REFERENCES public.clientes_enderecos(id) ON DELETE CASCADE,
    motorista_id UUID NOT NULL REFERENCES public.motoristas(id) ON DELETE CASCADE,
    tempo_portaria_espera_minutos NUMERIC(6, 2) NOT NULL DEFAULT 0.00,
    tempo_deslocamento_interno_minutos NUMERIC(6, 2) NOT NULL DEFAULT 0.00,
    tempo_total_minutos NUMERIC(6, 2) NOT NULL,
    data_hora_chegada TIMESTAMPTZ NOT NULL,
    data_hora_conclusao TIMESTAMPTZ NOT NULL,
    sucesso BOOLEAN NOT NULL DEFAULT TRUE,
    motivo_falha TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/fn_validar_completude_veiculo.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: fn_validar_completude_veiculo.sql
-- Validação centralizada e reutilizável de completude e integridade de veículos.
-- Usada em todas as vias de aprovação e análise (analisar_veiculo_motorista e aprovar_solicitacao_motorista).
-- Reconfere campos cadastrais, as 4 fotos distintas, CRLV e a existência física
-- real de cada evidência em storage.objects.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.fn_validar_completude_veiculo(p_veiculo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_veiculo RECORD;
    v_angulos_presentes TEXT[];
    v_qtd_crlv INT;
    v_doc RECORD;
    v_storage_meta JSONB;
BEGIN
    -- 1. Carrega dados do veículo
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = p_veiculo_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'valido', FALSE,
            'codigo', 'VEICULO_NAO_ENCONTRADO',
            'mensagem', 'Veículo não encontrado no sistema.'
        );
    END IF;

    -- 2. Valida regras cadastrais do veículo (conforme VEICULO_MOBILE.md)
    IF v_veiculo.tipo_veiculo = 'carro' THEN
        IF NULLIF(TRIM(v_veiculo.marca), '') IS NULL OR 
           NULLIF(TRIM(v_veiculo.modelo), '') IS NULL OR 
           NULLIF(TRIM(v_veiculo.placa), '') IS NULL THEN
            RETURN jsonb_build_object(
                'valido', FALSE,
                'codigo', 'DADOS_CARRO_INCOMPLETOS',
                'mensagem', 'Carro com dados cadastrais incompletos (marca, modelo e placa são obrigatórios).'
            );
        END IF;

        IF v_veiculo.compartimento IS NOT NULL OR 
           v_veiculo.volume_litros IS NOT NULL OR 
           v_veiculo.tamanho_compartimento IS NOT NULL OR 
           v_veiculo.capacidade_kg IS NOT NULL THEN
            RETURN jsonb_build_object(
                'valido', FALSE,
                'codigo', 'CARRO_CAMPOS_INDEVIDOS',
                'mensagem', 'Carro não pode conter campos de compartimento ou capacidade nesta versão.'
            );
        END IF;

    ELSIF v_veiculo.tipo_veiculo = 'moto' THEN
        IF NULLIF(TRIM(v_veiculo.marca), '') IS NULL OR 
           NULLIF(TRIM(v_veiculo.modelo), '') IS NULL OR 
           NULLIF(TRIM(v_veiculo.placa), '') IS NULL THEN
            RETURN jsonb_build_object(
                'valido', FALSE,
                'codigo', 'DADOS_MOTO_INCOMPLETOS',
                'mensagem', 'Moto com dados cadastrais incompletos (marca, modelo e placa são obrigatórios).'
            );
        END IF;

        IF v_veiculo.capacidade_kg IS NULL OR v_veiculo.capacidade_kg <= 0 THEN
            RETURN jsonb_build_object(
                'valido', FALSE,
                'codigo', 'CAPACIDADE_KG_OBRIGATORIA',
                'mensagem', 'A capacidade disponível em kg é obrigatória e deve ser maior que zero.'
            );
        END IF;

        IF v_veiculo.compartimento = 'bau' THEN
            IF v_veiculo.volume_litros IS NULL OR v_veiculo.volume_litros <= 0 THEN
                RETURN jsonb_build_object(
                    'valido', FALSE,
                    'codigo', 'VOLUME_LITROS_OBRIGATORIO',
                    'mensagem', 'Moto com baú deve informar volume em litros positivo.'
                );
            END IF;
            IF v_veiculo.tamanho_compartimento IS NOT NULL THEN
                RETURN jsonb_build_object(
                    'valido', FALSE,
                    'codigo', 'BAU_COM_TAMANHO_CATEGORICO',
                    'mensagem', 'Moto com baú não aceita tamanho categórico (use apenas litros).'
                );
            END IF;

        ELSIF v_veiculo.compartimento IN ('mochila', 'bag') THEN
            IF v_veiculo.tamanho_compartimento IS NULL OR 
               v_veiculo.tamanho_compartimento NOT IN ('pequeno', 'medio', 'grande') THEN
                RETURN jsonb_build_object(
                    'valido', FALSE,
                    'codigo', 'TAMANHO_CATEGORICO_OBRIGATORIO',
                    'mensagem', 'Moto com mochila/bag deve selecionar tamanho: pequeno, medio ou grande.'
                );
            END IF;
            IF v_veiculo.volume_litros IS NOT NULL THEN
                RETURN jsonb_build_object(
                    'valido', FALSE,
                    'codigo', 'MOCHILA_COM_LITROS',
                    'mensagem', 'Moto com mochila/bag não aceita especificação em litros.'
                );
            END IF;
        ELSE
            RETURN jsonb_build_object(
                'valido', FALSE,
                'codigo', 'COMPARTIMENTO_INVALIDO',
                'mensagem', 'Compartimento de moto deve ser: bau, mochila ou bag.'
            );
        END IF;
    ELSE
        RETURN jsonb_build_object(
            'valido', FALSE,
            'codigo', 'TIPO_VEICULO_INVALIDO',
            'mensagem', 'Tipo de veículo deve ser moto ou carro.'
        );
    END IF;

    -- 3. Valida presença das 4 fotos distintas por ângulo
    SELECT array_agg(DISTINCT angulo_foto) INTO v_angulos_presentes
    FROM public.veiculos_documentos
    WHERE veiculo_id = v_veiculo.id
      AND tipo_documento = 'foto_veiculo'
      AND angulo_foto IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira');

    IF v_angulos_presentes IS NULL OR array_length(v_angulos_presentes, 1) < 4 THEN
        RETURN jsonb_build_object(
            'valido', FALSE,
            'codigo', 'FOTOS_INCOMPLETAS',
            'mensagem', 'O veículo não possui as 4 fotos válidas obrigatórias (frente, lado direito, lado esquerdo e traseira).'
        );
    END IF;

    -- 4. Valida presença do CRLV
    SELECT COUNT(*) INTO v_qtd_crlv
    FROM public.veiculos_documentos
    WHERE veiculo_id = v_veiculo.id
      AND tipo_documento = 'crlv';

    IF v_qtd_crlv < 1 THEN
        RETURN jsonb_build_object(
            'valido', FALSE,
            'codigo', 'CRLV_AUSENTE',
            'mensagem', 'O documento CRLV é obrigatório para aprovação do veículo.'
        );
    END IF;

    -- 5. RECONFIRMAÇÃO NO STORAGE: Verifica se cada objeto vinculador ainda existe em storage.objects
    -- NOTA DE PRECISÃO: Consultar storage.objects confirma a presença do registro de metadados
    -- gerenciado pelo Supabase Storage no PostgreSQL. Não comprova, isoladamente, a integridade
    -- dos blocos físicos brutos no provedor subjacente (ex: S3/disco) caso haja corrupção externa.
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        RETURN jsonb_build_object(
            'valido', FALSE,
            'codigo', 'INFRAESTRUTURA_STORAGE_INDISPONIVEL',
            'mensagem', 'A infraestrutura de Storage não está acessível no banco de dados para reconfirmação das evidências.'
        );
    END IF;

    FOR v_doc IN (
        SELECT id, tipo_documento, angulo_foto, storage_path, nome_arquivo
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND (tipo_documento = 'crlv' OR (tipo_documento = 'foto_veiculo' AND angulo_foto IS NOT NULL))
    ) LOOP
        SELECT metadata INTO v_storage_meta
        FROM storage.objects
        WHERE bucket_id = 'veiculos-documentos'
          AND name = v_doc.storage_path;

        IF NOT FOUND THEN
            RETURN jsonb_build_object(
                'valido', FALSE,
                'codigo', 'ARQUIVO_FISICO_AUSENTE',
                'mensagem', 'O arquivo da evidência ' || 
                            COALESCE(v_doc.angulo_foto, v_doc.tipo_documento) || 
                            ' (' || v_doc.nome_arquivo || ') não foi localizado no Storage.',
                'documento_id', v_doc.id,
                'storage_path', v_doc.storage_path
            );
        END IF;
    END LOOP;

    -- Sucesso: todas as regras, ângulos e arquivos físicos reconfirmados
    RETURN jsonb_build_object(
        'valido', TRUE,
        'codigo', 'COMPLETO',
        'mensagem', 'Veículo e evidências validados com sucesso.',
        'veiculo_id', v_veiculo.id,
        'revisao', COALESCE(v_veiculo.revisao, 1),
        'qtd_fotos', 4,
        'crlv_validado', TRUE
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/solicitar_acesso_empresa.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: solicitar_acesso_empresa.sql
-- Solicitação idempotente e restrita ao papel de motorista.
-- Impede sobrecargas inseguras ou solicitação direta de papéis administrativos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.solicitar_acesso_empresa(
    p_codigo_convite TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_empresa RECORD;
    v_membro_existente RECORD;
    v_solicitacao_existente RECORD;
    v_novo_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- 1. Localiza a empresa pelo código de convite ativo
    SELECT * INTO v_empresa
    FROM public.empresas
    WHERE UPPER(TRIM(codigo_convite)) = UPPER(TRIM(p_codigo_convite))
      AND ativa = TRUE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EMPRESA_NAO_ENCONTRADA',
            'mensagem', 'Código de convite inválido ou empresa inativa.'
        );
    END IF;

    -- 2. Verifica se o usuário já possui vínculo com esta empresa
    SELECT * INTO v_membro_existente
    FROM public.empresa_membros
    WHERE empresa_id = v_empresa.id AND user_id = v_user_id;

    IF FOUND THEN
        IF v_membro_existente.status = 'aprovado' THEN
            RETURN jsonb_build_object(
                'sucesso', TRUE,
                'codigo', 'JA_APROVADO',
                'mensagem', 'Você já é um membro aprovado desta empresa.',
                'empresa_id', v_empresa.id,
                'empresa_nome', v_empresa.nome
            );
        ELSIF v_membro_existente.status = 'suspenso' THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'USUARIO_SUSPENSO',
                'mensagem', 'Seu acesso a esta empresa está suspenso. Contate a gestão.'
            );
        END IF;
    END IF;

    -- 3. Verifica se já existe solicitação pendente (idempotência)
    SELECT * INTO v_solicitacao_existente
    FROM public.solicitacoes_acesso
    WHERE empresa_id = v_empresa.id AND user_id = v_user_id;

    IF FOUND AND v_solicitacao_existente.status = 'pendente' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'SOLICITACAO_EXISTENTE',
            'mensagem', 'Sua solicitação anterior já está pendente de análise pela gestão.',
            'empresa_id', v_empresa.id,
            'empresa_nome', v_empresa.nome,
            'solicitacao_id', v_solicitacao_existente.id
        );
    END IF;

    -- 4. Registra solicitação estritamente com papel_solicitado = 'motorista'
    INSERT INTO public.solicitacoes_acesso (
        empresa_id,
        user_id,
        papel_solicitado,
        status,
        motivo_decisao,
        created_at,
        updated_at
    ) VALUES (
        v_empresa.id,
        v_user_id,
        'motorista',
        'pendente',
        NULL,
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel_solicitado = 'motorista',
        status = 'pendente',
        motivo_decisao = NULL,
        decidido_por = NULL,
        decidido_em = NULL,
        updated_at = timezone('utc'::text, now())
    RETURNING id INTO v_novo_id;

    -- Cria ou atualiza membro em estado pendente
    INSERT INTO public.empresa_membros (
        empresa_id,
        user_id,
        papel,
        status,
        updated_at
    ) VALUES (
        v_empresa.id,
        v_user_id,
        'motorista',
        'pendente',
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        status = CASE 
            WHEN empresa_membros.status = 'aprovado' THEN 'aprovado'
            ELSE 'pendente' 
        END,
        updated_at = timezone('utc'::text, now());

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'SOLICITACAO_REGISTRADA',
        'mensagem', 'Solicitação de acesso enviada com sucesso.',
        'empresa_id', v_empresa.id,
        'empresa_nome', v_empresa.nome,
        'solicitacao_id', v_novo_id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/aprovar_solicitacao_motorista.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: aprovar_solicitacao_motorista.sql
-- Aprovação auditada de motorista pela gestão da empresa.
-- Atômica e consistente sob concorrência (FOR UPDATE).
-- Suporta:
--   Opção A: Criar cadastro de motorista novo a partir da solicitação real.
--   Opção B: Vincular a um cadastro existente desocupado da frota.
-- Valida autorização de gestão ANTES da resposta de idempotência.
-- Valida concorrência via p_revisao_esperada_veiculo.
-- Valida obrigatoriedades e impede aprovação indevida de veículos incompletos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.aprovar_solicitacao_motorista(
    p_solicitacao_id UUID,
    p_motorista_id UUID DEFAULT NULL,
    p_criar_novo_motorista BOOLEAN DEFAULT FALSE,
    p_nome_motorista TEXT DEFAULT NULL,
    p_telefone_motorista VARCHAR DEFAULT NULL,
    p_revisao_esperada_veiculo INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_solicitacao RECORD;
    v_perfil RECORD;
    v_veiculo RECORD;
    v_motorista RECORD;
    v_motorista_final_id UUID;
    v_nome_final TEXT;
    v_telefone_final VARCHAR(30);
    v_modelo_final VARCHAR(100);
    v_placa_final VARCHAR(20);
    v_validacao_veic JSONB;
BEGIN
    -- 1. Localiza e bloqueia a solicitação para concorrência
    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE id = p_solicitacao_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'SOLICITACAO_NAO_ENCONTRADA',
            'mensagem', 'Solicitação de acesso não encontrada.'
        );
    END IF;

    -- 2. Valida autorização do executor PRIMEIRO (gestor ou admin da empresa)
    -- Impede vazamento de informações para chamadas não autorizadas
    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem aprovar solicitações.'
        );
    END IF;

    -- 3. Idempotência autorizada: se já aprovada por esta empresa, retorna sucesso sem duplicar
    IF v_solicitacao.status = 'aprovado' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'JA_APROVADO',
            'mensagem', 'Esta solicitação já foi aprovada anteriormente.',
            'motorista_id', v_solicitacao.motorista_vinculado_id
        );
    END IF;

    -- 4. Definição do motorista (Opção A: Criar Novo | Opção B: Vincular Existente)
    IF p_criar_novo_motorista THEN
        -- Busca dados do perfil do usuário
        SELECT * INTO v_perfil FROM public.perfis_usuarios WHERE id = v_solicitacao.user_id;
        -- Busca veículo declarado se houver
        SELECT * INTO v_veiculo FROM public.veiculos_motoristas WHERE user_id = v_solicitacao.user_id FOR UPDATE;

        v_nome_final := COALESCE(NULLIF(TRIM(p_nome_motorista), ''), v_perfil.nome, 'Motorista Operacional');
        v_telefone_final := COALESCE(NULLIF(TRIM(p_telefone_motorista), ''), v_perfil.telefone, '(00) 00000-0000');
        v_modelo_final := CASE 
            WHEN v_veiculo.id IS NOT NULL THEN (v_veiculo.marca || ' ' || v_veiculo.modelo)
            ELSE 'Veículo Declarado'
        END;
        v_placa_final := COALESCE(v_veiculo.placa, 'SEM-PLACA');

        -- Insere novo registro de motorista na frota da empresa
        INSERT INTO public.motoristas (
            empresa_id,
            user_id,
            nome,
            telefone,
            email,
            veiculo_modelo,
            veiculo_placa,
            status,
            ativo
        ) VALUES (
            v_solicitacao.empresa_id,
            v_solicitacao.user_id,
            v_nome_final,
            v_telefone_final,
            v_perfil.email,
            v_modelo_final,
            v_placa_final,
            'disponivel',
            TRUE
        )
        RETURNING id INTO v_motorista_final_id;

        -- Validação condicional do veículo com conferência de revisão
        IF v_veiculo.id IS NOT NULL THEN
            IF p_revisao_esperada_veiculo IS NOT NULL AND v_veiculo.revisao != p_revisao_esperada_veiculo THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'REVISAO_DESATUALIZADA',
                    'mensagem', 'O veículo do condutor foi alterado durante a análise (revisão atual: ' || v_veiculo.revisao || ', esperada: ' || p_revisao_esperada_veiculo || '). Atualize e revise a versão atual antes de aprovar.',
                    'revisao_esperada', p_revisao_esperada_veiculo,
                    'revisao_atual', v_veiculo.revisao
                );
            END IF;

            v_validacao_veic := public.fn_validar_completude_veiculo(v_veiculo.id);

            IF (v_validacao_veic->>'valido')::boolean = TRUE THEN
                UPDATE public.veiculos_motoristas
                SET status_analise = 'aprovado',
                    revisao = revisao + 1,
                    analisado_por = auth.uid(),
                    analisado_em = timezone('utc'::text, now()),
                    motivo_rejeicao = NULL,
                    updated_at = timezone('utc'::text, now())
                WHERE id = v_veiculo.id;

                UPDATE public.veiculos_documentos
                SET status_analise = 'aprovado',
                    analisado_por = auth.uid(),
                    analisado_em = timezone('utc'::text, now()),
                    motivo_rejeicao = NULL,
                    updated_at = timezone('utc'::text, now())
                WHERE veiculo_id = v_veiculo.id;
            ELSE
                -- Veículo incompleto ou sem arquivo no Storage NÃO pode ser marcado como aprovado
                UPDATE public.veiculos_motoristas
                SET status_analise = 'pendente',
                    updated_at = timezone('utc'::text, now())
                WHERE id = v_veiculo.id;
            END IF;
        END IF;

    ELSE
        -- Opção B: Vinculação a cadastro pré-existente
        IF p_motorista_id IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTORISTA_OBRIGATORIO',
                'mensagem', 'Selecione um motorista da frota para realizar o vínculo.'
            );
        END IF;

        SELECT * INTO v_motorista
        FROM public.motoristas
        WHERE id = p_motorista_id
          AND empresa_id = v_solicitacao.empresa_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTORISTA_NAO_ENCONTRADO',
                'mensagem', 'Motorista selecionado não foi encontrado ou não pertence a esta empresa.'
            );
        END IF;

        IF v_motorista.user_id IS NOT NULL AND v_motorista.user_id != v_solicitacao.user_id THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTORISTA_JA_VINCULADO',
                'mensagem', 'Este motorista já está vinculado a outro usuário.'
            );
        END IF;

        -- Atualiza o motorista existente com o user_id do condutor
        UPDATE public.motoristas
        SET user_id = v_solicitacao.user_id,
            ativo = TRUE,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_motorista.id;

        v_motorista_final_id := v_motorista.id;
    END IF;

    -- 5. Atualiza a solicitação de acesso
    UPDATE public.solicitacoes_acesso
    SET status = 'aprovado',
        motorista_vinculado_id = v_motorista_final_id,
        motivo_decisao = 'Aprovado pela gestão',
        decidido_por = auth.uid(),
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

    -- 6. Insere ou atualiza o membro em empresa_membros
    INSERT INTO public.empresa_membros (
        empresa_id,
        user_id,
        papel,
        status,
        motorista_id,
        motivo_decisao,
        aprovado_por,
        aprovado_em,
        updated_at
    ) VALUES (
        v_solicitacao.empresa_id,
        v_solicitacao.user_id,
        'motorista',
        'aprovado',
        v_motorista_final_id,
        'Aprovado pela gestão',
        auth.uid(),
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel = 'motorista',
        status = 'aprovado',
        motorista_id = v_motorista_final_id,
        motivo_decisao = 'Aprovado pela gestão',
        aprovado_por = auth.uid(),
        aprovado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now());

    -- 7. Auditoria com revisão analisada
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motorista_id,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_solicitacao.empresa_id,
        v_solicitacao.user_id,
        'aprovacao_motorista',
        v_solicitacao.status,
        'aprovado',
        v_motorista_final_id,
        'Aprovado pela gestão',
        auth.uid(),
        jsonb_build_object(
            'solicitacao_id', v_solicitacao.id,
            'criou_novo_motorista', p_criar_novo_motorista,
            'motorista_id', v_motorista_final_id,
            'veiculo_id', CASE WHEN v_veiculo.id IS NOT NULL THEN v_veiculo.id ELSE NULL END,
            'revisao_veiculo_analisada', p_revisao_esperada_veiculo,
            'veiculo_aprovado', CASE WHEN v_validacao_veic IS NOT NULL THEN (v_validacao_veic->>'valido')::boolean ELSE FALSE END
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'APROVADO_COM_SUCESSO',
        'mensagem', 'Motorista aprovado e vinculado com sucesso.',
        'motorista_id', v_motorista_final_id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/rejeitar_solicitacao_acesso.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: rejeitar_solicitacao_acesso.sql
-- Rejeição auditada com motivo obrigatório.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rejeitar_solicitacao_acesso(
    p_solicitacao_id UUID,
    p_motivo TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_solicitacao RECORD;
BEGIN
    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTIVO_OBRIGATORIO',
            'mensagem', 'Informe o motivo da rejeição para registro de auditoria.'
        );
    END IF;

    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE id = p_solicitacao_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'SOLICITACAO_NAO_ENCONTRADA',
            'mensagem', 'Solicitação de acesso não encontrada.'
        );
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem rejeitar solicitações.'
        );
    END IF;

    -- Atualiza solicitação
    UPDATE public.solicitacoes_acesso
    SET status = 'rejeitado',
        motivo_decisao = TRIM(p_motivo),
        decidido_por = auth.uid(),
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

    -- Atualiza status de membro para rejeitado
    UPDATE public.empresa_membros
    SET status = 'rejeitado',
        motivo_decisao = TRIM(p_motivo),
        updated_at = timezone('utc'::text, now())
    WHERE empresa_id = v_solicitacao.empresa_id
      AND user_id = v_solicitacao.user_id;

    -- Auditoria
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_solicitacao.empresa_id,
        v_solicitacao.user_id,
        'rejeicao_solicitacao',
        v_solicitacao.status,
        'rejeitado',
        TRIM(p_motivo),
        auth.uid(),
        jsonb_build_object('solicitacao_id', v_solicitacao.id)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'SOLICITACAO_REJEITADA',
        'mensagem', 'Solicitação rejeitada com sucesso.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/suspender_acesso_membro.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: suspender_acesso_membro.sql
-- Suspensão preventiva de acesso a rotas e dados operacionais.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.suspender_acesso_membro(
    p_membro_id UUID,
    p_motivo TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
BEGIN
    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTIVO_OBRIGATORIO',
            'mensagem', 'Informe a justificativa da suspensão.'
        );
    END IF;

    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE id = p_membro_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MEMBRO_NAO_ENCONTRADO',
            'mensagem', 'Membro da empresa não encontrado.'
        );
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores desta empresa podem suspender acessos.'
        );
    END IF;

    -- Não permite suspender a si mesmo
    IF v_membro.user_id = auth.uid() THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'AUTO_SUSPENSAO_PROIBIDA',
            'mensagem', 'Não é permitido suspender a própria conta.'
        );
    END IF;

    -- Atualiza status do membro para suspenso
    UPDATE public.empresa_membros
    SET status = 'suspenso',
        motivo_decisao = TRIM(p_motivo),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_membro.id;

    -- Desativa motorista da frota se houver
    IF v_membro.motorista_id IS NOT NULL THEN
        UPDATE public.motoristas
        SET ativo = FALSE,
            status = 'offline',
            updated_at = timezone('utc'::text, now())
        WHERE id = v_membro.motorista_id;
    END IF;

    -- Auditoria
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motorista_id,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_membro.empresa_id,
        v_membro.user_id,
        'suspensao_acesso',
        v_membro.status,
        'suspenso',
        v_membro.motorista_id,
        TRIM(p_motivo),
        auth.uid(),
        jsonb_build_object('membro_id', v_membro.id)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ACESSO_SUSPENSO',
        'mensagem', 'Acesso operacional do membro suspenso com sucesso.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/reativar_acesso_membro.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: reativar_acesso_membro.sql
-- Reativação de membros anteriormente suspensos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.reativar_acesso_membro(
    p_membro_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
BEGIN
    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE id = p_membro_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MEMBRO_NAO_ENCONTRADO',
            'mensagem', 'Membro da empresa não encontrado.'
        );
    END IF;

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores desta empresa podem reativar acessos.'
        );
    END IF;

    -- Atualiza status para aprovado
    UPDATE public.empresa_membros
    SET status = 'aprovado',
        motivo_decisao = 'Acesso reativado pela gestão',
        aprovado_por = auth.uid(),
        aprovado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_membro.id;

    -- Reativa motorista da frota se houver
    IF v_membro.motorista_id IS NOT NULL THEN
        UPDATE public.motoristas
        SET ativo = TRUE,
            status = 'disponivel',
            updated_at = timezone('utc'::text, now())
        WHERE id = v_membro.motorista_id;
    END IF;

    -- Auditoria
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motorista_id,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_membro.empresa_id,
        v_membro.user_id,
        'reativacao_acesso',
        v_membro.status,
        'aprovado',
        v_membro.motorista_id,
        'Reativação pela gestão',
        auth.uid(),
        jsonb_build_object('membro_id', v_membro.id)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ACESSO_REATIVADO',
        'mensagem', 'Acesso operacional do membro reativado com sucesso.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/alterar_papel_membro.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: alterar_papel_membro.sql
-- Alteração de papéis organizacionais (admin, gestor, motorista).
-- Exige estritamente papel de administrador da empresa.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.alterar_papel_membro(
    p_membro_id UUID,
    p_novo_papel TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
    v_novo_papel_norm VARCHAR(30);
BEGIN
    v_novo_papel_norm := LOWER(TRIM(p_novo_papel));

    IF v_novo_papel_norm NOT IN ('admin', 'gestor', 'motorista') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'PAPEL_INVALIDO',
            'mensagem', 'Papel inválido. Opções: admin, gestor, motorista.'
        );
    END IF;

    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE id = p_membro_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MEMBRO_NAO_ENCONTRADO',
            'mensagem', 'Membro da empresa não encontrado.'
        );
    END IF;

    -- REGRA DE SEGURANÇA: Apenas administradores da empresa podem alterar papéis
    IF NOT public.fn_usuario_e_admin_empresa(v_membro.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas administradores desta empresa têm permissão para alterar papéis.'
        );
    END IF;

    -- Atualiza papel
    UPDATE public.empresa_membros
    SET papel = v_novo_papel_norm,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_membro.id;

    -- Auditoria
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_membro.empresa_id,
        v_membro.user_id,
        'alteracao_papel',
        v_membro.papel,
        v_novo_papel_norm,
        'Alteração de papel por administrador',
        auth.uid(),
        jsonb_build_object('membro_id', v_membro.id, 'novo_papel', v_novo_papel_norm)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'PAPEL_ALTERADO',
        'mensagem', 'Papel do membro alterado com sucesso.',
        'novo_papel', v_novo_papel_norm
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/cadastrar_meu_veiculo.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: cadastrar_meu_veiculo.sql
-- Cadastro e atualização de veículos pelo condutor autenticado.
-- Valida as regras de negócio simplificadas de VEICULO_MOBILE.md
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.cadastrar_meu_veiculo(
    p_dados JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_empresa_id UUID;
    v_tipo_veiculo VARCHAR(20);
    v_marca VARCHAR(100);
    v_modelo VARCHAR(100);
    v_placa VARCHAR(20);
    v_compartimento VARCHAR(20);
    v_volume_litros NUMERIC(6, 2);
    v_tamanho_compartimento VARCHAR(20);
    v_capacidade_kg NUMERIC(6, 2);

    v_veiculo_existente RECORD;
    v_status_analise VARCHAR(30) := 'pendente';
    v_novo_id UUID;
    v_revisao_nova INT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- 1. Descobre a empresa do condutor via membro ou solicitação pendente
    SELECT empresa_id INTO v_empresa_id
    FROM public.empresa_membros
    WHERE user_id = v_user_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_empresa_id IS NULL THEN
        SELECT empresa_id INTO v_empresa_id
        FROM public.solicitacoes_acesso
        WHERE user_id = v_user_id AND status = 'pendente'
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    IF v_empresa_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'SEM_VINCULO_EMPRESA',
            'mensagem', 'Solicite acesso a uma empresa antes de cadastrar o veículo.'
        );
    END IF;

    -- Validação centralizada de autorização (bloqueia suspenso e sem vínculo ativo)
    IF (public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    -- 2. Extrai e normaliza campos comuns
    v_tipo_veiculo := LOWER(TRIM(p_dados->>'tipo_veiculo'));
    v_marca := TRIM(p_dados->>'marca');
    v_modelo := TRIM(p_dados->>'modelo');
    v_placa := UPPER(REGEXP_REPLACE(p_dados->>'placa', '[^a-zA-Z0-9]', '', 'g'));

    IF v_tipo_veiculo NOT IN ('moto', 'carro') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TIPO_VEICULO_INVALIDO',
            'mensagem', 'Tipo de veículo deve ser "moto" ou "carro".'
        );
    END IF;

    IF v_marca IS NULL OR v_marca = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MARCA_OBRIGATORIA',
            'mensagem', 'Informe a marca do veículo.'
        );
    END IF;

    IF v_modelo IS NULL OR v_modelo = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MODELO_OBRIGATORIO',
            'mensagem', 'Informe o modelo do veículo.'
        );
    END IF;

    IF v_placa IS NULL OR LENGTH(v_placa) < 7 OR LENGTH(v_placa) > 8 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'PLACA_INVALIDA',
            'mensagem', 'Placa inválida. Forneça uma placa padrão Mercosul ou brasileira válida.'
        );
    END IF;

    -- 3. Validação condicional por tipo de veículo (VEICULO_MOBILE.md)
    IF v_tipo_veiculo = 'carro' THEN
        -- Carro NÃO coleta peso, volume, compartimento ou medidas
        IF (p_dados ? 'compartimento' AND p_dados->>'compartimento' IS NOT NULL) OR
           (p_dados ? 'volume_litros' AND p_dados->>'volume_litros' IS NOT NULL) OR
           (p_dados ? 'tamanho_compartimento' AND p_dados->>'tamanho_compartimento' IS NOT NULL) OR
           (p_dados ? 'capacidade_kg' AND p_dados->>'capacidade_kg' IS NOT NULL) THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'CAMPOS_INVALIDOS_CARRO',
                'mensagem', 'Veículos do tipo carro não aceitam compartimento, volume ou capacidade nesta versão.'
            );
        END IF;

        v_compartimento := NULL;
        v_volume_litros := NULL;
        v_tamanho_compartimento := NULL;
        v_capacidade_kg := NULL;

    ELSIF v_tipo_veiculo = 'moto' THEN
        v_compartimento := LOWER(TRIM(p_dados->>'compartimento'));
        IF v_compartimento NOT IN ('bau', 'mochila', 'bag') THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'COMPARTIMENTO_OBRIGATORIO',
                'mensagem', 'Para moto, informe o compartimento: "bau", "mochila" ou "bag".'
            );
        END IF;

        -- Capacidade em KG obrigatória e positiva
        BEGIN
            v_capacidade_kg := (p_dados->>'capacidade_kg')::NUMERIC;
        EXCEPTION WHEN OTHERS THEN
            v_capacidade_kg := NULL;
        END;

        IF v_capacidade_kg IS NULL OR v_capacidade_kg <= 0 THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'CAPACIDADE_KG_INVALIDA',
                'mensagem', 'Informe a capacidade de carga em kg (número positivo).'
            );
        END IF;

        IF v_compartimento = 'bau' THEN
            -- Baú: volume_litros obrigatório e positivo; sem tamanho categórico
            BEGIN
                v_volume_litros := (p_dados->>'volume_litros')::NUMERIC;
            EXCEPTION WHEN OTHERS THEN
                v_volume_litros := NULL;
            END;

            IF v_volume_litros IS NULL OR v_volume_litros <= 0 THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'VOLUME_LITROS_OBRIGATORIO',
                    'mensagem', 'Para baú, informe o volume em litros (número positivo).'
                );
            END IF;

            v_tamanho_compartimento := NULL;

        ELSIF v_compartimento IN ('mochila', 'bag') THEN
            -- Mochila / Bag: tamanho_compartimento obrigatório (pequeno|medio|grande); sem litros
            v_tamanho_compartimento := LOWER(TRIM(p_dados->>'tamanho_compartimento'));
            IF v_tamanho_compartimento NOT IN ('pequeno', 'medio', 'grande') THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'TAMANHO_COMPARTIMENTO_OBRIGATORIO',
                    'mensagem', 'Para mochila/bag, selecione o tamanho: "pequeno", "medio" ou "grande".'
                );
            END IF;

            v_volume_litros := NULL;
        END IF;
    END IF;

    -- 4. Gravação / Atualização (Upsert)
    SELECT * INTO v_veiculo_existente
    FROM public.veiculos_motoristas
    WHERE user_id = v_user_id;

    -- Se já existia e estava aprovado, alteração de dados exige nova análise
    v_status_analise := 'pendente';

    INSERT INTO public.veiculos_motoristas (
        user_id,
        empresa_id,
        tipo_veiculo,
        marca,
        modelo,
        placa,
        compartimento,
        volume_litros,
        tamanho_compartimento,
        capacidade_kg,
        status_analise,
        motivo_rejeicao,
        updated_at
    ) VALUES (
        v_user_id,
        v_empresa_id,
        v_tipo_veiculo,
        v_marca,
        v_modelo,
        v_placa,
        v_compartimento,
        v_volume_litros,
        v_tamanho_compartimento,
        v_capacidade_kg,
        v_status_analise,
        NULL,
        timezone('utc'::text, now())
    )
    ON CONFLICT (user_id) DO UPDATE SET
        empresa_id = v_empresa_id,
        tipo_veiculo = EXCLUDED.tipo_veiculo,
        marca = EXCLUDED.marca,
        modelo = EXCLUDED.modelo,
        placa = EXCLUDED.placa,
        compartimento = EXCLUDED.compartimento,
        volume_litros = EXCLUDED.volume_litros,
        tamanho_compartimento = EXCLUDED.tamanho_compartimento,
        capacidade_kg = EXCLUDED.capacidade_kg,
        status_analise = 'pendente',
        motivo_rejeicao = NULL,
        revisao = public.veiculos_motoristas.revisao + 1,
        updated_at = timezone('utc'::text, now())
    RETURNING id, revisao INTO v_novo_id, v_revisao_nova;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'VEICULO_CADASTRADO',
        'mensagem', 'Dados do veículo salvos com sucesso e aguardando análise da gestão.',
        'veiculo_id', v_novo_id,
        'status_analise', 'pendente',
        'revisao', COALESCE(v_revisao_nova, 1)
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/anexar_documento_veiculo.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: anexar_documento_veiculo.sql
-- Confirmação e vinculação de anexos (4 fotos por ângulo, CRLV ou complementar).
-- Valida no servidor a existência real do objeto no storage.objects,
-- o isolamento por empresa/usuário, tamanho, MIME type e limites operacionais.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.anexar_documento_veiculo(
    p_veiculo_id UUID,
    p_tipo_documento TEXT,
    p_nome_arquivo TEXT,
    p_storage_path TEXT,
    p_tamanho_bytes INT,
    p_angulo_foto TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_veiculo RECORD;
    v_mime_type VARCHAR(100);
    v_docs_count INT;
    v_ext TEXT;
    v_doc_id UUID;
    v_parts TEXT[];
    v_empresa_path UUID;
    v_user_path UUID;
    v_storage_meta JSONB;
    v_tamanho_real BIGINT;
    v_mime_real TEXT;
    v_old_storage_path TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- 1. Localiza e bloqueia o veículo para escrita concorrente segura
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = p_veiculo_id AND user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'VEICULO_NAO_ENCONTRADO',
            'mensagem', 'Veículo não encontrado ou não pertence ao usuário autenticado.'
        );
    END IF;

    -- Validação centralizada de autorização (bloqueia usuário suspenso ou sem vínculo ativo)
    IF (public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    -- 2. Valida tipo de documento canônico
    IF p_tipo_documento NOT IN ('foto_veiculo', 'crlv', 'complementar') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TIPO_DOCUMENTO_INVALIDO',
            'mensagem', 'Tipo de documento deve ser foto_veiculo, crlv ou complementar.'
        );
    END IF;

    -- 3. Validação de ângulo para foto do veículo
    IF p_tipo_documento = 'foto_veiculo' THEN
        IF p_angulo_foto IS NULL OR p_angulo_foto NOT IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira') THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'ANGULO_INVALIDO',
                'mensagem', 'Para foto_veiculo, o ângulo é obrigatório e deve ser: frente, lado_direito, lado_esquerdo ou traseira.'
            );
        END IF;
    ELSE
        -- Documentos não devem ter ângulo
        p_angulo_foto := NULL;
    END IF;

    -- 4. Validação estrita do padrão de caminho de armazenamento: {empresa_id}/{user_id}/{filename}
    v_parts := string_to_array(TRIM(p_storage_path), '/');
    IF array_length(v_parts, 1) < 3 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'CAMINHO_STORAGE_INVALIDO',
            'mensagem', 'Caminho de armazenamento fora do padrão seguro {empresa_id}/{user_id}/{arquivo}.'
        );
    END IF;

    v_empresa_path := public.fn_safe_uuid(v_parts[1]);
    v_user_path := public.fn_safe_uuid(v_parts[2]);

    IF v_empresa_path IS NULL OR v_empresa_path != v_veiculo.empresa_id THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EMPRESA_STORAGE_DIVERGENTE',
            'mensagem', 'O caminho do arquivo não corresponde à empresa do veículo declarado.'
        );
    END IF;

    IF v_user_path IS NULL OR v_user_path != v_user_id THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'USUARIO_STORAGE_DIVERGENTE',
            'mensagem', 'Tentativa de vincular arquivo pertencente a outro condutor.'
        );
    END IF;

    -- 4b. Previne reutilização ou colisão de caminho já vinculado a outro documento
    IF EXISTS (
        SELECT 1 FROM public.veiculos_documentos
        WHERE storage_path = TRIM(p_storage_path)
          AND (
            veiculo_id != v_veiculo.id OR
            tipo_documento != p_tipo_documento OR
            (tipo_documento = 'foto_veiculo' AND angulo_foto IS DISTINCT FROM p_angulo_foto)
          )
    ) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_JA_VINCULADO',
            'mensagem', 'Este caminho de arquivo já está vinculado a outro registro de documento ativo.'
        );
    END IF;

    -- 5. Validação do arquivo real no Storage (tabela storage.objects)
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'INFRAESTRUTURA_STORAGE_INDISPONIVEL',
            'mensagem', 'A infraestrutura de Storage não está acessível para validação do arquivo enviado.'
        );
    END IF;

    SELECT metadata INTO v_storage_meta
    FROM storage.objects
    WHERE bucket_id = 'veiculos-documentos'
      AND name = TRIM(p_storage_path);

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_STORAGE_NAO_ENCONTRADO',
            'mensagem', 'O arquivo físico não foi localizado no bucket privado de armazenamento.'
        );
    END IF;

        -- Validação cruzada de tamanho real reportado pelo Storage
        IF v_storage_meta IS NOT NULL AND (v_storage_meta ? 'size') THEN
            v_tamanho_real := (v_storage_meta->>'size')::bigint;
            IF v_tamanho_real > 10485760 THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'TAMANHO_EXCEDIDO',
                    'mensagem', 'O arquivo real excede o limite máximo permitido de 10 MB.'
                );
            END IF;
            p_tamanho_bytes := v_tamanho_real::int;
        END IF;

        -- Validação cruzada de MIME type reportado pelo Storage
        IF v_storage_meta IS NOT NULL AND (v_storage_meta ? 'mimetype') THEN
            v_mime_real := LOWER(v_storage_meta->>'mimetype');
            IF v_mime_real NOT IN ('image/jpeg', 'image/png', 'application/pdf') THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'MIMETYPE_STORAGE_INVALIDO',
                    'mensagem', 'Tipo de arquivo não permitido no bucket privado: ' || v_mime_real
                );
            END IF;
        END IF;
    END IF;

    -- 6. Validação de tamanho no payload (caso storage.objects não tenha metadata)
    IF p_tamanho_bytes <= 0 OR p_tamanho_bytes > 10485760 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TAMANHO_EXCEDIDO',
            'mensagem', 'O arquivo deve ter entre 1 byte e 10 MB.'
        );
    END IF;

    -- 7. Dedução e validação do formato MIME pelo nome e consistência
    v_ext := LOWER(SUBSTRING(TRIM(p_nome_arquivo) FROM '\.([^\.]+)$'));
    IF v_ext IN ('jpg', 'jpeg') THEN
        v_mime_type := 'image/jpeg';
    ELSIF v_ext = 'png' THEN
        v_mime_type := 'image/png';
    ELSIF v_ext = 'pdf' THEN
        v_mime_type := 'application/pdf';
    ELSE
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EXTENSAO_INVALIDA',
            'mensagem', 'Formato de arquivo não suportado. Envie JPG, PNG ou PDF.'
        );
    END IF;

    -- Fotos de veículo aceitam apenas JPG ou PNG
    IF p_tipo_documento = 'foto_veiculo' AND v_mime_type = 'application/pdf' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'FOTO_NAO_ACEITA_PDF',
            'mensagem', 'Fotos do veículo devem ser imagens nos formatos JPG ou PNG.'
        );
    END IF;

    -- 8. Gerenciamento de Substituição e Limites
    IF p_tipo_documento = 'foto_veiculo' THEN
        -- Substitui EXCLUSIVAMENTE a foto do mesmo ângulo, preservando os demais 3 ângulos
        SELECT storage_path INTO v_old_storage_path
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'foto_veiculo'
          AND angulo_foto = p_angulo_foto;

        IF FOUND THEN
            DELETE FROM public.veiculos_documentos
            WHERE veiculo_id = v_veiculo.id
              AND tipo_documento = 'foto_veiculo'
              AND angulo_foto = p_angulo_foto;
        END IF;

    ELSIF p_tipo_documento = 'crlv' THEN
        -- Substitui o CRLV anterior se houver
        SELECT storage_path INTO v_old_storage_path
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'crlv';

        IF FOUND THEN
            DELETE FROM public.veiculos_documentos
            WHERE veiculo_id = v_veiculo.id
              AND tipo_documento = 'crlv';
        END IF;

    ELSIF p_tipo_documento = 'complementar' THEN
        -- Limite de até 5 documentos complementares
        SELECT COUNT(*) INTO v_docs_count
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'complementar';

        IF v_docs_count >= 5 THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'LIMITE_DOCUMENTOS_EXCEDIDO',
                'mensagem', 'Limite máximo de 5 documentos complementares atingido.'
            );
        END IF;
    END IF;

    -- 9. Insere novo registro de metadados
    INSERT INTO public.veiculos_documentos (
        veiculo_id,
        user_id,
        empresa_id,
        tipo_documento,
        angulo_foto,
        nome_arquivo,
        storage_path,
        mime_type,
        tamanho_bytes,
        status_analise
    ) VALUES (
        v_veiculo.id,
        v_user_id,
        v_veiculo.empresa_id,
        p_tipo_documento,
        p_angulo_foto,
        TRIM(p_nome_arquivo),
        TRIM(p_storage_path),
        v_mime_type,
        p_tamanho_bytes,
        'pendente'
    )
    RETURNING id INTO v_doc_id;

    -- 10. Atualiza revisão e reverte status para pendente caso estivesse aprovado
    IF v_veiculo.status_analise = 'aprovado' THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'pendente',
            motivo_rejeicao = 'Aprovação invalidada: nova evidência (' || COALESCE(p_angulo_foto, p_tipo_documento) || ') enviada para análise.',
            revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    ELSE
        UPDATE public.veiculos_motoristas
        SET revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DOCUMENTO_ANEXADO',
        'mensagem', 'Anexo vinculado com sucesso e registrado para análise da gestão.',
        'documento_id', v_doc_id,
        'angulo_foto', p_angulo_foto,
        'tipo_documento', p_tipo_documento,
        'revisao', v_veiculo.revisao + 1
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/remover_documento_veiculo.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: remover_documento_veiculo.sql
-- Desvinculação autorizada e segura de documentos veiculares.
-- Se o veículo estiver 'aprovado', a remoção da evidência INVALIDA imediatamente
-- a aprovação, revertendo para 'pendente' e incrementando a revisão do veículo.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.remover_documento_veiculo(
    p_documento_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_doc RECORD;
    v_veiculo RECORD;
    v_eh_gestor BOOLEAN := FALSE;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- 1. Localiza o documento
    SELECT * INTO v_doc
    FROM public.veiculos_documentos
    WHERE id = p_documento_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'DOCUMENTO_NAO_ENCONTRADO',
            'mensagem', 'Documento não encontrado.'
        );
    END IF;

    -- 2. Localiza e bloqueia o veículo para coordenação de estado
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = v_doc.veiculo_id
    FOR UPDATE;

    -- 3. Validação de autorização centralizada (proprietário ativo ou gestor/admin da empresa)
    IF v_doc.user_id = v_user_id THEN
        -- Condutor deve ter vínculo ativo (não suspenso, não rejeitado)
        IF (public.fn_validar_autorizacao_condutor(v_doc.empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', public.fn_validar_autorizacao_condutor(v_doc.empresa_id, v_user_id)->>'codigo',
                'mensagem', public.fn_validar_autorizacao_condutor(v_doc.empresa_id, v_user_id)->>'mensagem'
            );
        END IF;
    ELSIF public.fn_usuario_e_gestor_empresa(v_doc.empresa_id) THEN
        v_eh_gestor := TRUE;
    ELSE
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Você não possui autorização para remover esta evidência.'
        );
    END IF;

    -- 4. Remove a linha de metadados no Postgres
    DELETE FROM public.veiculos_documentos WHERE id = v_doc.id;

    -- 5. Se o veículo já estava aprovado, a remoção INVALIDA a aprovação
    IF v_veiculo.status_analise = 'aprovado' THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'pendente',
            motivo_rejeicao = 'Aprovação invalidada: evidência (' || COALESCE(v_doc.angulo_foto, v_doc.tipo_documento) || ') foi removida.',
            revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    ELSE
        UPDATE public.veiculos_motoristas
        SET revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    END IF;

    -- 6. Auditoria
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_doc.empresa_id,
        v_doc.user_id,
        'remocao_documento_veiculo',
        v_veiculo.status_analise,
        'pendente',
        'Documento ' || v_doc.nome_arquivo || ' removido.',
        v_user_id,
        jsonb_build_object(
            'documento_id', v_doc.id,
            'storage_path', v_doc.storage_path,
            'tipo_documento', v_doc.tipo_documento,
            'angulo_foto', v_doc.angulo_foto,
            'eh_gestor', v_eh_gestor
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DOCUMENTO_REMOVIDO',
        'mensagem', 'Documento desvinculado com sucesso. Análise revertida para pendente.',
        'storage_path', v_doc.storage_path,
        'veiculo_id', v_veiculo.id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/analisar_veiculo_motorista.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: analisar_veiculo_motorista.sql
-- Decisão humana da gestão sobre aprovação ou rejeição de veículo e seus anexos.
-- Centraliza a validação chamando fn_validar_completude_veiculo, que reconfere
-- campos obrigatórios, 4 fotos distintas, CRLV e existência física no Storage.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.analisar_veiculo_motorista(
    p_veiculo_id UUID,
    p_aprovar BOOLEAN,
    p_revisao_esperada INT,
    p_motivo_rejeicao TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_veiculo RECORD;
    v_novo_status VARCHAR(30);
    v_validacao JSONB;
BEGIN
    -- 1. Localiza e bloqueia o veículo para evitar alterações concorrentes
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = p_veiculo_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'VEICULO_NAO_ENCONTRADO',
            'mensagem', 'Veículo não encontrado.'
        );
    END IF;

    -- 2. Valida concorrência otimista via número de revisão
    IF p_revisao_esperada IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'REVISAO_OBRIGATORIA',
            'mensagem', 'A revisão esperada do veículo é obrigatória para registrar a análise.'
        );
    END IF;

    IF v_veiculo.revisao != p_revisao_esperada THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'REVISAO_DESATUALIZADA',
            'mensagem', 'O veículo foi alterado durante a análise (revisão atual: ' || v_veiculo.revisao || ', esperada: ' || p_revisao_esperada || '). Atualize a visualização e confira os dados novamente antes de decidir.',
            'revisao_esperada', p_revisao_esperada,
            'revisao_atual', v_veiculo.revisao
        );
    END IF;

    -- 3. Valida permissão de gestão na empresa do veículo
    IF NOT public.fn_usuario_e_gestor_empresa(v_veiculo.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem analisar veículos.'
        );
    END IF;

    -- 4. Decisão de Aprovação ou Rejeição
    IF p_aprovar THEN
        -- Invoca a validação centralizada e reconfere evidências físicas
        v_validacao := public.fn_validar_completude_veiculo(v_veiculo.id);

        IF (v_validacao->>'valido')::boolean != TRUE THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', v_validacao->>'codigo',
                'mensagem', v_validacao->>'mensagem'
            );
        END IF;

        v_novo_status := 'aprovado';
    ELSE
        -- Rejeição exige motivo explícito
        IF p_motivo_rejeicao IS NULL OR TRIM(p_motivo_rejeicao) = '' THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTIVO_OBRIGATORIO',
                'mensagem', 'Informe a justificativa da rejeição do veículo.'
            );
        END IF;
        v_novo_status := 'rejeitado';
    END IF;

    -- 4. Atualiza veículo e incrementa revisão
    UPDATE public.veiculos_motoristas
    SET status_analise = v_novo_status,
        motivo_rejeicao = CASE WHEN p_aprovar THEN NULL ELSE TRIM(p_motivo_rejeicao) END,
        revisao = revisao + 1,
        analisado_por = auth.uid(),
        analisado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_veiculo.id;

    -- 5. Atualiza os documentos associados
    UPDATE public.veiculos_documentos
    SET status_analise = v_novo_status,
        motivo_rejeicao = CASE WHEN p_aprovar THEN NULL ELSE TRIM(p_motivo_rejeicao) END,
        analisado_por = auth.uid(),
        analisado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE veiculo_id = v_veiculo.id;

    -- 6. Auditoria detalhada com registro da revisão
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_veiculo.empresa_id,
        v_veiculo.user_id,
        'analise_veiculo',
        v_veiculo.status_analise,
        v_novo_status,
        p_motivo_rejeicao,
        auth.uid(),
        jsonb_build_object(
            'veiculo_id', v_veiculo.id,
            'placa', v_veiculo.placa,
            'revisao_analisada', p_revisao_esperada,
            'revisao_gerada', v_veiculo.revisao + 1,
            'validacao_centralizada', v_validacao
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ANALISE_CONCLUIDA',
        'mensagem', 'Decisão sobre o veículo registrada com sucesso.',
        'status_analise', v_novo_status,
        'revisao', v_veiculo.revisao + 1
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/despachar_rota_transacional.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: despachar_rota_transacional.sql
-- Despacho atômico e idempotente de rotas sob alta concorrência.
-- Bloqueio FOR UPDATE, coluna dedicada idempotency_key e detecção de conflitos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.despachar_rota_transacional(
    p_dados JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_empresa_id UUID;
    v_motorista_id UUID;
    v_idempotency_key VARCHAR(100);
    v_payload_hash VARCHAR(64);
    v_rota_existente RECORD;
    v_motorista RECORD;
    v_rota_id UUID;
    v_parada RECORD;
    v_paradas JSONB;
    v_distancia_orig NUMERIC(8, 2);
    v_tempo_orig NUMERIC(8, 2);
    v_distancia_otim NUMERIC(8, 2);
    v_tempo_otim NUMERIC(8, 2);
    v_economia_dist NUMERIC(5, 2) := 0;
    v_economia_tempo NUMERIC(5, 2) := 0;
    v_ordem_json JSONB;
    v_idx INT := 0;
BEGIN
    -- 1. Extração dos identificadores obrigatórios
    v_empresa_id := (p_dados->>'empresa_id')::UUID;
    v_motorista_id := (p_dados->>'motorista_id')::UUID;
    v_idempotency_key := TRIM(p_dados->>'idempotency_key');
    v_paradas := p_dados->'paradas';

    IF v_empresa_id IS NULL OR v_motorista_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'DADOS_OBRIGATORIOS_AUSENTES',
            'mensagem', 'empresa_id e motorista_id são obrigatórios.'
        );
    END IF;

    IF v_idempotency_key IS NULL OR v_idempotency_key = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'CHAVE_IDEMPOTENCIA_OBRIGATORIA',
            'mensagem', 'Chave de operação (idempotency_key) não informada.'
        );
    END IF;

    IF v_paradas IS NULL OR jsonb_array_length(v_paradas) = 0 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'PARADAS_VAZIAS',
            'mensagem', 'A rota deve conter pelo menos uma parada.'
        );
    END IF;

    -- 2. VALIDAÇÃO DE AUTORIZAÇÃO ANTES DE QUALQUER LEITURA OU BLOQUEIO
    IF NOT public.fn_usuario_e_gestor_empresa(v_empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores autorizados desta empresa podem despachar rotas.'
        );
    END IF;

    -- 3. Cálculo de hash do payload para conferência de consistência
    v_payload_hash := encode(digest(p_dados::text, 'sha256'), 'hex');

    -- 4. Serialização sob concorrência: bloqueia a linha do motorista
    SELECT * INTO v_motorista
    FROM public.motoristas
    WHERE id = v_motorista_id AND empresa_id = v_empresa_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTORISTA_NAO_ENCONTRADO',
            'mensagem', 'Motorista não encontrado na empresa especificada.'
        );
    END IF;

    IF NOT v_motorista.ativo THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTORISTA_INATIVO',
            'mensagem', 'O motorista selecionado está inativo ou suspenso.'
        );
    END IF;

    -- 5. Tratamento de Idempotência: busca rota com a mesma chave na mesma empresa
    SELECT * INTO v_rota_existente
    FROM public.rotas_planejadas
    WHERE empresa_id = v_empresa_id AND idempotency_key = v_idempotency_key;

    IF FOUND THEN
        -- Se o hash coincidir, retorna a rota já existente sem duplicar
        IF v_rota_existente.payload_hash = v_payload_hash OR v_rota_existente.payload_hash IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', TRUE,
                'codigo', 'ROTA_JA_DESPACHADA',
                'mensagem', 'Rota já processada anteriormente (idempotência atendida).',
                'rota_id', v_rota_existente.id,
                'idempotente', TRUE
            );
        ELSE
            -- Mesma chave com payload divergente: CONFLITO EXPLÍCITO
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'CONFLITO_IDEMPOTENCIA',
                'mensagem', 'A chave de operação fornecida já foi utilizada com dados diferentes.'
            );
        END IF;
    END IF;

    -- 6. Extração e cálculo de métricas
    v_distancia_orig := COALESCE((p_dados->>'distancia_original_km')::NUMERIC, 0);
    v_tempo_orig := COALESCE((p_dados->>'tempo_original_minutos')::NUMERIC, 0);
    v_distancia_otim := COALESCE((p_dados->>'distancia_otimizada_km')::NUMERIC, 0);
    v_tempo_otim := COALESCE((p_dados->>'tempo_otimizado_minutos')::NUMERIC, 0);

    IF v_distancia_orig > 0 THEN
        v_economia_dist := ROUND(((v_distancia_orig - v_distancia_otim) / v_distancia_orig * 100), 2);
    END IF;
    IF v_tempo_orig > 0 THEN
        v_economia_tempo := ROUND(((v_tempo_orig - v_tempo_otim) / v_tempo_orig * 100), 2);
    END IF;

    v_ordem_json := COALESCE(p_dados->'ordem_paradas_json', '[]'::jsonb);

    -- 7. Criação da Rota Planejada (Atômica)
    INSERT INTO public.rotas_planejadas (
        empresa_id,
        motorista_id,
        idempotency_key,
        payload_hash,
        status,
        distancia_original_km,
        tempo_original_minutos,
        distancia_otimizada_km,
        tempo_otimizado_minutos,
        percentual_economia_km,
        percentual_economia_tempo,
        ordem_paradas_json
    ) VALUES (
        v_empresa_id,
        v_motorista_id,
        v_idempotency_key,
        v_payload_hash,
        'planejada',
        v_distancia_orig,
        v_tempo_orig,
        v_distancia_otim,
        v_tempo_otim,
        v_economia_dist,
        v_economia_tempo,
        v_ordem_json
    )
    RETURNING id INTO v_rota_id;

    -- 8. Inserção das Entregas/Paradas vinculadas à rota
    FOR v_parada IN SELECT * FROM jsonb_to_recordset(v_paradas) AS x(
        cliente_endereco_id UUID,
        destinatario_nome TEXT,
        destinatario_telefone TEXT,
        unidade_apartamento TEXT,
        codigo_rastreio TEXT,
        tipo_tarefa TEXT,
        descricao_outro TEXT,
        peso_kg NUMERIC,
        volumes_qtd INT,
        prioridade TEXT,
        ordem_na_rota INT,
        observacoes_gestor TEXT
    )
    LOOP
        v_idx := v_idx + 1;

        -- Valida se o cliente_endereco pertence à mesma empresa
        IF NOT EXISTS (
            SELECT 1 FROM public.clientes_enderecos
            WHERE id = v_parada.cliente_endereco_id AND empresa_id = v_empresa_id
        ) THEN
            RAISE EXCEPTION 'Endereço de cliente % não pertence à empresa do despacho.', v_parada.cliente_endereco_id;
        END IF;

        INSERT INTO public.entregas (
            empresa_id,
            rota_id,
            motorista_id,
            cliente_endereco_id,
            codigo_rastreio,
            destinatario_nome,
            destinatario_telefone,
            unidade_apartamento,
            status,
            prioridade,
            tipo_tarefa,
            descricao_outro,
            peso_kg,
            volumes_qtd,
            ordem_na_rota,
            observacoes_gestor
        ) VALUES (
            v_empresa_id,
            v_rota_id,
            v_motorista_id,
            v_parada.cliente_endereco_id,
            COALESCE(NULLIF(TRIM(v_parada.codigo_rastreio), ''), 'EC-' || SUBSTRING(gen_random_uuid()::text, 1, 8)),
            COALESCE(NULLIF(TRIM(v_parada.destinatario_nome), ''), 'Morador/Recepção'),
            v_parada.destinatario_telefone,
            v_parada.unidade_apartamento,
            'atribuida',
            COALESCE(v_parada.prioridade, 'normal'),
            COALESCE(v_parada.tipo_tarefa, 'entrega'),
            v_parada.descricao_outro,
            v_parada.peso_kg,
            COALESCE(v_parada.volumes_qtd, 1),
            COALESCE(v_parada.ordem_na_rota, v_idx),
            v_parada.observacoes_gestor
        );
    END LOOP;

    -- 9. Atualiza status do motorista para em_rota
    UPDATE public.motoristas
    SET status = 'em_rota',
        updated_at = timezone('utc'::text, now())
    WHERE id = v_motorista_id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ROTA_DESPACHADA',
        'mensagem', 'Rota e paradas despachadas com sucesso.',
        'rota_id', v_rota_id,
        'total_paradas', v_idx,
        'idempotente', FALSE
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/iniciar_rota.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: iniciar_rota.sql
-- Início de execução da rota pelo condutor atribuído. Idempotente.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.iniciar_rota(
    p_rota_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_motorista_id UUID;
    v_rota RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    SELECT * INTO v_rota
    FROM public.rotas_planejadas
    WHERE id = p_rota_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ROTA_NAO_ENCONTRADA',
            'mensagem', 'Rota planejada não encontrada.'
        );
    END IF;

    -- Descobre o motorista_id do usuário atual
    v_motorista_id := public.fn_motorista_id_do_usuario(v_user_id);

    -- Validação de titularidade: deve ser o motorista atribuído ou gestor da empresa
    IF v_motorista_id != v_rota.motorista_id AND NOT public.fn_usuario_e_gestor_empresa(v_rota.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas o motorista atribuído ou a gestão da empresa podem iniciar esta rota.'
        );
    END IF;

    -- Idempotência: se já estiver em_execucao, retorna sucesso
    IF v_rota.status = 'em_execucao' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'ROTA_JA_EM_EXECUCAO',
            'mensagem', 'A rota já está em execução.',
            'rota_id', v_rota.id
        );
    END IF;

    IF v_rota.status IN ('concluida', 'cancelada') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TRANSICAO_INVALIDA',
            'mensagem', 'Não é possível iniciar uma rota finalizada ou cancelada.'
        );
    END IF;

    -- Atualiza status da rota para em_execucao
    UPDATE public.rotas_planejadas
    SET status = 'em_execucao',
        iniciada_em = COALESCE(iniciada_em, timezone('utc'::text, now()))
    WHERE id = v_rota.id;

    -- Atualiza status das entregas atribuídas para em_transito
    UPDATE public.entregas
    SET status = 'em_transito',
        updated_at = timezone('utc'::text, now())
    WHERE rota_id = v_rota.id AND status = 'atribuida';

    -- Atualiza status do motorista
    UPDATE public.motoristas
    SET status = 'em_rota',
        updated_at = timezone('utc'::text, now())
    WHERE id = v_rota.motorista_id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ROTA_INICIADA',
        'mensagem', 'Rota iniciada com sucesso.',
        'rota_id', v_rota.id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/concluir_rota.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: concluir_rota.sql
-- Conclusão de rota quando todas as paradas foram atendidas.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.concluir_rota(
    p_rota_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_motorista_id UUID;
    v_rota RECORD;
    v_paradas_pendentes INT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    SELECT * INTO v_rota
    FROM public.rotas_planejadas
    WHERE id = p_rota_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ROTA_NAO_ENCONTRADA',
            'mensagem', 'Rota planejada não encontrada.'
        );
    END IF;

    v_motorista_id := public.fn_motorista_id_do_usuario(v_user_id);

    IF v_motorista_id != v_rota.motorista_id AND NOT public.fn_usuario_e_gestor_empresa(v_rota.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas o motorista atribuído ou a gestão da empresa podem concluir esta rota.'
        );
    END IF;

    -- Verifica se ainda existem entregas não finalizadas
    SELECT COUNT(*) INTO v_paradas_pendentes
    FROM public.entregas
    WHERE rota_id = v_rota.id AND status IN ('pendente', 'atribuida', 'em_transito');

    IF v_paradas_pendentes > 0 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'PARADAS_PENDENTES',
            'mensagem', 'Não é possível concluir a rota enquanto houver paradas pendentes de baixa ou ocorrência.'
        );
    END IF;

    -- Atualiza status da rota para concluida
    UPDATE public.rotas_planejadas
    SET status = 'concluida',
        concluida_em = timezone('utc'::text, now())
    WHERE id = v_rota.id;

    -- Libera status do motorista se não houver outras rotas ativas
    IF NOT EXISTS (
        SELECT 1 FROM public.rotas_planejadas
        WHERE motorista_id = v_rota.motorista_id AND status = 'em_execucao' AND id != v_rota.id
    ) THEN
        UPDATE public.motoristas
        SET status = 'disponivel',
            updated_at = timezone('utc'::text, now())
        WHERE id = v_rota.motorista_id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ROTA_CONCLUIDA',
        'mensagem', 'Rota concluída com sucesso.',
        'rota_id', v_rota.id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/registrar_conclusao_entrega.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: registrar_conclusao_entrega.sql
-- Baixa atômica de entrega / ocorrência, histórico e recálculo de tempos médios.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.registrar_conclusao_entrega(
    p_entrega_id UUID,
    p_sucesso BOOLEAN,
    p_motivo_falha TEXT DEFAULT NULL,
    p_tempo_portaria NUMERIC DEFAULT 0.00,
    p_tempo_deslocamento NUMERIC DEFAULT 0.00,
    p_data_hora_chegada TIMESTAMPTZ DEFAULT NULL,
    p_data_hora_conclusao TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_motorista_id UUID;
    v_entrega RECORD;
    v_chegada TIMESTAMPTZ;
    v_conclusao TIMESTAMPTZ;
    v_tempo_total NUMERIC;
    v_novo_status VARCHAR(30);
    v_hist_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    SELECT * INTO v_entrega
    FROM public.entregas
    WHERE id = p_entrega_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ENTREGA_NAO_ENCONTRADA',
            'mensagem', 'Entrega não encontrada.'
        );
    END IF;

    -- Valida permissão do motorista ou gestor
    v_motorista_id := public.fn_motorista_id_do_usuario(v_user_id);

    IF (v_entrega.motorista_id IS NOT NULL AND v_motorista_id != v_entrega.motorista_id)
       AND NOT public.fn_usuario_e_gestor_empresa(v_entrega.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas o motorista atribuído ou gestor da empresa podem registrar a baixa desta entrega.'
        );
    END IF;

    -- Define horários
    v_conclusao := COALESCE(p_data_hora_conclusao, timezone('utc'::text, now()));
    v_chegada := COALESCE(p_data_hora_chegada, v_conclusao - INTERVAL '10 minutes');

    v_tempo_total := COALESCE(p_tempo_portaria, 0) + COALESCE(p_tempo_deslocamento, 0);
    IF v_tempo_total <= 0 THEN
        v_tempo_total := GREATEST(1, ROUND(EXTRACT(EPOCH FROM (v_conclusao - v_chegada)) / 60));
    END IF;

    v_novo_status := CASE WHEN p_sucesso THEN 'entregue' ELSE 'tentativa_falha' END;

    -- Atualiza status da entrega
    UPDATE public.entregas
    SET status = v_novo_status,
        data_hora_entrega = v_conclusao,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_entrega.id;

    -- Insere registro imutável no histórico de atendimentos
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
    ) VALUES (
        v_entrega.id,
        v_entrega.cliente_endereco_id,
        COALESCE(v_entrega.motorista_id, v_motorista_id),
        COALESCE(p_tempo_portaria, 0),
        COALESCE(p_tempo_deslocamento, 0),
        v_tempo_total,
        v_chegada,
        v_conclusao,
        p_sucesso,
        p_motivo_falha
    )
    RETURNING id INTO v_hist_id;

    -- Recalcula tempo médio de atendimento do local
    UPDATE public.clientes_enderecos
    SET total_entregas_realizadas = total_entregas_realizadas + 1,
        tempo_medio_minutos = ROUND(
            ((tempo_medio_minutos * total_entregas_realizadas) + v_tempo_total) / (total_entregas_realizadas + 1),
            2
        ),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_entrega.cliente_endereco_id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ENTREGA_CONCLUIDA',
        'mensagem', 'Baixa de entrega registrada com sucesso.',
        'entrega_id', v_entrega.id,
        'status', v_novo_status,
        'historico_id', v_hist_id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/obter_meu_status_acesso.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: obter_meu_status_acesso.sql
-- RPC Soberana de consulta do estado de acesso do usuário autenticado no app.
-- Diferencia: conta autenticada -> vinculo -> aprovacao -> veiculo -> operacional
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.obter_meu_status_acesso()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_membro RECORD;
    v_solicitacao RECORD;
    v_motorista RECORD;
    v_veiculo RECORD;
    v_empresa RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'autenticado', FALSE,
            'status', 'nao_autenticado',
            'mensagem', 'Nenhuma sessão ativa identificada.'
        );
    END IF;

    -- 1. Busca vínculo na tabela empresa_membros
    SELECT em.*, e.nome AS empresa_nome, e.ativa AS empresa_ativa
    INTO v_membro
    FROM public.empresa_membros em
    JOIN public.empresas e ON e.id = em.empresa_id
    WHERE em.user_id = v_user_id
    ORDER BY em.created_at DESC
    LIMIT 1;

    -- 2. Busca veículo declarado
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE user_id = v_user_id;

    -- Caso A: Membro encontrado
    IF v_membro.id IS NOT NULL THEN
        -- Verifica se empresa está ativa
        IF NOT v_membro.empresa_ativa THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'suspenso',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'motivo', 'Empresa desativada pela administração.',
                'mensagem', 'A empresa vinculada está temporariamente inativa.'
            );
        END IF;

        IF v_membro.status = 'suspenso' THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'suspenso',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'motivo', v_membro.motivo_decisao,
                'mensagem', 'Seu acesso foi suspenso pela gestão.'
            );
        ELSIF v_membro.status = 'rejeitado' THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'rejeitado',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'motivo', v_membro.motivo_decisao,
                'mensagem', 'Sua solicitação de acesso foi recusada.'
            );
        ELSIF v_membro.status = 'pendente' THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'pendente',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'veiculo_declarado', v_veiculo.id IS NOT NULL,
                'veiculo_status', v_veiculo.status_analise,
                'mensagem', 'Solicitação aguardando aprovação da gestão.'
            );
        ELSIF v_membro.status = 'aprovado' THEN
            -- Se for gestor ou admin, acesso liberado
            IF v_membro.papel IN ('admin', 'gestor') THEN
                RETURN jsonb_build_object(
                    'autenticado', TRUE,
                    'user_id', v_user_id,
                    'status', 'aprovado',
                    'papel', v_membro.papel,
                    'empresa_id', v_membro.empresa_id,
                    'empresa_nome', v_membro.empresa_nome,
                    'mensagem', 'Acesso administrativo liberado.'
                );
            END IF;

            -- Se for motorista, verifica se já possui motorista_id vinculado na frota
            IF v_membro.motorista_id IS NOT NULL THEN
                SELECT * INTO v_motorista FROM public.motoristas WHERE id = v_membro.motorista_id;
                RETURN jsonb_build_object(
                    'autenticado', TRUE,
                    'user_id', v_user_id,
                    'status', 'aprovado',
                    'papel', 'motorista',
                    'empresa_id', v_membro.empresa_id,
                    'empresa_nome', v_membro.empresa_nome,
                    'motorista_id', v_motorista.id,
                    'motorista_nome', v_motorista.nome,
                    'veiculo', v_motorista.veiculo_modelo || ' (' || v_motorista.veiculo_placa || ')',
                    'veiculo_status', v_veiculo.status_analise,
                    'veiculo_tipo', v_veiculo.tipo_veiculo,
                    'mensagem', 'Acesso operacional liberado com sucesso.'
                );
            ELSE
                RETURN jsonb_build_object(
                    'autenticado', TRUE,
                    'user_id', v_user_id,
                    'status', 'aprovado_sem_cadastro',
                    'papel', 'motorista',
                    'empresa_id', v_membro.empresa_id,
                    'empresa_nome', v_membro.empresa_nome,
                    'veiculo_declarado', v_veiculo.id IS NOT NULL,
                    'veiculo_status', v_veiculo.status_analise,
                    'mensagem', 'Membro aprovado. Aguardando vinculação operacional da frota.'
                );
            END IF;
        END IF;
    END IF;

    -- Caso B: Sem membro, mas com solicitação em solicitacoes_acesso
    SELECT sa.*, e.nome AS empresa_nome
    INTO v_solicitacao
    FROM public.solicitacoes_acesso sa
    JOIN public.empresas e ON e.id = sa.empresa_id
    WHERE sa.user_id = v_user_id
    ORDER BY sa.created_at DESC
    LIMIT 1;

    IF v_solicitacao.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'autenticado', TRUE,
            'user_id', v_user_id,
            'status', v_solicitacao.status,
            'papel', 'motorista',
            'empresa_id', v_solicitacao.empresa_id,
            'empresa_nome', v_solicitacao.empresa_nome,
            'motivo', v_solicitacao.motivo_decisao,
            'veiculo_declarado', v_veiculo.id IS NOT NULL,
            'veiculo_status', v_veiculo.status_analise,
            'mensagem', CASE 
                WHEN v_solicitacao.status = 'pendente' THEN 'Solicitação aguardando análise da gestão.'
                WHEN v_solicitacao.status = 'rejeitado' THEN 'Solicitação de acesso recusada.'
                ELSE 'Solicitação em análise.'
            END
        );
    END IF;

    -- Caso C: Sem nenhum vínculo ou solicitação
    RETURN jsonb_build_object(
        'autenticado', TRUE,
        'user_id', v_user_id,
        'status', 'sem_vinculo',
        'papel', NULL,
        'empresa_id', NULL,
        'mensagem', 'Conta autenticada sem vínculo empresarial. Insira o código da empresa para solicitar acesso.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/sincronizar_meu_perfil.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: sincronizar_meu_perfil.sql
-- Garante sincronização automática do perfil a partir do auth.users.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.sincronizar_meu_perfil()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user RECORD;
    v_nome TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'mensagem', 'Não autenticado.');
    END IF;

    SELECT * INTO v_user FROM auth.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'mensagem', 'Usuário não encontrado em auth.users.');
    END IF;

    v_nome := COALESCE(
        v_user.raw_user_meta_data->>'name',
        v_user.raw_user_meta_data->>'full_name',
        SPLIT_PART(v_user.email, '@', 1)
    );

    INSERT INTO public.perfis_usuarios (
        id,
        email,
        nome,
        avatar_url,
        updated_at
    ) VALUES (
        v_user_id,
        v_user.email,
        v_nome,
        v_user.raw_user_meta_data->>'avatar_url',
        timezone('utc'::text, now())
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        nome = COALESCE(perfis_usuarios.nome, EXCLUDED.nome),
        updated_at = timezone('utc'::text, now());

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'mensagem', 'Perfil sincronizado com sucesso.'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/bootstrap_primeiro_gestor.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: bootstrap_primeiro_gestor.sql
-- Inicialização controlada do primeiro administrador da empresa.
-- Executável estritamente pela service_role.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.bootstrap_primeiro_gestor(
    p_email_gestor TEXT,
    p_codigo_convite TEXT,
    p_nome_empresa TEXT DEFAULT 'EntregaCondo Matriz (Florianópolis)'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user RECORD;
    v_empresa RECORD;
BEGIN
    -- Busca usuário em auth.users
    SELECT * INTO v_user
    FROM auth.users
    WHERE LOWER(email) = LOWER(TRIM(p_email_gestor));

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'USUARIO_NAO_ENCONTRADO',
            'mensagem', 'Usuário com este e-mail ainda não criou conta no Supabase Auth.'
        );
    END IF;

    -- Cria ou obtém a empresa
    INSERT INTO public.empresas (
        nome,
        codigo_convite,
        cidade,
        uf,
        ativa
    ) VALUES (
        p_nome_empresa,
        UPPER(TRIM(p_codigo_convite)),
        'Florianópolis',
        'SC',
        TRUE
    )
    ON CONFLICT (codigo_convite) DO UPDATE SET ativa = TRUE
    RETURNING * INTO v_empresa;

    -- Garante perfil
    INSERT INTO public.perfis_usuarios (
        id,
        email,
        nome
    ) VALUES (
        v_user.id,
        v_user.email,
        COALESCE(v_user.raw_user_meta_data->>'full_name', v_user.raw_user_meta_data->>'name', 'Administrador')
    )
    ON CONFLICT (id) DO NOTHING;

    -- Define o usuário como administrador da empresa
    INSERT INTO public.empresa_membros (
        empresa_id,
        user_id,
        papel,
        status,
        aprovado_em
    ) VALUES (
        v_empresa.id,
        v_user.id,
        'admin',
        'aprovado',
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel = 'admin',
        status = 'aprovado',
        aprovado_em = timezone('utc'::text, now());

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'BOOTSTRAP_CONCLUIDO',
        'mensagem', 'Primeiro administrador configurado com sucesso.',
        'empresa_id', v_empresa.id,
        'empresa_nome', v_empresa.nome,
        'user_id', v_user.id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/04_storage.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 04_storage.sql
-- Bucket privado e políticas de ciclo de vida seguro para fotos e documentos.
-- Bloqueia exclusão direta de qualquer evidência vinculada (pendente ou aprovada).
-- Bloqueia sobrescrita (UPDATE/upsert) de evidências vinculadas.
-- Permite exclusão autorizada de uploads temporários e arquivos desvinculados.
--
-- GARANTIAS OBTIDAS:
-- 1. Toda evidência vinculada em veiculos_documentos está protegida contra
--    exclusão direta e sobrescrita pela API do Storage.
-- 2. Concorrência entre análise/aprovação e exclusão é neutralizada: a política
--    impede o DELETE no Storage enquanto a linha persistir em veiculos_documentos.
-- 3. Apenas a RPC remover_documento_veiculo (ou substituição autorizada) desvincula
--    o arquivo no Postgres, rebaixa o veículo para 'pendente' e então autoriza a
--    remoção física pelo cliente.
-- 4. Uploads temporários não vinculados podem ser limpos pelo próprio condutor.
--
-- LIMITAÇÕES:
-- O Supabase Storage e o PostgreSQL não compartilham transação atômica 2PC.
-- As regras são coordenadas via RLS em storage.objects. Acessos que utilizem a
-- chave master service_role ou acessos diretos à infraestrutura de blocos (S3/disco)
-- contornam o motor SQL e não são governados por estas políticas.
-- ==============================================================================

-- 1. Criação e parametrização do bucket privado 'veiculos-documentos'
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'veiculos-documentos',
    'veiculos-documentos',
    FALSE,
    10485760, -- 10 MB
    ARRAY['image/jpeg', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
    public = FALSE,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'application/pdf'];

-- 2. Políticas de Ciclo de Vida e Acesso no schema storage.objects

-- POLÍTICA 1: Upload (INSERT) de evidências pelo condutor autorizado
DROP POLICY IF EXISTS "Condutores enviam documentos do proprio veiculo" ON storage.objects;
CREATE POLICY "Condutores enviam documentos do proprio veiculo"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'veiculos-documentos' AND
    public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
    public.fn_safe_uuid(split_part(name, '/', 1)) IS NOT NULL AND
    (
        (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
    )
);

-- POLÍTICA 2: Visualização (SELECT) por condutor proprietário ou gestor da empresa
DROP POLICY IF EXISTS "Acesso autorizado a documentos veiculares" ON storage.objects;
CREATE POLICY "Acesso autorizado a documentos veiculares"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    (
        public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid()
        OR
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)))
    )
);

-- POLÍTICA 3: Alteração / Sobrescrita (UPDATE / upsert)
-- Bloqueia terminantemente a sobrescrita direta de qualquer evidência vinculada.
-- Um arquivo só pode ser atualizado se for um upload temporário ainda não vinculado.
DROP POLICY IF EXISTS "Atualizacao de documentos veiculares" ON storage.objects;
CREATE POLICY "Atualizacao de documentos veiculares"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
    (
        (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    )
)
WITH CHECK (
    bucket_id = 'veiculos-documentos' AND
    public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
    (
        (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    )
);

-- POLÍTICA 4: Exclusão (DELETE) com proteção de evidências vinculadas
-- Bloqueia a exclusão direta de QUALQUER evidência vinculada (pendente ou aprovada).
-- A exclusão é autorizada apenas para:
-- A) Uploads temporários do próprio condutor que ainda não foram vinculados via RPC.
-- B) Arquivos desvinculados previamente através da RPC remover_documento_veiculo ou substituição.
DROP POLICY IF EXISTS "Exclusao de documentos veiculares" ON storage.objects;
CREATE POLICY "Exclusao de documentos veiculares"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    (
        -- Condutor proprietário autorizado (não suspenso)
        (
            public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
        )
        OR
        -- Gestor da empresa
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)))
    ) AND
    -- PROTEÇÃO CRÍTICA: Bloqueia exclusão direta enquanto o arquivo estiver vinculado
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    )
);

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/05_rls_policies.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 05_rls_policies.sql
-- Funções de verificação e políticas RLS para todas as tabelas públicas.
-- Bloqueio absoluto de registros sem empresa. Sem 'empresa_id IS NULL OR'.
-- ==============================================================================

-- 1. FUNÇÕES AUXILIARES DE AUTORIZAÇÃO (SECURITY DEFINER)

CREATE OR REPLACE FUNCTION public.fn_usuario_e_gestor_empresa(p_empresa_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id
        WHERE em.empresa_id = p_empresa_id
          AND em.user_id = auth.uid()
          AND em.papel IN ('admin', 'gestor')
          AND em.status = 'aprovado'
          AND e.ativa = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.fn_usuario_e_admin_empresa(p_empresa_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id
        WHERE em.empresa_id = p_empresa_id
          AND em.user_id = auth.uid()
          AND em.papel = 'admin'
          AND em.status = 'aprovado'
          AND e.ativa = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.fn_motorista_id_do_usuario(p_user_id UUID)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT em.motorista_id
    FROM public.empresa_membros em
    JOIN public.empresas e ON e.id = em.empresa_id
    WHERE em.user_id = p_user_id
      AND em.status = 'aprovado'
      AND em.motorista_id IS NOT NULL
      AND e.ativa = TRUE
    LIMIT 1;
$$;

-- 2. HABILITAÇÃO DE RLS EM TODAS AS TABELAS
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfis_usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.empresa_membros ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.solicitacoes_acesso ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_acessos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veiculos_motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.veiculos_documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes_enderecos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rotas_planejadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historico_atendimentos ENABLE ROW LEVEL SECURITY;

-- 3. POLÍTICAS RLS

-- empresas
DROP POLICY IF EXISTS "Usuarios visualizam empresas das quais sao membros" ON public.empresas;
CREATE POLICY "Usuarios visualizam empresas das quais sao membros"
ON public.empresas FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.empresa_membros em
        WHERE em.empresa_id = id
          AND em.user_id = auth.uid()
    )
);

-- perfis_usuarios
DROP POLICY IF EXISTS "Usuarios visualizam proprio perfil ou de membros da mesma empresa" ON public.perfis_usuarios;
CREATE POLICY "Usuarios visualizam proprio perfil ou de membros da mesma empresa"
ON public.perfis_usuarios FOR SELECT
TO authenticated
USING (
    id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM public.empresa_membros m1
        JOIN public.empresa_membros m2 ON m1.empresa_id = m2.empresa_id
        WHERE m1.user_id = auth.uid()
          AND m2.user_id = perfis_usuarios.id
          AND m1.status = 'aprovado'
    )
);

DROP POLICY IF EXISTS "Usuarios atualizam apenas proprio perfil" ON public.perfis_usuarios;
CREATE POLICY "Usuarios atualizam apenas proprio perfil"
ON public.perfis_usuarios FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- empresa_membros
DROP POLICY IF EXISTS "Leitura de membros por membros da empresa" ON public.empresa_membros;
CREATE POLICY "Leitura de membros por membros da empresa"
ON public.empresa_membros FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

-- solicitacoes_acesso
DROP POLICY IF EXISTS "Leitura de solicitacoes pelo usuario ou gestao" ON public.solicitacoes_acesso;
CREATE POLICY "Leitura de solicitacoes pelo usuario ou gestao"
ON public.solicitacoes_acesso FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

-- auditoria_acessos
DROP POLICY IF EXISTS "Gestores leem auditoria da empresa" ON public.auditoria_acessos;
CREATE POLICY "Gestores leem auditoria da empresa"
ON public.auditoria_acessos FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

-- motoristas
DROP POLICY IF EXISTS "Leitura de motoristas autorizada" ON public.motoristas;
CREATE POLICY "Leitura de motoristas autorizada"
ON public.motoristas FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id)
    OR
    (
        user_id = auth.uid() AND
        EXISTS (
            SELECT 1 FROM public.empresa_membros em
            JOIN public.empresas e ON e.id = em.empresa_id
            WHERE em.empresa_id = motoristas.empresa_id
              AND em.user_id = auth.uid()
              AND em.status = 'aprovado'
              AND em.motorista_id = motoristas.id
              AND e.ativa = TRUE
        )
    )
);

-- veiculos_motoristas
DROP POLICY IF EXISTS "Leitura de veiculos por condutor ou gestao" ON public.veiculos_motoristas;
CREATE POLICY "Leitura de veiculos por condutor ou gestao"
ON public.veiculos_motoristas FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

-- veiculos_documentos
DROP POLICY IF EXISTS "Leitura de documentos por condutor ou gestao" ON public.veiculos_documentos;
CREATE POLICY "Leitura de documentos por condutor ou gestao"
ON public.veiculos_documentos FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

-- clientes_enderecos
DROP POLICY IF EXISTS "Leitura de clientes enderecos por gestao ou motorista atribuido" ON public.clientes_enderecos;
CREATE POLICY "Leitura de clientes enderecos por gestao ou motorista atribuido"
ON public.clientes_enderecos FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id)
    OR
    EXISTS (
        SELECT 1 FROM public.entregas ent
        WHERE ent.cliente_endereco_id = clientes_enderecos.id
          AND ent.motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
          AND ent.status IN ('atribuida', 'em_transito')
    )
);

-- rotas_planejadas
DROP POLICY IF EXISTS "Leitura de rotas por gestao ou motorista atribuido" ON public.rotas_planejadas;
CREATE POLICY "Leitura de rotas por gestao ou motorista atribuido"
ON public.rotas_planejadas FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id)
    OR
    (
        motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.empresa_membros em
            JOIN public.empresas e ON e.id = em.empresa_id
            WHERE em.empresa_id = rotas_planejadas.empresa_id
              AND em.user_id = auth.uid()
              AND em.status = 'aprovado'
              AND e.ativa = TRUE
        )
    )
);

-- entregas
DROP POLICY IF EXISTS "Leitura de entregas por gestao ou motorista atribuido" ON public.entregas;
CREATE POLICY "Leitura de entregas por gestao ou motorista atribuido"
ON public.entregas FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id)
    OR
    (
        motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.empresa_membros em
            JOIN public.empresas e ON e.id = em.empresa_id
            WHERE em.empresa_id = entregas.empresa_id
              AND em.user_id = auth.uid()
              AND em.status = 'aprovado'
              AND e.ativa = TRUE
        )
    )
);

-- historico_atendimentos
DROP POLICY IF EXISTS "Leitura de historico por gestao ou motorista" ON public.historico_atendimentos;
CREATE POLICY "Leitura de historico por gestao ou motorista"
ON public.historico_atendimentos FOR SELECT
TO authenticated
USING (
    motorista_id = public.fn_motorista_id_do_usuario(auth.uid())
    OR
    EXISTS (
        SELECT 1 FROM public.entregas e
        WHERE e.id = historico_atendimentos.entrega_id
          AND public.fn_usuario_e_gestor_empresa(e.empresa_id)
    )
);

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/06_grants.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 06_grants.sql
-- Concessão explícita e coerente de privilégios.
-- Elimina contradições: sem mutações diretas em tabelas operacionais ou administrativas.
-- Mutações ocorrem exclusivamente por RPCs com SECURITY DEFINER auditadas.
-- ==============================================================================

-- 1. REVOGAÇÃO GERAL DE ESCRITA DIRETA PARA ANON E AUTHENTICATED
REVOKE ALL ON public.empresas FROM anon, authenticated;
REVOKE ALL ON public.perfis_usuarios FROM anon, authenticated;
REVOKE ALL ON public.empresa_membros FROM anon, authenticated;
REVOKE ALL ON public.solicitacoes_acesso FROM anon, authenticated;
REVOKE ALL ON public.auditoria_acessos FROM anon, authenticated;
REVOKE ALL ON public.motoristas FROM anon, authenticated;
REVOKE ALL ON public.veiculos_motoristas FROM anon, authenticated;
REVOKE ALL ON public.veiculos_documentos FROM anon, authenticated;
REVOKE ALL ON public.clientes_enderecos FROM anon, authenticated;
REVOKE ALL ON public.rotas_planejadas FROM anon, authenticated;
REVOKE ALL ON public.entregas FROM anon, authenticated;
REVOKE ALL ON public.historico_atendimentos FROM anon, authenticated;

-- 2. CONCESSÃO DE LEITURA (SELECT) RESTRITA VIA RLS
GRANT SELECT ON public.empresas TO authenticated;
GRANT SELECT ON public.perfis_usuarios TO authenticated;
GRANT SELECT ON public.empresa_membros TO authenticated;
GRANT SELECT ON public.solicitacoes_acesso TO authenticated;
GRANT SELECT ON public.auditoria_acessos TO authenticated;
GRANT SELECT ON public.motoristas TO authenticated;
GRANT SELECT ON public.veiculos_motoristas TO authenticated;
GRANT SELECT ON public.veiculos_documentos TO authenticated;
GRANT SELECT ON public.clientes_enderecos TO authenticated;
GRANT SELECT ON public.rotas_planejadas TO authenticated;
GRANT SELECT ON public.entregas TO authenticated;
GRANT SELECT ON public.historico_atendimentos TO authenticated;

-- 3. PERMISSÃO DE EDIÇÃO BÁSICA EXCLUSIVA NO PRÓPRIO PERFIL
GRANT UPDATE (nome, telefone, avatar_url) ON public.perfis_usuarios TO authenticated;

-- 4. REVOGAÇÃO DE SOBRECARGAS OBSOLETAS E PRIVILÉGIOS PÚBLICOS PADRÃO
DROP FUNCTION IF EXISTS public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS public.analisar_veiculo_motorista(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR);

REVOKE EXECUTE ON FUNCTION public.fn_validar_autorizacao_condutor(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, INT) FROM PUBLIC;

-- 5. CONCESSÃO DE EXECUÇÃO NAS RPCS DE NEGÓCIO
GRANT EXECUTE ON FUNCTION public.fn_safe_uuid(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_pertence_empresa(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_e_gestor_empresa(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_e_admin_empresa(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_e_motorista_ativo(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_motorista_id_do_usuario(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validar_autorizacao_condutor(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) TO authenticated;

GRANT EXECUTE ON FUNCTION public.obter_meu_status_acesso() TO authenticated;
GRANT EXECUTE ON FUNCTION public.solicitar_acesso_empresa(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) TO authenticated;

GRANT EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rejeitar_solicitacao_acesso(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suspender_acesso_membro(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reativar_acesso_membro(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alterar_papel_membro(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.despachar_rota_transacional(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iniciar_rota(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.concluir_rota(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_conclusao_entrega(UUID, BOOLEAN, TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sincronizar_meu_perfil() TO authenticated;

GRANT EXECUTE ON FUNCTION public.bootstrap_primeiro_gestor(TEXT, TEXT, TEXT) TO service_role;

-- ------------------------------------------------------------------------------
-- PUBLICAÇÃO REALTIME
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.empresa_membros;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.solicitacoes_acesso;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.veiculos_motoristas;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.veiculos_documentos;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.rotas_planejadas;
        ALTER PUBLICATION supabase_realtime ADD TABLE public.entregas;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- ------------------------------------------------------------------------------
-- DADOS INICIAIS BASE (EMPRESA MATRIZ)
-- ------------------------------------------------------------------------------
INSERT INTO public.empresas (id, nome, cnpj, codigo_convite, cidade, uf, ativa)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'EntregaCondo Matriz (Florianópolis)',
    '00.000.000/0001-00',
    'EC-FLN-01',
    'Florianópolis',
    'SC',
    TRUE
)
ON CONFLICT (codigo_convite) DO NOTHING;
