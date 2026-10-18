-- ==============================================================================
-- FUNÇÃO SQL: solicitar_acesso_empresa.sql
-- Solicitação idempotente e restrita ao papel de motorista.
-- Impede sobrecargas inseguras ou solicitação direta de papéis administrativos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.solicitar_acesso_empresa(
    p_codigo_convite TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_empresa RECORD;
    v_membro_existente RECORD;
    v_solicitacao_existente RECORD;
    v_novo_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- 1. Localiza a empresa pelo código de convite ativo
    SELECT * INTO v_empresa
    FROM public.empresas
    WHERE UPPER(TRIM(codigo_convite)) = UPPER(TRIM(p_codigo_convite))
      AND ativa = TRUE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EMPRESA_NAO_ENCONTRADA',
            'mensagem', 'Código de convite inválido ou empresa inativa.'
        );
    END IF;

    -- 2. Verifica se o usuário já possui vínculo com esta empresa
    SELECT * INTO v_membro_existente
    FROM public.empresa_membros
    WHERE empresa_id = v_empresa.id AND user_id = v_user_id;

    IF FOUND THEN
        IF v_membro_existente.status = 'aprovado' THEN
            RETURN jsonb_build_object(
                'sucesso', TRUE,
                'codigo', 'JA_APROVADO',
                'mensagem', 'Você já é um membro aprovado desta empresa.',
                'empresa_id', v_empresa.id,
                'empresa_nome', v_empresa.nome
            );
        ELSIF v_membro_existente.status = 'suspenso' THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'USUARIO_SUSPENSO',
                'mensagem', 'Seu acesso a esta empresa está suspenso. Contate a gestão.'
            );
        END IF;
    END IF;

    -- 3. Verifica se já existe solicitação pendente (idempotência)
    SELECT * INTO v_solicitacao_existente
    FROM public.solicitacoes_acesso
    WHERE empresa_id = v_empresa.id AND user_id = v_user_id;

    IF FOUND AND v_solicitacao_existente.status = 'pendente' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'SOLICITACAO_EXISTENTE',
            'mensagem', 'Sua solicitação anterior já está pendente de análise pela gestão.',
            'empresa_id', v_empresa.id,
            'empresa_nome', v_empresa.nome,
            'solicitacao_id', v_solicitacao_existente.id
        );
    END IF;

    -- 4. Registra solicitação estritamente com papel_solicitado = 'motorista'
    INSERT INTO public.solicitacoes_acesso (
        empresa_id,
        user_id,
        papel_solicitado,
        status,
        motivo_decisao,
        created_at,
        updated_at
    ) VALUES (
        v_empresa.id,
        v_user_id,
        'motorista',
        'pendente',
        NULL,
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel_solicitado = 'motorista',
        status = 'pendente',
        motivo_decisao = NULL,
        decidido_por = NULL,
        decidido_em = NULL,
        updated_at = timezone('utc'::text, now())
    RETURNING id INTO v_novo_id;

    -- Cria ou atualiza membro em estado pendente
    INSERT INTO public.empresa_membros (
        empresa_id,
        user_id,
        papel,
        status,
        updated_at
    ) VALUES (
        v_empresa.id,
        v_user_id,
        'motorista',
        'pendente',
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        status = CASE 
            WHEN empresa_membros.status = 'aprovado' THEN 'aprovado'
            ELSE 'pendente' 
        END,
        updated_at = timezone('utc'::text, now());

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'SOLICITACAO_REGISTRADA',
        'mensagem', 'Solicitação de acesso enviada com sucesso.',
        'empresa_id', v_empresa.id,
        'empresa_nome', v_empresa.nome,
        'solicitacao_id', v_novo_id
    );
END;
$$;
