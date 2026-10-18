-- ==============================================================================
-- FUNÇÃO SQL: rejeitar_solicitacao_acesso.sql
-- Rejeição auditada com motivo obrigatório.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.rejeitar_solicitacao_acesso(
    p_solicitacao_id UUID,
    p_motivo TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_solicitacao RECORD;
BEGIN
    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTIVO_OBRIGATORIO',
            'mensagem', 'Informe o motivo da rejeição para registro de auditoria.'
        );
    END IF;

    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE id = p_solicitacao_id;

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
            'mensagem', 'Apenas gestores ou administradores desta empresa podem rejeitar solicitações.'
        );
    END IF;

    -- Atualiza solicitação
    UPDATE public.solicitacoes_acesso
    SET status = 'rejeitado',
        motivo_decisao = TRIM(p_motivo),
        decidido_por = auth.uid(),
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

    -- Atualiza status de membro para rejeitado
    UPDATE public.empresa_membros
    SET status = 'rejeitado',
        motivo_decisao = TRIM(p_motivo),
        updated_at = timezone('utc'::text, now())
    WHERE empresa_id = v_solicitacao.empresa_id
      AND user_id = v_solicitacao.user_id;

    -- Auditoria
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
        v_solicitacao.empresa_id,
        v_solicitacao.user_id,
        'rejeicao_solicitacao',
        v_solicitacao.status,
        'rejeitado',
        TRIM(p_motivo),
        auth.uid(),
        jsonb_build_object('solicitacao_id', v_solicitacao.id)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'SOLICITACAO_REJEITADA',
        'mensagem', 'Solicitação rejeitada com sucesso.'
    );
END;
$$;
