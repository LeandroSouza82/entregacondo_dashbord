-- ==============================================================================
-- FUNÇÃO SQL: suspender_acesso_membro.sql
-- Suspensão preventiva de acesso a rotas e dados operacionais.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.suspender_acesso_membro(
    p_membro_id UUID,
    p_motivo TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
BEGIN
    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'MOTIVO_OBRIGATORIO',
            'mensagem', 'Informe a justificativa da suspensão.'
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

    IF NOT public.fn_usuario_e_gestor_empresa(v_membro.empresa_id, auth.uid()) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores desta empresa podem suspender acessos.'
        );
    END IF;

    -- Não permite suspender a si mesmo
    IF v_membro.user_id = auth.uid() THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'AUTO_SUSPENSAO_PROIBIDA',
            'mensagem', 'Não é permitido suspender a própria conta.'
        );
    END IF;

    -- Atualiza status do membro para suspenso
    UPDATE public.empresa_membros
    SET status = 'suspenso',
        motivo_decisao = TRIM(p_motivo),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_membro.id;

    -- Desativa motorista da frota se houver
    IF v_membro.motorista_id IS NOT NULL THEN
        UPDATE public.motoristas
        SET ativo = FALSE,
            status = 'offline',
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
        'suspensao_acesso',
        v_membro.status,
        'suspenso',
        v_membro.motorista_id,
        TRIM(p_motivo),
        auth.uid(),
        jsonb_build_object('membro_id', v_membro.id)
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ACESSO_SUSPENSO',
        'mensagem', 'Acesso operacional do membro suspenso com sucesso.'
    );
END;
$$;
