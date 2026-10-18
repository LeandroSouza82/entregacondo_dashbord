-- ==============================================================================
-- FUNÇÃO SQL: remover_documento_veiculo.sql
-- Desvinculação autorizada e segura de documentos veiculares.
--
-- PROTOCOLO DE COORDENAÇÃO DE STORAGE:
-- 1. Remove os metadados da tabela veiculos_documentos.
-- 2. Insere atomicamente o storage_path na tabela storage_limpeza_fila com
--    status 'pendente', autorizando formalmente o DELETE físico no Storage.
-- 3. Se o veículo estiver 'aprovado', a remoção da evidência INVALIDA imediatamente
--    a aprovação, revertendo para 'pendente' e incrementando a revisão do veículo.
-- 4. Retorna fila_id e storage_path para que o cliente realize o DELETE físico
--    e confirme o sucesso via RPC registrar_limpeza_storage_executada.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.remover_documento_veiculo(
    p_documento_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_doc RECORD;
    v_veiculo RECORD;
    v_eh_gestor BOOLEAN := FALSE;
    v_fila_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- 1. Localiza o documento
    SELECT * INTO v_doc
    FROM public.veiculos_documentos
    WHERE id = p_documento_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'DOCUMENTO_NAO_ENCONTRADO',
            'mensagem', 'Documento não encontrado.'
        );
    END IF;

    -- 2. Localiza e bloqueia o veículo para coordenação de estado
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = v_doc.veiculo_id
    FOR UPDATE;

    -- 3. Validação de autorização centralizada (proprietário ativo ou gestor/admin da empresa)
    IF v_doc.user_id = v_user_id THEN
        -- Condutor deve ter vínculo ativo (não suspenso, não rejeitado)
        IF (public.fn_validar_autorizacao_condutor(v_doc.empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', public.fn_validar_autorizacao_condutor(v_doc.empresa_id, v_user_id)->>'codigo',
                'mensagem', public.fn_validar_autorizacao_condutor(v_doc.empresa_id, v_user_id)->>'mensagem'
            );
        END IF;
    ELSIF public.fn_usuario_e_gestor_empresa(v_doc.empresa_id) THEN
        v_eh_gestor := TRUE;
    ELSE
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Você não possui autorização para remover esta evidência.'
        );
    END IF;

    -- 4. Remove a linha de metadados no Postgres
    DELETE FROM public.veiculos_documentos WHERE id = v_doc.id;

    -- 5. Enfileira o arquivo para limpeza física controlada
    INSERT INTO public.storage_limpeza_fila (
        bucket_id,
        storage_path,
        empresa_id,
        user_id,
        motivo,
        status
    ) VALUES (
        'veiculos-documentos',
        v_doc.storage_path,
        v_doc.empresa_id,
        v_user_id,
        'remocao_documento_veiculo',
        'pendente'
    )
    RETURNING id INTO v_fila_id;

    -- 6. Se o veículo já estava aprovado, a remoção INVALIDA a aprovação
    IF v_veiculo.status_analise = 'aprovado' THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'pendente',
            motivo_rejeicao = 'Aprovação invalidada: evidência (' || COALESCE(v_doc.angulo_foto, v_doc.tipo_documento) || ') foi removida.',
            revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    ELSE
        UPDATE public.veiculos_motoristas
        SET revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    END IF;

    -- 7. Auditoria da desvinculação
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_doc.empresa_id,
        v_doc.user_id,
        'remocao_documento_veiculo',
        v_veiculo.status_analise,
        'pendente',
        'Documento ' || v_doc.nome_arquivo || ' removido.',
        v_user_id,
        jsonb_build_object(
            'documento_id', v_doc.id,
            'storage_path', v_doc.storage_path,
            'tipo_documento', v_doc.tipo_documento,
            'angulo_foto', v_doc.angulo_foto,
            'eh_gestor', v_eh_gestor,
            'limpeza_fila_id', v_fila_id
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DOCUMENTO_REMOVIDO',
        'mensagem', 'Documento desvinculado com sucesso e enfileirado para limpeza física.',
        'storage_path', v_doc.storage_path,
        'fila_id', v_fila_id,
        'veiculo_id', v_veiculo.id,
        'revisao', v_veiculo.revisao + 1
    );
END;
$$;
