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
