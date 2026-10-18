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
