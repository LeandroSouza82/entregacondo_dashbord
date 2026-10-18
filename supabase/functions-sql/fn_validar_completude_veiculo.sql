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
