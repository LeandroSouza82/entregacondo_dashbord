-- ==============================================================================
-- FUNÇÃO SQL: bootstrap_primeiro_gestor.sql
-- Inicialização controlada do primeiro administrador da empresa.
-- Executável estritamente pela service_role.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.bootstrap_primeiro_gestor(
    p_email_gestor TEXT,
    p_codigo_convite TEXT,
    p_nome_empresa TEXT DEFAULT 'EntregaCondo Matriz (Florianópolis)'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user RECORD;
    v_empresa RECORD;
BEGIN
    -- Busca usuário em auth.users
    SELECT * INTO v_user
    FROM auth.users
    WHERE LOWER(email) = LOWER(TRIM(p_email_gestor));

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'USUARIO_NAO_ENCONTRADO',
            'mensagem', 'Usuário com este e-mail ainda não criou conta no Supabase Auth.'
        );
    END IF;

    -- Cria ou obtém a empresa
    INSERT INTO public.empresas (
        nome,
        codigo_convite,
        cidade,
        uf,
        ativa
    ) VALUES (
        p_nome_empresa,
        UPPER(TRIM(p_codigo_convite)),
        'Florianópolis',
        'SC',
        TRUE
    )
    ON CONFLICT (codigo_convite) DO UPDATE SET ativa = TRUE
    RETURNING * INTO v_empresa;

    -- Garante perfil
    INSERT INTO public.perfis_usuarios (
        id,
        email,
        nome
    ) VALUES (
        v_user.id,
        v_user.email,
        COALESCE(v_user.raw_user_meta_data->>'full_name', v_user.raw_user_meta_data->>'name', 'Administrador')
    )
    ON CONFLICT (id) DO NOTHING;

    -- Define o usuário como administrador da empresa
    INSERT INTO public.empresa_membros (
        empresa_id,
        user_id,
        papel,
        status,
        aprovado_em
    ) VALUES (
        v_empresa.id,
        v_user.id,
        'admin',
        'aprovado',
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel = 'admin',
        status = 'aprovado',
        aprovado_em = timezone('utc'::text, now());

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'BOOTSTRAP_CONCLUIDO',
        'mensagem', 'Primeiro administrador configurado com sucesso.',
        'empresa_id', v_empresa.id,
        'empresa_nome', v_empresa.nome,
        'user_id', v_user.id
    );
END;
$$;
