CREATE OR REPLACE FUNCTION public.descartar_evidencia_temporaria(
    p_storage_path TEXT
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
    WHERE storage_path = TRIM(p_storage_path)
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'OBJETO_NAO_ENCONTRADO',
            'mensagem', 'Objeto não encontrado no ciclo de vida de armazenamento.'
        );
    END IF;

    -- Permissão: condutor proprietário ou gestor da empresa
    IF auth.uid() IS NULL OR NOT (public.fn_usuario_e_gestor_empresa(v_item.empresa_id, auth.uid()) IS TRUE OR (v_item.user_id = auth.uid() AND (public.fn_validar_autorizacao_condutor(v_item.empresa_id, auth.uid())->>'autorizado')::boolean IS TRUE)) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Sem permissão para descartar este arquivo.'
        );
    END IF;

    -- Se já estiver vinculado em veiculos_documentos, não pode ser descartado como temporário
    IF EXISTS (SELECT 1 FROM public.veiculos_documentos WHERE storage_path = v_item.storage_path) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_VINCULADO',
            'mensagem', 'O arquivo já está vinculado a um veículo ativo. Use a desvinculação oficial.'
        );
    END IF;

    IF v_item.status NOT IN ('reservado', 'pendente', 'em_processamento') THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'STATUS_INVALIDO', 'mensagem', 'O estado atual não autoriza este descarte.');
    END IF;

    -- Transição permitida: de 'reservado' para 'pendente' (autoriza exclusão física)
    IF v_item.status = 'reservado' THEN
        UPDATE public.storage_limpeza_fila
        SET status = 'pendente',
            motivo = 'descarte_temporario_nao_vinculado',
            autorizado_em = timezone('utc'::text, now()),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_item.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DESCARTE_AUTORIZADO',
        'mensagem', 'Descarte autorizado. Objeto liberado para limpeza física.',
        'fila_id', v_item.id,
        'storage_path', v_item.storage_path
    );
END;
$$;
