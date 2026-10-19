DROP FUNCTION IF EXISTS public.registrar_limpeza_storage_executada(UUID, BOOLEAN, TEXT);
CREATE OR REPLACE FUNCTION public.registrar_limpeza_storage_executada(
    p_fila_id UUID, p_claim_token UUID, p_sucesso BOOLEAN, p_erro TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_item public.storage_limpeza_fila%ROWTYPE;
    v_novo_status VARCHAR(30);
BEGIN
    IF auth.uid() IS NULL OR p_claim_token IS NULL OR p_sucesso IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'CLAIM_INVALIDO', 'mensagem', 'Uma tentativa autenticada é obrigatória.');
    END IF;
    SELECT * INTO v_item FROM public.storage_limpeza_fila f WHERE f.id = p_fila_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ITEM_FILA_NAO_ENCONTRADO');
    END IF;
    IF v_item.claim_token IS DISTINCT FROM p_claim_token OR v_item.claimed_by IS DISTINCT FROM auth.uid() THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'CLAIM_INVALIDO', 'mensagem', 'Esta resposta não pertence à tentativa atual.');
    END IF;
    IF NOT (public.fn_usuario_e_gestor_empresa(v_item.empresa_id, auth.uid()) IS TRUE
        OR (v_item.user_id = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(v_item.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE)) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO');
    END IF;
    IF v_item.status = 'concluido' THEN
        RETURN jsonb_build_object('sucesso', true, 'codigo', 'JA_CONCLUIDO', 'status', 'concluido');
    END IF;
    IF v_item.status <> 'em_processamento' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ESTADO_INVALIDO', 'mensagem', 'O item não está nesta tentativa de processamento.');
    END IF;
    IF v_item.lease_expires_at IS NULL OR v_item.lease_expires_at <= clock_timestamp() THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'CLAIM_EXPIRADO', 'mensagem', 'O prazo desta tentativa expirou.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.veiculos_documentos vd WHERE vd.storage_path = v_item.storage_path) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ARQUIVO_VINCULADO');
    END IF;
    -- Confere metadados removidos pela API; não afirma acesso físico ao provedor S3.
    IF p_sucesso AND EXISTS (SELECT 1 FROM storage.objects o
        WHERE o.bucket_id = v_item.bucket_id AND o.name = v_item.storage_path) THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'OBJETO_AINDA_PRESENTE', 'mensagem', 'A remoção ainda não foi confirmada no Storage.');
    END IF;
    v_novo_status := CASE WHEN p_sucesso THEN 'concluido'
        WHEN v_item.tentativas >= v_item.max_tentativas THEN 'falhou' ELSE 'pendente' END;
    UPDATE public.storage_limpeza_fila f
    SET status = v_novo_status, ultimo_erro = CASE WHEN p_sucesso THEN NULL ELSE LEFT(p_erro, 2000) END,
        processado_em = clock_timestamp(), lease_expires_at = NULL, updated_at = clock_timestamp()
    WHERE f.id = v_item.id;
    INSERT INTO public.auditoria_acessos
        (empresa_id, user_id, acao, status_anterior, novo_status, executado_por, detalhes)
    VALUES (v_item.empresa_id, v_item.user_id, 'storage_resultado', v_item.status, v_novo_status, auth.uid(),
        jsonb_build_object('fila_id', v_item.id, 'claim_token', p_claim_token, 'tentativa', v_item.tentativas,
            'erro', CASE WHEN p_sucesso THEN NULL ELSE LEFT(p_erro, 2000) END));
    RETURN jsonb_build_object('sucesso', true, 'codigo', 'LIMPEZA_REGISTRADA', 'status', v_novo_status);
END;
$$;