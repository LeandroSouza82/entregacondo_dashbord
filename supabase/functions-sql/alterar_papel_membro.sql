-- ==============================================================================
-- FUNÇÃO SQL: alterar_papel_membro.sql
-- Alteração de papéis organizacionais (admin, gestor, motorista).
-- Exige estritamente papel de administrador da empresa.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.alterar_papel_membro(
    p_membro_id UUID,
    p_novo_papel TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
    v_novo_papel_norm VARCHAR(30);
BEGIN
    v_novo_papel_norm := LOWER(TRIM(p_novo_papel));

    IF v_novo_papel_norm NOT IN ('admin', 'gestor', 'motorista') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'PAPEL_INVALIDO',
            'mensagem', 'Papel inválido. Opções: admin, gestor, motorista.'
        );
    END IF;

    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE id = p_membro_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MEMBRO_NAO_ENCONTRADO',
            'mensagem', 'Membro da empresa não encontrado.'
        );
    END IF;

    -- REGRA DE SEGURANÇA: Apenas administradores da empresa podem alterar papéis
    IF NOT public.fn_usuario_e_admin_empresa(v_membro.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas administradores desta empresa têm permissão para alterar papéis.'
        );
    END IF;

    -- Atualiza papel
    UPDATE public.empresa_membros
    SET papel = v_novo_papel_norm,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_membro.id;

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
        v_membro.empresa_id,
        v_membro.user_id,
        'alteracao_papel',
        v_membro.papel,
        v_novo_papel_norm,
        'Alteração de papel por administrador',
        auth.uid(),
        jsonb_build_object('membro_id', v_membro.id, 'novo_papel', v_novo_papel_norm)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'PAPEL_ALTERADO',
        'mensagem', 'Papel do membro alterado com sucesso.',
        'novo_papel', v_novo_papel_norm
    );
END;
$$;
