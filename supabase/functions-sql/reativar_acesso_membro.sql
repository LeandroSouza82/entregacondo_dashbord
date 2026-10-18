-- ==============================================================================
-- FUNÇÃO SQL: reativar_acesso_membro.sql
-- Reativação de membros anteriormente suspensos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.reativar_acesso_membro(
    p_membro_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
BEGIN
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores desta empresa podem reativar acessos.'
        );
    END IF;

    -- Atualiza status para aprovado
    UPDATE public.empresa_membros
    SET status = 'aprovado',
        motivo_decisao = 'Acesso reativado pela gestão',
        aprovado_por = auth.uid(),
        aprovado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_membro.id;

    -- Reativa motorista da frota se houver
    IF v_membro.motorista_id IS NOT NULL THEN
        UPDATE public.motoristas
        SET ativo = TRUE,
            status = 'disponivel',
            updated_at = timezone('utc'::text, now())
        WHERE id = v_membro.motorista_id;
    END IF;

    -- Auditoria
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
        v_membro.empresa_id,
        v_membro.user_id,
        'reativacao_acesso',
        v_membro.status,
        'aprovado',
        v_membro.motorista_id,
        'Reativação pela gestão',
        auth.uid(),
        jsonb_build_object('membro_id', v_membro.id)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ACESSO_REATIVADO',
        'mensagem', 'Acesso operacional do membro reativado com sucesso.'
    );
END;
$$;
