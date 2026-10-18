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
