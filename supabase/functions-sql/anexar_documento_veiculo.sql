-- ==============================================================================
-- FUNÇÃO SQL: anexar_documento_veiculo.sql
-- Confirmação e vinculação de anexos (4 fotos por ângulo, CRLV ou complementar).
-- Valida no servidor a existência real do objeto no storage.objects,
-- o isolamento por empresa/usuário, tamanho, MIME type e limites operacionais.
--
-- COORDENAÇÃO DE CICLO DE VIDA DO STORAGE:
-- 1. Impede vinculação de objeto cuja exclusão está autorizada ou em andamento
--    (verificando status na tabela storage_limpeza_fila).
-- 2. Na substituição de arquivo (novo CRLV ou nova foto para o mesmo ângulo),
--    desvincula a evidência antiga e a enfileira atomicamente em storage_limpeza_fila
--    com status 'pendente' para limpeza física via API do Storage.
-- 3. A substituição ou vinculação incrementa a revisão do veículo e, se aprovado,
--    reverte o status para 'pendente' com justificativa explícita.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.anexar_documento_veiculo(
    p_veiculo_id UUID,
    p_tipo_documento TEXT,
    p_nome_arquivo TEXT,
    p_storage_path TEXT,
    p_tamanho_bytes INT,
    p_angulo_foto TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_veiculo RECORD;
    v_mime_type VARCHAR(100);
    v_docs_count INT;
    v_ext TEXT;
    v_doc_id UUID;
    v_parts TEXT[];
    v_empresa_path UUID;
    v_user_path UUID;
    v_storage_meta JSONB;
    v_tamanho_real BIGINT;
    v_mime_real TEXT;
    v_old_storage_path TEXT;
    v_fila_id UUID := NULL;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- 1. Localiza e bloqueia o veículo para escrita concorrente segura
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = p_veiculo_id AND user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'VEICULO_NAO_ENCONTRADO',
            'mensagem', 'Veículo não encontrado ou não pertence ao usuário autenticado.'
        );
    END IF;

    -- Validação centralizada de autorização (bloqueia usuário suspenso ou sem vínculo ativo)
    IF (public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(v_veiculo.empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    -- 2. Valida tipo de documento canônico
    IF p_tipo_documento NOT IN ('foto_veiculo', 'crlv', 'complementar') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TIPO_DOCUMENTO_INVALIDO',
            'mensagem', 'Tipo de documento deve ser foto_veiculo, crlv ou complementar.'
        );
    END IF;

    -- 3. Validação de ângulo para foto do veículo
    IF p_tipo_documento = 'foto_veiculo' THEN
        IF p_angulo_foto IS NULL OR p_angulo_foto NOT IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira') THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'ANGULO_INVALIDO',
                'mensagem', 'Para foto_veiculo, o ângulo é obrigatório e deve ser: frente, lado_direito, lado_esquerdo ou traseira.'
            );
        END IF;
    ELSE
        -- Documentos não devem ter ângulo
        p_angulo_foto := NULL;
    END IF;

    -- 4. Validação estrita do padrão de caminho de armazenamento: {empresa_id}/{user_id}/{filename}
    v_parts := string_to_array(TRIM(p_storage_path), '/');
    IF array_length(v_parts, 1) < 3 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'CAMINHO_STORAGE_INVALIDO',
            'mensagem', 'Caminho de armazenamento fora do padrão seguro {empresa_id}/{user_id}/{arquivo}.'
        );
    END IF;

    v_empresa_path := public.fn_safe_uuid(v_parts[1]);
    v_user_path := public.fn_safe_uuid(v_parts[2]);

    IF v_empresa_path IS NULL OR v_empresa_path != v_veiculo.empresa_id THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EMPRESA_STORAGE_DIVERGENTE',
            'mensagem', 'O caminho do arquivo não corresponde à empresa do veículo declarado.'
        );
    END IF;

    IF v_user_path IS NULL OR v_user_path != v_user_id THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'USUARIO_STORAGE_DIVERGENTE',
            'mensagem', 'Tentativa de vincular arquivo pertencente a outro condutor.'
        );
    END IF;

    -- 4b. Previne vinculação ou reutilização de objeto cuja exclusão foi autorizada ou está em andamento
    IF EXISTS (
        SELECT 1 FROM public.storage_limpeza_fila
        WHERE storage_path = TRIM(p_storage_path)
          AND status IN ('pendente', 'em_processamento', 'concluido')
    ) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_EM_LIMPEZA',
            'mensagem', 'Este objeto do Storage está em processo de limpeza ou já foi descartado e não pode ser vinculado.'
        );
    END IF;

    -- 4c. Previne reutilização ou colisão de caminho já vinculado a outro documento ativo
    IF EXISTS (
        SELECT 1 FROM public.veiculos_documentos
        WHERE storage_path = TRIM(p_storage_path)
          AND (
            veiculo_id != v_veiculo.id OR
            tipo_documento != p_tipo_documento OR
            (tipo_documento = 'foto_veiculo' AND angulo_foto IS DISTINCT FROM p_angulo_foto)
          )
    ) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_JA_VINCULADO',
            'mensagem', 'Este caminho de arquivo já está vinculado a outro registro de documento ativo.'
        );
    END IF;

    -- 5. Validação do arquivo real no Storage (tabela storage.objects)
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'storage' AND table_name = 'objects') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'INFRAESTRUTURA_STORAGE_INDISPONIVEL',
            'mensagem', 'A infraestrutura de Storage não está acessível para validação do arquivo enviado.'
        );
    END IF;

    SELECT metadata INTO v_storage_meta
    FROM storage.objects
    WHERE bucket_id = 'veiculos-documentos'
      AND name = TRIM(p_storage_path);

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ARQUIVO_STORAGE_NAO_ENCONTRADO',
            'mensagem', 'O arquivo físico não foi localizado no bucket privado de armazenamento.'
        );
    END IF;

    -- Validação cruzada de tamanho real reportado pelo Storage
    IF v_storage_meta IS NOT NULL AND (v_storage_meta ? 'size') THEN
        v_tamanho_real := (v_storage_meta->>'size')::bigint;
        IF v_tamanho_real > 10485760 THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'TAMANHO_EXCEDIDO',
                'mensagem', 'O arquivo real excede o limite máximo permitido de 10 MB.'
            );
        END IF;
        p_tamanho_bytes := v_tamanho_real::int;
    END IF;

    -- Validação cruzada de MIME type reportado pelo Storage
    IF v_storage_meta IS NOT NULL AND (v_storage_meta ? 'mimetype') THEN
        v_mime_real := LOWER(v_storage_meta->>'mimetype');
        IF v_mime_real NOT IN ('image/jpeg', 'image/png', 'application/pdf') THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MIMETYPE_STORAGE_INVALIDO',
                'mensagem', 'Tipo de arquivo não permitido no bucket privado: ' || v_mime_real
            );
        END IF;
    END IF;

    -- 6. Validação de tamanho no payload (caso storage.objects não tenha metadata)
    IF p_tamanho_bytes <= 0 OR p_tamanho_bytes > 10485760 THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TAMANHO_EXCEDIDO',
            'mensagem', 'O arquivo deve ter entre 1 byte e 10 MB.'
        );
    END IF;

    -- 7. Dedução e validação do formato MIME pelo nome e consistência
    v_ext := LOWER(SUBSTRING(TRIM(p_nome_arquivo) FROM '\.([^\.]+)$'));
    IF v_ext IN ('jpg', 'jpeg') THEN
        v_mime_type := 'image/jpeg';
    ELSIF v_ext = 'png' THEN
        v_mime_type := 'image/png';
    ELSIF v_ext = 'pdf' THEN
        v_mime_type := 'application/pdf';
    ELSE
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EXTENSAO_INVALIDA',
            'mensagem', 'Formato de arquivo não suportado. Envie JPG, PNG ou PDF.'
        );
    END IF;

    -- Fotos de veículo aceitam apenas JPG ou PNG
    IF p_tipo_documento = 'foto_veiculo' AND v_mime_type = 'application/pdf' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'FOTO_NAO_ACEITA_PDF',
            'mensagem', 'Fotos do veículo devem ser imagens nos formatos JPG ou PNG.'
        );
    END IF;

    -- 8. Gerenciamento de Substituição e Limites
    IF p_tipo_documento = 'foto_veiculo' THEN
        -- Localiza foto anterior do mesmo ângulo para desvinculação e limpeza
        SELECT storage_path INTO v_old_storage_path
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'foto_veiculo'
          AND angulo_foto = p_angulo_foto;

        IF FOUND THEN
            DELETE FROM public.veiculos_documentos
            WHERE veiculo_id = v_veiculo.id
              AND tipo_documento = 'foto_veiculo'
              AND angulo_foto = p_angulo_foto;

            -- Se o caminho for diferente, enfileira o antigo para limpeza segura
            IF v_old_storage_path IS NOT NULL AND v_old_storage_path != TRIM(p_storage_path) THEN
                INSERT INTO public.storage_limpeza_fila (
                    bucket_id,
                    storage_path,
                    empresa_id,
                    user_id,
                    motivo,
                    status
                ) VALUES (
                    'veiculos-documentos',
                    v_old_storage_path,
                    v_veiculo.empresa_id,
                    v_user_id,
                    'substituicao_foto_' || p_angulo_foto,
                    'pendente'
                )
                RETURNING id INTO v_fila_id;
            END IF;
        END IF;

    ELSIF p_tipo_documento = 'crlv' THEN
        -- Localiza CRLV anterior para desvinculação e limpeza
        SELECT storage_path INTO v_old_storage_path
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'crlv';

        IF FOUND THEN
            DELETE FROM public.veiculos_documentos
            WHERE veiculo_id = v_veiculo.id
              AND tipo_documento = 'crlv';

            -- Se o caminho for diferente, enfileira o antigo para limpeza segura
            IF v_old_storage_path IS NOT NULL AND v_old_storage_path != TRIM(p_storage_path) THEN
                INSERT INTO public.storage_limpeza_fila (
                    bucket_id,
                    storage_path,
                    empresa_id,
                    user_id,
                    motivo,
                    status
                ) VALUES (
                    'veiculos-documentos',
                    v_old_storage_path,
                    v_veiculo.empresa_id,
                    v_user_id,
                    'substituicao_crlv',
                    'pendente'
                )
                RETURNING id INTO v_fila_id;
            END IF;
        END IF;

    ELSIF p_tipo_documento = 'complementar' THEN
        -- Limite de até 5 documentos complementares
        SELECT COUNT(*) INTO v_docs_count
        FROM public.veiculos_documentos
        WHERE veiculo_id = v_veiculo.id
          AND tipo_documento = 'complementar';

        IF v_docs_count >= 5 THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'LIMITE_DOCUMENTOS_EXCEDIDO',
                'mensagem', 'Limite máximo de 5 documentos complementares atingido.'
            );
        END IF;
    END IF;

    -- 9. Insere novo registro de metadados
    INSERT INTO public.veiculos_documentos (
        veiculo_id,
        user_id,
        empresa_id,
        tipo_documento,
        angulo_foto,
        nome_arquivo,
        storage_path,
        mime_type,
        tamanho_bytes,
        status_analise
    ) VALUES (
        v_veiculo.id,
        v_user_id,
        v_veiculo.empresa_id,
        p_tipo_documento,
        p_angulo_foto,
        TRIM(p_nome_arquivo),
        TRIM(p_storage_path),
        v_mime_type,
        p_tamanho_bytes,
        'pendente'
    )
    RETURNING id INTO v_doc_id;

    -- 10. Atualiza revisão e reverte status para pendente caso estivesse aprovado
    IF v_veiculo.status_analise = 'aprovado' THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'pendente',
            motivo_rejeicao = 'Aprovação invalidada: nova evidência (' || COALESCE(p_angulo_foto, p_tipo_documento) || ') enviada para análise.',
            revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    ELSE
        UPDATE public.veiculos_motoristas
        SET revisao = revisao + 1,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id;
    END IF;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'DOCUMENTO_ANEXADO',
        'mensagem', 'Anexo vinculado com sucesso e registrado para análise da gestão.',
        'documento_id', v_doc_id,
        'angulo_foto', p_angulo_foto,
        'tipo_documento', p_tipo_documento,
        'revisao', v_veiculo.revisao + 1,
        'arquivo_substituido_path', v_old_storage_path,
        'limpeza_fila_id', v_fila_id
    );
END;
$$;
