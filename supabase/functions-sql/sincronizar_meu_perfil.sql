-- ==============================================================================
-- FUNÇÃO SQL: sincronizar_meu_perfil.sql
-- Garante sincronização automática do perfil a partir do auth.users.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.sincronizar_meu_perfil()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user RECORD;
    v_nome TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'mensagem', 'Não autenticado.');
    END IF;

    SELECT * INTO v_user FROM auth.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', FALSE, 'mensagem', 'Usuário não encontrado em auth.users.');
    END IF;

    v_nome := COALESCE(
        v_user.raw_user_meta_data->>'name',
        v_user.raw_user_meta_data->>'full_name',
        SPLIT_PART(v_user.email, '@', 1)
    );

    INSERT INTO public.perfis_usuarios (
        id,
        email,
        nome,
        avatar_url,
        updated_at
    ) VALUES (
        v_user_id,
        v_user.email,
        v_nome,
        v_user.raw_user_meta_data->>'avatar_url',
        timezone('utc'::text, now())
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        nome = COALESCE(perfis_usuarios.nome, EXCLUDED.nome),
        updated_at = timezone('utc'::text, now());

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'mensagem', 'Perfil sincronizado com sucesso.'
    );
END;
$$;
