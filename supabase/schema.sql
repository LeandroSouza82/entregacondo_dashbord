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
SET search_path=''
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
    whatsapp_cliente VARCHAR(30),
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
REVOKE ALL ON public.saved_addresses FROM anon;
GRANT SELECT ON public.saved_addresses TO authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/03b_route_rules.sql
-- ------------------------------------------------------------------------------

-- Optional planning rules. Legacy time columns/data remain untouched.
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC,anon,authenticated;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_inicio time;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_fim time;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_data date;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS coleta_origem_id uuid;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS tempo_atendimento_previsto_min integer NOT NULL DEFAULT 0;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_inicio_em timestamptz
 GENERATED ALWAYS AS ((janela_data+janela_inicio) AT TIME ZONE 'America/Sao_Paulo') STORED;
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS janela_fim_em timestamptz
 GENERATED ALWAYS AS ((janela_data+janela_fim) AT TIME ZONE 'America/Sao_Paulo') STORED;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_empresa_id_id_unique UNIQUE(empresa_id,id);
ALTER TABLE public.entregas ADD CONSTRAINT entregas_coleta_origem_fk
 FOREIGN KEY(empresa_id,coleta_origem_id) REFERENCES public.entregas(empresa_id,id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.entregas ADD CONSTRAINT entregas_janela_planejada_check
 CHECK(janela_data IS NULL OR (janela_inicio IS NOT NULL AND janela_fim IS NOT NULL AND janela_fim>janela_inicio));
ALTER TABLE public.entregas ADD CONSTRAINT entregas_atendimento_previsto_check CHECK(tempo_atendimento_previsto_min BETWEEN 0 AND 240);
CREATE INDEX entregas_coleta_origem_idx ON public.entregas(empresa_id,coleta_origem_id) WHERE coleta_origem_id IS NOT NULL;

CREATE OR REPLACE FUNCTION ec_private.proteger_regras_rota() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE changed boolean; parent_status text;
BEGIN
 IF TG_OP='INSERT' THEN
  changed:=NEW.janela_data IS NOT NULL OR NEW.coleta_origem_id IS NOT NULL OR NEW.tempo_atendimento_previsto_min<>0;
 ELSE
  changed:=(NEW.janela_data,NEW.janela_inicio,NEW.janela_fim,NEW.coleta_origem_id,NEW.tempo_atendimento_previsto_min)
    IS DISTINCT FROM (OLD.janela_data,OLD.janela_inicio,OLD.janela_fim,OLD.coleta_origem_id,OLD.tempo_atendimento_previsto_min);
  IF changed AND (OLD.chegada_em IS NOT NULL OR OLD.status IN ('entregue','tentativa_falha','cancelada')) THEN
   RAISE EXCEPTION 'Não altere as condições de um atendimento iniciado ou finalizado.';
  END IF;
 END IF;
 IF changed THEN
  IF auth.uid() IS NOT NULL AND public.fn_usuario_e_gestor_empresa(NEW.empresa_id,auth.uid()) IS NOT TRUE THEN
   RAISE EXCEPTION 'Somente a gestão pode definir as condições do pedido.' USING ERRCODE='42501';
  END IF;
  IF NEW.janela_data IS NULL AND (NEW.janela_inicio IS NOT NULL OR NEW.janela_fim IS NOT NULL) THEN
   RAISE EXCEPTION 'Informe a data junto com os dois horários.';
  END IF;
  IF NEW.janela_data IS NOT NULL AND (extract(epoch FROM (NEW.janela_fim-NEW.janela_inicio))/60)<NEW.tempo_atendimento_previsto_min THEN
   RAISE EXCEPTION 'O atendimento previsto não cabe na faixa de horário.';
  END IF;
 END IF;
 IF NEW.coleta_origem_id IS NOT NULL AND NEW.status NOT IN ('tentativa_falha','cancelada') AND
   (TG_OP='INSERT' AND (NEW.chegada_em IS NOT NULL OR NEW.status='entregue') OR
    TG_OP='UPDATE' AND (NEW.chegada_em IS DISTINCT FROM OLD.chegada_em OR NEW.status='entregue' AND OLD.status<>'entregue')) THEN
  SELECT status INTO parent_status FROM public.entregas WHERE id=NEW.coleta_origem_id AND empresa_id=NEW.empresa_id FOR SHARE;
  IF parent_status IS DISTINCT FROM 'entregue' THEN RAISE EXCEPTION 'Conclua a coleta vinculada antes de atender esta entrega.'; END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION ec_private.proteger_regras_rota() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER entregas_proteger_regras BEFORE INSERT OR UPDATE ON public.entregas FOR EACH ROW EXECUTE FUNCTION ec_private.proteger_regras_rota();

CREATE OR REPLACE FUNCTION ec_private.validar_vinculo_coleta() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE child public.entregas%ROWTYPE; parent public.entregas%ROWTYPE;
BEGIN
 FOR child IN SELECT * FROM public.entregas WHERE empresa_id=NEW.empresa_id AND coleta_origem_id IS NOT NULL AND (id=NEW.id OR coleta_origem_id=NEW.id) ORDER BY id LOOP
  SELECT * INTO parent FROM public.entregas WHERE id=child.coleta_origem_id FOR SHARE;
  IF NOT FOUND OR child.id=parent.id OR child.tipo_tarefa<>'entrega' OR parent.tipo_tarefa<>'coleta'
   OR child.empresa_id<>parent.empresa_id OR child.motorista_id IS DISTINCT FROM parent.motorista_id THEN
   RAISE EXCEPTION 'Vincule a entrega a uma coleta da mesma empresa e do mesmo motorista.';
  END IF;
  IF child.rota_id IS NOT NULL AND child.rota_id=parent.rota_id
   AND child.status NOT IN ('entregue','tentativa_falha','cancelada') AND parent.status NOT IN ('entregue','tentativa_falha','cancelada')
   AND COALESCE(parent.ordem_na_rota,2147483647)>=COALESCE(child.ordem_na_rota,2147483647) THEN
   RAISE EXCEPTION 'A entrega deve ficar depois da coleta vinculada.';
  END IF;
 END LOOP;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION ec_private.validar_vinculo_coleta() FROM PUBLIC,anon,authenticated;
CREATE CONSTRAINT TRIGGER entregas_validar_vinculo AFTER INSERT OR UPDATE ON public.entregas
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ec_private.validar_vinculo_coleta();

CREATE OR REPLACE FUNCTION ec_private.validar_agenda(p_ids uuid[],p_agenda jsonb,p_partida timestamptz,p_atual boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item record; visit jsonb; t timestamptz; finish timestamptz; previous timestamptz:=p_partida;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.entregas WHERE id=ANY(p_ids) AND janela_data IS NOT NULL) THEN RETURN; END IF;
 IF p_partida IS NULL OR p_partida<now()-interval '5 minutes' OR (p_atual AND p_partida NOT BETWEEN now()-interval '5 minutes' AND now()+interval '5 minutes')
   OR jsonb_typeof(p_agenda) IS DISTINCT FROM 'array' OR jsonb_array_length(p_agenda)<>cardinality(p_ids) THEN
  RAISE EXCEPTION 'Recalcule os horários antes de salvar ou enviar a rota.';
 END IF;
 FOR item IN SELECT e.*,u.pos FROM unnest(p_ids) WITH ORDINALITY u(id,pos) JOIN public.entregas e ON e.id=u.id ORDER BY u.pos LOOP
  visit:=p_agenda->(item.pos::integer-1);
  IF visit->>'entrega_id' IS DISTINCT FROM item.id::text THEN RAISE EXCEPTION 'A agenda não corresponde à sequência dos pedidos.'; END IF;
  t:=(visit->>'inicio_em')::timestamptz; finish:=(visit->>'fim_em')::timestamptz;
  IF t IS NULL OR finish IS NULL OR t<previous OR finish<t+make_interval(mins=>item.tempo_atendimento_previsto_min)
   OR item.janela_data IS NOT NULL AND (t<item.janela_inicio_em OR finish>item.janela_fim_em) THEN
   RAISE EXCEPTION 'A sequência não cabe nos horários definidos. Recalcule a organização.';
  END IF;
  previous:=finish;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION ec_private.validar_agenda(uuid[],jsonb,timestamptz,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION ec_private.encaixar_coletas_vinculadas(p_rota uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[]; slots integer[]; item record; i integer; j integer;
BEGIN
 SELECT array_agg(id ORDER BY ordem_na_rota NULLS LAST,id),array_agg(pos ORDER BY ordem_na_rota NULLS LAST,id) INTO ids,slots
 FROM (SELECT id,ordem_na_rota,row_number() OVER(ORDER BY ordem_na_rota NULLS LAST,id)::integer pos,status FROM public.entregas WHERE rota_id=p_rota) e
 WHERE status NOT IN ('entregue','tentativa_falha','cancelada');
 FOR item IN SELECT id,coleta_origem_id FROM public.entregas WHERE rota_id=p_rota AND coleta_origem_id IS NOT NULL ORDER BY ordem_na_rota NULLS LAST,id LOOP
  i:=array_position(ids,item.id); j:=array_position(ids,item.coleta_origem_id);
  IF i IS NOT NULL AND j>i THEN
   ids:=array_remove(ids,item.coleta_origem_id);
   ids:=COALESCE(ids[1:i-1],'{}'::uuid[])||ARRAY[item.coleta_origem_id]||ids[i:cardinality(ids)];
  END IF;
 END LOOP;
 UPDATE public.entregas e SET ordem_na_rota=slots[u.pos::integer] FROM unnest(ids) WITH ORDINALITY u(id,pos) WHERE e.id=u.id;
END $$;
REVOKE ALL ON FUNCTION ec_private.encaixar_coletas_vinculadas(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.obter_capacidades_rotas() RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre novamente.' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('regras_opcionais',1,'fuso_horarios','America/Sao_Paulo');
END $$;
REVOKE ALL ON FUNCTION public.obter_capacidades_rotas() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obter_capacidades_rotas() TO authenticated;

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
        id UUID,
        janela_data DATE, janela_inicio TIME, janela_fim TIME, coleta_origem_id UUID, tempo_atendimento_previsto_min INT,
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
            id,janela_data,janela_inicio,janela_fim,coleta_origem_id,tempo_atendimento_previsto_min,
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
            COALESCE(v_parada.id,gen_random_uuid()),v_parada.janela_data,v_parada.janela_inicio,v_parada.janela_fim,v_parada.coleta_origem_id,COALESCE(v_parada.tempo_atendimento_previsto_min,0),
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

    PERFORM ec_private.validar_agenda(
      (SELECT array_agg(id ORDER BY ordem_na_rota,id) FROM public.entregas WHERE rota_id=v_rota_id),
      p_dados->'agenda',(p_dados->>'planejamento_saida_em')::timestamptz,false);

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
-- MÓDULO: supabase/modules-sql/07_driver_order_inbox.sql
-- ------------------------------------------------------------------------------

-- New dispatches are offers. Existing deliveries remain available without backfill.
CREATE TABLE public.pedidos_fluxo (
 entrega_id uuid PRIMARY KEY REFERENCES public.entregas(id),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 motorista_id uuid NOT NULL REFERENCES public.motoristas(id),
 lote_id uuid NOT NULL REFERENCES public.rotas_planejadas(id),
 etapa text NOT NULL DEFAULT 'ofertado' CHECK(etapa IN ('ofertado','aguardando_retirada','liberado')),
 aceito_em timestamptz,
 retirado_em timestamptz
);
ALTER TABLE public.pedidos_fluxo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pedidos_fluxo FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.pedidos_fluxo TO authenticated;
CREATE POLICY pedidos_fluxo_leitura ON public.pedidos_fluxo FOR SELECT TO authenticated
USING(public.fn_usuario_pode_operar_motorista(empresa_id,motorista_id) OR public.fn_usuario_e_gestor_empresa(empresa_id,auth.uid()));

CREATE FUNCTION public.enviar_pedidos_motorista(p_dados jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r jsonb; rid uuid; company uuid := (p_dados->>'empresa_id')::uuid; driver uuid := (p_dados->>'motorista_id')::uuid; k text:=p_dados->>'idempotency_key'; h text;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(company,auth.uid()) IS NOT TRUE THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 IF k IS NULL OR length(k) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Chave de envio inválida'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(company::text||':envio:'||k,0));
 h:=encode(sha256(convert_to(jsonb_build_object('motorista_id',driver,'paradas',p_dados->'paradas')::text,'UTF8')),'hex');
 SELECT resultado INTO r FROM public.operacoes_envio_motorista WHERE empresa_id=company AND chave=k AND payload_hash=h;
 IF FOUND THEN RETURN r||jsonb_build_object('idempotente',true); END IF;
 IF EXISTS(SELECT 1 FROM public.operacoes_envio_motorista WHERE empresa_id=company AND chave=k) THEN RAISE EXCEPTION 'Envio já utilizado com outros pedidos'; END IF;
 r:=public.despachar_rota_transacional(p_dados);
 IF r->>'sucesso' IS DISTINCT FROM 'true' THEN RETURN r; END IF;
 rid:=(r->>'rota_id')::uuid;
 INSERT INTO public.pedidos_fluxo(entrega_id,empresa_id,motorista_id,lote_id)
 SELECT id,empresa_id,motorista_id,rota_id FROM public.entregas WHERE rota_id=rid ON CONFLICT DO NOTHING;
 r:=r||jsonb_build_object('nova_rota_id',rid,'codigo','PEDIDOS_OFERTADOS','mensagem','Pedidos enviados para aceite do motorista.');
 INSERT INTO public.operacoes_envio_motorista VALUES(company,k,h,r,now());
 RETURN r;
END $$;

CREATE FUNCTION public.aceitar_pedidos_motorista(p_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE f public.pedidos_fluxo%ROWTYPE; target public.rotas_planejadas%ROWTYPE; item record; n integer; snapshot jsonb;
BEGIN
 IF auth.uid() IS NULL OR cardinality(p_ids) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Pedidos inválidos'; END IF;
 SELECT * INTO f FROM public.pedidos_fluxo WHERE entrega_id=p_ids[1];
 IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(f.empresa_id,f.motorista_id) IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.motoristas WHERE id=f.motorista_id AND empresa_id=f.empresa_id AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(f.empresa_id::text||':'||f.motorista_id::text,0));
 IF EXISTS(SELECT 1 FROM unnest(p_ids) requested(id) WHERE NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo x JOIN public.entregas e ON e.id=x.entrega_id JOIN public.rotas_planejadas r ON r.id=e.rota_id WHERE x.entrega_id=requested.id AND x.empresa_id=f.empresa_id AND x.motorista_id=f.motorista_id AND e.motorista_id=f.motorista_id AND e.empresa_id=f.empresa_id AND r.status IN ('planejada','em_execucao'))) THEN RAISE EXCEPTION 'Pedidos alterados; atualize'; END IF;
 SELECT r.* INTO target FROM public.rotas_planejadas r WHERE r.empresa_id=f.empresa_id AND r.motorista_id=f.motorista_id AND r.status IN ('planejada','em_execucao') AND EXISTS(SELECT 1 FROM public.entregas e LEFT JOIN public.pedidos_fluxo x ON x.entrega_id=e.id WHERE e.rota_id=r.id AND (x.entrega_id IS NULL OR x.etapa<>'ofertado')) ORDER BY (r.status='em_execucao') DESC,r.created_at,r.id LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN SELECT r.* INTO target FROM public.rotas_planejadas r JOIN public.entregas e ON e.rota_id=r.id WHERE e.id=p_ids[1] FOR UPDATE OF r; END IF;
 SELECT COALESCE(max(ordem_na_rota),0) INTO n FROM public.entregas WHERE rota_id=target.id;
 FOR item IN SELECT e.*,r.ordem_paradas_json FROM public.entregas e JOIN public.rotas_planejadas r ON r.id=e.rota_id JOIN public.pedidos_fluxo x ON x.entrega_id=e.id WHERE e.id=ANY(p_ids) AND x.etapa='ofertado' ORDER BY e.ordem_na_rota,e.id FOR UPDATE OF e LOOP
  IF item.rota_id<>target.id THEN
   SELECT value INTO snapshot FROM jsonb_array_elements(COALESCE(item.ordem_paradas_json,'[]')) WHERE value->>'id'=item.id::text OR value->>'cliente_endereco_id'=item.cliente_endereco_id::text LIMIT 1;
   n:=n+1;
   UPDATE public.entregas SET rota_id=target.id,ordem_na_rota=n WHERE id=item.id;
   IF snapshot IS NOT NULL THEN UPDATE public.rotas_planejadas SET ordem_paradas_json=COALESCE(ordem_paradas_json,'[]')||jsonb_build_array(snapshot||jsonb_build_object('id',item.id,'sequencia',n)) WHERE id=target.id; END IF;
  END IF;
  UPDATE public.pedidos_fluxo SET etapa=CASE WHEN item.tipo_tarefa='entrega' AND item.coleta_origem_id IS NULL THEN 'aguardando_retirada' ELSE 'liberado' END,aceito_em=now() WHERE entrega_id=item.id;
 END LOOP;
 -- Preserve linked pickups before their deliveries, even on partial batch acceptance.
 IF EXISTS(SELECT 1 FROM public.entregas WHERE rota_id=target.id AND (coleta_origem_id IS NOT NULL OR janela_data IS NOT NULL)) THEN
  PERFORM ec_private.encaixar_coletas_vinculadas(target.id);
  UPDATE public.rotas_planejadas SET metricas_fonte=NULL,metricas_atualizadas_em=NULL,ordem_paradas_json=(
   SELECT COALESCE(jsonb_agg(to_jsonb(e)||jsonb_build_object('sequencia',e.ordem_na_rota,'destinatario',e.destinatario_nome,
    'nome_local',c.nome_identificador,'endereco_formatado',c.endereco_completo,
    'coordenadas',jsonb_build_object('lat',c.latitude,'lng',c.longitude)) ORDER BY e.ordem_na_rota,e.id),'[]'::jsonb)
   FROM public.entregas e JOIN public.clientes_enderecos c ON c.id=e.cliente_endereco_id AND c.empresa_id=e.empresa_id WHERE e.rota_id=target.id
  ) WHERE id=target.id;
 END IF;
 -- Empty send containers are not another driver route.
 UPDATE public.rotas_planejadas r SET status='concluida' WHERE r.empresa_id=f.empresa_id AND r.motorista_id=f.motorista_id AND r.id<>target.id AND r.status='planejada' AND EXISTS(SELECT 1 FROM public.pedidos_fluxo x WHERE x.lote_id=r.id) AND NOT EXISTS(SELECT 1 FROM public.entregas e WHERE e.rota_id=r.id);
 RETURN jsonb_build_object('sucesso',true,'rota_id',target.id);
END $$;

-- Test phase: explicit manual confirmation. No GPS/geofence requirement is claimed.
CREATE FUNCTION public.confirmar_retirada_pedidos(p_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE f public.pedidos_fluxo%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR cardinality(p_ids) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Pedidos inválidos'; END IF;
 SELECT * INTO f FROM public.pedidos_fluxo WHERE entrega_id=p_ids[1];
 IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(f.empresa_id,f.motorista_id) IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.motoristas WHERE id=f.motorista_id AND empresa_id=f.empresa_id AND user_id=auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(f.empresa_id::text||':'||f.motorista_id::text,0));
 IF EXISTS(SELECT 1 FROM unnest(p_ids) requested(id) WHERE NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo x JOIN public.entregas e ON e.id=x.entrega_id WHERE x.entrega_id=requested.id AND x.empresa_id=f.empresa_id AND x.motorista_id=f.motorista_id AND e.empresa_id=f.empresa_id AND e.motorista_id=f.motorista_id AND x.etapa IN ('aguardando_retirada','liberado'))) THEN RAISE EXCEPTION 'Pedido não aceito ou acesso negado'; END IF;
 UPDATE public.pedidos_fluxo SET etapa='liberado',retirado_em=now() WHERE entrega_id=ANY(p_ids) AND etapa='aguardando_retirada';
 RETURN jsonb_build_object('sucesso',true);
END $$;

CREATE FUNCTION public.fn_proteger_pedido_sem_retirada() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF (NEW.chegada_em IS DISTINCT FROM OLD.chegada_em OR (NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('entregue','tentativa_falha'))) AND EXISTS(SELECT 1 FROM public.pedidos_fluxo WHERE entrega_id=NEW.id AND etapa<>'liberado') THEN RAISE EXCEPTION 'Aceite o pedido e confirme a retirada antes de atender'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER proteger_pedido_sem_retirada BEFORE UPDATE ON public.entregas FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_pedido_sem_retirada();
REVOKE ALL ON FUNCTION public.enviar_pedidos_motorista(jsonb),public.aceitar_pedidos_motorista(uuid[]),public.confirmar_retirada_pedidos(uuid[]),public.fn_proteger_pedido_sem_retirada() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enviar_pedidos_motorista(jsonb),public.aceitar_pedidos_motorista(uuid[]),public.confirmar_retirada_pedidos(uuid[]) TO authenticated;

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
    ) x WHERE status NOT IN ('entregue','tentativa_falha','cancelada')
      AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=x.id AND f.etapa<>'liberado');
    IF p_ordem_esperada IS DISTINCT FROM v_current THEN
        RETURN jsonb_build_object('sucesso',false,'codigo','ORDEM_DESATUALIZADA','mensagem','A rota mudou. Atualize e organize novamente.');
    END IF;
    IF p_entrega_ids IS NULL OR cardinality(p_entrega_ids)>500
       OR (SELECT array_agg(id ORDER BY id) FROM unnest(p_entrega_ids) id)
          IS DISTINCT FROM (SELECT array_agg(id ORDER BY id) FROM unnest(v_current) id) THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','Informe todas as paradas pendentes, sem duplicar ou adicionar paradas.');
    END IF;
    IF EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=ANY(v_current) AND e.chegada_em IS NOT NULL AND e.id IS DISTINCT FROM p_entrega_ids[1]) THEN
      RETURN jsonb_build_object('sucesso',false,'mensagem','Mantenha o atendimento em andamento na primeira posição.');
    END IF;
    IF EXISTS(SELECT 1 FROM public.entregas child JOIN public.entregas parent ON parent.id=child.coleta_origem_id AND parent.empresa_id=child.empresa_id
      WHERE child.id=ANY(v_current) AND parent.status<>'entregue' AND
      (array_position(p_entrega_ids,parent.id) IS NULL OR array_position(p_entrega_ids,parent.id)>=array_position(p_entrega_ids,child.id))) THEN
      RETURN jsonb_build_object('sucesso',false,'mensagem','Conclua a coleta vinculada ou coloque-a antes da entrega.');
    END IF;
    PERFORM ec_private.validar_agenda(p_entrega_ids,p_configuracao->'agenda',(p_configuracao->>'planejamento_saida_em')::timestamptz,true);
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
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'paradas') p WHERE
   NULLIF(p->>'janela_data','') IS NOT NULL OR NULLIF(p->>'coleta_origem_id','') IS NOT NULL) THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','USE_ENVIO_PEDIDOS','mensagem','Envie pedidos com condições pelo fluxo de aceite do motorista.');
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

    IF p_dados ? 'whatsapp_cliente' AND NULLIF(p_dados->>'whatsapp_cliente','') IS NOT NULL AND p_dados->>'whatsapp_cliente' !~ '^[1-9][0-9]{9,14}$' THEN
        RETURN jsonb_build_object('sucesso',false,'mensagem','WhatsApp inválido.');
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
    BEGIN
        v_lat := (COALESCE(p_dados->>'latitude', p_dados->>'lat'))::NUMERIC;
        v_lng := (COALESCE(p_dados->>'longitude', p_dados->>'lng'))::NUMERIC;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN jsonb_build_object('sucesso',false,'codigo','COORDENADAS_INVALIDAS','mensagem','Selecione o endereço no mapa antes de salvar.');
    END;
    IF v_lat IS NULL OR v_lng IS NULL OR NOT (v_lat BETWEEN -90 AND 90) OR NOT (v_lng BETWEEN -180 AND 180) OR (v_lat=0 AND v_lng=0) THEN
        RETURN jsonb_build_object('sucesso',false,'codigo','COORDENADAS_INVALIDAS','mensagem','Selecione o endereço no mapa antes de salvar.');
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
            whatsapp_cliente = CASE WHEN p_dados ? 'whatsapp_cliente' THEN NULLIF(p_dados->>'whatsapp_cliente','') ELSE whatsapp_cliente END,
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
                whatsapp_cliente = CASE WHEN p_dados ? 'whatsapp_cliente' THEN NULLIF(p_dados->>'whatsapp_cliente','') ELSE whatsapp_cliente END,
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
                whatsapp_cliente,
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
                NULLIF(p_dados->>'whatsapp_cliente',''),
                v_endereco,
                COALESCE(p_dados->>'numero', ''),
                COALESCE(p_dados->>'bairro', ''),
                COALESCE(p_dados->>'cidade', ''),
                COALESCE(p_dados->>'cep', ''),
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
-- MÓDULO: supabase/modules-sql/09_customer_tracking.sql
-- ------------------------------------------------------------------------------

-- Customer arrival tracking. Tokens are bearer secrets; only their SHA-256 is stored.
-- No direct access to the private table, including authenticated dashboard users.
ALTER TABLE public.clientes_enderecos ADD COLUMN IF NOT EXISTS whatsapp_cliente varchar(30);
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS ec_private.customer_tracking (
 entrega_id uuid PRIMARY KEY REFERENCES public.entregas(id) ON DELETE CASCADE,
 rota_id uuid NOT NULL, motorista_id uuid NOT NULL, token_hash bytea NOT NULL UNIQUE,
 cliente_endereco_id uuid NOT NULL, recipient_phone text NOT NULL,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '8 hours',
 latitude double precision, longitude double precision, observed_at timestamptz,
 eta_at timestamptz, eta_observed_at timestamptz
);
ALTER TABLE ec_private.customer_tracking ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.customer_tracking FROM PUBLIC, anon, authenticated;

-- Also rechecked on EVERY public read: terminal status, reassignment, departure to
-- another stop, membership suspension or route closure immediately hide all GPS.
CREATE OR REPLACE FUNCTION ec_private.tracking_active(p_entrega uuid,p_rota uuid,p_motorista uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT EXISTS(
  SELECT 1 FROM public.entregas e
  JOIN public.rotas_planejadas r ON r.id=e.rota_id AND r.empresa_id=e.empresa_id AND r.motorista_id=e.motorista_id
  JOIN public.motoristas m ON m.id=e.motorista_id AND m.empresa_id=e.empresa_id AND m.ativo
  JOIN public.empresas c ON c.id=e.empresa_id AND c.ativa
  JOIN public.empresa_membros em ON em.empresa_id=e.empresa_id AND em.user_id=m.user_id AND em.motorista_id=m.id AND em.status='aprovado' AND em.papel='motorista'
  WHERE e.id=p_entrega AND e.rota_id=p_rota AND e.motorista_id=p_motorista
   AND r.status='em_execucao' AND e.status NOT IN ('entregue','tentativa_falha','cancelada')
   AND (e.coleta_origem_id IS NULL OR EXISTS(SELECT 1 FROM public.entregas p WHERE p.id=e.coleta_origem_id AND p.empresa_id=e.empresa_id AND p.status='entregue'))
   AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=e.id AND f.etapa<>'liberado')
   AND e.id=(SELECT x.id FROM public.entregas x WHERE x.rota_id=r.id AND x.empresa_id=r.empresa_id
    AND x.status NOT IN ('entregue','tentativa_falha','cancelada')
    AND (x.coleta_origem_id IS NULL OR EXISTS(SELECT 1 FROM public.entregas p WHERE p.id=x.coleta_origem_id AND p.empresa_id=x.empresa_id AND p.status='entregue'))
    AND NOT EXISTS(SELECT 1 FROM public.pedidos_fluxo f WHERE f.entrega_id=x.id AND f.etapa<>'liberado')
    ORDER BY (x.chegada_em IS NOT NULL) DESC,x.ordem_na_rota NULLS LAST,x.id LIMIT 1)
 );
$$;
REVOKE ALL ON FUNCTION ec_private.tracking_active(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.configurar_nome_empresa(p_empresa_id uuid,p_nome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(p_empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório nesta empresa.' USING ERRCODE='42501'; END IF;
 IF p_nome IS NULL OR length(btrim(p_nome)) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'Informe um nome entre 2 e 120 caracteres.'; END IF;
 UPDATE public.empresas SET nome=btrim(p_nome) WHERE id=p_empresa_id;
 RETURN jsonb_build_object('sucesso',true);
END $$;

CREATE OR REPLACE FUNCTION public.preparar_aviso_cliente(p_entrega_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e public.entregas%ROWTYPE; h bytea; t ec_private.customer_tracking%ROWTYPE; result jsonb;
BEGIN
 SELECT * INTO e FROM public.entregas WHERE id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE
  OR NOT EXISTS(SELECT 1 FROM public.motoristas m WHERE m.id=e.motorista_id AND m.user_id=auth.uid())
  OR ec_private.tracking_active(e.id,e.rota_id,e.motorista_id) IS NOT TRUE THEN
  RAISE EXCEPTION 'Avise somente o próximo atendimento liberado da sua rota ativa.' USING ERRCODE='42501'; END IF;
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Token inválido.'; END IF;
 IF e.destinatario_telefone IS NULL OR e.destinatario_telefone !~ '^[1-9][0-9]{9,14}$' THEN RAISE EXCEPTION 'WhatsApp do cliente não cadastrado ou inválido.'; END IF;
 h:=sha256(convert_to(p_token,'UTF8'));
 SELECT * INTO t FROM ec_private.customer_tracking WHERE entrega_id=e.id;
 IF t.token_hash=h AND (t.expires_at<=now() OR t.cliente_endereco_id IS DISTINCT FROM e.cliente_endereco_id OR t.recipient_phone IS DISTINCT FROM e.destinatario_telefone) THEN
  RETURN jsonb_build_object('sucesso',false,'codigo','EXPIRADO','mensagem','Gere um novo link.'); END IF;
 -- Repeated taps reuse the same valid link; a new device/token revokes the old one.
 INSERT INTO ec_private.customer_tracking(entrega_id,rota_id,motorista_id,token_hash,cliente_endereco_id,recipient_phone)
 VALUES(e.id,e.rota_id,e.motorista_id,h,e.cliente_endereco_id,e.destinatario_telefone)
 ON CONFLICT(entrega_id) DO UPDATE SET rota_id=EXCLUDED.rota_id,motorista_id=EXCLUDED.motorista_id,
 token_hash=EXCLUDED.token_hash,cliente_endereco_id=EXCLUDED.cliente_endereco_id,recipient_phone=EXCLUDED.recipient_phone,expires_at=now()+interval '8 hours',latitude=NULL,longitude=NULL,observed_at=NULL,eta_at=NULL,eta_observed_at=NULL
 WHERE customer_tracking.token_hash<>EXCLUDED.token_hash OR customer_tracking.rota_id<>EXCLUDED.rota_id OR customer_tracking.motorista_id<>EXCLUDED.motorista_id OR customer_tracking.cliente_endereco_id<>EXCLUDED.cliente_endereco_id OR customer_tracking.recipient_phone<>EXCLUDED.recipient_phone;
 SELECT jsonb_build_object('sucesso',true,'empresa_nome',c.nome,'motorista_nome',COALESCE(NULLIF(btrim(p.nome),''),m.nome),
  'telefone',e.destinatario_telefone,'tipo_tarefa',e.tipo_tarefa,'descricao_outro',e.descricao_outro)
 INTO result FROM public.empresas c JOIN public.motoristas m ON m.id=e.motorista_id LEFT JOIN public.perfis_usuarios p ON p.id=m.user_id WHERE c.id=e.empresa_id;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.obter_meu_acompanhamento(p_rota_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE((SELECT jsonb_build_object('sucesso',true,'entrega_id',t.entrega_id,'latitude',a.latitude,'longitude',a.longitude)
 FROM ec_private.customer_tracking t JOIN public.entregas e ON e.id=t.entrega_id
 JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id
 JOIN public.motoristas m ON m.id=t.motorista_id
 WHERE t.rota_id=p_rota_id AND m.user_id=auth.uid() AND t.expires_at>now()
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id)
 AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone
 AND ec_private.tracking_active(e.id,t.rota_id,t.motorista_id) LIMIT 1),'{"sucesso":false}'::jsonb);
$$;

CREATE OR REPLACE FUNCTION public.publicar_localizacao_acompanhamento(p_entrega_id uuid,p_latitude double precision,p_longitude double precision,p_observada_em timestamptz,p_previsao_chegada_em timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR p_latitude IS NULL OR p_longitude IS NULL
 OR NOT(p_latitude BETWEEN -90 AND 90) OR NOT(p_longitude BETWEEN -180 AND 180)
 OR p_observada_em IS NULL OR p_observada_em NOT BETWEEN now()-interval '2 minutes' AND now()+interval '30 seconds'
 OR (p_previsao_chegada_em IS NOT NULL AND p_previsao_chegada_em NOT BETWEEN p_observada_em AND p_observada_em+interval '24 hours') THEN
 RETURN jsonb_build_object('sucesso',false); END IF;
 UPDATE ec_private.customer_tracking t SET latitude=p_latitude,longitude=p_longitude,observed_at=p_observada_em,
 eta_at=COALESCE(p_previsao_chegada_em,t.eta_at),eta_observed_at=CASE WHEN p_previsao_chegada_em IS NULL THEN t.eta_observed_at ELSE p_observada_em END
 FROM public.entregas e,public.motoristas m WHERE t.entrega_id=p_entrega_id AND e.id=t.entrega_id AND m.id=e.motorista_id AND m.user_id=auth.uid()
 AND t.expires_at>now() AND (t.observed_at IS NULL OR p_observada_em>t.observed_at)
 AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id)
 AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone
 AND ec_private.tracking_active(e.id,t.rota_id,t.motorista_id);
 RETURN jsonb_build_object('sucesso',FOUND);
END $$;

CREATE OR REPLACE FUNCTION public.obter_acompanhamento_cliente(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE t ec_private.customer_tracking%ROWTYPE; result jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('estado','indisponivel'); END IF;
 SELECT * INTO t FROM ec_private.customer_tracking WHERE token_hash=sha256(convert_to(p_token,'UTF8'));
 IF NOT FOUND THEN RETURN jsonb_build_object('estado','indisponivel'); END IF;
 IF t.expires_at<=now() OR ec_private.tracking_active(t.entrega_id,t.rota_id,t.motorista_id) IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM public.entregas e WHERE e.id=t.entrega_id AND e.cliente_endereco_id=t.cliente_endereco_id AND e.destinatario_telefone=t.recipient_phone) THEN
  RETURN jsonb_build_object('estado','encerrado'); END IF;
 SELECT jsonb_build_object('estado','ativo','empresa',c.nome,'tipo_tarefa',e.tipo_tarefa,
  'destino',jsonb_build_object('latitude',a.latitude,'longitude',a.longitude),
  'posicao',CASE WHEN t.observed_at IS NULL THEN NULL ELSE jsonb_build_object('latitude',t.latitude,'longitude',t.longitude) END,
  'atualizada_em',t.observed_at,'previsao_chegada_em',t.eta_at,'previsao_atualizada_em',t.eta_observed_at,'servidor_em',now())
 INTO result FROM public.entregas e JOIN public.empresas c ON c.id=e.empresa_id
 JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id WHERE e.id=t.entrega_id;
 RETURN COALESCE(result,jsonb_build_object('estado','indisponivel'));
END $$;
REVOKE ALL ON FUNCTION public.configurar_nome_empresa(uuid,text),public.preparar_aviso_cliente(uuid,text),public.obter_meu_acompanhamento(uuid),public.publicar_localizacao_acompanhamento(uuid,double precision,double precision,timestamptz,timestamptz),public.obter_acompanhamento_cliente(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configurar_nome_empresa(uuid,text),public.preparar_aviso_cliente(uuid,text),public.obter_meu_acompanhamento(uuid),public.publicar_localizacao_acompanhamento(uuid,double precision,double precision,timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_acompanhamento_cliente(text) TO anon,authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/functions-sql/obter_comprovante_publico.sql
-- ------------------------------------------------------------------------------

-- Compatibility endpoint for authenticated operations. UUID alone is never public authorization.
CREATE OR REPLACE FUNCTION public.obter_comprovante_publico(p_entrega_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('sucesso',true,'entrega_id',cp.entrega_id,'destinatario_nome',e.destinatario_nome,
  'endereco',COALESCE(to_jsonb(e)->>'endereco',a.endereco_completo),'empresa_nome',c.nome,
  'recebedor_tipo',cp.recebedor_tipo,'recebedor_nome',cp.recebedor_nome,'observacao',cp.observacao,
  'foto_path',cp.foto_path,'assinatura_path',cp.assinatura_path,'concluida_em',cp.concluida_em,'duracao_segundos',cp.duracao_segundos)
 INTO result FROM public.entrega_comprovantes cp JOIN public.entregas e ON e.id=cp.entrega_id AND e.empresa_id=cp.empresa_id
 JOIN public.empresas c ON c.id=cp.empresa_id LEFT JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id
 WHERE cp.entrega_id=p_entrega_id AND public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS TRUE;
 RETURN COALESCE(result,'{"sucesso":false}'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.obter_comprovante_publico(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_comprovante_publico(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/10_receipt_sharing.sql
-- ------------------------------------------------------------------------------

-- A share is scoped to one immutable receipt; the bucket itself remains private.
DROP POLICY IF EXISTS comprovante_publico_download ON storage.objects;
UPDATE storage.buckets SET public=false WHERE id='entregas-comprovantes';
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS ec_private.receipt_shares (
 entrega_id uuid PRIMARY KEY REFERENCES public.entrega_comprovantes(entrega_id) ON DELETE CASCADE,
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 criado_por uuid NOT NULL REFERENCES auth.users(id),
 token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
 expires_at timestamptz NOT NULL,
 foto_url text, assinatura_url text
);
CREATE INDEX IF NOT EXISTS receipt_shares_empresa_idx ON ec_private.receipt_shares(empresa_id);
CREATE INDEX IF NOT EXISTS receipt_shares_criado_por_idx ON ec_private.receipt_shares(criado_por);
ALTER TABLE ec_private.receipt_shares ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.receipt_shares FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION ec_private.receipt_url_matches(p_url text,p_path text) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT COALESCE(p_url IS NOT NULL AND p_path IS NOT NULL AND length(p_url)<=8192
  AND p_url ~ '^https://[a-zA-Z0-9.-]+(:[0-9]+)?/storage/v1/object/sign/entregas-comprovantes/'
  AND split_part(split_part(p_url,'?',1),'/storage/v1/object/sign/entregas-comprovantes/',2)=p_path
  AND p_url ~ '[?]token=[A-Za-z0-9_.-]+$',false);
$$;
REVOKE ALL ON FUNCTION ec_private.receipt_url_matches(text,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.criar_compartilhamento_comprovante(
 p_entrega_id uuid,p_token text,p_foto_url text DEFAULT NULL,p_assinatura_url text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE cp public.entrega_comprovantes%ROWTYPE; e public.entregas%ROWTYPE; expires timestamptz;
BEGIN
 SELECT * INTO cp FROM public.entrega_comprovantes WHERE entrega_id=p_entrega_id FOR UPDATE;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_e_gestor_empresa(cp.empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Apenas a gestão da empresa pode compartilhar este comprovante.' USING ERRCODE='42501'; END IF;
 SELECT * INTO e FROM public.entregas WHERE id=cp.entrega_id AND empresa_id=cp.empresa_id;
 IF NOT FOUND OR public.fn_usuario_pode_operar_motorista(e.empresa_id,e.motorista_id) IS NOT TRUE
  OR e.status NOT IN ('entregue','tentativa_falha') THEN
  RAISE EXCEPTION 'Comprovante indisponível para compartilhamento.' USING ERRCODE='42501'; END IF;
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Token inválido.'; END IF;
 IF (cp.foto_path IS NULL AND p_foto_url IS NOT NULL) OR (cp.foto_path IS NOT NULL AND NOT ec_private.receipt_url_matches(p_foto_url,cp.foto_path))
  OR (cp.assinatura_path IS NULL AND p_assinatura_url IS NOT NULL) OR (cp.assinatura_path IS NOT NULL AND NOT ec_private.receipt_url_matches(p_assinatura_url,cp.assinatura_path)) THEN
  RAISE EXCEPTION 'Gere as imagens temporárias deste comprovante antes de compartilhar.'; END IF;
 expires:=clock_timestamp()+interval '55 minutes';
 INSERT INTO ec_private.receipt_shares(entrega_id,empresa_id,criado_por,token_hash,expires_at,foto_url,assinatura_url)
 VALUES(cp.entrega_id,cp.empresa_id,auth.uid(),sha256(convert_to(p_token,'UTF8')),expires,p_foto_url,p_assinatura_url)
 ON CONFLICT(entrega_id) DO UPDATE SET criado_por=EXCLUDED.criado_por,token_hash=EXCLUDED.token_hash,expires_at=EXCLUDED.expires_at,
 foto_url=EXCLUDED.foto_url,assinatura_url=EXCLUDED.assinatura_url;
 RETURN jsonb_build_object('sucesso',true,'expira_em',expires,'servidor_em',clock_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.criar_compartilhamento_comprovante(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.criar_compartilhamento_comprovante(uuid,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obter_comprovante_compartilhado(p_token text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN '{"sucesso":false}'::jsonb; END IF;
 SELECT jsonb_build_object('sucesso',true,'entrega_id',cp.entrega_id,'destinatario_nome',e.destinatario_nome,
  'endereco',COALESCE(to_jsonb(e)->>'endereco',a.endereco_completo),'empresa_nome',c.nome,'tipo_tarefa',e.tipo_tarefa,
  'recebedor_tipo',cp.recebedor_tipo,'recebedor_nome',cp.recebedor_nome,'observacao',cp.observacao,
  'concluida_em',cp.concluida_em,'duracao_segundos',cp.duracao_segundos,
  'foto_url',s.foto_url,'assinatura_url',s.assinatura_url,'expira_em',s.expires_at,'servidor_em',now()) INTO result
 FROM ec_private.receipt_shares s
 JOIN public.entrega_comprovantes cp ON cp.entrega_id=s.entrega_id AND cp.empresa_id=s.empresa_id
 JOIN public.entregas e ON e.id=cp.entrega_id AND e.empresa_id=cp.empresa_id AND e.status IN ('entregue','tentativa_falha')
 JOIN public.empresas c ON c.id=s.empresa_id AND c.ativa
 LEFT JOIN public.clientes_enderecos a ON a.id=e.cliente_endereco_id AND a.empresa_id=e.empresa_id
 WHERE s.token_hash=sha256(convert_to(p_token,'UTF8')) AND s.expires_at>now()
  AND public.fn_usuario_e_gestor_empresa(s.empresa_id,s.criado_por) IS TRUE
  AND (cp.foto_path IS NULL AND s.foto_url IS NULL OR ec_private.receipt_url_matches(s.foto_url,cp.foto_path))
  AND (cp.assinatura_path IS NULL AND s.assinatura_url IS NULL OR ec_private.receipt_url_matches(s.assinatura_url,cp.assinatura_path));
 RETURN COALESCE(result,'{"sucesso":false}'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.obter_comprovante_compartilhado(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_comprovante_compartilhado(text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.revogar_compartilhamento_comprovante(p_entrega_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company uuid;
BEGIN
 SELECT empresa_id INTO company FROM public.entrega_comprovantes WHERE entrega_id=p_entrega_id;
 IF auth.uid() IS NULL OR NOT FOUND OR public.fn_usuario_e_gestor_empresa(company,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório nesta empresa.' USING ERRCODE='42501'; END IF;
 DELETE FROM ec_private.receipt_shares WHERE entrega_id=p_entrega_id AND empresa_id=company;
 RETURN '{"sucesso":true}'::jsonb;
END $$;
REVOKE ALL ON FUNCTION public.revogar_compartilhamento_comprovante(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.revogar_compartilhamento_comprovante(uuid) TO authenticated;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/11_company_trial.sql
-- ------------------------------------------------------------------------------

-- Company provisioning is atomic. Subscription dates and limits are server-owned.
CREATE SCHEMA IF NOT EXISTS ec_private;
REVOKE ALL ON SCHEMA ec_private FROM PUBLIC,anon,authenticated;
CREATE TABLE IF NOT EXISTS ec_private.assinaturas_empresas (
 empresa_id uuid PRIMARY KEY REFERENCES public.empresas(id) ON DELETE CASCADE,
 titular_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
 teste_inicio timestamptz NOT NULL DEFAULT now(),
 teste_fim timestamptz NOT NULL DEFAULT (now()+interval '30 days'),
 pago_ate timestamptz,
 suspensa boolean NOT NULL DEFAULT false,
 ambiente_pagamento text NOT NULL DEFAULT 'production' CHECK(ambiente_pagamento IN ('test','production')),
 valor_mensal numeric(10,2) NOT NULL DEFAULT 149.90 CHECK(valor_mensal=149.90),
 limite_motoristas integer NOT NULL DEFAULT 3 CHECK(limite_motoristas=3),
 limite_atendimentos integer NOT NULL DEFAULT 1000 CHECK(limite_atendimentos=1000),
 CHECK(teste_fim=teste_inicio+interval '30 days')
);
CREATE TABLE IF NOT EXISTS ec_private.uso_plano (
 empresa_id uuid NOT NULL REFERENCES ec_private.assinaturas_empresas(empresa_id) ON DELETE CASCADE,
 mes date NOT NULL, atendimentos integer NOT NULL DEFAULT 0 CHECK(atendimentos>=0),
 PRIMARY KEY(empresa_id,mes)
);
ALTER TABLE ec_private.assinaturas_empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE ec_private.uso_plano ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.assinaturas_empresas,ec_private.uso_plano FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION ec_private.empresa_assinatura_liberada(p_empresa_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT NOT EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas a WHERE a.empresa_id=p_empresa_id)
 OR EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas a WHERE a.empresa_id=p_empresa_id
  AND NOT a.suspensa AND greatest(a.teste_fim,a.pago_ate)>now());
$$;
REVOKE ALL ON FUNCTION ec_private.empresa_assinatura_liberada(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.iniciar_teste_empresa(p_nome_empresa text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u auth.users%ROWTYPE; m public.empresa_membros%ROWTYPE; company uuid; company_name text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT * INTO u FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 IF NOT FOUND OR u.email_confirmed_at IS NULL OR coalesce(u.is_anonymous,false) THEN
  RAISE EXCEPTION 'Confirme seu e-mail para iniciar o teste grátis.' USING ERRCODE='42501'; END IF;
 -- The auth.users row lock serializes retries and simultaneous first logins.
 SELECT * INTO m FROM public.empresa_membros WHERE user_id=u.id ORDER BY created_at DESC,id LIMIT 1;
 IF FOUND THEN
  IF m.status<>'aprovado' OR m.papel NOT IN ('admin','gestor') THEN
   RAISE EXCEPTION 'Sua conta já possui um vínculo empresarial. Consulte a gestão.' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('sucesso',true,'empresa_id',m.empresa_id,'existente',true);
 END IF;
 IF EXISTS(SELECT 1 FROM public.solicitacoes_acesso WHERE user_id=u.id) THEN
  RAISE EXCEPTION 'Sua conta já possui uma solicitação de acesso. Consulte a gestão.' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas WHERE titular_id=u.id) THEN
  RAISE EXCEPTION 'O teste desta conta já foi utilizado.' USING ERRCODE='42501'; END IF;
 -- User metadata supplies display text only; never a role, company id or validity.
 company_name:=btrim(coalesce(p_nome_empresa,u.raw_user_meta_data->>'empresa_nome',''));
 IF length(company_name) NOT BETWEEN 2 AND 120 THEN
  RAISE EXCEPTION 'Informe o nome da empresa entre 2 e 120 caracteres.' USING ERRCODE='22023'; END IF;
 INSERT INTO public.empresas(nome,codigo_convite,ativa)
 VALUES(company_name,'EC-'||upper(replace(gen_random_uuid()::text,'-','')),true) RETURNING id INTO company;
 INSERT INTO public.perfis_usuarios(id,email,nome)
 VALUES(u.id,u.email,coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'),''),nullif(btrim(u.raw_user_meta_data->>'name'),''),'Gestor'))
 ON CONFLICT(id) DO NOTHING;
 INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status,aprovado_em)
 VALUES(company,u.id,'admin','aprovado',now());
 INSERT INTO ec_private.assinaturas_empresas(empresa_id,titular_id) VALUES(company,u.id);
 RETURN jsonb_build_object('sucesso',true,'empresa_id',company,'existente',false,'teste_fim',now()+interval '30 days');
END;
$$;
REVOKE ALL ON FUNCTION public.iniciar_teste_empresa(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iniciar_teste_empresa(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obter_minha_assinatura(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a ec_private.assinaturas_empresas%ROWTYPE; used integer; active_drivers integer;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.empresa_membros m WHERE m.empresa_id=p_empresa_id
  AND m.user_id=auth.uid() AND m.status='aprovado') THEN
  RAISE EXCEPTION 'Acesso negado a esta empresa.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=p_empresa_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('legado',true,'operacional',true,'servidor_em',now()); END IF;
 SELECT coalesce(atendimentos,0) INTO used FROM ec_private.uso_plano
 WHERE empresa_id=p_empresa_id AND mes=date_trunc('month',now() AT TIME ZONE 'America/Sao_Paulo')::date;
 SELECT count(*) INTO active_drivers FROM public.motoristas WHERE empresa_id=p_empresa_id AND ativo;
 RETURN jsonb_build_object('legado',false,'operacional',ec_private.empresa_assinatura_liberada(p_empresa_id),
  'estado',CASE WHEN a.suspensa THEN 'suspensa' WHEN a.pago_ate>now() THEN 'ativa' WHEN a.teste_fim>now() THEN 'teste' ELSE 'expirada' END,
  'teste_fim',a.teste_fim,'pago_ate',a.pago_ate,'servidor_em',now(),
  'dias_restantes',greatest(0,ceil(extract(epoch FROM (greatest(a.teste_fim,a.pago_ate)-now()))/86400)),
  'valor_mensal',a.valor_mensal,'limite_motoristas',a.limite_motoristas,'limite_atendimentos',a.limite_atendimentos,
  'atendimentos_mes',coalesce(used,0),'motoristas_ativos',active_drivers);
END;
$$;
REVOKE ALL ON FUNCTION public.obter_minha_assinatura(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_minha_assinatura(uuid) TO authenticated;

-- A trigger also guards SECURITY DEFINER RPCs, so an old APK cannot bypass expiry.
CREATE OR REPLACE FUNCTION ec_private.proteger_operacao_assinatura()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company uuid; a ec_private.assinaturas_empresas%ROWTYPE; current_count integer;
BEGIN
 IF TG_TABLE_NAME='historico_atendimentos' THEN
  SELECT empresa_id INTO company FROM public.entregas WHERE id=coalesce(to_jsonb(NEW)->>'entrega_id',to_jsonb(OLD)->>'entrega_id')::uuid;
 ELSE
  company:=coalesce(to_jsonb(NEW)->>'empresa_id',to_jsonb(OLD)->>'empresa_id')::uuid;
 END IF;
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)->>'empresa_id') IS DISTINCT FROM (to_jsonb(OLD)->>'empresa_id') THEN
  RAISE EXCEPTION 'Não é permitido transferir registros entre empresas.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=company FOR UPDATE;
 -- Existing companies retain their current operation; no retroactive trial or reset.
 IF NOT FOUND OR auth.uid() IS NULL THEN
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
 END IF;
 IF NOT ec_private.empresa_assinatura_liberada(company) THEN
  RAISE EXCEPTION 'Seu período de acesso terminou. Assine o plano para continuar operando.' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='motoristas' AND TG_OP<>'DELETE' THEN
  IF NEW.ativo THEN
  SELECT count(*) INTO current_count FROM public.motoristas WHERE empresa_id=company AND ativo AND id<>NEW.id;
  IF current_count>=a.limite_motoristas THEN
   RAISE EXCEPTION 'O plano permite até 3 motoristas ativos.' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
CREATE OR REPLACE FUNCTION ec_private.contar_atendimento_plano()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE cap integer; total integer;
BEGIN
 SELECT limite_atendimentos INTO cap FROM ec_private.assinaturas_empresas WHERE empresa_id=NEW.empresa_id FOR UPDATE;
 IF FOUND THEN
  INSERT INTO ec_private.uso_plano(empresa_id,mes,atendimentos)
  VALUES(NEW.empresa_id,date_trunc('month',now() AT TIME ZONE 'America/Sao_Paulo')::date,1)
  ON CONFLICT(empresa_id,mes) DO UPDATE SET atendimentos=ec_private.uso_plano.atendimentos+1
  RETURNING atendimentos INTO total;
  IF total>cap THEN RAISE EXCEPTION 'O plano permite até 1.000 atendimentos por mês.' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION ec_private.proteger_operacao_assinatura(),ec_private.contar_atendimento_plano() FROM PUBLIC,anon,authenticated;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['motoristas','clientes_enderecos','rotas_planejadas','entregas','entrega_comprovantes','pedidos_fluxo','empresa_membros','veiculos_motoristas','veiculos_documentos','historico_atendimentos'] LOOP
  EXECUTE format('DROP TRIGGER IF EXISTS assinatura_operacional ON public.%I',t);
  EXECUTE format('CREATE TRIGGER assinatura_operacional BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION ec_private.proteger_operacao_assinatura()',t);
 END LOOP;
END $$;
DROP TRIGGER IF EXISTS assinatura_cota_atendimentos ON public.entregas;
CREATE TRIGGER assinatura_cota_atendimentos AFTER INSERT ON public.entregas FOR EACH ROW EXECUTE FUNCTION ec_private.contar_atendimento_plano();

-- Remove legacy permissive policies: a permissive USING(true) defeats other RLS.
DROP POLICY IF EXISTS "Acesso empresas" ON public.empresas;
DROP POLICY IF EXISTS "Acesso membros" ON public.empresa_membros;
DROP POLICY IF EXISTS "Acesso perfis" ON public.perfis_usuarios;
DROP POLICY IF EXISTS "Acesso total a motoristas para membros da empresa" ON public.motoristas;
DROP POLICY IF EXISTS "Acesso a entregas para autenticados" ON public.entregas;
DROP POLICY IF EXISTS "Acesso a rotas para autenticados" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Acesso a clientes enderecos para autenticados" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Permitir exclusao de enderecos" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Usuarios visualizam empresas das quais sao membros" ON public.empresas;
CREATE POLICY "Usuarios visualizam empresas das quais sao membros" ON public.empresas FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public.empresa_membros m WHERE m.empresa_id=empresas.id AND m.user_id=(SELECT auth.uid())));
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['empresas','perfis_usuarios','empresa_membros','solicitacoes_acesso','auditoria_acessos','motoristas','veiculos_motoristas','veiculos_documentos','clientes_enderecos','rotas_planejadas','entregas','historico_atendimentos','storage_limpeza_fila'] LOOP
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated',t);
  EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
 END LOOP;
END $$;
GRANT UPDATE(nome,telefone,avatar_url) ON public.perfis_usuarios TO authenticated;
-- Keep the existing headquarters-city preference writable by its own manager.
GRANT UPDATE(cidade) ON public.empresas TO authenticated;
DROP POLICY IF EXISTS "Gestao configura cidade da propria empresa" ON public.empresas;
CREATE POLICY "Gestao configura cidade da propria empresa" ON public.empresas FOR UPDATE TO authenticated
USING(public.fn_usuario_e_gestor_empresa(id,auth.uid()))
WITH CHECK(public.fn_usuario_e_gestor_empresa(id,auth.uid()));
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon',p.oid,'EXECUTE')
   AND p.proname NOT IN ('obter_acompanhamento_cliente','obter_comprovante_compartilhado') LOOP
  EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC,anon',f.signature);
  IF f.proname NOT IN ('rls_auto_enable','bootstrap_primeiro_gestor') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.signature); END IF;
 END LOOP;
END $$;

-- The old manual bootstrap is maintenance-only; it can self-approve an admin.
REVOKE ALL ON FUNCTION public.bootstrap_primeiro_gestor(text,text,text) FROM PUBLIC,anon,authenticated;

-- Operational driver RPCs stop when the trial ends, including public tracking.
CREATE OR REPLACE FUNCTION public.fn_usuario_pode_operar_motorista(
    p_empresa_id UUID, p_motorista_id UUID
)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
    SELECT auth.uid() IS NOT NULL AND ec_private.empresa_assinatura_liberada(p_empresa_id) AND EXISTS (
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
-- MÓDULO: supabase/modules-sql/12_subscription_payments.sql
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ec_private.checkouts_assinatura (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_id uuid NOT NULL UNIQUE REFERENCES ec_private.assinaturas_empresas(empresa_id) ON DELETE CASCADE,
 preapproval_id text UNIQUE, url text, criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS ec_private.pagamentos_assinatura (
 pagamento_id text PRIMARY KEY,
 checkout_id uuid NOT NULL REFERENCES ec_private.checkouts_assinatura(id),
 status text NOT NULL, aprovado_em timestamptz, atualizado_em timestamptz NOT NULL,
 cobertura_ate timestamptz, valor numeric(10,2) NOT NULL CHECK(valor=149.90)
);
ALTER TABLE ec_private.checkouts_assinatura ENABLE ROW LEVEL SECURITY;
ALTER TABLE ec_private.pagamentos_assinatura ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.checkouts_assinatura,ec_private.pagamentos_assinatura FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.preparar_checkout_assinatura(p_empresa_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a ec_private.assinaturas_empresas%ROWTYPE; c ec_private.checkouts_assinatura%ROWTYPE; email text;
BEGIN
 IF auth.uid() IS NULL OR public.fn_usuario_e_gestor_empresa(p_empresa_id,auth.uid()) IS NOT TRUE THEN
  RAISE EXCEPTION 'Acesso de gestão obrigatório.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=p_empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Esta empresa não possui uma assinatura comercial.' USING ERRCODE='22023'; END IF;
 IF a.teste_fim>now() OR a.pago_ate>now() THEN RAISE EXCEPTION 'Seu período de acesso ainda está ativo.' USING ERRCODE='22023'; END IF;
 SELECT u.email INTO email FROM auth.users u WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL;
 IF email IS NULL THEN RAISE EXCEPTION 'Confirme seu e-mail.' USING ERRCODE='42501'; END IF;
 INSERT INTO ec_private.checkouts_assinatura(empresa_id) VALUES(p_empresa_id) ON CONFLICT(empresa_id) DO NOTHING;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE empresa_id=p_empresa_id;
 RETURN jsonb_build_object('id',c.id,'email',email,'url',c.url,'preapproval_id',c.preapproval_id,'valor',a.valor_mensal,'ambiente',a.ambiente_pagamento);
END;
$$;
CREATE OR REPLACE FUNCTION public.vincular_checkout_assinatura(p_checkout_id uuid,p_preapproval_id text,p_url text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 IF p_checkout_id IS NULL OR p_preapproval_id IS NULL OR p_url IS NULL OR p_preapproval_id !~ '^[A-Za-z0-9_-]{1,100}$' OR p_url !~ '^https://(www\.)?mercadopago\.com\.br/' THEN
  RAISE EXCEPTION 'Resposta de checkout inválida.' USING ERRCODE='22023'; END IF;
 UPDATE ec_private.checkouts_assinatura SET preapproval_id=p_preapproval_id,url=p_url
 WHERE id=p_checkout_id AND (preapproval_id IS NULL OR preapproval_id=p_preapproval_id);
 RETURN FOUND;
END;
$$;
CREATE OR REPLACE FUNCTION public.registrar_pagamento_assinatura(
 p_checkout_id uuid,p_preapproval_id text,p_pagamento_id text,p_status text,p_valor numeric,
 p_moeda text,p_aprovado_em timestamptz,p_atualizado_em timestamptz,p_ambiente text DEFAULT 'production')
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c ec_private.checkouts_assinatura%ROWTYPE; a ec_private.assinaturas_empresas%ROWTYPE;
 payment ec_private.pagamentos_assinatura%ROWTYPE; coverage timestamptz;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 IF p_valor IS DISTINCT FROM 149.90 OR p_moeda IS DISTINCT FROM 'BRL'
  OR p_pagamento_id IS NULL OR p_pagamento_id !~ '^[0-9]{1,30}$'
  OR p_status IS NULL OR p_status NOT IN ('approved','pending','in_process','rejected','cancelled','refunded','charged_back')
  OR p_atualizado_em IS NULL OR p_atualizado_em>now()+interval '5 minutes' THEN
  RAISE EXCEPTION 'Pagamento incompatível com o plano.' USING ERRCODE='22023'; END IF;
 SELECT * INTO c FROM ec_private.checkouts_assinatura WHERE id=p_checkout_id AND preapproval_id=p_preapproval_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Assinatura não vinculada a esta empresa.' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM ec_private.assinaturas_empresas WHERE empresa_id=c.empresa_id FOR UPDATE;
 IF p_ambiente IS DISTINCT FROM a.ambiente_pagamento THEN
  RAISE EXCEPTION 'O ambiente do pagamento não corresponde ao cadastro.' USING ERRCODE='42501'; END IF;
 SELECT * INTO payment FROM ec_private.pagamentos_assinatura WHERE pagamento_id=p_pagamento_id;
 IF FOUND THEN
  IF payment.checkout_id<>c.id THEN RAISE EXCEPTION 'Pagamento já vinculado a outro cadastro.' USING ERRCODE='42501'; END IF;
  IF payment.atualizado_em>=p_atualizado_em THEN RETURN true; END IF;
  coverage:=payment.cobertura_ate;
 END IF;
 IF p_status='approved' THEN
  IF p_aprovado_em IS NULL OR p_aprovado_em>now()+interval '5 minutes' THEN
   RAISE EXCEPTION 'Confirmação de pagamento inválida.' USING ERRCODE='22023'; END IF;
  IF coverage IS NULL THEN coverage:=greatest(p_aprovado_em,a.pago_ate,a.teste_fim)+interval '1 month'; END IF;
 END IF;
 INSERT INTO ec_private.pagamentos_assinatura(pagamento_id,checkout_id,status,aprovado_em,atualizado_em,cobertura_ate,valor)
 VALUES(p_pagamento_id,c.id,p_status,p_aprovado_em,p_atualizado_em,coverage,p_valor)
 ON CONFLICT(pagamento_id) DO UPDATE SET status=excluded.status,aprovado_em=excluded.aprovado_em,
  atualizado_em=excluded.atualizado_em,cobertura_ate=excluded.cobertura_ate;
 UPDATE ec_private.assinaturas_empresas SET
  pago_ate=(SELECT max(p.cobertura_ate) FROM ec_private.pagamentos_assinatura p
   JOIN ec_private.checkouts_assinatura x ON x.id=p.checkout_id WHERE x.empresa_id=c.empresa_id AND p.status='approved'),
  suspensa=EXISTS(SELECT 1 FROM ec_private.pagamentos_assinatura p JOIN ec_private.checkouts_assinatura x ON x.id=p.checkout_id
   WHERE x.empresa_id=c.empresa_id AND p.status='charged_back')
 WHERE empresa_id=c.empresa_id;
 RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.preparar_checkout_assinatura(uuid),public.vincular_checkout_assinatura(uuid,text,text),
 public.registrar_pagamento_assinatura(uuid,text,text,text,numeric,text,timestamptz,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.preparar_checkout_assinatura(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vincular_checkout_assinatura(uuid,text,text),
 public.registrar_pagamento_assinatura(uuid,text,text,text,numeric,text,timestamptz,timestamptz,text) TO service_role;

CREATE OR REPLACE FUNCTION public.obter_contexto_pagamento_assinatura(p_pagamento_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Operação exclusiva do servidor.' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object('checkout_id',c.id,'preapproval_id',c.preapproval_id) INTO result
 FROM ec_private.pagamentos_assinatura p JOIN ec_private.checkouts_assinatura c ON c.id=p.checkout_id WHERE p.pagamento_id=p_pagamento_id;
 RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.obter_contexto_pagamento_assinatura(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obter_contexto_pagamento_assinatura(text) TO service_role;

-- ------------------------------------------------------------------------------
-- MÓDULO: supabase/modules-sql/13_trial_registration.sql
-- ------------------------------------------------------------------------------

-- Private registration data is never copied into auth metadata or public companies.
-- The document ledger intentionally survives account/company deletion.
CREATE TABLE IF NOT EXISTS ec_private.documentos_teste (
 tipo_pessoa text NOT NULL CHECK(tipo_pessoa IN ('pf','pj')),
 documento text NOT NULL,
 empresa_id uuid REFERENCES public.empresas(id) ON DELETE SET NULL,
 titular_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 teste_inicio timestamptz NOT NULL DEFAULT now(),
 teste_fim timestamptz NOT NULL DEFAULT (now()+interval '30 days'),
 PRIMARY KEY(tipo_pessoa,documento),
 CHECK(teste_fim=teste_inicio+interval '30 days')
);
CREATE TABLE IF NOT EXISTS ec_private.cadastros_empresas (
 empresa_id uuid PRIMARY KEY REFERENCES public.empresas(id) ON DELETE CASCADE,
 tipo_pessoa text NOT NULL,
 documento text NOT NULL,
 nome_responsavel text NOT NULL CHECK(length(nome_responsavel) BETWEEN 3 AND 120),
 razao_social text,
 nome_fantasia text,
 celular text NOT NULL CHECK(celular ~ '^[1-9][0-9]9[0-9]{8}$'),
 email text NOT NULL,
 cadastrado_em timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tipo_pessoa,documento) REFERENCES ec_private.documentos_teste(tipo_pessoa,documento),
 CHECK(tipo_pessoa='pf' OR length(razao_social) BETWEEN 2 AND 120)
);
ALTER TABLE ec_private.documentos_teste ENABLE ROW LEVEL SECURITY;
ALTER TABLE ec_private.cadastros_empresas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ec_private.documentos_teste,ec_private.cadastros_empresas FROM PUBLIC,anon,authenticated;

-- CPF and numeric/alphanumeric CNPJ check digits. This validates format, NOT ownership.
CREATE OR REPLACE FUNCTION ec_private.documento_valido(p_tipo text,p_documento text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE doc text:=upper(regexp_replace(coalesce(p_documento,''),'[./[:space:]-]','','g'));
 total integer; digit integer; i integer; pass integer; base integer; weights integer[];
BEGIN
 IF doc ~ '^(.)\1+$' THEN RETURN false; END IF;
 IF p_tipo='pf' THEN
  IF doc !~ '^[0-9]{11}$' THEN RETURN false; END IF;
  FOR pass IN 1..2 LOOP
   total:=0; base:=8+pass;
   FOR i IN 1..base LOOP total:=total+substr(doc,i,1)::integer*(base+2-i); END LOOP;
   digit:=(total*10)%11; IF digit=10 THEN digit:=0; END IF;
   IF digit<>substr(doc,base+1,1)::integer THEN RETURN false; END IF;
  END LOOP;
 ELSIF p_tipo='pj' THEN
  IF doc !~ '^[A-Z0-9]{12}[0-9]{2}$' THEN RETURN false; END IF;
  FOR pass IN 1..2 LOOP
   weights:=CASE WHEN pass=1 THEN ARRAY[5,4,3,2,9,8,7,6,5,4,3,2] ELSE ARRAY[6,5,4,3,2,9,8,7,6,5,4,3,2] END;
   total:=0; base:=11+pass;
   FOR i IN 1..base LOOP total:=total+(ascii(substr(doc,i,1))-48)*weights[i]; END LOOP;
   digit:=CASE WHEN total%11<2 THEN 0 ELSE 11-total%11 END;
   IF digit<>substr(doc,base+1,1)::integer THEN RETURN false; END IF;
  END LOOP;
 ELSE RETURN false;
 END IF;
 RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION ec_private.documento_valido(text,text) FROM PUBLIC,anon,authenticated;

-- Keep the old RPC only as an idempotent lookup for existing managers.
-- Older frontends and direct RPC calls cannot create a trial without registration.
CREATE OR REPLACE FUNCTION public.iniciar_teste_empresa(p_nome_empresa text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE m public.empresa_membros%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT * INTO m FROM public.empresa_membros WHERE user_id=auth.uid() ORDER BY created_at DESC,id LIMIT 1;
 IF FOUND AND m.status='aprovado' AND m.papel IN ('admin','gestor') THEN
  RETURN jsonb_build_object('sucesso',true,'empresa_id',m.empresa_id,'existente',true);
 END IF;
 RAISE EXCEPTION 'Complete o cadastro de pessoa física ou jurídica para iniciar o teste.' USING ERRCODE='42501';
END;
$$;
REVOKE ALL ON FUNCTION public.iniciar_teste_empresa(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.iniciar_teste_empresa(text) TO authenticated;

-- Definer is required to atomically provision membership and write private tables.
-- Identity comes only from auth.uid(); client-supplied dates, IDs and roles are ignored.
CREATE OR REPLACE FUNCTION public.registrar_teste_empresa(p_cadastro jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u auth.users%ROWTYPE; m public.empresa_membros%ROWTYPE; company uuid;
 kind text:=p_cadastro->>'tipo_pessoa';
 doc text:=upper(regexp_replace(coalesce(p_cadastro->>'documento',''),'[./[:space:]-]','','g'));
 person text:=btrim(coalesce(p_cadastro->>'nome_responsavel',''));
 legal_name text:=btrim(coalesce(p_cadastro->>'razao_social',''));
 trade_name text:=btrim(coalesce(p_cadastro->>'nome_fantasia',''));
 phone text:=regexp_replace(coalesce(p_cadastro->>'celular',''),'[()[:space:]-]','','g');
 company_name text; claimed integer;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta.' USING ERRCODE='42501'; END IF;
 SELECT * INTO u FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 IF NOT FOUND OR u.email_confirmed_at IS NULL OR coalesce(u.is_anonymous,false) THEN
  RAISE EXCEPTION 'Confirme seu e-mail para iniciar o teste grátis.' USING ERRCODE='42501'; END IF;
 SELECT * INTO m FROM public.empresa_membros WHERE user_id=u.id ORDER BY created_at DESC,id LIMIT 1;
 IF FOUND THEN
  IF m.status<>'aprovado' OR m.papel NOT IN ('admin','gestor') THEN
   RAISE EXCEPTION 'Sua conta já possui um vínculo empresarial. Consulte a gestão.' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('sucesso',true,'empresa_id',m.empresa_id,'existente',true);
 END IF;
 IF EXISTS(SELECT 1 FROM public.solicitacoes_acesso WHERE user_id=u.id)
 OR EXISTS(SELECT 1 FROM ec_private.assinaturas_empresas WHERE titular_id=u.id)
 OR EXISTS(SELECT 1 FROM ec_private.documentos_teste WHERE titular_id=u.id) THEN
  RAISE EXCEPTION 'Esta conta já possui cadastro. Entre na conta original ou contate o suporte para recuperar o acesso.' USING ERRCODE='42501'; END IF;
 IF NOT ec_private.documento_valido(kind,doc) THEN
  RAISE EXCEPTION 'Informe um CPF ou CNPJ válido para o tipo de cadastro selecionado.' USING ERRCODE='22023'; END IF;
 IF length(person) NOT BETWEEN 3 AND 120 OR length(trade_name)>120
 OR (kind='pj' AND length(legal_name) NOT BETWEEN 2 AND 120)
 OR phone !~ '^[1-9][0-9]9[0-9]{8}$' THEN
  RAISE EXCEPTION 'Confira o nome, os dados da empresa e o celular com DDD.' USING ERRCODE='22023'; END IF;
 -- Unique index serializes simultaneous registrations, including different accounts.
 -- Avoid returning a constraint error containing the document value.
 INSERT INTO ec_private.documentos_teste(tipo_pessoa,documento,titular_id)
 VALUES(kind,doc,u.id) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS claimed=ROW_COUNT;
 IF claimed=0 THEN
  RAISE EXCEPTION 'Não foi possível liberar um novo teste com este documento. Entre na conta original ou contate o suporte para recuperar o acesso.' USING ERRCODE='42501'; END IF;
 company_name:=coalesce(nullif(trade_name,''),CASE WHEN kind='pj' THEN legal_name ELSE person END);
 INSERT INTO public.empresas(nome,codigo_convite,ativa)
 VALUES(company_name,'EC-'||upper(replace(gen_random_uuid()::text,'-','')),true) RETURNING id INTO company;
 INSERT INTO public.perfis_usuarios(id,email,nome) VALUES(u.id,u.email,person)
 ON CONFLICT(id) DO UPDATE SET nome=excluded.nome,email=excluded.email;
 INSERT INTO public.empresa_membros(empresa_id,user_id,papel,status,aprovado_em)
 VALUES(company,u.id,'admin','aprovado',now());
 INSERT INTO ec_private.assinaturas_empresas(empresa_id,titular_id) VALUES(company,u.id);
 UPDATE ec_private.documentos_teste SET empresa_id=company WHERE tipo_pessoa=kind AND documento=doc;
 INSERT INTO ec_private.cadastros_empresas(empresa_id,tipo_pessoa,documento,nome_responsavel,razao_social,nome_fantasia,celular,email)
 VALUES(company,kind,doc,person,CASE WHEN kind='pj' THEN legal_name ELSE NULL END,nullif(trade_name,''),phone,u.email);
 RETURN jsonb_build_object('sucesso',true,'empresa_id',company,'existente',false,'teste_fim',now()+interval '30 days');
END;
$$;
REVOKE ALL ON FUNCTION public.registrar_teste_empresa(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_teste_empresa(jsonb) TO authenticated;

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
