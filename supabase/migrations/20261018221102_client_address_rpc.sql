BEGIN;

-- ==============================================================================
-- FUNÇÃO SQL: salvar_cliente_endereco.sql
-- Cadastro e atualização resiliente de clientes, condomínios e endereços salvos.
-- Aceita variações de chaves do frontend e valida isolamento empresarial de gestão.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.salvar_cliente_endereco(p_dados JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_empresa_id UUID;
    v_nome TEXT;
    v_endereco TEXT;
    v_complemento TEXT;
    v_lat NUMERIC;
    v_lng NUMERIC;
    v_tempo_medio INT;
    v_id UUID;
    v_registro public.clientes_enderecos%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_AUTENTICADO', 'mensagem', 'Não autenticado.');
    END IF;

    -- 1. Resolução e validação estrita da empresa do gestor
    v_empresa_id := public.fn_safe_uuid(p_dados->>'empresa_id');
    IF v_empresa_id IS NULL THEN
        SELECT em.empresa_id INTO v_empresa_id
        FROM public.empresa_membros em
        WHERE em.user_id = v_user_id
          AND em.status = 'aprovado'
          AND em.papel IN ('admin', 'gestor')
        LIMIT 1;
    END IF;

    -- Rejeita se não houver empresa ou se o usuário não for gestor autorizado dela
    IF v_empresa_id IS NULL OR public.fn_usuario_e_gestor_empresa(v_empresa_id, v_user_id) IS NOT TRUE THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Acesso de gestão obrigatório nesta empresa.');
    END IF;

    -- 2. Extrai o nome aceitando qualquer variação enviada pelo frontend
    v_nome := TRIM(COALESCE(
        p_dados->>'nome_identificador',
        p_dados->>'nome',
        p_dados->>'nome_cliente',
        p_dados->>'cliente_nome',
        p_dados->>'condominio',
        p_dados->>'destinatario_padrao',
        split_part(p_dados->>'endereco_completo', ',', 1),
        split_part(p_dados->>'endereco', ',', 1)
    ));

    -- 3. Extrai o endereço aceitando variações
    v_endereco := TRIM(COALESCE(
        p_dados->>'endereco_completo',
        p_dados->>'endereco',
        p_dados->>'logradouro'
    ));

    -- 4. Extrai complemento / observações de acesso
    v_complemento := NULLIF(TRIM(COALESCE(
        p_dados->>'observacoes_acesso',
        p_dados->>'complemento',
        p_dados->>'bloco_apartamento'
    )), '');

    -- 5. Extrai coordenadas aceitando variações lat/lng e latitude/longitude
    v_lat := (COALESCE(p_dados->>'latitude', p_dados->>'lat'))::NUMERIC;
    v_lng := (COALESCE(p_dados->>'longitude', p_dados->>'lng'))::NUMERIC;

    IF v_lat IS NULL OR v_lng IS NULL OR NOT (v_lat BETWEEN -90 AND 90) OR NOT (v_lng BETWEEN -180 AND 180) THEN
        v_lat := -27.5954;
        v_lng := -48.5480;
    END IF;

    v_tempo_medio := COALESCE(
        (p_dados->>'tempo_medio_minutos')::INT,
        (p_dados->>'tempo_medio_atendimento_min')::INT,
        15
    );

    IF v_nome IS NULL OR v_nome = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DADOS_INVALIDOS', 'mensagem', 'Nome do cliente ou condomínio é obrigatório.');
    END IF;

    IF v_endereco IS NULL OR v_endereco = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DADOS_INVALIDOS', 'mensagem', 'Endereço é obrigatório.');
    END IF;

    -- Lock transacional para evitar duplicação concorrente do mesmo condomínio
    PERFORM pg_advisory_xact_lock(hashtextextended(v_empresa_id::text || lower(v_nome) || lower(v_endereco), 0));

    -- Verifica se foi fornecido ID específico ou se o registro já existe pelo nome/endereço
    v_id := public.fn_safe_uuid(p_dados->>'id');

    IF v_id IS NOT NULL THEN
        UPDATE public.clientes_enderecos
        SET 
            nome_identificador = v_nome,
            endereco_completo = v_endereco,
            latitude = v_lat,
            longitude = v_lng,
            tempo_medio_minutos = v_tempo_medio,
            observacoes_acesso = COALESCE(v_complemento, observacoes_acesso),
            updated_at = timezone('utc'::text, now())
        WHERE id = v_id AND empresa_id = v_empresa_id
        RETURNING * INTO v_registro;
    END IF;

    IF v_registro.id IS NULL THEN
        SELECT * INTO v_registro
        FROM public.clientes_enderecos
        WHERE empresa_id = v_empresa_id
          AND (lower(nome_identificador) = lower(v_nome) AND lower(endereco_completo) = lower(v_endereco))
        LIMIT 1;

        IF v_registro.id IS NOT NULL THEN
            UPDATE public.clientes_enderecos
            SET 
                latitude = v_lat,
                longitude = v_lng,
                tempo_medio_minutos = v_tempo_medio,
                observacoes_acesso = COALESCE(v_complemento, observacoes_acesso),
                updated_at = timezone('utc'::text, now())
            WHERE id = v_registro.id
            RETURNING * INTO v_registro;
        ELSE
            INSERT INTO public.clientes_enderecos (
                empresa_id,
                nome_identificador,
                destinatario_padrao,
                endereco_completo,
                numero,
                bairro,
                cidade,
                cep,
                latitude,
                longitude,
                tempo_medio_minutos,
                tipo_local,
                observacoes_acesso
            )
            VALUES (
                v_empresa_id,
                v_nome,
                NULLIF(TRIM(p_dados->>'destinatario_padrao'), ''),
                v_endereco,
                COALESCE(p_dados->>'numero', ''),
                COALESCE(p_dados->>'bairro', ''),
                COALESCE(p_dados->>'cidade', 'Florianópolis'),
                COALESCE(p_dados->>'cep', '88000-000'),
                v_lat,
                v_lng,
                v_tempo_medio,
                COALESCE(p_dados->>'tipo_local', 'condominio_horizontal'),
                v_complemento
            )
            RETURNING * INTO v_registro;
        END IF;
    END IF;

    -- Retorna tanto em formato direto de registro quanto no encapsulamento canônico
    RETURN to_jsonb(v_registro) || jsonb_build_object(
        'sucesso', TRUE,
        'id', v_registro.id,
        'nome', v_registro.nome_identificador,
        'nome_identificador', v_registro.nome_identificador,
        'endereco', v_registro.endereco_completo,
        'endereco_completo', v_registro.endereco_completo,
        'cliente', to_jsonb(v_registro)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.salvar_cliente_endereco(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.salvar_cliente_endereco(JSONB) TO authenticated;

COMMIT;
