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
    WHERE id = p_rota_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ROTA_NAO_ENCONTRADA',
            'mensagem', 'Rota planejada não encontrada.'
        );
    END IF;

    v_motorista_id := public.fn_motorista_id_do_usuario(v_user_id);

    IF v_motorista_id != v_rota.motorista_id AND NOT public.fn_usuario_e_gestor_empresa(v_rota.empresa_id) THEN
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
