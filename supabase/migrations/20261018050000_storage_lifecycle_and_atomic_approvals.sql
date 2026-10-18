-- ==============================================================================
-- MIGRAÇÃO: 20261018050000_storage_lifecycle_and_atomic_approvals.sql
-- Coordenação explícita de ciclo de vida do Storage, persistência de fila de limpeza,
-- aprovação atômica sem mutações parciais, obrigatoriedade estrita de revisão e
-- alinhamento canônico de todas as RPCs de veículo e documentos.
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

-- 2. Fila persistente e auditável de limpeza do Storage
CREATE TABLE IF NOT EXISTS public.storage_limpeza_fila (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id VARCHAR(100) NOT NULL DEFAULT 'veiculos-documentos',
    storage_path TEXT NOT NULL,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    motivo TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'em_processamento', 'concluido', 'falhou')),
    tentativas INT NOT NULL DEFAULT 0,
    max_tentativas INT NOT NULL DEFAULT 5,
    ultimo_erro TEXT,
    autorizado_em TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    processado_em TIMESTAMPTZ,
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
    public.fn_usuario_e_gestor_empresa(empresa_id) OR user_id = auth.uid()
);

-- 3. Função auditada para registrar resultado da limpeza física do Storage
CREATE OR REPLACE FUNCTION public.registrar_limpeza_storage_executada(
    p_fila_id UUID,
    p_sucesso BOOLEAN,
    p_erro TEXT DEFAULT NULL
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

    -- Permissão: condutor proprietário do arquivo ou gestor da empresa
    IF v_item.user_id != auth.uid() AND NOT public.fn_usuario_e_gestor_empresa(v_item.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Sem permissão para registrar limpeza deste item.'
        );
    END IF;

    IF p_sucesso THEN
        UPDATE public.storage_limpeza_fila
        SET status = 'concluido',
            tentativas = tentativas + 1,
            ultimo_erro = NULL,
            processado_em = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_item.id;
    ELSE
        UPDATE public.storage_limpeza_fila
        SET status = CASE WHEN tentativas + 1 >= max_tentativas THEN 'falhou' ELSE 'pendente' END,
            tentativas = tentativas + 1,
            ultimo_erro = p_erro,
            processado_em = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_item.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'LIMPEZA_REGISTRADA',
        'status', CASE WHEN p_sucesso THEN 'concluido' WHEN v_item.tentativas + 1 >= v_item.max_tentativas THEN 'falhou' ELSE 'pendente' END
    );
END;
$$;

-- 4. Políticas de Ciclo de Vida e Acesso no schema storage.objects
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
    NOT EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
          AND slf.status IN ('pendente', 'em_processamento', 'concluido')
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
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
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
    ) AND
    NOT EXISTS (
        SELECT 1
        FROM public.storage_limpeza_fila slf
        WHERE slf.storage_path = name
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
    ) AND
    (
        EXISTS (
            SELECT 1
            FROM public.storage_limpeza_fila slf
            WHERE slf.storage_path = name
              AND slf.status IN ('pendente', 'em_processamento')
        )
        OR
        NOT EXISTS (
            SELECT 1
            FROM public.storage_limpeza_fila slf
            WHERE slf.storage_path = name
        )
    )
);

-- 5. Revogação de sobrecargas antigas
DROP FUNCTION IF EXISTS public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS public.analisar_veiculo_motorista(UUID, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR);
DROP FUNCTION IF EXISTS public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, INT);

-- 6. Validação centralizada de completude
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

-- 7. Cadastro de veículos pelo condutor
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

    IF v_tipo_veiculo = 'carro' THEN
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

    SELECT * INTO v_veiculo_existente
    FROM public.veiculos_motoristas
    WHERE user_id = v_user_id;

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

-- 8. Análise técnica de veículos pela gestão
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_veiculo.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem analisar veículos.'
        );
    END IF;

    IF p_aprovar THEN
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
        IF p_motivo_rejeicao IS NULL OR TRIM(p_motivo_rejeicao) = '' THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTIVO_OBRIGATORIO',
                'mensagem', 'Informe a justificativa da rejeição do veículo.'
            );
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

-- 9. Anexação coordenada de documentos veiculares
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
    v_fila_id UUID := NULL;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

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

    IF (public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    IF p_tipo_documento NOT IN ('foto_veiculo', 'crlv', 'complementar') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TIPO_DOCUMENTO_INVALIDO',
            'mensagem', 'Tipo de documento deve ser foto_veiculo, crlv ou complementar.'
        );
    END IF;

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

    IF EXISTS (
        SELECT 1 FROM public.storage_limpeza_fila
        WHERE storage_path = TRIM(p_storage_path)
          AND status IN ('pendente', 'em_processamento', 'concluido')
    ) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_EM_LIMPEZA',
            'mensagem', 'Este objeto do Storage está em processo de limpeza ou já foi descartado e não pode ser vinculado.'
        );
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
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_JA_VINCULADO',
            'mensagem', 'Este caminho de arquivo já está vinculado a outro registro de documento ativo.'
        );
    END IF;

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

    IF p_tamanho_bytes <= 0 OR p_tamanho_bytes > 10485760 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TAMANHO_EXCEDIDO',
            'mensagem', 'O arquivo deve ter entre 1 byte e 10 MB.'
        );
    END IF;

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

    IF p_tipo_documento = 'foto_veiculo' AND v_mime_type = 'application/pdf' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'FOTO_NAO_ACEITA_PDF',
            'mensagem', 'Fotos do veículo devem ser imagens nos formatos JPG ou PNG.'
        );
    END IF;

    IF p_tipo_documento = 'foto_veiculo' THEN
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

            IF v_old_storage_path IS NOT NULL AND v_old_storage_path != TRIM(p_storage_path) THEN
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
                RETURNING id INTO v_fila_id;
            END IF;
        END IF;

    ELSIF p_tipo_documento = 'crlv' THEN
        SELECT storage_path INTO v_old_storage_path
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'crlv';

        IF FOUND THEN
            DELETE FROM public.veiculos_documentos
            WHERE veiculo_id = v_veiculo.id
              AND tipo_documento = 'crlv';

            IF v_old_storage_path IS NOT NULL AND v_old_storage_path != TRIM(p_storage_path) THEN
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
                RETURNING id INTO v_fila_id;
            END IF;
        END IF;

    ELSIF p_tipo_documento = 'complementar' THEN
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
        'limpeza_fila_id', v_fila_id
    );
END;
$$;

-- 10. Desvinculação coordenada de documentos veiculares
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
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

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

    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = v_doc.veiculo_id
    FOR UPDATE;

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
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Você não possui autorização para remover esta evidência.'
        );
    END IF;

    DELETE FROM public.veiculos_documentos WHERE id = v_doc.id;

    INSERT INTO public.storage_limpeza_fila (
        bucket_id,
        storage_path,
        empresa_id,
        user_id,
        motivo,
        status
    ) VALUES (
        'veiculos-documentos',
        v_doc.storage_path,
        v_doc.empresa_id,
        v_user_id,
        'remocao_documento_veiculo',
        'pendente'
    )
    RETURNING id INTO v_fila_id;

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

-- 11. Aprovação atômica sem mutações parciais
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem aprovar solicitações.'
        );
    END IF;

    IF v_solicitacao.status = 'aprovado' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'JA_APROVADO',
            'mensagem', 'Esta solicitação já foi aprovada anteriormente.',
            'motorista_id', v_solicitacao.motorista_vinculado_id
        );
    END IF;

    IF NOT p_criar_novo_motorista THEN
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

    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE user_id = v_solicitacao.user_id
    FOR UPDATE;

    IF p_aprovar_veiculo THEN
        IF v_veiculo.id IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'VEICULO_NAO_ENCONTRADO',
                'mensagem', 'O condutor não possui veículo declarado para aprovação.'
            );
        END IF;

        IF p_revisao_esperada_veiculo IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'REVISAO_OBRIGATORIA',
                'mensagem', 'A revisão esperada do veículo é obrigatória para aprovar o veículo.'
            );
        END IF;

        IF v_veiculo.revisao != p_revisao_esperada_veiculo THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'REVISAO_DESATUALIZADA',
                'mensagem', 'O veículo do condutor foi alterado durante a análise (revisão atual: ' || v_veiculo.revisao || ', esperada: ' || p_revisao_esperada_veiculo || '). Atualize e revise a versão atual antes de decidir.',
                'revisao_esperada', p_revisao_esperada_veiculo,
                'revisao_atual', v_veiculo.revisao
            );
        END IF;

        v_validacao_veic := public.fn_validar_completude_veiculo(v_veiculo.id);
        IF (v_validacao_veic->>'valido')::boolean != TRUE THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', v_validacao_veic->>'codigo',
                'mensagem', 'Veículo não atende aos requisitos para aprovação: ' || (v_validacao_veic->>'mensagem')
            );
        END IF;
    END IF;

    IF p_criar_novo_motorista THEN
        SELECT * INTO v_perfil FROM public.perfis_usuarios WHERE id = v_solicitacao.user_id;

        v_nome_final := COALESCE(NULLIF(TRIM(p_nome_motorista), ''), v_perfil.nome, 'Motorista Operacional');
        v_telefone_final := COALESCE(NULLIF(TRIM(p_telefone_motorista), ''), v_perfil.telefone, '(00) 00000-0000');
        v_modelo_final := CASE 
            WHEN v_veiculo.id IS NOT NULL THEN (v_veiculo.marca || ' ' || v_veiculo.modelo)
            ELSE 'Veículo Declarado'
        END;
        v_placa_final := COALESCE(v_veiculo.placa, 'SEM-PLACA');

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
        UPDATE public.motoristas
        SET user_id = v_solicitacao.user_id,
            ativo = TRUE,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_motorista.id;

        v_motorista_final_id := v_motorista.id;
    END IF;

    IF p_aprovar_veiculo AND v_veiculo.id IS NOT NULL THEN
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
    END IF;

    UPDATE public.solicitacoes_acesso
    SET status = 'aprovado',
        motorista_vinculado_id = v_motorista_final_id,
        motivo_decisao = 'Aprovado pela gestão',
        decidido_por = auth.uid(),
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

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

-- 12. Privilégios estritos e revogações
REVOKE EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, BOOLEAN, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registrar_limpeza_storage_executada(UUID, BOOLEAN, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_validar_completude_veiculo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cadastrar_meu_veiculo(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.analisar_veiculo_motorista(UUID, BOOLEAN, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anexar_documento_veiculo(UUID, TEXT, TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remover_documento_veiculo(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aprovar_solicitacao_motorista(UUID, UUID, BOOLEAN, TEXT, VARCHAR, BOOLEAN, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_limpeza_storage_executada(UUID, BOOLEAN, TEXT) TO authenticated;

-- 13. Políticas RLS das tabelas públicas (alinhamento estrito)
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

DROP POLICY IF EXISTS "Leitura de membros por membros da empresa" ON public.empresa_membros;
CREATE POLICY "Leitura de membros por membros da empresa"
ON public.empresa_membros FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

DROP POLICY IF EXISTS "Leitura de solicitacoes pelo usuario ou gestao" ON public.solicitacoes_acesso;
CREATE POLICY "Leitura de solicitacoes pelo usuario ou gestao"
ON public.solicitacoes_acesso FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

DROP POLICY IF EXISTS "Gestores leem auditoria da empresa" ON public.auditoria_acessos;
CREATE POLICY "Gestores leem auditoria da empresa"
ON public.auditoria_acessos FOR SELECT
TO authenticated
USING (
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

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

DROP POLICY IF EXISTS "Leitura de veiculos por condutor ou gestao" ON public.veiculos_motoristas;
CREATE POLICY "Leitura de veiculos por condutor ou gestao"
ON public.veiculos_motoristas FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

DROP POLICY IF EXISTS "Leitura de documentos por condutor ou gestao" ON public.veiculos_documentos;
CREATE POLICY "Leitura de documentos por condutor ou gestao"
ON public.veiculos_documentos FOR SELECT
TO authenticated
USING (
    user_id = auth.uid() OR
    public.fn_usuario_e_gestor_empresa(empresa_id)
);

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

