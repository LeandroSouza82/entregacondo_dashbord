BEGIN;

-- ==============================================================================
-- FUNÇÃO SQL: excluir_cliente_endereco
-- Exclusão permanente de um endereço salvo (clientes_enderecos) por gestor da empresa.
-- A tabela é somente-leitura para `authenticated` (sem GRANT DELETE), então a
-- exclusão passa por esta RPC com validação de empresa e de papel de gestão.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.excluir_cliente_endereco(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_empresa_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_AUTENTICADO', 'mensagem', 'Não autenticado.');
    END IF;

    SELECT empresa_id INTO v_empresa_id
    FROM public.clientes_enderecos
    WHERE id = p_id;

    IF v_empresa_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_ENCONTRADO', 'mensagem', 'Endereço não encontrado.');
    END IF;

    IF public.fn_usuario_e_gestor_empresa(v_empresa_id, v_user_id) IS NOT TRUE THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Acesso de gestão obrigatório nesta empresa.');
    END IF;

    BEGIN
        DELETE FROM public.clientes_enderecos
        WHERE id = p_id AND empresa_id = v_empresa_id;
    EXCEPTION WHEN foreign_key_violation THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ENDERECO_EM_USO', 'mensagem', 'Este endereço possui entregas vinculadas e não pode ser excluído.');
    END;

    RETURN jsonb_build_object('sucesso', true, 'id', p_id);
END;
$$;

REVOKE ALL ON FUNCTION public.excluir_cliente_endereco(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.excluir_cliente_endereco(UUID) TO authenticated;

COMMIT;
