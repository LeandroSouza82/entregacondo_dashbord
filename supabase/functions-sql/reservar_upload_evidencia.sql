CREATE OR REPLACE FUNCTION public.reservar_upload_evidencia(
    p_empresa_id UUID,
    p_tipo_documento TEXT,
    p_nome_arquivo TEXT,
    p_angulo_foto TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_ext TEXT;
    v_random_uuid UUID := gen_random_uuid();
    v_timestamp BIGINT := (extract(epoch from timezone('utc'::text, now())) * 1000)::bigint;
    v_storage_path TEXT;
    v_fila_id UUID;
    v_identificador_tipo TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'NAO_AUTENTICADO',
            'mensagem', 'Usuário não autenticado.'
        );
    END IF;

    -- Validação de autorização do condutor na empresa
    IF (public.fn_validar_autorizacao_condutor(p_empresa_id, v_user_id)->>'autorizado')::boolean != TRUE THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', public.fn_validar_autorizacao_condutor(p_empresa_id, v_user_id)->>'codigo',
            'mensagem', public.fn_validar_autorizacao_condutor(p_empresa_id, v_user_id)->>'mensagem'
        );
    END IF;

    -- Valida tipo de documento
    IF p_tipo_documento NOT IN ('foto_veiculo', 'crlv', 'complementar') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'TIPO_DOCUMENTO_INVALIDO',
            'mensagem', 'Tipo de documento deve ser foto_veiculo, crlv ou complementar.'
        );
    END IF;

    -- Valida ângulo para foto do veículo
    IF p_tipo_documento = 'foto_veiculo' THEN
        IF p_angulo_foto IS NULL OR p_angulo_foto NOT IN ('frente', 'lado_direito', 'lado_esquerdo', 'traseira') THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'ANGULO_INVALIDO',
                'mensagem', 'Para foto_veiculo, o ângulo é obrigatório e deve ser: frente, lado_direito, lado_esquerdo ou traseira.'
            );
        END IF;
        v_identificador_tipo := 'foto_' || p_angulo_foto;
    ELSE
        p_angulo_foto := NULL;
        v_identificador_tipo := p_tipo_documento;
    END IF;

    -- Valida extensão
    v_ext := LOWER(SUBSTRING(TRIM(p_nome_arquivo) FROM '\.([^\.]+)$'));
    IF v_ext NOT IN ('jpg', 'jpeg', 'png', 'pdf') THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'EXTENSAO_INVALIDA',
            'mensagem', 'Extensão de arquivo não permitida. Use JPG, PNG ou PDF.'
        );
    END IF;

    IF p_tipo_documento = 'foto_veiculo' AND v_ext = 'pdf' THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'FOTO_NAO_ACEITA_PDF',
            'mensagem', 'Fotos do veículo não podem estar no formato PDF.'
        );
    END IF;

    -- Gera caminho estritamente único que previne colisões e reutilizações de caminhos descartados
    v_storage_path := p_empresa_id::text || '/' || v_user_id::text || '/' || v_identificador_tipo || '_' || v_timestamp::text || '_' || v_random_uuid::text || '.' || v_ext;

    -- Registra reserva com status 'reservado'
    INSERT INTO public.storage_limpeza_fila (
        bucket_id,
        storage_path,
        empresa_id,
        user_id,
        motivo,
        status
    ) VALUES (
        'veiculos-documentos',
        v_storage_path,
        p_empresa_id,
        v_user_id,
        'reserva_upload_' || v_identificador_tipo,
        'reservado'
    )
    RETURNING id INTO v_fila_id;

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'UPLOAD_RESERVADO',
        'mensagem', 'Upload autorizado e reservado com caminho único.',
        'storage_path', v_storage_path,
        'fila_id', v_fila_id,
        'bucket_id', 'veiculos-documentos'
    );
END;
$$;
