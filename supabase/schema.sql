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
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id AND e.ativa = TRUE
        WHERE em.empresa_id = p_empresa_id
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
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id AND e.ativa = TRUE
        WHERE em.empresa_id = p_empresa_id
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
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id AND e.ativa = TRUE
        WHERE em.empresa_id = p_empresa_id
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

    IF NOT EXISTS (SELECT 1 FROM public.empresas WHERE id = p_empresa_id AND ativa = TRUE) THEN
        RETURN jsonb_build_object('autorizado', false, 'codigo', 'EMPRESA_INATIVA', 'mensagem', 'Empresa indisponível.');
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

        IF v_membro.status <> 'pendente' THEN
            RETURN jsonb_build_object('autorizado', false, 'codigo', 'ACESSO_NAO_AUTORIZADO', 'mensagem', 'Vínculo com a empresa não está ativo.');
        END IF;
        -- Pendente só pode preparar cadastro se a solicitação atual também estiver pendente.
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
    tempo_medio_minutos NUMERIC(8, 2) NOT NULL DEFAULT 15.00,
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
    metricas_fonte TEXT,
    metricas_atualizadas_em TIMESTAMPTZ,
    configuracao_navegacao JSONB NOT NULL DEFAULT '{}'::jsonb,
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

ALTER TABLE public.clientes_enderecos ADD COLUMN IF NOT EXISTS place_id VARCHAR(255);
CREATE OR REPLACE VIEW public.saved_addresses WITH (security_invoker=true) AS
SELECT id,empresa_id,nome_identificador AS label,endereco_completo AS full_address,latitude AS lat,longitude AS lng,place_id,created_at FROM public.clientes_enderecos;
GRANT SELECT ON public.saved_addresses TO authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/04_storage.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- MODULO SQL: 04_storage.sql
-- Bucket privado, protocolo de coordenação de ciclo de vida e fila de limpeza.
-- Bloqueia exclusão direta de qualquer evidência vinculada (pendente ou aprovada).
-- Bloqueia sobrescrita (UPDATE/upsert) de todas as evidências.
-- Coordena upload com reserva prévia, vinculação, substituição e descarte seguro.
--
-- GARANTIAS OBTIDAS:
-- 1. Todo upload exige reserva prévia via RPC reservar_upload_evidencia com caminho
--    único não reutilizável e status 'reservado'.
-- 2. Sobrescrita direta (UPDATE) de evidências é permanentemente bloqueada via RLS.
-- 3. Exclusão física (DELETE) só é autorizada para arquivos que NÃO estejam vinculados
--    em veiculos_documentos E cujo status na fila de limpeza seja 'pendente' ou 'em_processamento'.
-- 4. Anexar ou vincular documento disputa o lock da linha na fila de limpeza (FOR UPDATE).
--    Se houver tentativa concorrente de exclusão/descarte, a disputa no mesmo registro
--    impede a vinculação de arquivo em processo de limpeza ou já descartado.
-- 5. Objetos com status 'falhou' continuam bloqueados permanentemente contra upload ou
--    vinculação. A retomada exige chamada explícita e autorizada a retomar_limpeza_falha.
-- 6. A fila de limpeza possui constraint UNIQUE em storage_path, impedindo registros
--    conflitantes para o mesmo objeto.
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

-- 2. Fila persistente e auditável de limpeza e ciclo de vida do Storage
CREATE TABLE IF NOT EXISTS public.storage_limpeza_fila (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id VARCHAR(100) NOT NULL DEFAULT 'veiculos-documentos',
    storage_path TEXT NOT NULL UNIQUE,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    motivo TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('reservado', 'vinculado', 'pendente', 'em_processamento', 'concluido', 'falhou')),
    tentativas INT NOT NULL DEFAULT 0,
    max_tentativas INT NOT NULL DEFAULT 5,
    ultimo_erro TEXT,
    autorizado_em TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    processado_em TIMESTAMPTZ,
    claim_token UUID,
    claimed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    lease_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_storage_limpeza_status_path
ON public.storage_limpeza_fila(status, storage_path);

CREATE INDEX IF NOT EXISTS idx_storage_limpeza_empresa
ON public.storage_limpeza_fila(empresa_id, status);

ALTER TABLE public.storage_limpeza_fila ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Gestores e condutores visualizam fila de limpeza da empresa" ON public.storage_limpeza_fila;
CREATE POLICY "Gestores e condutores visualizam fila de limpeza da empresa"
ON public.storage_limpeza_fila FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid()) OR user_id = auth.uid()
);

-- 3. RPC: Reserva prévia de upload de evidência (Caminho único e coordenação de ciclo de vida)
-- RPC modular: functions-sql/reservar_upload_evidencia.sql

-- 4. RPC: Descarte coordenado de evidência temporária não vinculada
-- RPC modular: functions-sql/descartar_evidencia_temporaria.sql

-- 5. RPC: Reivindicação atômica de itens da fila de limpeza (Lock seguro contra concorrência)
-- RPC modular: functions-sql/reivindicar_itens_limpeza_storage.sql

-- 6. RPC: Retomada explícita e autorizada de limpeza falha
-- RPC modular: functions-sql/retomar_limpeza_falha.sql

-- 7. Função auditada para registrar resultado da limpeza física do Storage
-- RPC modular: functions-sql/registrar_limpeza_storage_executada.sql

-- 8. Políticas de Ciclo de Vida e Acesso no schema storage.objects

-- POLÍTICA 1: Upload (INSERT) de evidências pelo condutor autorizado com reserva prévia obrigatória
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
    ) AND
    -- EXIGE RESERVA PRÉVIA ATIVA (STATUS = 'reservado')
    EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
          AND slf.status = 'reservado'
          AND slf.user_id = auth.uid()
          AND slf.empresa_id = public.fn_safe_uuid(split_part(name, '/', 1))
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
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())
    )
);

-- POLÍTICA 3: Alteração / Sobrescrita (UPDATE / upsert)
-- Bloqueia terminantemente qualquer UPDATE/sobrescrita de evidências veiculares.
DROP POLICY IF EXISTS "Atualizacao de documentos veiculares" ON storage.objects;
CREATE POLICY "Atualizacao de documentos veiculares"
ON storage.objects FOR UPDATE
TO authenticated
USING (FALSE)
WITH CHECK (FALSE);

-- POLÍTICA 4: Exclusão (DELETE) com protocolo coordenado de ciclo de vida
-- Bloqueia a exclusão direta de QUALQUER evidência vinculada.
-- A exclusão é autorizada apenas se o arquivo NÃO está vinculado em veiculos_documentos E
-- a exclusão física foi formalmente autorizada na fila de limpeza com status pendente ou em_processamento.
DROP POLICY IF EXISTS "Exclusao de documentos veiculares" ON storage.objects;
CREATE POLICY "Exclusao de documentos veiculares"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'veiculos-documentos' AND
    (
        (
            public.fn_safe_uuid(split_part(name, '/', 2)) = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())->>'autorizado')::boolean = TRUE
        )
        OR
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)), auth.uid())
    ) AND
    -- NUNCA permite excluir se persistir vínculo em veiculos_documentos
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    ) AND
    -- EXIGE autorização formal na fila de limpeza com status pendente ou em_processamento
    EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
          AND slf.status = 'em_processamento'
          AND slf.claimed_by = auth.uid()
          AND slf.claim_token IS NOT NULL
          AND slf.lease_expires_at > clock_timestamp()
    )
);

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/04a_storage_constraints.sql
-- ------------------------------------------------------------------------------

-- Aborta com diagnóstico; nunca ignora falha de integridade nem exclui dados.
DO $$
DECLARE v_constraint RECORD;
BEGIN
    IF EXISTS (SELECT 1 FROM public.storage_limpeza_fila GROUP BY storage_path HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Caminhos duplicados em storage_limpeza_fila. Reconcilie os registros sem excluir o histórico antes da migração.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.storage_limpeza_fila WHERE status NOT IN ('reservado','vinculado','pendente','em_processamento','concluido','falhou')) THEN
        RAISE EXCEPTION 'Estado legado de Storage desconhecido. Migração interrompida sem alterar os dados.';
    END IF;
    FOR v_constraint IN SELECT conname FROM pg_constraint WHERE conrelid = 'public.storage_limpeza_fila'::regclass
        AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%status%'
    LOOP EXECUTE format('ALTER TABLE public.storage_limpeza_fila DROP CONSTRAINT %I', v_constraint.conname); END LOOP;
    ALTER TABLE public.storage_limpeza_fila ADD CONSTRAINT storage_limpeza_fila_status_check
        CHECK (status IN ('reservado','vinculado','pendente','em_processamento','concluido','falhou'));
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.storage_limpeza_fila'::regclass AND c.contype IN ('u','p')
          AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = c.conrelid AND attname = 'storage_path')]::smallint[]) THEN
        ALTER TABLE public.storage_limpeza_fila ADD CONSTRAINT storage_limpeza_fila_storage_path_key UNIQUE (storage_path);
    END IF;
END $$;

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
-- MÓDULO: supabase/functions-sql/fn_usuario_pode_operar_motorista.sql
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_usuario_pode_operar_motorista(
    p_empresa_id UUID, p_motorista_id UUID
)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.motoristas m
        JOIN public.empresas e ON e.id = m.empresa_id AND e.ativa = TRUE
        JOIN public.veiculos_motoristas vm ON vm.user_id = m.user_id AND vm.empresa_id = m.empresa_id
        WHERE m.id = p_motorista_id AND m.empresa_id = p_empresa_id AND m.ativo = TRUE
          AND vm.status_analise = 'aprovado'
          AND (public.fn_validar_completude_veiculo(vm.id)->>'valido')::boolean IS TRUE
          AND (public.fn_usuario_e_gestor_empresa(p_empresa_id, auth.uid()) IS TRUE OR (
              m.user_id = auth.uid() AND EXISTS (
                  SELECT 1 FROM public.empresa_membros em
                  WHERE em.empresa_id = p_empresa_id AND em.user_id = auth.uid()
                    AND em.motorista_id = m.id AND em.papel = 'motorista' AND em.status = 'aprovado'
              )
          ))
    );
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/reservar_upload_evidencia.sql
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reservar_upload_evidencia(
    p_empresa_id UUID,
    p_tipo_documento TEXT,
    p_nome_arquivo TEXT,
    p_angulo_foto TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_ext TEXT;
    v_random_uuid UUID := gen_random_uuid();
    v_timestamp BIGINT := (extract(epoch from timezone('utc'::text, now())) * 1000)::bigint;
    v_storage_path TEXT;
    v_fila_id UUID;
    v_identificador_tipo TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- Validação de autorização do condutor na empresa
    IF (public.fn_validar_autorizacao_condutor(p_empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(p_empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(p_empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    -- Valida tipo de documento
    IF p_tipo_documento NOT IN ('foto_veiculo', 'crlv', 'complementar') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TIPO_DOCUMENTO_INVALIDO',
            'mensagem', 'Tipo de documento deve ser foto_veiculo, crlv ou complementar.'
        );
    END IF;

    -- Valida ângulo para foto do veículo
    IF p_tipo_documento = 'foto_veiculo' THEN
        IF p_angulo_foto IS NULL OR p_angulo_foto NOT IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira') THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'ANGULO_INVALIDO',
                'mensagem', 'Para foto_veiculo, o ângulo é obrigatório e deve ser: frente, lado_direito, lado_esquerdo ou traseira.'
            );
        END IF;
        v_identificador_tipo := 'foto_' || p_angulo_foto;
    ELSE
        p_angulo_foto := NULL;
        v_identificador_tipo := p_tipo_documento;
    END IF;

    -- Valida extensão
    v_ext := LOWER(SUBSTRING(TRIM(p_nome_arquivo) FROM '\.([^\.]+)$'));
    IF v_ext NOT IN ('jpg', 'jpeg', 'png', 'pdf') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EXTENSAO_INVALIDA',
            'mensagem', 'Extensão de arquivo não permitida. Use JPG, PNG ou PDF.'
        );
    END IF;

    IF p_tipo_documento = 'foto_veiculo' AND v_ext = 'pdf' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'FOTO_NAO_ACEITA_PDF',
            'mensagem', 'Fotos do veículo não podem estar no formato PDF.'
        );
    END IF;

    -- Gera caminho estritamente único que previne colisões e reutilizações de caminhos descartados
    v_storage_path := p_empresa_id::text || '/' || v_user_id::text || '/' || v_identificador_tipo || '_' || v_timestamp::text || '_' || v_random_uuid::text || '.' || v_ext;

    -- Registra reserva com status 'reservado'
    INSERT INTO public.storage_limpeza_fila (
        bucket_id,
        storage_path,
        empresa_id,
        user_id,
        motivo,
        status
    ) VALUES (
        'veiculos-documentos',
        v_storage_path,
        p_empresa_id,
        v_user_id,
        'reserva_upload_' || v_identificador_tipo,
        'reservado'
    )
    RETURNING id INTO v_fila_id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'UPLOAD_RESERVADO',
        'mensagem', 'Upload autorizado e reservado com caminho único.',
        'storage_path', v_storage_path,
        'fila_id', v_fila_id,
        'bucket_id', 'veiculos-documentos'
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/descartar_evidencia_temporaria.sql
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.descartar_evidencia_temporaria(
    p_storage_path TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item RECORD;
BEGIN
    SELECT * INTO v_item
    FROM public.storage_limpeza_fila
    WHERE storage_path = TRIM(p_storage_path)
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'OBJETO_NAO_ENCONTRADO',
            'mensagem', 'Objeto não encontrado no ciclo de vida de armazenamento.'
        );
    END IF;

    -- Permissão: condutor proprietário ou gestor da empresa
    IF auth.uid() IS NULL OR NOT (public.fn_usuario_e_gestor_empresa(v_item.empresa_id, auth.uid()) IS TRUE OR (v_item.user_id = auth.uid() AND (public.fn_validar_autorizacao_condutor(v_item.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE)) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Sem permissão para descartar este arquivo.'
        );
    END IF;

    -- Se já estiver vinculado em veiculos_documentos, não pode ser descartado como temporário
    IF EXISTS (SELECT 1 FROM public.veiculos_documentos WHERE storage_path = v_item.storage_path) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_VINCULADO',
            'mensagem', 'O arquivo já está vinculado a um veículo ativo. Use a desvinculação oficial.'
        );
    END IF;

    IF v_item.status NOT IN ('reservado', 'pendente', 'em_processamento') THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'STATUS_INVALIDO', 'mensagem', 'O estado atual não autoriza este descarte.');
    END IF;

    -- Transição permitida: de 'reservado' para 'pendente' (autoriza exclusão física)
    IF v_item.status = 'reservado' THEN
        UPDATE public.storage_limpeza_fila
        SET status = 'pendente',
            motivo = 'descarte_temporario_nao_vinculado',
            autorizado_em = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_item.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DESCARTE_AUTORIZADO',
        'mensagem', 'Descarte autorizado. Objeto liberado para limpeza física.',
        'fila_id', v_item.id,
        'storage_path', v_item.storage_path
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/reivindicar_itens_limpeza_storage.sql
-- ------------------------------------------------------------------------------

-- A assinatura anterior não contém filtro de item nem identidade da tentativa.
DROP FUNCTION IF EXISTS public.reivindicar_itens_limpeza_storage(INT);
CREATE OR REPLACE FUNCTION public.reivindicar_itens_limpeza_storage(
    p_limite INT DEFAULT 10, p_fila_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID, bucket_id VARCHAR, storage_path TEXT, empresa_id UUID,
    user_id UUID, motivo TEXT, status VARCHAR, tentativas INT,
    max_tentativas INT, claim_token UUID, lease_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_item public.storage_limpeza_fila%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuário não autenticado.' USING ERRCODE = '42501';
    END IF;
    IF p_limite IS NULL OR p_limite < 1 OR p_limite > 100 THEN
        RAISE EXCEPTION 'O limite deve estar entre 1 e 100.' USING ERRCODE = '22023';
    END IF;
    -- Uma interrupção também consome tentativa.
    UPDATE public.storage_limpeza_fila f
    SET status = 'falhou', lease_expires_at = NULL, updated_at = clock_timestamp(),
        ultimo_erro = COALESCE(f.ultimo_erro, 'Prazo da última tentativa expirou sem confirmação.')
    WHERE f.status = 'em_processamento' AND f.lease_expires_at <= clock_timestamp()
      AND f.tentativas >= f.max_tentativas AND (p_fila_id IS NULL OR f.id = p_fila_id)
      AND (public.fn_usuario_e_gestor_empresa(f.empresa_id, auth.uid()) IS TRUE
        OR (f.user_id = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(f.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE));

    FOR v_item IN
        SELECT f.* FROM public.storage_limpeza_fila f
        WHERE (f.status = 'pendente' OR
            (f.status = 'em_processamento' AND f.lease_expires_at <= clock_timestamp()))
          AND f.tentativas < f.max_tentativas AND (p_fila_id IS NULL OR f.id = p_fila_id)
          AND (public.fn_usuario_e_gestor_empresa(f.empresa_id, auth.uid()) IS TRUE
            OR (f.user_id = auth.uid() AND
                (public.fn_validar_autorizacao_condutor(f.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE))
        ORDER BY f.created_at, f.id LIMIT p_limite FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.storage_limpeza_fila f
        SET status = 'em_processamento', claim_token = gen_random_uuid(),
            claimed_by = auth.uid(), lease_expires_at = clock_timestamp() + INTERVAL '5 minutes',
            tentativas = f.tentativas + 1,
            processado_em = clock_timestamp(), updated_at = clock_timestamp()
        WHERE f.id = v_item.id RETURNING f.* INTO v_item;
        INSERT INTO public.auditoria_acessos
            (empresa_id, user_id, acao, novo_status, executado_por, detalhes)
        VALUES (v_item.empresa_id, v_item.user_id, 'storage_claim', 'em_processamento', auth.uid(),
            jsonb_build_object('fila_id', v_item.id, 'claim_token', v_item.claim_token,
                'tentativa', v_item.tentativas, 'lease_expires_at', v_item.lease_expires_at));
        id := v_item.id; bucket_id := v_item.bucket_id; storage_path := v_item.storage_path;
        empresa_id := v_item.empresa_id; user_id := v_item.user_id; motivo := v_item.motivo;
        status := v_item.status; tentativas := v_item.tentativas; max_tentativas := v_item.max_tentativas;
        claim_token := v_item.claim_token; lease_expires_at := v_item.lease_expires_at;
        RETURN NEXT;
    END LOOP;
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/retomar_limpeza_falha.sql
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.retomar_limpeza_falha(
    p_fila_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item RECORD;
BEGIN
    SELECT * INTO v_item
    FROM public.storage_limpeza_fila
    WHERE id = p_fila_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ITEM_FILA_NAO_ENCONTRADO',
            'mensagem', 'Item da fila de limpeza não encontrado.'
        );
    END IF;

    IF auth.uid() IS NULL OR NOT (public.fn_usuario_e_gestor_empresa(v_item.empresa_id, auth.uid()) IS TRUE OR (v_item.user_id = auth.uid() AND (public.fn_validar_autorizacao_condutor(v_item.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE)) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Sem permissão para retomar limpeza deste item.'
        );
    END IF;

    IF v_item.status != 'falhou' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'STATUS_INVALIDO',
            'mensagem', 'Apenas itens com status "falhou" podem ser retomados (status atual: ' || v_item.status || ').'
        );
    END IF;

    INSERT INTO public.auditoria_acessos
        (empresa_id, user_id, acao, status_anterior, novo_status, executado_por, detalhes)
    VALUES (v_item.empresa_id, v_item.user_id, 'storage_retomada', 'falhou', 'pendente', auth.uid(),
        jsonb_build_object('fila_id', v_item.id, 'tentativas_anteriores', v_item.tentativas, 'ultimo_erro', v_item.ultimo_erro));

    UPDATE public.storage_limpeza_fila
    SET status = 'pendente',
        claim_token = NULL, claimed_by = NULL, lease_expires_at = NULL,
        tentativas = 0,
        ultimo_erro = NULL,
        processado_em = NULL,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_item.id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'LIMPEZA_RETOMADA',
        'mensagem', 'Item retornado ao estado pendente para nova tentativa de limpeza.',
        'fila_id', v_item.id,
        'storage_path', v_item.storage_path
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/registrar_limpeza_storage_executada.sql
-- ------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.registrar_limpeza_storage_executada(UUID, BOOLEAN, TEXT);
CREATE OR REPLACE FUNCTION public.registrar_limpeza_storage_executada(
    p_fila_id UUID, p_claim_token UUID, p_sucesso BOOLEAN, p_erro TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_item public.storage_limpeza_fila%ROWTYPE;
    v_novo_status VARCHAR(30);
BEGIN
    IF auth.uid() IS NULL OR p_claim_token IS NULL OR p_sucesso IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'CLAIM_INVALIDO', 'mensagem', 'Uma tentativa autenticada é obrigatória.');
    END IF;
    SELECT * INTO v_item FROM public.storage_limpeza_fila f WHERE f.id = p_fila_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ITEM_FILA_NAO_ENCONTRADO');
    END IF;
    IF v_item.claim_token IS DISTINCT FROM p_claim_token OR v_item.claimed_by IS DISTINCT FROM auth.uid() THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'CLAIM_INVALIDO', 'mensagem', 'Esta resposta não pertence à tentativa atual.');
    END IF;
    IF NOT (public.fn_usuario_e_gestor_empresa(v_item.empresa_id, auth.uid()) IS TRUE
        OR (v_item.user_id = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(v_item.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE)) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO');
    END IF;
    IF v_item.status = 'concluido' THEN
        RETURN jsonb_build_object('sucesso', true, 'codigo', 'JA_CONCLUIDO', 'status', 'concluido');
    END IF;
    IF v_item.status <> 'em_processamento' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ESTADO_INVALIDO', 'mensagem', 'O item não está nesta tentativa de processamento.');
    END IF;
    IF v_item.lease_expires_at IS NULL OR v_item.lease_expires_at <= clock_timestamp() THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'CLAIM_EXPIRADO', 'mensagem', 'O prazo desta tentativa expirou.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.veiculos_documentos vd WHERE vd.storage_path = v_item.storage_path) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ARQUIVO_VINCULADO');
    END IF;
    -- Confere metadados removidos pela API; não afirma acesso físico ao provedor S3.
    IF p_sucesso AND EXISTS (SELECT 1 FROM storage.objects o
        WHERE o.bucket_id = v_item.bucket_id AND o.name = v_item.storage_path) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'OBJETO_AINDA_PRESENTE', 'mensagem', 'A remoção ainda não foi confirmada no Storage.');
    END IF;
    v_novo_status := CASE WHEN p_sucesso THEN 'concluido'
        WHEN v_item.tentativas >= v_item.max_tentativas THEN 'falhou' ELSE 'pendente' END;
    UPDATE public.storage_limpeza_fila f
    SET status = v_novo_status, ultimo_erro = CASE WHEN p_sucesso THEN NULL ELSE LEFT(p_erro, 2000) END,
        processado_em = clock_timestamp(), lease_expires_at = NULL, updated_at = clock_timestamp()
    WHERE f.id = v_item.id;
    INSERT INTO public.auditoria_acessos
        (empresa_id, user_id, acao, status_anterior, novo_status, executado_por, detalhes)
    VALUES (v_item.empresa_id, v_item.user_id, 'storage_resultado', v_item.status, v_novo_status, auth.uid(),
        jsonb_build_object('fila_id', v_item.id, 'claim_token', p_claim_token, 'tentativa', v_item.tentativas,
            'erro', CASE WHEN p_sucesso THEN NULL ELSE LEFT(p_erro, 2000) END));
    RETURN jsonb_build_object('sucesso', true, 'codigo', 'LIMPEZA_REGISTRADA', 'status', v_novo_status);
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
--
-- GARANTIAS:
-- 1. Valida autorização do executor, existência de dados e condições de recusa
--    (inclusive conferência de revisão de veículo e completude) ANTES de qualquer mutação.
-- 2. Zero mutações parciais: em caso de recusa (ex: revisão desatualizada ou ausente),
--    nenhum registro é inserido em motoristas, empresa_membros ou solicitacoes_acesso.
-- 3. Idempotência e prevenção de duplicidades: retentativas após recusa ou chamadas
--    repetidas não duplicam registros na frota de motoristas.
-- 4. Separação explícita entre aprovação de vínculo e aprovação de veículo:
--    Aprovar o vínculo não aprova automaticamente o veículo a menos que
--    p_aprovar_veiculo = TRUE E a revisão esperada seja fornecida e conferida.
-- 5. ISOLAMENTO ESTRITO ENTRE EMPRESAS:
--    O veículo aprovado deve obrigatoriamente pertencer à mesma empresa da solicitação.
--    Veículos pertencentes a outras empresas nunca são aprovados nem têm seus dados
--    copiados para o cadastro do motorista nesta empresa.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.aprovar_solicitacao_motorista(
    p_solicitacao_id UUID,
    p_motorista_id UUID DEFAULT NULL,
    p_criar_novo_motorista BOOLEAN DEFAULT FALSE,
    p_nome_motorista TEXT DEFAULT NULL,
    p_telefone_motorista VARCHAR DEFAULT NULL,
    p_aprovar_veiculo BOOLEAN DEFAULT FALSE,
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
    v_motorista_existente_id UUID;
    v_motorista_final_id UUID;
    v_nome_final TEXT;
    v_telefone_final VARCHAR(30);
    v_modelo_final VARCHAR(100);
    v_placa_final VARCHAR(20);
    v_validacao_veic JSONB;
BEGIN
    -- --------------------------------------------------------------------------
    -- 1. LOCALIZAÇÃO E LOCK DA SOLICITAÇÃO (CONCORRÊNCIA SEGURA)
    -- --------------------------------------------------------------------------
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

    -- --------------------------------------------------------------------------
    -- 2. VALIDAÇÃO DE AUTORIZAÇÃO ANTES DE QUALQUER LEITURA OU RESPOSTA
    -- --------------------------------------------------------------------------
    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id, auth.uid()) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem aprovar solicitações.'
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 3. IDEMPOTÊNCIA AUTORIZADA (JÁ APROVADO PREVIAMENTE)
    -- --------------------------------------------------------------------------
    IF v_solicitacao.status = 'aprovado' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'JA_APROVADO',
            'mensagem', 'Esta solicitação já foi aprovada anteriormente.',
            'motorista_id', v_solicitacao.motorista_vinculado_id
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 4. PRÉ-VALIDAÇÃO DA OPÇÃO DE VÍNCULO (SEM MUTAÇÕES)
    -- --------------------------------------------------------------------------
    IF NOT p_criar_novo_motorista THEN
        -- Opção B: Vincular a motorista existente da frota
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
    END IF;

    -- --------------------------------------------------------------------------
    -- 5. PRÉ-VALIDAÇÃO DO VEÍCULO COM ISOLAMENTO ESTRITO ENTRE EMPRESAS
    -- --------------------------------------------------------------------------
    -- O veículo deve pertencer OBRIGATORIAMENTE à mesma empresa da solicitação
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE user_id = v_solicitacao.user_id
      AND empresa_id = v_solicitacao.empresa_id
    FOR UPDATE;

    -- Se não encontrou veículo nesta empresa, confere se há veículo cadastrado em OUTRA empresa
    IF v_veiculo.id IS NULL THEN
        IF EXISTS (
            SELECT 1
            FROM public.veiculos_motoristas
            WHERE user_id = v_solicitacao.user_id
              AND empresa_id != v_solicitacao.empresa_id
        ) THEN
            -- O condutor possui veículo declarado em outra empresa
            IF p_aprovar_veiculo THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'VEICULO_OUTRA_EMPRESA',
                    'mensagem', 'O condutor possui veículo cadastrado em outra empresa. A gestão não pode aprovar veículo de terceiros.'
                );
            END IF;
        END IF;
    END IF;

    IF p_aprovar_veiculo THEN
        IF v_veiculo.id IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'VEICULO_NAO_ENCONTRADO',
                'mensagem', 'O condutor não possui veículo declarado para esta empresa.'
            );
        END IF;

        -- Validação explícita de consistência de isolamento
        IF v_veiculo.empresa_id != v_solicitacao.empresa_id THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'VEICULO_OUTRA_EMPRESA',
                'mensagem', 'Divergência de isolamento: o veículo pertence a outra empresa.'
            );
        END IF;

        -- Exige revisão obrigatoriamente
        IF p_revisao_esperada_veiculo IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'REVISAO_OBRIGATORIA',
                'mensagem', 'A revisão esperada do veículo é obrigatória para aprovar o veículo.'
            );
        END IF;

        -- Confere se a revisão confere com a visualizada pelo gestor
        IF v_veiculo.revisao != p_revisao_esperada_veiculo THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'REVISAO_DESATUALIZADA',
                'mensagem', 'O veículo do condutor foi alterado durante a análise (revisão atual: ' || v_veiculo.revisao || ', esperada: ' || p_revisao_esperada_veiculo || '). Atualize e revise a versão atual antes de decidir.',
                'revisao_esperada', p_revisao_esperada_veiculo,
                'revisao_atual', v_veiculo.revisao
            );
        END IF;

        -- Valida completude (4 fotos distintas, CRLV e existência física no Storage)
        v_validacao_veic := public.fn_validar_completude_veiculo(v_veiculo.id);
        IF (v_validacao_veic->>'valido')::boolean != TRUE THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', v_validacao_veic->>'codigo',
                'mensagem', 'Veículo não atende aos requisitos para aprovação: ' || (v_validacao_veic->>'mensagem')
            );
        END IF;
    END IF;

    -- --------------------------------------------------------------------------
    -- 6. TODAS AS CONDIÇÕES FORAM APROVADAS -> EXECUTAR MUTAÇÕES ATÔMICAS
    -- --------------------------------------------------------------------------

    IF p_criar_novo_motorista THEN
        -- Busca dados do perfil do usuário para compor dados do motorista
        SELECT * INTO v_perfil FROM public.perfis_usuarios WHERE id = v_solicitacao.user_id;

        v_nome_final := COALESCE(NULLIF(TRIM(p_nome_motorista), ''), v_perfil.nome, 'Motorista Operacional');
        v_telefone_final := COALESCE(NULLIF(TRIM(p_telefone_motorista), ''), v_perfil.telefone, '(00) 00000-0000');
        v_modelo_final := CASE 
            WHEN v_veiculo.id IS NOT NULL THEN (v_veiculo.marca || ' ' || v_veiculo.modelo)
            ELSE 'Veículo Não Declarado'
        END;
        v_placa_final := CASE
            WHEN v_veiculo.id IS NOT NULL THEN v_veiculo.placa
            ELSE 'SEM-PLACA'
        END;

        -- Previne duplicidade de cadastro na retentativa: busca se já existe motorista desta empresa para este user_id
        SELECT id INTO v_motorista_existente_id
        FROM public.motoristas
        WHERE empresa_id = v_solicitacao.empresa_id
          AND user_id = v_solicitacao.user_id
        LIMIT 1;

        IF v_motorista_existente_id IS NOT NULL THEN
            UPDATE public.motoristas
            SET nome = v_nome_final,
                telefone = v_telefone_final,
                email = v_perfil.email,
                veiculo_modelo = v_modelo_final,
                veiculo_placa = v_placa_final,
                status = 'disponivel',
                ativo = TRUE,
                updated_at = timezone('utc'::text, now())
            WHERE id = v_motorista_existente_id;

            v_motorista_final_id := v_motorista_existente_id;
        ELSE
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
        END IF;

    ELSE
        -- Opção B: vincula o motorista selecionado
        UPDATE public.motoristas
        SET user_id = v_solicitacao.user_id,
            ativo = TRUE,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_motorista.id;

        v_motorista_final_id := v_motorista.id;
    END IF;

    -- --------------------------------------------------------------------------
    -- 7. ATUALIZAÇÃO DO VEÍCULO (SE APROVAÇÃO FOI EXPLICITAMENTE CONCEDIDA)
    -- --------------------------------------------------------------------------
    IF p_aprovar_veiculo AND v_veiculo.id IS NOT NULL AND v_veiculo.empresa_id = v_solicitacao.empresa_id THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'aprovado',
            revisao = revisao + 1,
            analisado_por = auth.uid(),
            analisado_em = timezone('utc'::text, now()),
            motivo_rejeicao = NULL,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id AND empresa_id = v_solicitacao.empresa_id;

        UPDATE public.veiculos_documentos
        SET status_analise = 'aprovado',
            analisado_por = auth.uid(),
            analisado_em = timezone('utc'::text, now()),
            motivo_rejeicao = NULL,
            updated_at = timezone('utc'::text, now())
        WHERE veiculo_id = v_veiculo.id AND empresa_id = v_solicitacao.empresa_id;
    END IF;

    -- --------------------------------------------------------------------------
    -- 8. ATUALIZA A SOLICITAÇÃO DE ACESSO
    -- --------------------------------------------------------------------------
    UPDATE public.solicitacoes_acesso
    SET status = 'aprovado',
        motorista_vinculado_id = v_motorista_final_id,
        motivo_decisao = 'Aprovado pela gestão',
        decidido_por = auth.uid(),
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

    -- --------------------------------------------------------------------------
    -- 9. INSERE OU ATUALIZA O MEMBRO EM EMPRESA_MEMBROS
    -- --------------------------------------------------------------------------
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

    -- --------------------------------------------------------------------------
    -- 10. AUDITORIA DA APROVAÇÃO
    -- --------------------------------------------------------------------------
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
            'veiculo_aprovado', p_aprovar_veiculo,
            'revisao_veiculo_analisada', p_revisao_esperada_veiculo
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'APROVADO_COM_SUCESSO',
        'mensagem', 'Motorista aprovado e vinculado com sucesso.',
        'motorista_id', v_motorista_final_id,
        'veiculo_aprovado', p_aprovar_veiculo
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id, auth.uid()) THEN
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id, auth.uid()) THEN
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id, auth.uid()) THEN
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
    IF NOT public.fn_usuario_e_admin_empresa(v_membro.empresa_id, auth.uid()) THEN
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
    v_empresas UUID[];
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

    -- Empresa explícita quando há mais de um vínculo; nunca transferir veículo.
    IF NULLIF(TRIM(p_dados->>'empresa_id'), '') IS NOT NULL THEN
        v_empresa_id := public.fn_safe_uuid(p_dados->>'empresa_id');
        IF v_empresa_id IS NULL THEN
            RETURN jsonb_build_object('sucesso', false, 'codigo', 'EMPRESA_INVALIDA', 'mensagem', 'Empresa inválida.');
        END IF;
    ELSE
        SELECT array_agg(DISTINCT candidato.empresa_id) INTO v_empresas FROM (
            SELECT em.empresa_id FROM public.empresa_membros em WHERE em.user_id = v_user_id AND em.status IN ('pendente','aprovado')
            UNION SELECT sa.empresa_id FROM public.solicitacoes_acesso sa WHERE sa.user_id = v_user_id AND sa.status = 'pendente'
        ) candidato;
        IF COALESCE(cardinality(v_empresas),0) > 1 THEN
            RETURN jsonb_build_object('sucesso', false, 'codigo', 'EMPRESA_OBRIGATORIA', 'mensagem', 'Selecione a empresa deste cadastro.');
        END IF;
        v_empresa_id := v_empresas[1];
    END IF;
    IF v_empresa_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'SEM_VINCULO_EMPRESA', 'mensagem', 'Solicite acesso a uma empresa antes de cadastrar o veículo.');
    END IF;

    -- Validação centralizada de autorização (bloqueia suspenso e sem vínculo ativo)
    IF (public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'mensagem'
        );
    END IF;


    -- Serializa também o primeiro cadastro, antes de existir uma linha do veículo.
    PERFORM pg_advisory_xact_lock(hashtextextended('veiculo:' || v_user_id::text, 0));
    SELECT * INTO v_veiculo_existente FROM public.veiculos_motoristas WHERE user_id = v_user_id FOR UPDATE;
    IF FOUND AND v_veiculo_existente.empresa_id IS DISTINCT FROM v_empresa_id THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'VEICULO_OUTRA_EMPRESA', 'mensagem', 'O veículo pertence a outra empresa. A transferência exige um processo separado; dados e evidências foram preservados.');
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
    WHERE public.veiculos_motoristas.empresa_id = EXCLUDED.empresa_id
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
--
-- PROTOCOLO DE RESERVA E COORDENAÇÃO DE CICLO DE VIDA DO STORAGE:
-- 1. Disputa atômica do recurso de coordenação: adquire lock FOR UPDATE na linha
--    correspondente em public.storage_limpeza_fila para o storage_path informado.
-- 2. Exige que o objeto esteja no estado 'reservado' (criado via reservar_upload_evidencia).
-- 3. Bloqueia terminantemente vinculação se o estado for 'pendente', 'em_processamento',
--    'concluido' (ARQUIVO_EM_LIMPEZA), 'falhou' (ARQUIVO_DESCARTADO) ou 'vinculado' (ARQUIVO_JA_VINCULADO).
-- 4. Ao vincular com sucesso, transiciona o estado da reserva para 'vinculado'.
-- 5. Na substituição (novo CRLV ou foto para mesmo ângulo), desvincula o arquivo anterior
--    e transiciona a linha antiga da fila para 'pendente' para permitir exclusão física.
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
    v_item_fila RECORD;
    v_fila_substituicao_id UUID := NULL;
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

    -- --------------------------------------------------------------------------
    -- 4b. PROTOCOLO DE RESERVA E COORDENAÇÃO ATÔMICA (MUTEX NA FILA DE LIMPEZA)
    -- --------------------------------------------------------------------------
    -- Adquire lock FOR UPDATE na linha correspondente ao storage_path na fila
    SELECT * INTO v_item_fila
    FROM public.storage_limpeza_fila
    WHERE storage_path = TRIM(p_storage_path)
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_NAO_RESERVADO',
            'mensagem', 'O arquivo não possui reserva prévia válida no sistema de armazenamento.'
        );
    END IF;

    -- Bloqueia reutilização de caminho com limpeza falha (Item 2)
    IF v_item_fila.status = 'falhou' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_DESCARTADO',
            'mensagem', 'Este caminho foi descartado com falha de limpeza e não pode ser reutilizado.'
        );
    END IF;

    -- Bloqueia vinculação se o arquivo estiver em limpeza ou já concluído
    IF v_item_fila.status IN ('pendente', 'em_processamento', 'concluido') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_EM_LIMPEZA',
            'mensagem', 'Este objeto do Storage está em processo de limpeza ou já foi descartado e não pode ser vinculado.'
        );
    END IF;

    -- Bloqueia vinculação se o arquivo já foi vinculado a outro documento ativo
    IF v_item_fila.status = 'vinculado' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_JA_VINCULADO',
            'mensagem', 'Este caminho de arquivo já se encontra vinculado a um documento ativo.'
        );
    END IF;

    -- Exige estritamente o status 'reservado'
    IF v_item_fila.status != 'reservado' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'STATUS_RESERVA_INVALIDO',
            'mensagem', 'O status da reserva (' || v_item_fila.status || ') não autoriza vinculação.'
        );
    END IF;

    -- Previne reutilização ou colisão na tabela de documentos ativos
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
        -- Localiza foto anterior do mesmo ângulo para desvinculação e limpeza
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

            -- Se o caminho for diferente, enfileira o antigo para limpeza segura
            IF v_old_storage_path IS NOT NULL AND v_old_storage_path != TRIM(p_storage_path) THEN
                UPDATE public.storage_limpeza_fila
                SET status = 'pendente',
                    motivo = 'substituicao_foto_' || p_angulo_foto,
                    tentativas = 0,
                    ultimo_erro = NULL,
                    autorizado_em = timezone('utc'::text, now()),
                    updated_at = timezone('utc'::text, now())
                WHERE storage_path = v_old_storage_path
                RETURNING id INTO v_fila_substituicao_id;

                IF NOT FOUND THEN
                    INSERT INTO public.storage_limpeza_fila (
                        bucket_id,
                        storage_path,
                        empresa_id,
                        user_id,
                        motivo,
                        status
                    ) VALUES (
                        'veiculos-documentos',
                        v_old_storage_path,
                        v_veiculo.empresa_id,
                        v_user_id,
                        'substituicao_foto_' || p_angulo_foto,
                        'pendente'
                    )
                    ON CONFLICT (storage_path) DO UPDATE SET
                        status = 'pendente',
                        motivo = 'substituicao_foto_' || p_angulo_foto,
                        updated_at = timezone('utc'::text, now())
                    RETURNING id INTO v_fila_substituicao_id;
                END IF;
            END IF;
        END IF;

    ELSIF p_tipo_documento = 'crlv' THEN
        -- Localiza CRLV anterior para desvinculação e limpeza
        SELECT storage_path INTO v_old_storage_path
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'crlv';

        IF FOUND THEN
            DELETE FROM public.veiculos_documentos
            WHERE veiculo_id = v_veiculo.id
              AND tipo_documento = 'crlv';

            -- Se o caminho for diferente, enfileira o antigo para limpeza segura
            IF v_old_storage_path IS NOT NULL AND v_old_storage_path != TRIM(p_storage_path) THEN
                UPDATE public.storage_limpeza_fila
                SET status = 'pendente',
                    motivo = 'substituicao_crlv',
                    tentativas = 0,
                    ultimo_erro = NULL,
                    autorizado_em = timezone('utc'::text, now()),
                    updated_at = timezone('utc'::text, now())
                WHERE storage_path = v_old_storage_path
                RETURNING id INTO v_fila_substituicao_id;

                IF NOT FOUND THEN
                    INSERT INTO public.storage_limpeza_fila (
                        bucket_id,
                        storage_path,
                        empresa_id,
                        user_id,
                        motivo,
                        status
                    ) VALUES (
                        'veiculos-documentos',
                        v_old_storage_path,
                        v_veiculo.empresa_id,
                        v_user_id,
                        'substituicao_crlv',
                        'pendente'
                    )
                    ON CONFLICT (storage_path) DO UPDATE SET
                        status = 'pendente',
                        motivo = 'substituicao_crlv',
                        updated_at = timezone('utc'::text, now())
                    RETURNING id INTO v_fila_substituicao_id;
                END IF;
            END IF;
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

    -- 9. Insere novo registro de metadados em veiculos_documentos
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

    -- 10. Atualiza o estado da reserva para 'vinculado'
    UPDATE public.storage_limpeza_fila
    SET status = 'vinculado',
        updated_at = timezone('utc'::text, now())
    WHERE id = v_item_fila.id;

    -- 11. Atualiza revisão e reverte status para pendente caso estivesse aprovado
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
        'revisao', v_veiculo.revisao + 1,
        'arquivo_substituido_path', v_old_storage_path,
        'limpeza_fila_id', v_fila_substituicao_id
    );
END;
$$;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/remover_documento_veiculo.sql
-- ------------------------------------------------------------------------------

-- ==============================================================================
-- FUNÇÃO SQL: remover_documento_veiculo.sql
-- Desvinculação autorizada e segura de documentos veiculares.
--
-- PROTOCOLO DE COORDENAÇÃO DE STORAGE:
-- 1. Remove os metadados da tabela veiculos_documentos.
-- 2. Transiciona atomicamente a linha em storage_limpeza_fila para o status 'pendente',
--    autorizando formalmente o DELETE físico no Storage.
-- 3. Se o veículo estiver 'aprovado', a remoção da evidência INVALIDA imediatamente
--    a aprovação, revertendo para 'pendente' e incrementando a revisão do veículo.
-- 4. Retorna fila_id e storage_path para que o cliente realize o DELETE físico
--    e confirme o sucesso via RPC registrar_limpeza_storage_executada.
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
    v_fila_id UUID;
    v_item_fila public.storage_limpeza_fila%ROWTYPE;
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
    ELSIF public.fn_usuario_e_gestor_empresa(v_doc.empresa_id, auth.uid()) THEN
        v_eh_gestor := TRUE;
    ELSE
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Você não possui autorização para remover esta evidência.'
        );
    END IF;

    -- Reconfere após adquirir o lock do veículo: outra remoção pode ter ocorrido enquanto aguardávamos.
    SELECT * INTO v_doc FROM public.veiculos_documentos vd WHERE vd.id = p_documento_id AND vd.veiculo_id = v_veiculo.id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DOCUMENTO_NAO_ENCONTRADO');
    END IF;
    SELECT * INTO v_item_fila FROM public.storage_limpeza_fila f WHERE f.storage_path = v_doc.storage_path FOR UPDATE;
    IF NOT FOUND OR v_item_fila.status IS DISTINCT FROM 'vinculado'
        OR v_item_fila.empresa_id IS DISTINCT FROM v_doc.empresa_id OR v_item_fila.user_id IS DISTINCT FROM v_doc.user_id THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'CICLO_EVIDENCIA_INCONSISTENTE', 'mensagem', 'O vínculo da evidência precisa ser reconciliado antes da remoção.');
    END IF;
    DELETE FROM public.veiculos_documentos vd WHERE vd.id = v_doc.id;
    UPDATE public.storage_limpeza_fila f
    SET status = 'pendente', motivo = 'remocao_documento_veiculo', tentativas = 0, ultimo_erro = NULL,
        claim_token = NULL, claimed_by = NULL, lease_expires_at = NULL,
        autorizado_em = clock_timestamp(), updated_at = clock_timestamp()
    WHERE f.id = v_item_fila.id RETURNING f.id INTO v_fila_id;

    -- 6. Se o veículo já estava aprovado, a remoção INVALIDA a aprovação
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

    -- 7. Auditoria da desvinculação
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
            'eh_gestor', v_eh_gestor,
            'limpeza_fila_id', v_fila_id
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DOCUMENTO_REMOVIDO',
        'mensagem', 'Documento desvinculado com sucesso e enfileirado para limpeza física.',
        'storage_path', v_doc.storage_path,
        'fila_id', v_fila_id,
        'veiculo_id', v_veiculo.id,
        'revisao', v_veiculo.revisao + 1
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
    IF NOT public.fn_usuario_e_gestor_empresa(v_veiculo.empresa_id, auth.uid()) THEN
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
    IF NOT public.fn_usuario_e_gestor_empresa(v_empresa_id, auth.uid()) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores autorizados desta empresa podem despachar rotas.'
        );
    END IF;

    -- 3. Cálculo de hash do payload para conferência de consistência
    v_payload_hash := encode(sha256(convert_to(p_dados::text, 'UTF8')), 'hex');

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
        ordem_paradas_json,
        metricas_fonte,
        metricas_atualizadas_em
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
        v_ordem_json,
        CASE WHEN p_dados->>'metricas_fonte'='mapbox_directions_planejamento' AND v_distancia_otim>0 AND v_tempo_otim>0 THEN 'mapbox_directions_planejamento' END,
        CASE WHEN p_dados->>'metricas_fonte'='mapbox_directions_planejamento' AND v_distancia_otim>0 AND v_tempo_otim>0 THEN now() END
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
    WHERE id = p_rota_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ROTA_NAO_ENCONTRADA',
            'mensagem', 'Rota planejada não encontrada.'
        );
    END IF;

    -- Descobre o motorista_id do usuário atual
    SELECT m.id INTO v_motorista_id
    FROM public.motoristas m
    WHERE m.id = v_rota.motorista_id
      AND m.empresa_id = v_rota.empresa_id AND m.user_id = v_user_id;

    -- Validação de titularidade: deve ser o motorista atribuído ou gestor da empresa
    IF public.fn_usuario_pode_operar_motorista(v_rota.empresa_id, v_rota.motorista_id) IS NOT TRUE THEN
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
-- MÓDULO: supabase/functions-sql/reordenar_paradas_rota.sql
-- ------------------------------------------------------------------------------

ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS metricas_fonte text;
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS metricas_atualizadas_em timestamptz;
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS configuracao_navegacao jsonb NOT NULL DEFAULT '{}'::jsonb;
-- Reorder only unfinished stops; preserve completed stops and reject stale edits.
CREATE OR REPLACE FUNCTION public.reordenar_paradas_rota(
    p_rota_id uuid, p_entrega_ids uuid[], p_ordem_esperada uuid[], p_configuracao jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_rota public.rotas_planejadas%ROWTYPE;
    v_current uuid[];
    v_slots integer[];
    v_metricas jsonb;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Entre novamente na sua conta.');
    END IF;
    SELECT * INTO v_rota FROM public.rotas_planejadas WHERE id=p_rota_id FOR UPDATE;
    IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(v_rota.empresa_id,v_rota.motorista_id) IS NOT TRUE THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso negado à rota.');
    END IF;
    IF v_rota.status NOT IN ('planejada','em_execucao') THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Esta rota já foi finalizada.');
    END IF;
    IF p_configuracao IS NOT NULL THEN
      IF jsonb_typeof(p_configuracao) <> 'object'
         OR jsonb_typeof(p_configuracao->'latitude') IS DISTINCT FROM 'number'
         OR jsonb_typeof(p_configuracao->'longitude') IS DISTINCT FROM 'number'
         OR jsonb_typeof(p_configuracao->'retornar_ao_inicio') IS DISTINCT FROM 'boolean'
         OR (p_configuracao->>'latitude')::numeric NOT BETWEEN -90 AND 90
         OR (p_configuracao->>'longitude')::numeric NOT BETWEEN -180 AND 180
         OR COALESCE(p_configuracao->>'metodo','') NOT IN ('manual','vizinho_proximo','circuito_2opt') THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Origem de navegação inválida. Atualize a posição do motorista.');
      END IF;
    END IF;
    v_metricas := p_configuracao->'metricas';
    IF v_metricas IS NOT NULL AND (
      jsonb_typeof(v_metricas) <> 'object'
      OR jsonb_typeof(v_metricas->'distancia_km') IS DISTINCT FROM 'number'
      OR jsonb_typeof(v_metricas->'tempo_minutos') IS DISTINCT FROM 'number'
      OR (v_metricas->>'distancia_km')::numeric NOT BETWEEN 0.01 AND 999999
      OR (v_metricas->>'tempo_minutos')::numeric NOT BETWEEN 0.01 AND 999999
      OR v_metricas->>'fonte' IS DISTINCT FROM 'mapbox_directions_restante'
    ) THEN
      RETURN jsonb_build_object('sucesso',false,'mensagem','Métricas viárias inválidas. Recalcule a rota.');
    END IF;
    PERFORM id FROM public.entregas WHERE rota_id=p_rota_id ORDER BY id FOR UPDATE;
    SELECT COALESCE(array_agg(id ORDER BY ordem_na_rota NULLS LAST,id),'{}'::uuid[]),
           COALESCE(array_agg(pos ORDER BY ordem_na_rota NULLS LAST,id),'{}'::integer[])
    INTO v_current,v_slots
    FROM (
      SELECT id,status,ordem_na_rota,row_number() OVER (ORDER BY ordem_na_rota NULLS LAST,id)::integer AS pos
      FROM public.entregas WHERE rota_id=p_rota_id AND empresa_id=v_rota.empresa_id
    ) x WHERE status NOT IN ('entregue','tentativa_falha','cancelada');
    IF p_ordem_esperada IS DISTINCT FROM v_current THEN
        RETURN jsonb_build_object('sucesso',false,'codigo','ORDEM_DESATUALIZADA','mensagem','A rota mudou. Atualize e organize novamente.');
    END IF;
    IF p_entrega_ids IS NULL OR cardinality(p_entrega_ids)>500
       OR (SELECT array_agg(id ORDER BY id) FROM unnest(p_entrega_ids) id)
          IS DISTINCT FROM (SELECT array_agg(id ORDER BY id) FROM unnest(v_current) id) THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Informe todas as paradas pendentes, sem duplicar ou adicionar paradas.');
    END IF;
    UPDATE public.entregas e SET ordem_na_rota=v_slots[requested.pos::integer],updated_at=now()
    FROM unnest(p_entrega_ids) WITH ORDINALITY AS requested(id,pos)
    WHERE e.id=requested.id AND e.rota_id=p_rota_id AND e.empresa_id=v_rota.empresa_id;
    UPDATE public.rotas_planejadas SET
        metricas_fonte=CASE WHEN v_metricas IS NOT NULL THEN 'mapbox_directions_restante' END,
        metricas_atualizadas_em=CASE WHEN v_metricas IS NOT NULL THEN now() END,
        distancia_otimizada_km=COALESCE((v_metricas->>'distancia_km')::numeric,distancia_otimizada_km),
        tempo_otimizado_minutos=COALESCE((v_metricas->>'tempo_minutos')::numeric,tempo_otimizado_minutos),
        configuracao_navegacao=COALESCE(p_configuracao,configuracao_navegacao), ordem_paradas_json=(
        SELECT COALESCE(jsonb_agg(to_jsonb(e) || jsonb_build_object(
            'sequencia',e.ordem_na_rota,'destinatario',e.destinatario_nome,
            'nome_local',COALESCE(to_jsonb(c)->>'nome_identificador',e.unidade_apartamento),
            'endereco_formatado',COALESCE(to_jsonb(e)->>'endereco',previous.value->>'endereco_formatado',to_jsonb(c)->>'endereco_completo'),
            'coordenadas',jsonb_build_object('lat',COALESCE(NULLIF(to_jsonb(e)->'latitude','null'::jsonb),NULLIF(to_jsonb(c)->'latitude','null'::jsonb),previous.value->'coordenadas'->'lat'),'lng',COALESCE(NULLIF(to_jsonb(e)->'longitude','null'::jsonb),NULLIF(to_jsonb(c)->'longitude','null'::jsonb),previous.value->'coordenadas'->'lng'))
        ) ORDER BY e.ordem_na_rota,e.id),'[]'::jsonb)
        FROM public.entregas e LEFT JOIN public.clientes_enderecos c ON c.id=e.cliente_endereco_id AND c.empresa_id=e.empresa_id
        LEFT JOIN LATERAL (
          SELECT value FROM jsonb_array_elements(v_rota.ordem_paradas_json) value
          WHERE value->>'id'=e.id::text OR value->>'cliente_endereco_id'=e.cliente_endereco_id::text LIMIT 1
        ) previous ON true
        WHERE e.rota_id=p_rota_id AND e.empresa_id=v_rota.empresa_id
    ) WHERE id=p_rota_id;
    RETURN jsonb_build_object('sucesso',true,'codigo','ORDEM_ATUALIZADA','mensagem','Ordem salva. O mapa foi atualizado.');
END;
$$;
REVOKE ALL ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[],jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[],jsonb) TO authenticated;
-- Keep the existing three-argument API for manual reorder clients.
CREATE OR REPLACE FUNCTION public.reordenar_paradas_rota(p_rota_id uuid,p_entrega_ids uuid[],p_ordem_esperada uuid[])
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=public AS $compat$
SELECT public.reordenar_paradas_rota(p_rota_id,p_entrega_ids,p_ordem_esperada,NULL::jsonb);
$compat$;
REVOKE ALL ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reordenar_paradas_rota(uuid,uuid[],uuid[]) TO authenticated;

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
    WHERE id = p_rota_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ROTA_NAO_ENCONTRADA',
            'mensagem', 'Rota planejada não encontrada.'
        );
    END IF;

    SELECT m.id INTO v_motorista_id
    FROM public.motoristas m
    WHERE m.id = v_rota.motorista_id
      AND m.empresa_id = v_rota.empresa_id AND m.user_id = v_user_id;

    IF public.fn_usuario_pode_operar_motorista(v_rota.empresa_id, v_rota.motorista_id) IS NOT TRUE THEN
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
    WHERE id = p_entrega_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ENTREGA_NAO_ENCONTRADA',
            'mensagem', 'Entrega não encontrada.'
        );
    END IF;

    -- Valida permissão do motorista ou gestor
    SELECT m.id INTO v_motorista_id
    FROM public.motoristas m
    WHERE m.id = v_entrega.motorista_id
      AND m.empresa_id = v_entrega.empresa_id AND m.user_id = v_user_id;

    IF public.fn_usuario_pode_operar_motorista(v_entrega.empresa_id, v_entrega.motorista_id) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas o motorista atribuído ou gestor da empresa podem registrar a baixa desta entrega.'
        );
    END IF;

    -- O lock da entrega torna reenvios idempotentes, inclusive após timeout.
    IF v_entrega.status IN ('entregue', 'tentativa_falha', 'cancelada') THEN
        IF v_entrega.status = (CASE WHEN p_sucesso THEN 'entregue' ELSE 'tentativa_falha' END) THEN
            RETURN jsonb_build_object('sucesso', TRUE, 'codigo', 'ENTREGA_JA_REGISTRADA',
                'entrega_id', v_entrega.id, 'status', v_entrega.status);
        END IF;
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'TRANSICAO_INVALIDA',
            'mensagem', 'Esta tarefa já foi finalizada. Atualize a rota.');
    END IF;

    IF p_sucesso IS NULL OR (NOT p_sucesso AND NULLIF(trim(p_motivo_falha), '') IS NULL) THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MOTIVO_OBRIGATORIO',
            'mensagem', 'Informe o motivo da tentativa sem sucesso.');
    END IF;

    IF p_data_hora_chegada IS NOT NULL AND p_data_hora_conclusao IS NOT NULL
       AND p_data_hora_chegada > p_data_hora_conclusao THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'HORARIO_INVALIDO',
            'mensagem', 'O horário de conclusão deve ser posterior à chegada. Confira o relógio do aparelho.');
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
-- MÓDULO: supabase/functions-sql/concluir_atendimento_entrega.sql
-- ------------------------------------------------------------------------------

-- Arrival is explicit; receipts are immutable and scoped to the assigned operation.
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS chegada_em timestamptz;
CREATE TABLE IF NOT EXISTS public.entrega_comprovantes (
 entrega_id uuid PRIMARY KEY REFERENCES public.entregas(id),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 registrado_por uuid NOT NULL REFERENCES auth.users(id),
 recebedor_tipo text NOT NULL,
 recebedor_nome text CHECK (length(recebedor_nome)<=160),
 observacao text CHECK (length(observacao)<=1000),
 foto_path text,
 assinatura_path text,
 chegada_em timestamptz NOT NULL,
 concluida_em timestamptz NOT NULL,
 duracao_segundos integer NOT NULL CHECK (duracao_segundos>=0),
 latitude double precision CHECK (latitude BETWEEN -90 AND 90),
 longitude double precision CHECK (longitude BETWEEN -180 AND 180),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS entrega_comprovantes_empresa_idx ON public.entrega_comprovantes(empresa_id);
ALTER TABLE public.entrega_comprovantes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.entrega_comprovantes FROM anon,authenticated;
GRANT SELECT ON public.entrega_comprovantes TO authenticated;
DROP POLICY IF EXISTS comprovante_operacao_select ON public.entrega_comprovantes;
CREATE POLICY comprovante_operacao_select ON public.entrega_comprovantes FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=entrega_id AND e.empresa_id=entrega_comprovantes.empresa_id
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id))
);
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('entregas-comprovantes','entregas-comprovantes',false,10485760,ARRAY['image/jpeg','image/png']) ON CONFLICT(id) DO NOTHING;
DROP POLICY IF EXISTS comprovante_operacao_upload ON storage.objects;
CREATE POLICY comprovante_operacao_upload ON storage.objects FOR INSERT TO authenticated WITH CHECK (
 bucket_id='entregas-comprovantes' AND split_part(name,'/',2)=(select auth.uid())::text
 AND EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=public.fn_safe_uuid(split_part(name,'/',3))
 AND e.empresa_id=public.fn_safe_uuid(split_part(name,'/',1)) AND e.status NOT IN ('entregue','tentativa_falha','cancelada')
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id))
);
DROP POLICY IF EXISTS comprovante_operacao_download ON storage.objects;
CREATE POLICY comprovante_operacao_download ON storage.objects FOR SELECT TO authenticated USING (
 bucket_id='entregas-comprovantes' AND EXISTS(SELECT 1 FROM public.entregas e
 WHERE e.id=public.fn_safe_uuid(split_part(name,'/',3)) AND e.empresa_id=public.fn_safe_uuid(split_part(name,'/',1))
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id))
);

CREATE OR REPLACE FUNCTION public.iniciar_atendimento_entrega(p_entrega_id uuid,p_chegada_em timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE e public.entregas%ROWTYPE;
BEGIN
 SELECT * INTO e FROM public.entregas WHERE id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso negado à tarefa.'); END IF;
 IF e.status IN ('entregue','tentativa_falha','cancelada') THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Esta tarefa já foi finalizada.'); END IF;
 IF p_chegada_em IS NULL OR p_chegada_em>now()+interval '5 minutes' THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Confira o relógio do aparelho.'); END IF;
 UPDATE public.entregas SET chegada_em=COALESCE(chegada_em,p_chegada_em) WHERE id=e.id RETURNING * INTO e;
 RETURN jsonb_build_object('sucesso',true,'chegada_em',e.chegada_em);
END $$;
REVOKE ALL ON FUNCTION public.iniciar_atendimento_entrega(uuid,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.iniciar_atendimento_entrega(uuid,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.concluir_atendimento_entrega(
 p_entrega_id uuid,p_sucesso boolean,p_chegada_em timestamptz,p_conclusao_em timestamptz,p_comprovante jsonb DEFAULT '{}'::jsonb,p_motivo text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE e public.entregas%ROWTYPE; result jsonb; arrival timestamptz; finish timestamptz; proof_path text; seconds integer;
BEGIN
 SELECT * INTO e FROM public.entregas WHERE id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso negado à tarefa.'); END IF;
 IF p_sucesso IS NULL THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Resultado inválido.'); END IF;
 -- Same outcome retry never alters an immutable receipt or the statistics.
 IF e.status IN ('entregue','tentativa_falha','cancelada') THEN
 RETURN public.registrar_conclusao_entrega(e.id,p_sucesso,p_motivo); END IF;
 arrival:=COALESCE(e.chegada_em,p_chegada_em); finish:=COALESCE(p_conclusao_em,now());
 IF arrival IS NULL OR arrival>finish OR finish>now()+interval '5 minutes' THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Marque sua chegada e confira o horário do aparelho.'); END IF;
 IF p_sucesso AND (jsonb_typeof(p_comprovante) IS DISTINCT FROM 'object' OR COALESCE(p_comprovante->>'recebedor_tipo','') NOT IN
 ('sindico','zelador','faxineiro','porteiro','vizinho','proprio_cliente','familiar','recepcao','funcionario','responsavel_coleta','outro')) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Informe quem recebeu ou entregou o pacote.'); END IF;
 IF length(COALESCE(p_comprovante->>'recebedor_nome',''))>160 OR length(COALESCE(p_comprovante->>'observacao',''))>1000 THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Nome ou observação excede o limite.'); END IF;
 FOREACH proof_path IN ARRAY ARRAY[NULLIF(p_comprovante->>'foto_path',''),NULLIF(p_comprovante->>'assinatura_path','')] LOOP
 IF proof_path IS NOT NULL AND (split_part(proof_path,'/',1)<>e.empresa_id::text OR split_part(proof_path,'/',2)<>auth.uid()::text OR split_part(proof_path,'/',3)<>e.id::text
 OR NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='entregas-comprovantes' AND o.name=proof_path)) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Comprovante não enviado ou sem autorização.'); END IF;
 END LOOP;
 seconds:=GREATEST(0,floor(extract(epoch FROM (finish-arrival)))::integer);
 result:=public.registrar_conclusao_entrega(e.id,p_sucesso,p_motivo,GREATEST(0.01,seconds/60.0),0,arrival,finish);
 IF result->>'sucesso' IS DISTINCT FROM 'true' THEN RETURN result; END IF;
 UPDATE public.entregas SET chegada_em=arrival WHERE id=e.id;
 INSERT INTO public.entrega_comprovantes(entrega_id,empresa_id,registrado_por,recebedor_tipo,recebedor_nome,observacao,foto_path,assinatura_path,chegada_em,concluida_em,duracao_segundos,latitude,longitude)
 VALUES(e.id,e.empresa_id,auth.uid(),CASE WHEN p_sucesso THEN p_comprovante->>'recebedor_tipo' ELSE 'tentativa_falha' END,
 NULLIF(trim(p_comprovante->>'recebedor_nome'),''),NULLIF(trim(p_comprovante->>'observacao'),''),NULLIF(p_comprovante->>'foto_path',''),NULLIF(p_comprovante->>'assinatura_path',''),arrival,finish,seconds,
 (p_comprovante->>'latitude')::double precision,(p_comprovante->>'longitude')::double precision);
 RETURN result||jsonb_build_object('duracao_segundos',seconds);
END $$;
REVOKE ALL ON FUNCTION public.concluir_atendimento_entrega(uuid,boolean,timestamptz,timestamptz,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.concluir_atendimento_entrega(uuid,boolean,timestamptz,timestamptz,jsonb,text) TO authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/atualizar_localizacao_motorista.sql
-- ------------------------------------------------------------------------------

ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS latitude_atual numeric(10,7);
ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS longitude_atual numeric(10,7);
ALTER TABLE public.motoristas ADD COLUMN IF NOT EXISTS localizacao_atualizada_em timestamptz;
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS distancia_registrada_km numeric(12,3);
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS distancia_registrada_em timestamptz;
CREATE OR REPLACE FUNCTION public.atualizar_localizacao_motorista(p_rota_id uuid,p_latitude double precision,p_longitude double precision,p_distancia_km numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.rotas_planejadas%ROWTYPE;
BEGIN
 SELECT * INTO r FROM public.rotas_planejadas WHERE id=p_rota_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR r.status<>'em_execucao' OR public.fn_usuario_pode_operar_motorista(r.empresa_id,r.motorista_id) IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM public.motoristas m WHERE m.id=r.motorista_id AND m.empresa_id=r.empresa_id AND m.user_id=auth.uid()) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Localização permitida somente ao motorista da rota ativa.'); END IF;
 IF p_latitude IS NULL OR p_longitude IS NULL OR p_distancia_km IS NULL OR NOT(p_latitude BETWEEN -90 AND 90) OR NOT(p_longitude BETWEEN -180 AND 180) OR NOT(p_distancia_km BETWEEN 0 AND 100000) THEN
 RETURN jsonb_build_object('sucesso',false,'mensagem','Localização inválida.'); END IF;
 UPDATE public.motoristas SET latitude_atual=p_latitude,longitude_atual=p_longitude,localizacao_atualizada_em=now() WHERE id=r.motorista_id;
 UPDATE public.rotas_planejadas SET distancia_registrada_km=GREATEST(COALESCE(distancia_registrada_km,0),p_distancia_km),distancia_registrada_em=now() WHERE id=r.id;
 RETURN jsonb_build_object('sucesso',true);
END $$;
REVOKE ALL ON FUNCTION public.atualizar_localizacao_motorista(uuid,double precision,double precision,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.atualizar_localizacao_motorista(uuid,double precision,double precision,numeric) TO authenticated;

-- Restrictive policy also constrains permissive policies left by older installations.
ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Localizacao restrita a gestao ou proprio condutor" ON public.motoristas;
CREATE POLICY "Localizacao restrita a gestao ou proprio condutor" ON public.motoristas AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id,auth.uid()) OR (user_id=auth.uid() AND public.fn_usuario_pode_operar_motorista(empresa_id,id)));
REVOKE ALL ON public.motoristas FROM anon;
REVOKE INSERT,UPDATE,DELETE ON public.motoristas FROM authenticated;
-- Membership approval stays behind the existing audited management RPCs.
REVOKE INSERT,UPDATE,DELETE ON public.empresa_membros FROM anon,authenticated;
CREATE OR REPLACE FUNCTION public.atualizar_meu_nome_motorista(p_nome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid:=auth.uid(); n text:=btrim(p_nome);
BEGIN
 IF uid IS NULL OR n IS NULL OR length(n)<2 OR length(n)>100 THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Informe um nome entre 2 e 100 caracteres.'); END IF;
 UPDATE public.motoristas m SET nome=n WHERE m.user_id=uid AND public.fn_usuario_pode_operar_motorista(m.empresa_id,m.id);
 IF NOT FOUND THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Motorista autorizado não encontrado.'); END IF;
 UPDATE public.perfis_usuarios SET nome=n WHERE id=uid;
 RETURN jsonb_build_object('sucesso',true);
END $$;
REVOKE ALL ON FUNCTION public.atualizar_meu_nome_motorista(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.atualizar_meu_nome_motorista(text) TO authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/enviar_servicos_motorista.sql
-- ------------------------------------------------------------------------------

-- Atomic dispatch: collections join the active route; deliveries/other tasks form a new route.
CREATE TABLE IF NOT EXISTS public.operacoes_envio_motorista (
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 chave varchar(80) NOT NULL,
 payload_hash text NOT NULL,
 resultado jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(empresa_id,chave)
);
ALTER TABLE public.operacoes_envio_motorista ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.operacoes_envio_motorista FROM PUBLIC,anon,authenticated;
-- Results are accessed through the authenticated management RPC, never by direct writes.
CREATE INDEX IF NOT EXISTS idx_rotas_motorista_ativas ON public.rotas_planejadas(empresa_id,motorista_id) WHERE status='em_execucao';
CREATE OR REPLACE FUNCTION public.enviar_servicos_motorista(p_dados jsonb,p_plano_coletas jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $function$
DECLARE
 company uuid := (p_dados->>'empresa_id')::uuid;
 driver uuid := (p_dados->>'motorista_id')::uuid;
 request_key text := btrim(p_dados->>'idempotency_key');
 request_hash text;
 previous public.operacoes_envio_motorista%ROWTYPE;
 active_route public.rotas_planejadas%ROWTYPE;
 driver_row public.motoristas%ROWTYPE;
 collections jsonb; regular jsonb; new_payload jsonb;
 result jsonb; new_result jsonb; route_count integer; count_new integer:=0;
 expected_keys text[]; requested_keys text[]; pinned uuid[]; new_ids jsonb:='{}';
 item record; key_item record; delivery_id uuid; slot integer:=0; gps jsonb; metric jsonb;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(company,auth.uid()) IS NOT TRUE THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','ACESSO_NEGADO','mensagem','Apenas a gestão da empresa pode enviar serviços.');
 END IF;
 IF company IS NULL OR driver IS NULL OR request_key IS NULL OR length(request_key) NOT BETWEEN 1 AND 80
 OR jsonb_typeof(p_dados->'paradas') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'paradas') NOT BETWEEN 1 AND 500 THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','DADOS_INVALIDOS','mensagem','Informe motorista, chave de envio e de 1 a 500 paradas.');
 END IF;
 -- Same request is serialized before checking its journal. Hash excludes volatile route/GPS metrics.
 PERFORM pg_advisory_xact_lock(hashtextextended(company::text||':envio:'||request_key,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(company::text||':'||driver::text,0));
 request_hash:=encode(sha256(convert_to(jsonb_build_object('motorista_id',driver,'paradas',p_dados->'paradas')::text,'UTF8')),'hex');
 SELECT * INTO previous FROM public.operacoes_envio_motorista WHERE empresa_id=company AND chave=request_key;
 IF FOUND THEN
  IF previous.payload_hash<>request_hash THEN RETURN jsonb_build_object('sucesso',false,'codigo','CONFLITO_IDEMPOTENCIA','mensagem','Este envio já foi processado com outros serviços. Atualize o painel.'); END IF;
  RETURN previous.resultado||jsonb_build_object('idempotente',true);
 END IF;
 SELECT * INTO driver_row FROM public.motoristas WHERE id=driver AND empresa_id=company AND ativo;
 IF NOT FOUND THEN RAISE EXCEPTION 'Motorista não encontrado ou inativo na empresa.'; END IF;
 SELECT COALESCE(jsonb_agg(value ORDER BY ord) FILTER(WHERE value->>'tipo_tarefa'='coleta'),'[]'),
        COALESCE(jsonb_agg(value ORDER BY ord) FILTER(WHERE COALESCE(value->>'tipo_tarefa','entrega')<>'coleta'),'[]')
 INTO collections,regular FROM jsonb_array_elements(p_dados->'paradas') WITH ORDINALITY p(value,ord);
 IF jsonb_array_length(collections)>0 THEN
  SELECT count(*) INTO route_count FROM public.rotas_planejadas WHERE empresa_id=company AND motorista_id=driver AND status='em_execucao';
  IF route_count>1 THEN RAISE EXCEPTION 'O motorista possui mais de uma rota em andamento. Regularize a rota ativa antes de inserir coletas.'; END IF;
  SELECT * INTO active_route FROM public.rotas_planejadas WHERE empresa_id=company AND motorista_id=driver AND status='em_execucao' FOR UPDATE;
 END IF;
 IF active_route.id IS NULL AND p_plano_coletas IS NOT NULL THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_DESATUALIZADO','mensagem','A rota em andamento mudou. Recalcule o envio.');
 END IF;
 IF active_route.id IS NOT NULL THEN
  IF p_plano_coletas IS NULL THEN RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_COLETAS_NECESSARIO','mensagem','Calcule a inserção das coletas na rota em andamento.'); END IF;
  IF (p_plano_coletas->>'rota_id')::uuid<>active_route.id OR public.fn_usuario_pode_operar_motorista(company,driver) IS NOT TRUE THEN RAISE EXCEPTION 'Rota ativa indisponível para receber coletas.'; END IF;
  gps:=p_plano_coletas->'origem';metric:=p_plano_coletas->'metricas';
  IF driver_row.localizacao_atualizada_em IS NULL OR driver_row.localizacao_atualizada_em<now()-interval '5 minutes'
    OR driver_row.latitude_atual IS NULL OR driver_row.longitude_atual IS NULL THEN RAISE EXCEPTION 'Sem GPS recente do motorista. Ative o compartilhamento de localização durante a rota e tente novamente.'; END IF;
  IF jsonb_typeof(gps->'lat') IS DISTINCT FROM 'number' OR jsonb_typeof(gps->'lng') IS DISTINCT FROM 'number'
   OR abs((gps->>'lat')::numeric-driver_row.latitude_atual)>0.0015 OR abs((gps->>'lng')::numeric-driver_row.longitude_atual)>0.0015 THEN
   RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_DESATUALIZADO','mensagem','O motorista mudou de posição. Recalcule o envio.'); END IF;
  IF metric->>'fonte' IS DISTINCT FROM 'mapbox_directions_restante' OR (metric->>'distancia_km') IS NULL OR (metric->>'tempo_minutos') IS NULL
   OR NOT ((metric->>'distancia_km')::numeric BETWEEN 0 AND 999999) OR NOT ((metric->>'tempo_minutos')::numeric BETWEEN 0 AND 999999) THEN RAISE EXCEPTION 'O cálculo viário da rota ativa está indisponível.'; END IF;
  -- Match the route/stop lock order of reordering; an arrival or completion invalidates the planning snapshot.
  PERFORM id FROM public.entregas WHERE rota_id=active_route.id ORDER BY id FOR UPDATE;
  IF jsonb_typeof(p_plano_coletas->'snapshot') IS DISTINCT FROM 'array' OR EXISTS(
    SELECT 1 FROM (SELECT id,status,ordem_na_rota,chegada_em FROM public.entregas WHERE rota_id=active_route.id AND empresa_id=company) e
    FULL JOIN jsonb_to_recordset(p_plano_coletas->'snapshot') s(id uuid,status text,ordem_na_rota int,chegada_em timestamptz)
      ON e.id=s.id WHERE e.id IS NULL OR s.id IS NULL OR e.status IS DISTINCT FROM s.status OR e.ordem_na_rota IS DISTINCT FROM s.ordem_na_rota OR e.chegada_em IS DISTINCT FROM s.chegada_em
  ) OR (SELECT count(*) FROM jsonb_array_elements(p_plano_coletas->'snapshot'))<>(SELECT count(DISTINCT value->>'id') FROM jsonb_array_elements(p_plano_coletas->'snapshot')) THEN
   RETURN jsonb_build_object('sucesso',false,'codigo','PLANO_DESATUALIZADO','mensagem','Uma parada mudou enquanto o envio era calculado. Recalcule sem perder os serviços.');
  END IF;
  SELECT COALESCE(array_agg(id ORDER BY ordem_na_rota,id),'{}'::uuid[]) INTO pinned FROM public.entregas WHERE rota_id=active_route.id AND status NOT IN ('entregue','tentativa_falha','cancelada') AND chegada_em IS NOT NULL;
  IF cardinality(pinned)>1 THEN RAISE EXCEPTION 'Há mais de um atendimento aberto nesta rota. Finalize o atendimento pendente.'; END IF;
  SELECT array_agg(k ORDER BY k) INTO expected_keys FROM (
   SELECT id::text k FROM public.entregas WHERE rota_id=active_route.id AND status NOT IN ('entregue','tentativa_falha','cancelada')
   UNION ALL SELECT 'nova:'||(ord-1)::text FROM jsonb_array_elements(p_dados->'paradas') WITH ORDINALITY p(value,ord) WHERE value->>'tipo_tarefa'='coleta'
  ) t;
  IF jsonb_typeof(p_plano_coletas->'ordem') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Informe a ordem calculada das paradas.'; END IF;
  SELECT array_agg(value ORDER BY value) INTO requested_keys FROM jsonb_array_elements_text(p_plano_coletas->'ordem');
  IF requested_keys IS DISTINCT FROM expected_keys OR cardinality(requested_keys)>500 THEN RAISE EXCEPTION 'A ordem deve conter todas as paradas pendentes e coletas novas uma única vez.'; END IF;
  IF cardinality(pinned)=1 AND p_plano_coletas->'ordem'->>0 IS DISTINCT FROM pinned[1]::text THEN RAISE EXCEPTION 'O atendimento atual deve permanecer na primeira posição pendente.'; END IF;
  -- Insert only collections, directly into the existing route; no transient route or phantom notification.
  FOR item IN SELECT value,ord-1 AS idx FROM jsonb_array_elements(p_dados->'paradas') WITH ORDINALITY p(value,ord) WHERE value->>'tipo_tarefa'='coleta' LOOP
   IF NOT EXISTS(SELECT 1 FROM public.clientes_enderecos WHERE id=(item.value->>'cliente_endereco_id')::uuid AND empresa_id=company) THEN RAISE EXCEPTION 'Endereço da coleta não pertence à empresa.'; END IF;
   delivery_id:=gen_random_uuid();
   INSERT INTO public.entregas(id,empresa_id,rota_id,motorista_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,destinatario_telefone,unidade_apartamento,status,prioridade,tipo_tarefa,descricao_outro,peso_kg,volumes_qtd,observacoes_gestor)
   VALUES(delivery_id,company,active_route.id,driver,(item.value->>'cliente_endereco_id')::uuid,COALESCE(NULLIF(btrim(item.value->>'codigo_rastreio'),''),'EC-'||substr(delivery_id::text,1,8)),COALESCE(NULLIF(btrim(item.value->>'destinatario_nome'),''),'Responsável pela coleta'),item.value->>'destinatario_telefone',item.value->>'unidade_apartamento','atribuida',COALESCE(item.value->>'prioridade','normal'),'coleta',item.value->>'descricao_outro',(item.value->>'peso_kg')::numeric,COALESCE((item.value->>'volumes_qtd')::int,1),item.value->>'observacoes_gestor');
   new_ids:=new_ids||jsonb_build_object('nova:'||item.idx::text,delivery_id);count_new:=count_new+1;
  END LOOP;
  FOR key_item IN SELECT value FROM jsonb_array_elements_text(p_plano_coletas->'ordem') LOOP
   LOOP
    slot:=slot+1;
    EXIT WHEN NOT EXISTS(SELECT 1 FROM public.entregas WHERE rota_id=active_route.id AND status IN ('entregue','tentativa_falha','cancelada') AND ordem_na_rota=slot);
   END LOOP;
   delivery_id:=CASE WHEN key_item.value LIKE 'nova:%' THEN (new_ids->>key_item.value)::uuid ELSE key_item.value::uuid END;
   UPDATE public.entregas SET ordem_na_rota=slot,updated_at=now() WHERE id=delivery_id AND rota_id=active_route.id;
  END LOOP;
  UPDATE public.rotas_planejadas SET metricas_fonte='mapbox_directions_restante',metricas_atualizadas_em=now(),distancia_otimizada_km=(metric->>'distancia_km')::numeric,tempo_otimizado_minutos=(metric->>'tempo_minutos')::numeric,
    configuracao_navegacao=configuracao_navegacao||jsonb_build_object('origem_atual',gps,'origem_atual_em',now(),'metricas',metric),
    ordem_paradas_json=(SELECT jsonb_agg(to_jsonb(e)||jsonb_build_object('sequencia',e.ordem_na_rota,'destinatario',e.destinatario_nome,'nome_local',c.nome_identificador,'endereco_formatado',c.endereco_completo,'coordenadas',jsonb_build_object('lat',c.latitude,'lng',c.longitude)) ORDER BY e.ordem_na_rota,e.id) FROM public.entregas e JOIN public.clientes_enderecos c ON c.id=e.cliente_endereco_id AND c.empresa_id=e.empresa_id WHERE e.rota_id=active_route.id)
   WHERE id=active_route.id;
 END IF;
 IF active_route.id IS NULL OR jsonb_array_length(regular)>0 THEN
  new_payload:=p_dados;
  IF active_route.id IS NOT NULL THEN
   SELECT jsonb_agg(value||jsonb_build_object('ordem_na_rota',ord) ORDER BY ord) INTO regular FROM jsonb_array_elements(regular) WITH ORDINALITY p(value,ord);
   new_payload:=p_dados||jsonb_build_object('paradas',regular,'idempotency_key',request_key||':nova','ordem_paradas_json',(SELECT COALESCE(jsonb_agg(value ORDER BY ord),'[]') FROM jsonb_array_elements(COALESCE(p_dados->'ordem_paradas_json','[]')) WITH ORDINALITY p(value,ord) WHERE COALESCE(value->>'tipo_tarefa','entrega')<>'coleta'));
   IF p_plano_coletas->'metricas_nova_rota' IS NULL THEN RAISE EXCEPTION 'Calcule a nova rota das entregas separadamente das coletas.'; END IF;
   new_payload:=new_payload||(p_plano_coletas->'metricas_nova_rota');
  END IF;
  IF new_payload->>'metricas_fonte' IS DISTINCT FROM 'mapbox_directions_planejamento' OR COALESCE((new_payload->>'distancia_otimizada_km')::numeric,0)<=0 OR COALESCE((new_payload->>'tempo_otimizado_minutos')::numeric,0)<=0 THEN RAISE EXCEPTION 'Tempo e distância da nova rota indisponíveis. Aguarde o cálculo viário; os serviços foram preservados.'; END IF;
  new_result:=public.despachar_rota_transacional(new_payload);
  IF new_result->>'sucesso' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION '%',COALESCE(new_result->>'mensagem','A nova rota não foi confirmada.'); END IF;
 END IF;
 result:=jsonb_build_object('sucesso',true,'codigo','SERVICOS_ENVIADOS','idempotente',false,'rota_ativa_id',active_route.id,'nova_rota_id',new_result->>'rota_id','coletas_adicionadas',count_new,'mensagem',CASE WHEN count_new>0 THEN count_new||' coleta(s) inserida(s) na rota em andamento.'||CASE WHEN new_result IS NOT NULL THEN ' Entregas e outros serviços enviados em uma nova rota.' ELSE '' END ELSE 'Serviços enviados em uma nova rota.' END);
 INSERT INTO public.operacoes_envio_motorista(empresa_id,chave,payload_hash,resultado) VALUES(company,request_key,request_hash,result);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 -- Subtransaction rolls back every insertion/reorder/new route before exposing a safe failure.
 RETURN jsonb_build_object('sucesso',false,'codigo','ENVIO_NAO_CONFIRMADO','mensagem',SQLERRM);
END $function$;
REVOKE ALL ON FUNCTION public.enviar_servicos_motorista(jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enviar_servicos_motorista(jsonb,jsonb) TO authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/08_push_notifications.sql
-- ------------------------------------------------------------------------------

-- Private FCM devices and transactional per-device notification outbox.
CREATE TABLE IF NOT EXISTS public.push_dispositivos (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 empresa_id uuid NOT NULL REFERENCES public.empresas(id), token text UNIQUE,
 plataforma text NOT NULL DEFAULT 'android' CHECK(plataforma='android'),
 ativo boolean NOT NULL DEFAULT true, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.push_envios (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 user_id uuid NOT NULL REFERENCES auth.users(id), dispositivo_id uuid NOT NULL REFERENCES public.push_dispositivos(id),
 rota_id uuid NOT NULL REFERENCES public.rotas_planejadas(id), evento text NOT NULL,
 tipo text NOT NULL CHECK(tipo IN ('nova_rota','nova_coleta')), quantidade int NOT NULL CHECK(quantidade>0),
 status text NOT NULL DEFAULT 'pendente' CHECK(status IN ('pendente','processando','aceito_fcm','cancelado','expirado','falhou')),
 tentativas int NOT NULL DEFAULT 0, proxima_tentativa timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '24 hours',
 claim_token uuid, lease_expires_at timestamptz, token_enviado text, ultimo_erro text,
 created_at timestamptz NOT NULL DEFAULT now(), enviado_em timestamptz,
 UNIQUE(evento,dispositivo_id)
);
ALTER TABLE public.push_dispositivos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_envios ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_dispositivos,public.push_envios FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.push_dispositivos,public.push_envios TO service_role;
CREATE INDEX IF NOT EXISTS idx_push_pendentes ON public.push_envios(proxima_tentativa) WHERE status IN ('pendente','processando');
CREATE OR REPLACE FUNCTION public.registrar_dispositivo_push(p_id uuid,p_empresa_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE owner_id uuid;
BEGIN
 IF auth.uid() IS NULL OR p_id IS NULL OR p_token IS NULL OR length(p_token) NOT BETWEEN 20 AND 4096
 OR NOT EXISTS(SELECT 1 FROM public.empresa_membros em JOIN public.empresas e ON e.id=em.empresa_id AND e.ativa
 JOIN public.motoristas m ON m.id=em.motorista_id AND m.user_id=em.user_id AND m.empresa_id=em.empresa_id AND m.ativo
 WHERE em.empresa_id=p_empresa_id AND em.user_id=auth.uid() AND em.status='aprovado' AND em.papel='motorista') THEN
  RETURN jsonb_build_object('sucesso',false,'mensagem','Acesso de motorista aprovado necessário para ativar avisos.');
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('push-token:'||p_token,0));
 SELECT user_id INTO owner_id FROM public.push_dispositivos WHERE id=p_id FOR UPDATE;
 IF FOUND AND owner_id<>auth.uid() THEN RETURN jsonb_build_object('sucesso',false,'mensagem','Dispositivo indisponível.'); END IF;
 -- Token possession transfers this installation to the currently authenticated account.
 UPDATE public.push_dispositivos SET token=NULL,ativo=false,updated_at=now() WHERE token=p_token AND id<>p_id;
 INSERT INTO public.push_dispositivos(id,user_id,empresa_id,token) VALUES(p_id,auth.uid(),p_empresa_id,p_token)
 ON CONFLICT(id) DO UPDATE SET empresa_id=excluded.empresa_id,token=excluded.token,ativo=true,updated_at=now();
 RETURN jsonb_build_object('sucesso',true);
END $$;
CREATE OR REPLACE FUNCTION public.desativar_dispositivo_push(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('sucesso',false); END IF;
 UPDATE public.push_dispositivos SET ativo=false,updated_at=now() WHERE id=p_id AND user_id=auth.uid();
 RETURN jsonb_build_object('sucesso',true);
END $$;
REVOKE ALL ON FUNCTION public.registrar_dispositivo_push(uuid,uuid,text),public.desativar_dispositivo_push(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_dispositivo_push(uuid,uuid,text),public.desativar_dispositivo_push(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_enfileirar_push_servicos()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE route_id uuid; kind text; amount int; target record;
BEGIN
 FOR target IN SELECT (NEW.resultado->>'rota_ativa_id')::uuid AS id,'nova_coleta'::text AS tipo,COALESCE((NEW.resultado->>'coletas_adicionadas')::int,0) AS qtd
 UNION ALL SELECT (NEW.resultado->>'nova_rota_id')::uuid,'nova_rota',0 LOOP
  route_id:=target.id;kind:=target.tipo;amount:=target.qtd;
  IF route_id IS NULL THEN CONTINUE; END IF;
  IF kind='nova_rota' THEN SELECT count(*) INTO amount FROM public.entregas WHERE rota_id=route_id AND empresa_id=NEW.empresa_id; END IF;
  IF amount<=0 THEN CONTINUE; END IF;
  INSERT INTO public.push_envios(empresa_id,user_id,dispositivo_id,rota_id,evento,tipo,quantidade)
  SELECT NEW.empresa_id,m.user_id,d.id,r.id,NEW.chave||':'||r.id::text,kind,amount
  FROM public.rotas_planejadas r JOIN public.motoristas m ON m.id=r.motorista_id AND m.empresa_id=r.empresa_id AND m.ativo
  JOIN public.push_dispositivos d ON d.user_id=m.user_id AND d.empresa_id=r.empresa_id AND d.ativo AND d.token IS NOT NULL
  JOIN public.empresa_membros em ON em.empresa_id=r.empresa_id AND em.user_id=m.user_id AND em.motorista_id=m.id AND em.papel='motorista' AND em.status='aprovado'
  WHERE r.id=route_id AND r.empresa_id=NEW.empresa_id AND r.status IN ('planejada','em_execucao')
  ON CONFLICT(evento,dispositivo_id) DO NOTHING;
 END LOOP;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.fn_enfileirar_push_servicos() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS push_servicos_confirmados ON public.operacoes_envio_motorista;
CREATE TRIGGER push_servicos_confirmados AFTER INSERT ON public.operacoes_envio_motorista FOR EACH ROW EXECUTE FUNCTION public.fn_enfileirar_push_servicos();
CREATE OR REPLACE FUNCTION public.reivindicar_push_envios(p_limite int DEFAULT 10)
RETURNS TABLE(id uuid,claim_token uuid,token text,rota_id uuid,tipo text,quantidade int,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 UPDATE public.push_envios j SET status=CASE WHEN j.expires_at<=now() THEN 'expirado' ELSE 'cancelado' END,claim_token=NULL,lease_expires_at=NULL
 WHERE j.status IN ('pendente','processando') AND (j.expires_at<=now() OR NOT EXISTS(
 SELECT 1 FROM public.push_dispositivos d JOIN public.rotas_planejadas r ON r.id=j.rota_id AND r.empresa_id=j.empresa_id
 JOIN public.motoristas m ON m.id=r.motorista_id AND m.empresa_id=r.empresa_id AND m.user_id=j.user_id AND m.ativo
 JOIN public.empresas e ON e.id=r.empresa_id AND e.ativa
 JOIN public.empresa_membros em ON em.empresa_id=r.empresa_id AND em.user_id=m.user_id AND em.motorista_id=m.id AND em.status='aprovado' AND em.papel='motorista'
 WHERE d.id=j.dispositivo_id AND d.user_id=j.user_id AND d.empresa_id=j.empresa_id AND d.ativo AND d.token IS NOT NULL AND r.status IN ('planejada','em_execucao')));
 RETURN QUERY WITH chosen AS (
 SELECT j.id FROM public.push_envios j WHERE (j.status='pendente' OR (j.status='processando' AND j.lease_expires_at<now())) AND j.proxima_tentativa<=now() AND j.tentativas<8
 ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT greatest(1,least(COALESCE(p_limite,10),25))
 ), claimed AS (
 UPDATE public.push_envios j SET status='processando',claim_token=gen_random_uuid(),lease_expires_at=now()+interval '2 minutes',tentativas=j.tentativas+1,
 token_enviado=d.token FROM chosen c,public.push_dispositivos d WHERE j.id=c.id AND d.id=j.dispositivo_id RETURNING j.*
 ) SELECT c.id,c.claim_token,c.token_enviado,c.rota_id,c.tipo,c.quantidade,c.expires_at FROM claimed c;
END $$;
CREATE OR REPLACE FUNCTION public.finalizar_push_envio(p_id uuid,p_claim uuid,p_resultado text,p_erro text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE job public.push_envios%ROWTYPE;
BEGIN
 SELECT * INTO job FROM public.push_envios WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR job.status<>'processando' OR job.claim_token IS DISTINCT FROM p_claim OR job.lease_expires_at<=now() THEN RETURN false; END IF;
 IF p_resultado NOT IN ('aceito','repetir','invalido','falhou') OR p_resultado IS NULL THEN RETURN false; END IF;
 IF p_resultado='invalido' THEN UPDATE public.push_dispositivos SET ativo=false WHERE id=job.dispositivo_id AND token=job.token_enviado; END IF;
 UPDATE public.push_envios SET status=CASE WHEN p_resultado='aceito' THEN 'aceito_fcm' WHEN p_resultado='repetir' AND tentativas<8 AND expires_at>now() THEN 'pendente' ELSE 'falhou' END,
 proxima_tentativa=now()+make_interval(secs=>least(3600,10*power(2,tentativas))::int),
 enviado_em=CASE WHEN p_resultado='aceito' THEN now() ELSE NULL END,ultimo_erro=left(p_erro,200),claim_token=NULL,lease_expires_at=NULL,token_enviado=NULL WHERE public.push_envios.id=job.id;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.reivindicar_push_envios(int),public.finalizar_push_envio(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reivindicar_push_envios(int),public.finalizar_push_envio(uuid,uuid,text,text) TO service_role;

-- Waking is best effort; the private outbox survives a network/configuration failure.
CREATE OR REPLACE FUNCTION public.fn_acordar_push_worker()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE secret text;
BEGIN
 IF to_regclass('vault.decrypted_secrets') IS NULL OR to_regnamespace('net') IS NULL THEN RETURN; END IF;
 EXECUTE 'SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name=$1 LIMIT 1' INTO secret USING 'entregacondo_push_worker';
 IF secret IS NULL OR length(secret)<32 THEN RETURN; END IF;
 EXECUTE 'SELECT net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 5000)'
 USING 'https://vblwuvhdqgzdjnoscyqo.supabase.co/functions/v1/push-servicos',jsonb_build_object('Content-Type','application/json','x-push-worker-secret',secret),'{}'::jsonb;
EXCEPTION WHEN OTHERS THEN
 RAISE WARNING 'O envio push aguardará a próxima tentativa agendada.';
END $$;
CREATE OR REPLACE FUNCTION public.fn_acordar_push_apos_fila()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN PERFORM public.fn_acordar_push_worker(); RETURN NULL; END $$;
REVOKE ALL ON FUNCTION public.fn_acordar_push_worker(),public.fn_acordar_push_apos_fila() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_acordar_push_worker() TO service_role;
DROP TRIGGER IF EXISTS acordar_push_fila ON public.push_envios;
CREATE TRIGGER acordar_push_fila AFTER INSERT ON public.push_envios FOR EACH STATEMENT EXECUTE FUNCTION public.fn_acordar_push_apos_fila();

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
    WHERE user_id = v_user_id AND empresa_id = v_membro.empresa_id;

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
                    'operacional_liberado', public.fn_usuario_pode_operar_motorista(v_membro.empresa_id, v_membro.motorista_id),
                    'mensagem', CASE WHEN public.fn_usuario_pode_operar_motorista(v_membro.empresa_id, v_membro.motorista_id)
                        THEN 'Acesso operacional liberado com sucesso.' ELSE 'Vínculo aprovado. Aguarde a aprovação do veículo para operar.' END
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
        SELECT * INTO v_veiculo FROM public.veiculos_motoristas WHERE user_id=v_user_id AND empresa_id=v_solicitacao.empresa_id;
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
-- MÓDULO: supabase/functions-sql/salvar_cliente_endereco.sql
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.salvar_cliente_endereco(p_dados JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_empresa_id UUID;
    v_nome TEXT;
    v_endereco TEXT;
    v_complemento TEXT;
    v_lat NUMERIC;
    v_lng NUMERIC;
    v_place_id TEXT;
    v_tempo_medio INT;
    v_id UUID;
    v_registro public.clientes_enderecos%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_AUTENTICADO', 'mensagem', 'Não autenticado.');
    END IF;

    -- 1. Resolução e validação estrita da empresa do gestor
    v_empresa_id := public.fn_safe_uuid(p_dados->>'empresa_id');
    IF v_empresa_id IS NULL THEN
        SELECT em.empresa_id INTO v_empresa_id
        FROM public.empresa_membros em
        WHERE em.user_id = v_user_id
          AND em.status = 'aprovado'
          AND em.papel IN ('admin', 'gestor')
        LIMIT 1;
    END IF;

    -- Rejeita se não houver empresa ou se o usuário não for gestor autorizado dela
    IF v_empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(v_empresa_id, v_user_id) IS NOT TRUE THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Acesso de gestão obrigatório nesta empresa.');
    END IF;

    -- 2. Extrai o nome/label aceitando qualquer variação enviada pelo frontend
    v_nome := TRIM(COALESCE(
        p_dados->>'nome_identificador',
        p_dados->>'label',
        p_dados->>'nome',
        p_dados->>'nome_cliente',
        p_dados->>'cliente_nome',
        p_dados->>'condominio',
        p_dados->>'destinatario_padrao',
        split_part(p_dados->>'full_address', ',', 1),
        split_part(p_dados->>'endereco_completo', ',', 1),
        split_part(p_dados->>'endereco', ',', 1)
    ));

    -- 3. Extrai o endereço aceitando variações
    v_endereco := TRIM(COALESCE(
        p_dados->>'full_address',
        p_dados->>'endereco_completo',
        p_dados->>'endereco',
        p_dados->>'logradouro'
    ));

    -- 4. Extrai complemento / observações de acesso
    v_complemento := NULLIF(TRIM(COALESCE(
        p_dados->>'observacoes_acesso',
        p_dados->>'complemento',
        p_dados->>'bloco_apartamento'
    )), '');

    -- 5. Extrai coordenadas aceitando variações lat/lng e latitude/longitude
    v_lat := (COALESCE(p_dados->>'latitude', p_dados->>'lat'))::NUMERIC;
    v_lng := (COALESCE(p_dados->>'longitude', p_dados->>'lng'))::NUMERIC;

    IF v_lat IS NULL OR v_lng IS NULL OR NOT (v_lat BETWEEN -90 AND 90) OR NOT (v_lng BETWEEN -180 AND 180) THEN
        v_lat := -27.5954;
        v_lng := -48.5480;
    END IF;

    v_place_id := NULLIF(TRIM(COALESCE(p_dados->>'place_id', p_dados->>'placeId')), '');

    v_tempo_medio := COALESCE(
        (p_dados->>'tempo_medio_minutos')::INT,
        (p_dados->>'tempo_medio_atendimento_min')::INT,
        15
    );

    IF v_nome IS NULL OR v_nome = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DADOS_INVALIDOS', 'mensagem', 'Nome do cliente ou condomínio é obrigatório.');
    END IF;

    IF v_endereco IS NULL OR v_endereco = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DADOS_INVALIDOS', 'mensagem', 'Endereço é obrigatório.');
    END IF;

    -- Lock transacional para evitar duplicação concorrente do mesmo condomínio
    PERFORM pg_advisory_xact_lock(hashtextextended(v_empresa_id::text || lower(v_nome) || lower(v_endereco), 0));

    -- Verifica se foi fornecido ID específico ou se o registro já existe pelo nome/endereço
    v_id := public.fn_safe_uuid(p_dados->>'id');

    IF v_id IS NOT NULL THEN
        UPDATE public.clientes_enderecos
        SET 
            nome_identificador = v_nome,
            endereco_completo = v_endereco,
            latitude = v_lat,
            longitude = v_lng,
            place_id = COALESCE(v_place_id, place_id),
            tempo_medio_minutos = v_tempo_medio,
            observacoes_acesso = COALESCE(v_complemento, observacoes_acesso),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_id AND empresa_id = v_empresa_id
        RETURNING * INTO v_registro;
    END IF;

    IF v_registro.id IS NULL THEN
        SELECT * INTO v_registro
        FROM public.clientes_enderecos
        WHERE empresa_id = v_empresa_id
          AND (lower(nome_identificador) = lower(v_nome) AND lower(endereco_completo) = lower(v_endereco))
        LIMIT 1;

        IF v_registro.id IS NOT NULL THEN
            UPDATE public.clientes_enderecos
            SET 
                latitude = v_lat,
                longitude = v_lng,
                place_id = COALESCE(v_place_id, place_id),
                tempo_medio_minutos = v_tempo_medio,
                observacoes_acesso = COALESCE(v_complemento, observacoes_acesso),
                updated_at = timezone('utc'::text, now())
            WHERE id = v_registro.id
            RETURNING * INTO v_registro;
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
                place_id,
                tempo_medio_minutos,
                total_entregas_realizadas,
                tipo_local,
                observacoes_acesso,
                created_at,
                updated_at
            ) VALUES (
                v_empresa_id,
                v_nome,
                p_dados->>'destinatario_padrao',
                v_endereco,
                COALESCE(p_dados->>'numero', ''),
                COALESCE(p_dados->>'bairro', ''),
                COALESCE(p_dados->>'cidade', 'Florianópolis'),
                COALESCE(p_dados->>'cep', '88000-000'),
                v_lat,
                v_lng,
                v_place_id,
                v_tempo_medio,
                0,
                COALESCE(p_dados->>'tipo_local', 'condominio_horizontal'),
                v_complemento,
                timezone('utc'::text, now()),
                timezone('utc'::text, now())
            )
            RETURNING * INTO v_registro;
        END IF;
    END IF;

    RETURN to_jsonb(v_registro) || jsonb_build_object(
        'id',v_registro.id,
        'nome',v_registro.nome_identificador,
        'endereco',v_registro.endereco_completo,
        'sucesso', true,
        'mensagem', 'Endereço salvo com sucesso no banco de dados.',
        'cliente', row_to_json(v_registro)
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.salvar_cliente_endereco(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.salvar_cliente_endereco(jsonb) TO authenticated;

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
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- solicitacoes_acesso
DROP POLICY IF EXISTS "Leitura de solicitacoes pelo usuario ou gestao" ON public.solicitacoes_acesso;
CREATE POLICY "Leitura de solicitacoes pelo usuario ou gestao"
ON public.solicitacoes_acesso FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- auditoria_acessos
DROP POLICY IF EXISTS "Gestores leem auditoria da empresa" ON public.auditoria_acessos;
CREATE POLICY "Gestores leem auditoria da empresa"
ON public.auditoria_acessos FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- motoristas
DROP POLICY IF EXISTS "Leitura de motoristas autorizada" ON public.motoristas;
CREATE POLICY "Leitura de motoristas autorizada"
ON public.motoristas FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
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
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- veiculos_documentos
DROP POLICY IF EXISTS "Leitura de documentos por condutor ou gestao" ON public.veiculos_documentos;
CREATE POLICY "Leitura de documentos por condutor ou gestao"
ON public.veiculos_documentos FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
);

-- clientes_enderecos
DROP POLICY IF EXISTS "Leitura de clientes enderecos por gestao ou motorista atribuido" ON public.clientes_enderecos;
CREATE POLICY "Leitura de clientes enderecos por gestao ou motorista atribuido"
ON public.clientes_enderecos FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
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
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
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
    public.fn_usuario_e_gestor_empresa(empresa_id, auth.uid())
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
          AND public.fn_usuario_e_gestor_empresa(e.empresa_id, auth.uid())
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
REVOKE ALL ON public.storage_limpeza_fila FROM anon, authenticated;

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
GRANT SELECT ON public.storage_limpeza_fila TO authenticated;

-- 3. PERMISSÃO DE EDIÇÃO BÁSICA EXCLUSIVA NO PRÓPRIO PERFIL
GRANT UPDATE (nome, telefone, avatar_url) ON public.perfis_usuarios TO authenticated;

-- 4. REVOGAÇÃO DE SOBRECARGAS OBSOLETAS E PRIVILÉGIOS PÚBLICOS PADRÃO
DROP FUNCTION IF EXISTS public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS public.analisar_veiculo_motorista(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, INT);

REVOKE EXECUTE ON FUNCTION public.fn_validar_autorizacao_condutor(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, BOOLEAN, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_limpeza_storage_executada(UUID, UUID, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reservar_upload_evidencia(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.descartar_evidencia_temporaria(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reivindicar_itens_limpeza_storage(INT, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.retomar_limpeza_falha(UUID) FROM PUBLIC;

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
GRANT EXECUTE ON FUNCTION public.reservar_upload_evidencia(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.descartar_evidencia_temporaria(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reivindicar_itens_limpeza_storage(INT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.retomar_limpeza_falha(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_limpeza_storage_executada(UUID, UUID, BOOLEAN, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, BOOLEAN, INT) TO authenticated;
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

-- Helpers de autorização e RPCs operacionais não herdam EXECUTE de PUBLIC.
REVOKE EXECUTE ON FUNCTION public.fn_usuario_pode_operar_motorista(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_usuario_pode_operar_motorista(UUID, UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.iniciar_rota(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.concluir_rota(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_conclusao_entrega(UUID, BOOLEAN, TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;

DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID);
REVOKE EXECUTE ON FUNCTION public.bootstrap_primeiro_gestor(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

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
