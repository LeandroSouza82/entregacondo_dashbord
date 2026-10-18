CREATE OR REPLACE FUNCTION public.retomar_limpeza_falha(
    p_fila_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item RECORD;
BEGIN
    SELECT * INTO v_item
    FROM public.storage_limpeza_fila
    WHERE id = p_fila_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ITEM_FILA_NAO_ENCONTRADO',
            'mensagem', 'Item da fila de limpeza não encontrado.'
        );
    END IF;

    IF auth.uid() IS NULL OR NOT (public.fn_usuario_e_gestor_empresa(v_item.empresa_id, auth.uid()) IS TRUE OR (v_item.user_id = auth.uid() AND (public.fn_validar_autorizacao_condutor(v_item.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE)) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Sem permissão para retomar limpeza deste item.'
        );
    END IF;

    IF v_item.status != 'falhou' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'STATUS_INVALIDO',
            'mensagem', 'Apenas itens com status "falhou" podem ser retomados (status atual: ' || v_item.status || ').'
        );
    END IF;

    INSERT INTO public.auditoria_acessos
        (empresa_id, user_id, acao, status_anterior, novo_status, executado_por, detalhes)
    VALUES (v_item.empresa_id, v_item.user_id, 'storage_retomada', 'falhou', 'pendente', auth.uid(),
        jsonb_build_object('fila_id', v_item.id, 'tentativas_anteriores', v_item.tentativas, 'ultimo_erro', v_item.ultimo_erro));

    UPDATE public.storage_limpeza_fila
    SET status = 'pendente',
        claim_token = NULL, claimed_by = NULL, lease_expires_at = NULL,
        tentativas = 0,
        ultimo_erro = NULL,
        processado_em = NULL,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_item.id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'LIMPEZA_RETOMADA',
        'mensagem', 'Item retornado ao estado pendente para nova tentativa de limpeza.',
        'fila_id', v_item.id,
        'storage_path', v_item.storage_path
    );
END;
$$;
