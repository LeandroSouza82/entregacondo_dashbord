-- ==============================================================================
-- FUNÇÃO SQL: analisar_veiculo_motorista.sql
-- Decisão humana da gestão sobre aprovação ou rejeição de veículo e seus anexos.
-- Centraliza a validação chamando fn_validar_completude_veiculo, que reconfere
-- campos obrigatórios, 4 fotos distintas, CRLV e existência física no Storage.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.analisar_veiculo_motorista(
    p_veiculo_id UUID,
    p_aprovar BOOLEAN,
    p_revisao_esperada INT,
    p_motivo_rejeicao TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_veiculo RECORD;
    v_novo_status VARCHAR(30);
    v_validacao JSONB;
BEGIN
    -- 1. Localiza e bloqueia o veículo para evitar alterações concorrentes
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE id = p_veiculo_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'VEICULO_NAO_ENCONTRADO',
            'mensagem', 'Veículo não encontrado.'
        );
    END IF;

    -- 2. Valida concorrência otimista via número de revisão
    IF p_revisao_esperada IS NULL THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'REVISAO_OBRIGATORIA',
            'mensagem', 'A revisão esperada do veículo é obrigatória para registrar a análise.'
        );
    END IF;

    IF v_veiculo.revisao != p_revisao_esperada THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'REVISAO_DESATUALIZADA',
            'mensagem', 'O veículo foi alterado durante a análise (revisão atual: ' || v_veiculo.revisao || ', esperada: ' || p_revisao_esperada || '). Atualize a visualização e confira os dados novamente antes de decidir.',
            'revisao_esperada', p_revisao_esperada,
            'revisao_atual', v_veiculo.revisao
        );
    END IF;

    -- 3. Valida permissão de gestão na empresa do veículo
    IF NOT public.fn_usuario_e_gestor_empresa(v_veiculo.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem analisar veículos.'
        );
    END IF;

    -- 4. Decisão de Aprovação ou Rejeição
    IF p_aprovar THEN
        -- Invoca a validação centralizada e reconfere evidências físicas
        v_validacao := public.fn_validar_completude_veiculo(v_veiculo.id);

        IF (v_validacao->>'valido')::boolean != TRUE THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', v_validacao->>'codigo',
                'mensagem', v_validacao->>'mensagem'
            );
        END IF;

        v_novo_status := 'aprovado';
    ELSE
        -- Rejeição exige motivo explícito
        IF p_motivo_rejeicao IS NULL OR TRIM(p_motivo_rejeicao) = '' THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTIVO_OBRIGATORIO',
                'mensagem', 'Informe a justificativa da rejeição do veículo.'
            );
        END IF;
        v_novo_status := 'rejeitado';
    END IF;

    -- 4. Atualiza veículo e incrementa revisão
    UPDATE public.veiculos_motoristas
    SET status_analise = v_novo_status,
        motivo_rejeicao = CASE WHEN p_aprovar THEN NULL ELSE TRIM(p_motivo_rejeicao) END,
        revisao = revisao + 1,
        analisado_por = auth.uid(),
        analisado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_veiculo.id;

    -- 5. Atualiza os documentos associados
    UPDATE public.veiculos_documentos
    SET status_analise = v_novo_status,
        motivo_rejeicao = CASE WHEN p_aprovar THEN NULL ELSE TRIM(p_motivo_rejeicao) END,
        analisado_por = auth.uid(),
        analisado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE veiculo_id = v_veiculo.id;

    -- 6. Auditoria detalhada com registro da revisão
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
        v_veiculo.empresa_id,
        v_veiculo.user_id,
        'analise_veiculo',
        v_veiculo.status_analise,
        v_novo_status,
        p_motivo_rejeicao,
        auth.uid(),
        jsonb_build_object(
            'veiculo_id', v_veiculo.id,
            'placa', v_veiculo.placa,
            'revisao_analisada', p_revisao_esperada,
            'revisao_gerada', v_veiculo.revisao + 1,
            'validacao_centralizada', v_validacao
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'ANALISE_CONCLUIDA',
        'mensagem', 'Decisão sobre o veículo registrada com sucesso.',
        'status_analise', v_novo_status,
        'revisao', v_veiculo.revisao + 1
    );
END;
$$;
