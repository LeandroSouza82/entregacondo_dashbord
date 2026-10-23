-- ==============================================================================
-- MODULO SQL: 01b_helpers.sql
-- Funções auxiliares de autorização, contexto e validação de segurança.
-- DEFINIDAS ANTES de RPCs, Políticas de Storage e Políticas RLS.
-- ==============================================================================

-- 1. Helper para conversão segura de texto para UUID (evita crash em paths inválidos de storage)
CREATE OR REPLACE FUNCTION public.fn_safe_uuid(p_val TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
SET search_path=''
AS $$
BEGIN
    IF p_val IS NULL OR p_val !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN NULL;
    END IF;
    RETURN p_val::uuid;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

-- 2. Verifica se o usuário pertence a uma empresa com status aprovado
CREATE OR REPLACE FUNCTION public.fn_usuario_pertence_empresa(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros
        WHERE empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND status = 'aprovado'
    );
$$;

-- 3. Verifica se o usuário é gestor ou admin aprovado de uma empresa
CREATE OR REPLACE FUNCTION public.fn_usuario_e_gestor_empresa(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id AND e.ativa = TRUE
        WHERE em.empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND papel IN ('admin', 'gestor')
          AND status = 'aprovado'
    );
$$;

-- 4. Verifica se o usuário é administrador master aprovado de uma empresa
CREATE OR REPLACE FUNCTION public.fn_usuario_e_admin_empresa(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id AND e.ativa = TRUE
        WHERE em.empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND papel = 'admin'
          AND status = 'aprovado'
    );
$$;

-- 5. Verifica se o usuário é motorista aprovado e ativo da empresa
CREATE OR REPLACE FUNCTION public.fn_usuario_e_motorista_ativo(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.empresa_membros em
        JOIN public.empresas e ON e.id = em.empresa_id AND e.ativa = TRUE
        WHERE em.empresa_id = p_empresa_id
          AND user_id = p_user_id
          AND papel = 'motorista'
          AND status = 'aprovado'
    );
$$;

-- 6. Retorna o motorista_id vinculado ao usuário aprovado
CREATE OR REPLACE FUNCTION public.fn_motorista_id_do_usuario(p_user_id UUID DEFAULT auth.uid())
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT em.motorista_id
    FROM public.empresa_membros em
    JOIN public.empresas e ON e.id = em.empresa_id
    WHERE em.user_id = p_user_id
      AND em.status = 'aprovado'
      AND em.motorista_id IS NOT NULL
      AND e.ativa = TRUE
    LIMIT 1;
$$;

-- 7. Validação centralizada de autorização de condutor para operações de veículos/documentos
CREATE OR REPLACE FUNCTION public.fn_validar_autorizacao_condutor(
    p_empresa_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
    v_membro RECORD;
    v_solicitacao RECORD;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'autorizado', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    IF p_empresa_id IS NULL THEN
        RETURN jsonb_build_object(
            'autorizado', FALSE,
            'codigo', 'EMPRESA_INVALIDA',
            'mensagem', 'Identificador de empresa inválido.'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.empresas WHERE id = p_empresa_id AND ativa = TRUE) THEN
        RETURN jsonb_build_object('autorizado', false, 'codigo', 'EMPRESA_INATIVA', 'mensagem', 'Empresa indisponível.');
    END IF;

    -- 1. Verifica status em empresa_membros
    SELECT * INTO v_membro
    FROM public.empresa_membros
    WHERE empresa_id = p_empresa_id
      AND user_id = p_user_id;

    IF FOUND THEN
        IF v_membro.status = 'suspenso' THEN
            RETURN jsonb_build_object(
                'autorizado', FALSE,
                'codigo', 'USUARIO_SUSPENSO',
                'mensagem', 'Acesso suspenso pela gestão da empresa.'
            );
        END IF;

        IF v_membro.status = 'aprovado' THEN
            RETURN jsonb_build_object(
                'autorizado', TRUE,
                'codigo', 'MEMBRO_APROVADO',
                'papel', v_membro.papel
            );
        END IF;

        IF v_membro.status <> 'pendente' THEN
            RETURN jsonb_build_object('autorizado', false, 'codigo', 'ACESSO_NAO_AUTORIZADO', 'mensagem', 'Vínculo com a empresa não está ativo.');
        END IF;
        -- Pendente só pode preparar cadastro se a solicitação atual também estiver pendente.
    END IF;

    -- 2. Se não é membro, verifica se possui solicitação de acesso ativa para cadastro inicial
    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE empresa_id = p_empresa_id
      AND user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF FOUND THEN
        IF v_solicitacao.status = 'pendente' THEN
            RETURN jsonb_build_object(
                'autorizado', TRUE,
                'codigo', 'SOLICITACAO_PENDENTE',
                'papel', 'candidato'
            );
        END IF;

        IF v_solicitacao.status = 'rejeitado' THEN
            RETURN jsonb_build_object(
                'autorizado', FALSE,
                'codigo', 'SOLICITACAO_REJEITADA',
                'mensagem', 'Sua solicitação de acesso a esta empresa foi rejeitada.'
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'autorizado', FALSE,
        'codigo', 'SEM_VINCULO_ATIVO',
        'mensagem', 'Nenhum vínculo ou solicitação pendente encontrada para esta empresa.'
    );
END;
$$;
