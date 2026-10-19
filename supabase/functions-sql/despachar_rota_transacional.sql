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
