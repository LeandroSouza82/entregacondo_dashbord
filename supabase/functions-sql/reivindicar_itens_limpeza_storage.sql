-- A assinatura anterior não contém filtro de item nem identidade da tentativa.
DROP FUNCTION IF EXISTS public.reivindicar_itens_limpeza_storage(INT);
CREATE OR REPLACE FUNCTION public.reivindicar_itens_limpeza_storage(
    p_limite INT DEFAULT 10, p_fila_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID, bucket_id VARCHAR, storage_path TEXT, empresa_id UUID,
    user_id UUID, motivo TEXT, status VARCHAR, tentativas INT,
    max_tentativas INT, claim_token UUID, lease_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_item public.storage_limpeza_fila%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuário não autenticado.' USING ERRCODE = '42501';
    END IF;
    IF p_limite IS NULL OR p_limite < 1 OR p_limite > 100 THEN
        RAISE EXCEPTION 'O limite deve estar entre 1 e 100.' USING ERRCODE = '22023';
    END IF;
    -- Uma interrupção também consome tentativa.
    UPDATE public.storage_limpeza_fila f
    SET status = 'falhou', lease_expires_at = NULL, updated_at = clock_timestamp(),
        ultimo_erro = COALESCE(f.ultimo_erro, 'Prazo da última tentativa expirou sem confirmação.')
    WHERE f.status = 'em_processamento' AND f.lease_expires_at <= clock_timestamp()
      AND f.tentativas >= f.max_tentativas AND (p_fila_id IS NULL OR f.id = p_fila_id)
      AND (public.fn_usuario_e_gestor_empresa(f.empresa_id, auth.uid()) IS TRUE
        OR (f.user_id = auth.uid() AND
            (public.fn_validar_autorizacao_condutor(f.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE));

    FOR v_item IN
        SELECT f.* FROM public.storage_limpeza_fila f
        WHERE (f.status = 'pendente' OR
            (f.status = 'em_processamento' AND f.lease_expires_at <= clock_timestamp()))
          AND f.tentativas < f.max_tentativas AND (p_fila_id IS NULL OR f.id = p_fila_id)
          AND (public.fn_usuario_e_gestor_empresa(f.empresa_id, auth.uid()) IS TRUE
            OR (f.user_id = auth.uid() AND
                (public.fn_validar_autorizacao_condutor(f.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE))
        ORDER BY f.created_at, f.id LIMIT p_limite FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.storage_limpeza_fila f
        SET status = 'em_processamento', claim_token = gen_random_uuid(),
            claimed_by = auth.uid(), lease_expires_at = clock_timestamp() + INTERVAL '5 minutes',
            tentativas = f.tentativas + 1,
            processado_em = clock_timestamp(), updated_at = clock_timestamp()
        WHERE f.id = v_item.id RETURNING f.* INTO v_item;
        INSERT INTO public.auditoria_acessos
            (empresa_id, user_id, acao, novo_status, executado_por, detalhes)
        VALUES (v_item.empresa_id, v_item.user_id, 'storage_claim', 'em_processamento', auth.uid(),
            jsonb_build_object('fila_id', v_item.id, 'claim_token', v_item.claim_token,
                'tentativa', v_item.tentativas, 'lease_expires_at', v_item.lease_expires_at));
        id := v_item.id; bucket_id := v_item.bucket_id; storage_path := v_item.storage_path;
        empresa_id := v_item.empresa_id; user_id := v_item.user_id; motivo := v_item.motivo;
        status := v_item.status; tentativas := v_item.tentativas; max_tentativas := v_item.max_tentativas;
        claim_token := v_item.claim_token; lease_expires_at := v_item.lease_expires_at;
        RETURN NEXT;
    END LOOP;
END;
$$;