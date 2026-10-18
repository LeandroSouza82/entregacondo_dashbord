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
