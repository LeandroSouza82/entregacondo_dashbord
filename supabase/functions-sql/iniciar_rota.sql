-- ==============================================================================
-- FUNÇÃO SQL: iniciar_rota.sql
-- Início de execução da rota pelo condutor atribuído. Idempotente.
-- ==============================================================================

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
    SET status = 'em_execucao'
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

