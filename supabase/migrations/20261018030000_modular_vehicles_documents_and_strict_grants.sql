-- ==============================================================================
-- MIGRATION: 20261018030000_modular_vehicles_documents_and_strict_grants.sql
-- Módulo: Alinhamento VEICULO_MOBILE.md (4 fotos por ângulo, CRLV, validação Storage),
-- Instalação Completa das RPCs Auditadas, Ciclo de Vida de Evidências e Fechamento Estrito de Grants.
-- Suporta atualização a partir da versão anterior (20261018020000).
-- ==============================================================================

-- 1. DIAGNÓSTICO SEGURO DE REGISTROS ÓRFÃOS SEM EMPRESA (SEM DELETES CEGOS)
DO $$
DECLARE
    v_orfaos_mot INT;
    v_orfaos_end INT;
    v_orfaos_rot INT;
    v_orfaos_ent INT;
BEGIN
    SELECT COUNT(*) INTO v_orfaos_mot FROM public.motoristas WHERE empresa_id IS NULL;
    SELECT COUNT(*) INTO v_orfaos_end FROM public.clientes_enderecos WHERE empresa_id IS NULL;
    SELECT COUNT(*) INTO v_orfaos_rot FROM public.rotas_planejadas WHERE empresa_id IS NULL;
    SELECT COUNT(*) INTO v_orfaos_ent FROM public.entregas WHERE empresa_id IS NULL;

    IF (v_orfaos_mot + v_orfaos_end + v_orfaos_rot + v_orfaos_ent) > 0 THEN
        RAISE EXCEPTION 'MIGRAÇÃO INTERROMPIDA: Existem registros órfãos sem empresa_id que exigem decisão administrativa manual antes de aplicar NOT NULL: motoristas (%), enderecos (%), rotas (%), entregas (%). Nenhum dado foi apagado automaticamente.',
            v_orfaos_mot, v_orfaos_end, v_orfaos_rot, v_orfaos_ent;
    END IF;
END $$;

-- 2. FUNÇÕES AUXILIARES DE SEGURANÇA E AUTORIZAÇÃO CENTRALIZADA
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

-- 3. AJUSTES NA TABELA veiculos_motoristas PARA VEICULO_MOBILE.md
ALTER TABLE public.veiculos_motoristas 
    ADD COLUMN IF NOT EXISTS tamanho_compartimento VARCHAR(20) 
    CHECK (tamanho_compartimento IN ('pequeno', 'medio', 'grande'));

ALTER TABLE public.veiculos_motoristas 
    ADD COLUMN IF NOT EXISTS revisao INT NOT NULL DEFAULT 1;

-- Atualização das restrições de compatibilidade (aceita 'bag')
ALTER TABLE public.veiculos_motoristas 
    DROP CONSTRAINT IF EXISTS chk_veiculo_regras_tipo;
ALTER TABLE public.veiculos_motoristas 
    DROP CONSTRAINT IF EXISTS chk_veiculo_contrato_mobile;

ALTER TABLE public.veiculos_motoristas 
    ADD CONSTRAINT chk_veiculo_contrato_mobile CHECK (
        (
            tipo_veiculo = 'carro' AND
            compartimento IS NULL AND
            volume_litros IS NULL AND
            tamanho_compartimento IS NULL AND
            capacidade_kg IS NULL
        )
        OR
        (
            tipo_veiculo = 'moto' AND
            compartimento = 'bau' AND
            volume_litros IS NOT NULL AND volume_litros > 0 AND
            tamanho_compartimento IS NULL AND
            capacidade_kg IS NOT NULL AND capacidade_kg > 0
        )
        OR
        (
            tipo_veiculo = 'moto' AND
            compartimento IN ('mochila', 'bag') AND
            tamanho_compartimento IS NOT NULL AND
            volume_litros IS NULL AND
            capacidade_kg IS NOT NULL AND capacidade_kg > 0
        )
    );

-- 4. TABELA DE METADADOS: veiculos_documentos (Suporte a 4 Fotos por Ângulo e CRLV)
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
    tamanho_bytes INT NOT NULL CHECK (tamanho_bytes > 0 AND tamanho_bytes <= 10485760),
    status_analise VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status_analise IN ('pendente', 'aprovado', 'rejeitado')),
    motivo_rejeicao TEXT,
    analisado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    analisado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT chk_foto_formato CHECK (
        tipo_documento != 'foto_veiculo' OR mime_type IN ('image/jpeg', 'image/png')
    ),

    CONSTRAINT chk_angulo_coerencia CHECK (
        (tipo_documento = 'foto_veiculo') OR
        (tipo_documento IN ('crlv', 'complementar') AND angulo_foto IS NULL)
    )
);

ALTER TABLE public.veiculos_documentos
    ADD COLUMN IF NOT EXISTS angulo_foto VARCHAR(30) 
    CHECK (angulo_foto IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira'));

CREATE UNIQUE INDEX IF NOT EXISTS uq_veiculo_foto_angulo 
ON public.veiculos_documentos (veiculo_id, angulo_foto) 
WHERE tipo_documento = 'foto_veiculo' AND angulo_foto IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_veiculo_crlv_ativo 
ON public.veiculos_documentos (veiculo_id) 
WHERE tipo_documento = 'crlv';

ALTER TABLE public.veiculos_documentos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Leitura de documentos por condutor ou gestao" ON public.veiculos_documentos;
CREATE POLICY "Leitura de documentos por condutor ou gestao"
ON public.veiculos_documentos FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

-- 5. BUCKET PRIVADO E POLÍTICAS DE STORAGE SEGURAS
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'veiculos-documentos',
    'veiculos-documentos',
    FALSE,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
    public = FALSE,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'application/pdf'];

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
        public.fn_usuario_e_gestor_empresa(public.fn_safe_uuid(split_part(name, '/', 1)))
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.veiculos_documentos vd
        WHERE vd.storage_path = name
    )
);

-- 6. REMOÇÃO DE SOBRECARGAS OBSOLETAS
DROP FUNCTION IF EXISTS public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS public.analisar_veiculo_motorista(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR);

-- 7. INSTALAÇÃO DAS DEFINIÇÕES ATUALIZADAS DAS RPCS

-- A. Validação Centralizada de Veículo
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
    SELECT * INTO v_veiculo FROM public.veiculos_motoristas WHERE id = p_veiculo_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('valido', FALSE, 'codigo', 'VEICULO_NAO_ENCONTRADO', 'mensagem', 'Veículo não encontrado.');
    END IF;

    IF v_veiculo.tipo_veiculo = 'carro' THEN
        IF NULLIF(TRIM(v_veiculo.marca), '') IS NULL OR NULLIF(TRIM(v_veiculo.modelo), '') IS NULL OR NULLIF(TRIM(v_veiculo.placa), '') IS NULL THEN
            RETURN jsonb_build_object('valido', FALSE, 'codigo', 'DADOS_CARRO_INCOMPLETOS', 'mensagem', 'Carro com dados cadastrais incompletos.');
        END IF;
        IF v_veiculo.compartimento IS NOT NULL OR v_veiculo.volume_litros IS NOT NULL OR v_veiculo.tamanho_compartimento IS NOT NULL OR v_veiculo.capacidade_kg IS NOT NULL THEN
            RETURN jsonb_build_object('valido', FALSE, 'codigo', 'CARRO_CAMPOS_INDEVIDOS', 'mensagem', 'Carro não aceita carga nesta versão.');
        END IF;
    ELSIF v_veiculo.tipo_veiculo = 'moto' THEN
        IF NULLIF(TRIM(v_veiculo.marca), '') IS NULL OR NULLIF(TRIM(v_veiculo.modelo), '') IS NULL OR NULLIF(TRIM(v_veiculo.placa), '') IS NULL THEN
            RETURN jsonb_build_object('valido', FALSE, 'codigo', 'DADOS_MOTO_INCOMPLETOS', 'mensagem', 'Moto com dados cadastrais incompletos.');
        END IF;
        IF v_veiculo.capacidade_kg IS NULL OR v_veiculo.capacidade_kg <= 0 THEN
            RETURN jsonb_build_object('valido', FALSE, 'codigo', 'CAPACIDADE_KG_OBRIGATORIA', 'mensagem', 'Capacidade em kg obrigatória.');
        END IF;
        IF v_veiculo.compartimento = 'bau' THEN
            IF v_veiculo.volume_litros IS NULL OR v_veiculo.volume_litros <= 0 OR v_veiculo.tamanho_compartimento IS NOT NULL THEN
                RETURN jsonb_build_object('valido', FALSE, 'codigo', 'VOLUME_LITROS_OBRIGATORIO', 'mensagem', 'Moto baú exige litros positivo.');
            END IF;
        ELSIF v_veiculo.compartimento IN ('mochila', 'bag') THEN
            IF v_veiculo.tamanho_compartimento IS NULL OR v_veiculo.tamanho_compartimento NOT IN ('pequeno', 'medio', 'grande') OR v_veiculo.volume_litros IS NOT NULL THEN
                RETURN jsonb_build_object('valido', FALSE, 'codigo', 'TAMANHO_CATEGORICO_OBRIGATORIO', 'mensagem', 'Moto mochila/bag exige tamanho: pequeno, medio ou grande.');
            END IF;
        ELSE
            RETURN jsonb_build_object('valido', FALSE, 'codigo', 'COMPARTIMENTO_INVALIDO', 'mensagem', 'Compartimento de moto inválido.');
        END IF;
    END IF;

    SELECT array_agg(DISTINCT angulo_foto) INTO v_angulos_presentes
    FROM public.veiculos_documentos
    WHERE veiculo_id = v_veiculo.id AND tipo_documento = 'foto_veiculo' AND angulo_foto IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira');

    IF v_angulos_presentes IS NULL OR array_length(v_angulos_presentes, 1) < 4 THEN
        RETURN jsonb_build_object('valido', FALSE, 'codigo', 'FOTOS_INCOMPLETAS', 'mensagem', 'O veículo não possui as 4 fotos obrigatórias.');
    END IF;

    SELECT COUNT(*) INTO v_qtd_crlv FROM public.veiculos_documentos WHERE veiculo_id = v_veiculo.id AND tipo_documento = 'crlv';
    IF v_qtd_crlv < 1 THEN
        RETURN jsonb_build_object('valido', FALSE, 'codigo', 'CRLV_AUSENTE', 'mensagem', 'O documento CRLV é obrigatório.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        RETURN jsonb_build_object('valido', FALSE, 'codigo', 'INFRAESTRUTURA_STORAGE_INDISPONIVEL', 'mensagem', 'A infraestrutura de Storage não está acessível no banco de dados para reconfirmação das evidências.');
    END IF;

    FOR v_doc IN (
        SELECT id, tipo_documento, angulo_foto, storage_path, nome_arquivo
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id AND (tipo_documento = 'crlv' OR (tipo_documento = 'foto_veiculo' AND angulo_foto IS NOT NULL))
    ) LOOP
        SELECT metadata INTO v_storage_meta FROM storage.objects WHERE bucket_id = 'veiculos-documentos' AND name = v_doc.storage_path;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('valido', FALSE, 'codigo', 'ARQUIVO_FISICO_AUSENTE', 'mensagem', 'Arquivo de ' || COALESCE(v_doc.angulo_foto, v_doc.tipo_documento) || ' não localizado no Storage.');
        END IF;
    END LOOP;

    RETURN jsonb_build_object('valido', TRUE, 'codigo', 'COMPLETO', 'mensagem', 'Veículo validado com sucesso.', 'veiculo_id', v_veiculo.id, 'revisao', v_veiculo.revisao);
END;
$$;

-- B. Cadastrar Meu Veículo
CREATE OR REPLACE FUNCTION public.cadastrar_meu_veiculo(p_dados JSONB)
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
    v_novo_id UUID;
    v_revisao_nova INT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'NAO_AUTENTICADO', 'mensagem', 'Usuário não autenticado.');
    END IF;

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
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'SEM_VINCULO_EMPRESA', 'mensagem', 'Solicite acesso a uma empresa antes de cadastrar o veículo.');
    END IF;

    IF (public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(v_empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    v_tipo_veiculo := LOWER(TRIM(p_dados->>'tipo_veiculo'));
    v_marca := TRIM(p_dados->>'marca');
    v_modelo := TRIM(p_dados->>'modelo');
    v_placa := UPPER(REGEXP_REPLACE(p_dados->>'placa', '[^a-zA-Z0-9]', '', 'g'));

    IF v_tipo_veiculo NOT IN ('moto', 'carro') THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'TIPO_VEICULO_INVALIDO', 'mensagem', 'Tipo de veículo deve ser "moto" ou "carro".');
    END IF;
    IF v_marca IS NULL OR v_marca = '' THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MARCA_OBRIGATORIA', 'mensagem', 'Informe a marca do veículo.');
    END IF;
    IF v_modelo IS NULL OR v_modelo = '' THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MODELO_OBRIGATORIO', 'mensagem', 'Informe o modelo do veículo.');
    END IF;
    IF v_placa IS NULL OR LENGTH(v_placa) < 7 THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'PLACA_INVALIDA', 'mensagem', 'Informe uma placa válida.');
    END IF;

    IF v_tipo_veiculo = 'carro' THEN
        v_compartimento := NULL;
        v_volume_litros := NULL;
        v_tamanho_compartimento := NULL;
        v_capacidade_kg := NULL;
    ELSIF v_tipo_veiculo = 'moto' THEN
        v_compartimento := LOWER(TRIM(p_dados->>'compartimento'));
        IF v_compartimento NOT IN ('bau', 'mochila', 'bag') THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'COMPARTIMENTO_INVALIDO', 'mensagem', 'Compartimento deve ser "bau", "mochila" ou "bag".');
        END IF;
        IF p_dados->>'capacidade_kg' IS NULL OR (p_dados->>'capacidade_kg')::numeric <= 0 THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'CAPACIDADE_OBRIGATORIA', 'mensagem', 'Informe a capacidade disponível em kg (> 0).');
        END IF;
        v_capacidade_kg := (p_dados->>'capacidade_kg')::numeric;

        IF v_compartimento = 'bau' THEN
            IF p_dados->>'volume_litros' IS NULL OR (p_dados->>'volume_litros')::numeric <= 0 THEN
                RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'VOLUME_OBRIGATORIO', 'mensagem', 'Informe o volume do baú em litros (> 0).');
            END IF;
            v_volume_litros := (p_dados->>'volume_litros')::numeric;
            v_tamanho_compartimento := NULL;
        ELSE
            v_tamanho_compartimento := LOWER(TRIM(p_dados->>'tamanho_compartimento'));
            IF v_tamanho_compartimento NOT IN ('pequeno', 'medio', 'grande') THEN
                RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'TAMANHO_OBRIGATORIO', 'mensagem', 'Informe o tamanho do compartimento: pequeno, medio ou grande.');
            END IF;
            v_volume_litros := NULL;
        END IF;
    END IF;

    INSERT INTO public.veiculos_motoristas (
        user_id, empresa_id, tipo_veiculo, marca, modelo, placa, compartimento, volume_litros, tamanho_compartimento, capacidade_kg, status_analise, motivo_rejeicao, updated_at
    ) VALUES (
        v_user_id, v_empresa_id, v_tipo_veiculo, v_marca, v_modelo, v_placa, v_compartimento, v_volume_litros, v_tamanho_compartimento, v_capacidade_kg, 'pendente', NULL, timezone('utc'::text, now())
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

-- C. Anexar Documento Veículo
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
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'NAO_AUTENTICADO', 'mensagem', 'Usuário não autenticado.');
    END IF;

    SELECT * INTO v_veiculo 
    FROM public.veiculos_motoristas 
    WHERE id = p_veiculo_id AND user_id = v_user_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'VEICULO_NAO_ENCONTRADO', 'mensagem', 'Veículo não encontrado ou não pertence ao usuário.');
    END IF;

    IF (public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    IF p_tipo_documento NOT IN ('foto_veiculo', 'crlv', 'complementar') THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'TIPO_DOCUMENTO_INVALIDO', 'mensagem', 'Tipo de documento deve ser foto_veiculo, crlv ou complementar.');
    END IF;

    IF p_tipo_documento = 'foto_veiculo' THEN
        IF p_angulo_foto IS NULL OR p_angulo_foto NOT IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira') THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'ANGULO_INVALIDO', 'mensagem', 'Para foto_veiculo, informe ângulo: frente, lado_direito, lado_esquerdo ou traseira.');
        END IF;
    ELSE
        p_angulo_foto := NULL;
    END IF;

    v_parts := string_to_array(TRIM(p_storage_path), '/');
    IF array_length(v_parts, 1) < 3 THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'CAMINHO_STORAGE_INVALIDO', 'mensagem', 'Caminho fora do padrão seguro.');
    END IF;

    v_empresa_path := public.fn_safe_uuid(v_parts[1]);
    v_user_path := public.fn_safe_uuid(v_parts[2]);

    IF v_empresa_path IS NULL OR v_empresa_path != v_veiculo.empresa_id THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'EMPRESA_STORAGE_DIVERGENTE', 'mensagem', 'Prefixo de empresa não corresponde ao veículo.');
    END IF;
    IF v_user_path IS NULL OR v_user_path != v_user_id THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'USUARIO_STORAGE_DIVERGENTE', 'mensagem', 'Arquivo pertence a outro condutor.');
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.veiculos_documentos
        WHERE storage_path = TRIM(p_storage_path)
          AND (
            veiculo_id != v_veiculo.id OR
            tipo_documento != p_tipo_documento OR
            (tipo_documento = 'foto_veiculo' AND angulo_foto IS DISTINCT FROM p_angulo_foto)
          )
    ) THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'ARQUIVO_JA_VINCULADO', 'mensagem', 'Este caminho de arquivo já está vinculado a outro registro de documento ativo.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'INFRAESTRUTURA_STORAGE_INDISPONIVEL', 'mensagem', 'A infraestrutura de Storage não está acessível para validação do arquivo enviado.');
    END IF;

    SELECT metadata INTO v_storage_meta FROM storage.objects WHERE bucket_id = 'veiculos-documentos' AND name = TRIM(p_storage_path);
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'ARQUIVO_STORAGE_NAO_ENCONTRADO', 'mensagem', 'Arquivo físico não encontrado no Storage.');
    END IF;

    IF v_storage_meta IS NOT NULL AND (v_storage_meta ? 'size') THEN
        v_tamanho_real := (v_storage_meta->>'size')::bigint;
        IF v_tamanho_real > 10485760 THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'TAMANHO_EXCEDIDO', 'mensagem', 'Arquivo físico excede 10 MB.');
        END IF;
        p_tamanho_bytes := v_tamanho_real::int;
    END IF;

    IF v_storage_meta IS NOT NULL AND (v_storage_meta ? 'mimetype') THEN
        v_mime_real := LOWER(v_storage_meta->>'mimetype');
        IF v_mime_real NOT IN ('image/jpeg', 'image/png', 'application/pdf') THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MIMETYPE_STORAGE_INVALIDO', 'mensagem', 'Formato não permitido no Storage.');
        END IF;
    END IF;

    IF p_tamanho_bytes <= 0 OR p_tamanho_bytes > 10485760 THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'TAMANHO_EXCEDIDO', 'mensagem', 'Arquivo deve ter até 10 MB.');
    END IF;

    v_ext := LOWER(SUBSTRING(TRIM(p_nome_arquivo) FROM '\.([^\.]+)$'));
    IF v_ext IN ('jpg', 'jpeg') THEN v_mime_type := 'image/jpeg';
    ELSIF v_ext = 'png' THEN v_mime_type := 'image/png';
    ELSIF v_ext = 'pdf' THEN v_mime_type := 'application/pdf';
    ELSE RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'EXTENSAO_INVALIDA', 'mensagem', 'Extensão não suportada.');
    END IF;

    IF p_tipo_documento = 'foto_veiculo' AND v_mime_type = 'application/pdf' THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'FOTO_NAO_ACEITA_PDF', 'mensagem', 'Foto do veículo deve ser JPG ou PNG.');
    END IF;

    IF p_tipo_documento = 'foto_veiculo' THEN
        DELETE FROM public.veiculos_documentos WHERE veiculo_id = v_veiculo.id AND tipo_documento = 'foto_veiculo' AND angulo_foto = p_angulo_foto;
    ELSIF p_tipo_documento = 'crlv' THEN
        DELETE FROM public.veiculos_documentos WHERE veiculo_id = v_veiculo.id AND tipo_documento = 'crlv';
    ELSIF p_tipo_documento = 'complementar' THEN
        SELECT COUNT(*) INTO v_docs_count FROM public.veiculos_documentos WHERE veiculo_id = v_veiculo.id AND tipo_documento = 'complementar';
        IF v_docs_count >= 5 THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'LIMITE_DOCUMENTOS_EXCEDIDO', 'mensagem', 'Limite de 5 documentos complementares excedido.');
        END IF;
    END IF;

    INSERT INTO public.veiculos_documentos (
        veiculo_id, user_id, empresa_id, tipo_documento, angulo_foto, nome_arquivo, storage_path, mime_type, tamanho_bytes, status_analise
    ) VALUES (
        v_veiculo.id, v_user_id, v_veiculo.empresa_id, p_tipo_documento, p_angulo_foto, TRIM(p_nome_arquivo), TRIM(p_storage_path), v_mime_type, p_tamanho_bytes, 'pendente'
    ) RETURNING id INTO v_doc_id;

    IF v_veiculo.status_analise = 'aprovado' THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'pendente',
            motivo_rejeicao = 'Aprovação invalidada: nova evidência (' || COALESCE(p_angulo_foto, p_tipo_documento) || ') enviada para análise.',
            revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    ELSE
        UPDATE public.veiculos_motoristas
        SET revisao = revisao + 1, updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DOCUMENTO_ANEXADO',
        'mensagem', 'Anexo vinculado com sucesso.',
        'documento_id', v_doc_id,
        'angulo_foto', p_angulo_foto,
        'revisao', v_veiculo.revisao + 1
    );
END;
$$;

-- D. Remover Documento Veículo
CREATE OR REPLACE FUNCTION public.remover_documento_veiculo(p_documento_id UUID)
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
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'NAO_AUTENTICADO', 'mensagem', 'Usuário não autenticado.');
    END IF;

    SELECT * INTO v_doc FROM public.veiculos_documentos WHERE id = p_documento_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'DOCUMENTO_NAO_ENCONTRADO', 'mensagem', 'Documento não encontrado.');
    END IF;

    SELECT * INTO v_veiculo FROM public.veiculos_motoristas WHERE id = v_doc.veiculo_id FOR UPDATE;

    IF v_doc.user_id = v_user_id THEN
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
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Você não tem permissão para remover este documento.');
    END IF;

    DELETE FROM public.veiculos_documentos WHERE id = v_doc.id;

    IF v_veiculo.status_analise = 'aprovado' THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'pendente',
            motivo_rejeicao = 'Aprovação invalidada: evidência (' || COALESCE(v_doc.angulo_foto, v_doc.tipo_documento) || ') removida.',
            revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    ELSE
        UPDATE public.veiculos_motoristas
        SET revisao = revisao + 1, updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DOCUMENTO_REMOVIDO',
        'mensagem', 'Documento desvinculado com sucesso.',
        'storage_path', v_doc.storage_path,
        'veiculo_id', v_veiculo.id,
        'revisao', v_veiculo.revisao + 1
    );
END;
$$;

-- E. Analisar Veículo Motorista
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
    SELECT * INTO v_veiculo FROM public.veiculos_motoristas WHERE id = p_veiculo_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'VEICULO_NAO_ENCONTRADO', 'mensagem', 'Veículo não encontrado.');
    END IF;

    IF p_revisao_esperada IS NULL THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'REVISAO_OBRIGATORIA', 'mensagem', 'A revisão esperada do veículo é obrigatória para registrar a análise.');
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_veiculo.empresa_id) THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Apenas gestores desta empresa podem analisar veículos.');
    END IF;

    IF p_aprovar THEN
        v_validacao := public.fn_validar_completude_veiculo(v_veiculo.id);
        IF (v_validacao->>'valido')::boolean != TRUE THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', v_validacao->>'codigo', 'mensagem', v_validacao->>'mensagem');
        END IF;
        v_novo_status := 'aprovado';
    ELSE
        IF p_motivo_rejeicao IS NULL OR TRIM(p_motivo_rejeicao) = '' THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MOTIVO_OBRIGATORIO', 'mensagem', 'Informe a justificativa da rejeição do veículo.');
        END IF;
        v_novo_status := 'rejeitado';
    END IF;

    UPDATE public.veiculos_motoristas
    SET status_analise = v_novo_status,
        motivo_rejeicao = CASE WHEN p_aprovar THEN NULL ELSE TRIM(p_motivo_rejeicao) END,
        revisao = revisao + 1,
        analisado_por = auth.uid(),
        analisado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_veiculo.id;

    UPDATE public.veiculos_documentos
    SET status_analise = v_novo_status,
        motivo_rejeicao = CASE WHEN p_aprovar THEN NULL ELSE TRIM(p_motivo_rejeicao) END,
        analisado_por = auth.uid(),
        analisado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE veiculo_id = v_veiculo.id;

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motivo, executado_por, detalhes
    ) VALUES (
        v_veiculo.empresa_id, v_veiculo.user_id, 'analise_veiculo', v_veiculo.status_analise, v_novo_status, p_motivo_rejeicao, auth.uid(),
        jsonb_build_object(
            'veiculo_id', v_veiculo.id,
            'placa', v_veiculo.placa,
            'revisao_analisada', p_revisao_esperada,
            'revisao_gerada', v_veiculo.revisao + 1,
            'validacao_centralizada', v_validacao
        )
    );

    RETURN jsonb_build_object('sucesso', TRUE, 'codigo', 'ANALISE_CONCLUIDA', 'mensagem', 'Decisão registrada com sucesso.', 'status_analise', v_novo_status, 'revisao', v_veiculo.revisao + 1);
END;
$$;

-- F. Aprovar Solicitação Motorista
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
    SELECT * INTO v_solicitacao FROM public.solicitacoes_acesso WHERE id = p_solicitacao_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'SOLICITACAO_NAO_ENCONTRADA', 'mensagem', 'Solicitação de acesso não encontrada.');
    END IF;

    -- Valida autorização de gestão PRIMEIRO
    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id) THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Apenas gestores podem aprovar solicitações.');
    END IF;

    -- Idempotência
    IF v_solicitacao.status = 'aprovado' THEN
        RETURN jsonb_build_object('sucesso', TRUE, 'codigo', 'JA_APROVADO', 'mensagem', 'Solicitação já aprovada anteriormente.', 'motorista_id', v_solicitacao.motorista_vinculado_id);
    END IF;

    IF p_criar_novo_motorista THEN
        SELECT * INTO v_perfil FROM public.perfis_usuarios WHERE id = v_solicitacao.user_id;
        SELECT * INTO v_veiculo FROM public.veiculos_motoristas WHERE user_id = v_solicitacao.user_id FOR UPDATE;

        v_nome_final := COALESCE(NULLIF(TRIM(p_nome_motorista), ''), v_perfil.nome, 'Motorista Operacional');
        v_telefone_final := COALESCE(NULLIF(TRIM(p_telefone_motorista), ''), v_perfil.telefone, '(00) 00000-0000');
        v_modelo_final := CASE WHEN v_veiculo.id IS NOT NULL THEN (v_veiculo.marca || ' ' || v_veiculo.modelo) ELSE 'Veículo Declarado' END;
        v_placa_final := COALESCE(v_veiculo.placa, 'SEM-PLACA');

        INSERT INTO public.motoristas (
            empresa_id, user_id, nome, telefone, email, veiculo_modelo, veiculo_placa, status, ativo
        ) VALUES (
            v_solicitacao.empresa_id, v_solicitacao.user_id, v_nome_final, v_telefone_final, v_perfil.email, v_modelo_final, v_placa_final, 'disponivel', TRUE
        ) RETURNING id INTO v_motorista_final_id;

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
                SET status_analise = 'aprovado', revisao = revisao + 1, analisado_por = auth.uid(), analisado_em = timezone('utc'::text, now()), motivo_rejeicao = NULL, updated_at = timezone('utc'::text, now())
                WHERE id = v_veiculo.id;

                UPDATE public.veiculos_documentos
                SET status_analise = 'aprovado', analisado_por = auth.uid(), analisado_em = timezone('utc'::text, now()), motivo_rejeicao = NULL, updated_at = timezone('utc'::text, now())
                WHERE veiculo_id = v_veiculo.id;
            ELSE
                UPDATE public.veiculos_motoristas
                SET status_analise = 'pendente', updated_at = timezone('utc'::text, now())
                WHERE id = v_veiculo.id;
            END IF;
        END IF;
    ELSE
        IF p_motorista_id IS NULL THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MOTORISTA_OBRIGATORIO', 'mensagem', 'Informe o motorista para vínculo.');
        END IF;

        SELECT * INTO v_motorista FROM public.motoristas WHERE id = p_motorista_id AND empresa_id = v_solicitacao.empresa_id FOR UPDATE;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MOTORISTA_INVALIDO', 'mensagem', 'Motorista selecionado não pertence a esta empresa.');
        END IF;

        IF v_motorista.user_id IS NOT NULL AND v_motorista.user_id != v_solicitacao.user_id THEN
            RETURN jsonb_build_object('sucesso', FALSE, 'codigo', 'MOTORISTA_JA_VINCULADO', 'mensagem', 'Motorista já vinculado a outro usuário.');
        END IF;

        UPDATE public.motoristas SET user_id = v_solicitacao.user_id, ativo = TRUE, updated_at = timezone('utc'::text, now()) WHERE id = v_motorista.id;
        v_motorista_final_id := v_motorista.id;
    END IF;

    UPDATE public.solicitacoes_acesso
    SET status = 'aprovado', motorista_vinculado_id = v_motorista_final_id, motivo_decisao = 'Aprovado pela gestão', decidido_por = auth.uid(), decidido_em = timezone('utc'::text, now()), updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

    INSERT INTO public.empresa_membros (
        empresa_id, user_id, papel, status, motorista_id, motivo_decisao, aprovado_por, aprovado_em, updated_at
    ) VALUES (
        v_solicitacao.empresa_id, v_solicitacao.user_id, 'motorista', 'aprovado', v_motorista_final_id, 'Aprovado pela gestão', auth.uid(), timezone('utc'::text, now()), timezone('utc'::text, now())
    ) ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel = 'motorista', status = 'aprovado', motorista_id = v_motorista_final_id, motivo_decisao = 'Aprovado pela gestão', aprovado_por = auth.uid(), aprovado_em = timezone('utc'::text, now()), updated_at = timezone('utc'::text, now());

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motorista_id, motivo, executado_por, detalhes
    ) VALUES (
        v_solicitacao.empresa_id, v_solicitacao.user_id, 'aprovacao_motorista', v_solicitacao.status, 'aprovado', v_motorista_final_id, 'Aprovado pela gestão', auth.uid(),
        jsonb_build_object(
            'solicitacao_id', v_solicitacao.id,
            'criou_novo_motorista', p_criar_novo_motorista,
            'motorista_id', v_motorista_final_id,
            'veiculo_id', CASE WHEN v_veiculo.id IS NOT NULL THEN v_veiculo.id ELSE NULL END,
            'revisao_veiculo_analisada', p_revisao_esperada_veiculo,
            'veiculo_aprovado', CASE WHEN v_validacao_veic IS NOT NULL THEN (v_validacao_veic->>'valido')::boolean ELSE FALSE END
        )
    );

    RETURN jsonb_build_object('sucesso', TRUE, 'codigo', 'APROVADO_COM_SUCESSO', 'mensagem', 'Motorista aprovado e vinculado com sucesso.', 'motorista_id', v_motorista_final_id);
END;
$$;

-- 8. PERMISSÕES E GRANTS FINAIS
REVOKE ALL ON public.rotas_planejadas FROM anon, authenticated;
REVOKE ALL ON public.entregas FROM anon, authenticated;
REVOKE ALL ON public.motoristas FROM anon, authenticated;
REVOKE ALL ON public.veiculos_motoristas FROM anon, authenticated;
REVOKE ALL ON public.veiculos_documentos FROM anon, authenticated;

GRANT SELECT ON public.rotas_planejadas TO authenticated;
GRANT SELECT ON public.entregas TO authenticated;
GRANT SELECT ON public.motoristas TO authenticated;
GRANT SELECT ON public.veiculos_motoristas TO authenticated;
GRANT SELECT ON public.veiculos_documentos TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fn_validar_autorizacao_condutor(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, INT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_safe_uuid(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_usuario_pertence_empresa(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validar_autorizacao_condutor(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, INT) TO authenticated;
