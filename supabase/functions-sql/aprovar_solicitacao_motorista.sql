-- ==============================================================================
-- FUNÇÃO SQL: aprovar_solicitacao_motorista.sql
-- Aprovação auditada de motorista pela gestão da empresa.
-- Atômica e consistente sob concorrência (FOR UPDATE).
--
-- GARANTIAS:
-- 1. Valida autorização do executor, existência de dados e condições de recusa
--    (inclusive conferência de revisão de veículo e completude) ANTES de qualquer mutação.
-- 2. Zero mutações parciais: em caso de recusa (ex: revisão desatualizada ou ausente),
--    nenhum registro é inserido em motoristas, empresa_membros ou solicitacoes_acesso.
-- 3. Idempotência e prevenção de duplicidades: retentativas após recusa ou chamadas
--    repetidas não duplicam registros na frota de motoristas.
-- 4. Separação explícita entre aprovação de vínculo e aprovação de veículo:
--    Aprovar o vínculo não aprova automaticamente o veículo a menos que
--    p_aprovar_veiculo = TRUE E a revisão esperada seja fornecida e conferida.
-- 5. ISOLAMENTO ESTRITO ENTRE EMPRESAS:
--    O veículo aprovado deve obrigatoriamente pertencer à mesma empresa da solicitação.
--    Veículos pertencentes a outras empresas nunca são aprovados nem têm seus dados
--    copiados para o cadastro do motorista nesta empresa.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.aprovar_solicitacao_motorista(
    p_solicitacao_id UUID,
    p_motorista_id UUID DEFAULT NULL,
    p_criar_novo_motorista BOOLEAN DEFAULT FALSE,
    p_nome_motorista TEXT DEFAULT NULL,
    p_telefone_motorista VARCHAR DEFAULT NULL,
    p_aprovar_veiculo BOOLEAN DEFAULT FALSE,
    p_revisao_esperada_veiculo INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_solicitacao RECORD;
    v_perfil RECORD;
    v_veiculo RECORD;
    v_motorista RECORD;
    v_motorista_existente_id UUID;
    v_motorista_final_id UUID;
    v_nome_final TEXT;
    v_telefone_final VARCHAR(30);
    v_modelo_final VARCHAR(100);
    v_placa_final VARCHAR(20);
    v_validacao_veic JSONB;
BEGIN
    -- --------------------------------------------------------------------------
    -- 1. LOCALIZAÇÃO E LOCK DA SOLICITAÇÃO (CONCORRÊNCIA SEGURA)
    -- --------------------------------------------------------------------------
    SELECT * INTO v_solicitacao
    FROM public.solicitacoes_acesso
    WHERE id = p_solicitacao_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'SOLICITACAO_NAO_ENCONTRADA',
            'mensagem', 'Solicitação de acesso não encontrada.'
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 2. VALIDAÇÃO DE AUTORIZAÇÃO ANTES DE QUALQUER LEITURA OU RESPOSTA
    -- --------------------------------------------------------------------------
    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id, auth.uid()) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem aprovar solicitações.'
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 3. IDEMPOTÊNCIA AUTORIZADA (JÁ APROVADO PREVIAMENTE)
    -- --------------------------------------------------------------------------
    IF v_solicitacao.status = 'aprovado' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'JA_APROVADO',
            'mensagem', 'Esta solicitação já foi aprovada anteriormente.',
            'motorista_id', v_solicitacao.motorista_vinculado_id
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 4. PRÉ-VALIDAÇÃO DA OPÇÃO DE VÍNCULO (SEM MUTAÇÕES)
    -- --------------------------------------------------------------------------
    IF NOT p_criar_novo_motorista THEN
        -- Opção B: Vincular a motorista existente da frota
        IF p_motorista_id IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTORISTA_OBRIGATORIO',
                'mensagem', 'Selecione um motorista da frota para realizar o vínculo.'
            );
        END IF;

        SELECT * INTO v_motorista
        FROM public.motoristas
        WHERE id = p_motorista_id
          AND empresa_id = v_solicitacao.empresa_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTORISTA_NAO_ENCONTRADO',
                'mensagem', 'Motorista selecionado não foi encontrado ou não pertence a esta empresa.'
            );
        END IF;

        IF v_motorista.user_id IS NOT NULL AND v_motorista.user_id != v_solicitacao.user_id THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'MOTORISTA_JA_VINCULADO',
                'mensagem', 'Este motorista já está vinculado a outro usuário.'
            );
        END IF;
    END IF;

    -- --------------------------------------------------------------------------
    -- 5. PRÉ-VALIDAÇÃO DO VEÍCULO COM ISOLAMENTO ESTRITO ENTRE EMPRESAS
    -- --------------------------------------------------------------------------
    -- O veículo deve pertencer OBRIGATORIAMENTE à mesma empresa da solicitação
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE user_id = v_solicitacao.user_id
      AND empresa_id = v_solicitacao.empresa_id
    FOR UPDATE;

    -- Se não encontrou veículo nesta empresa, confere se há veículo cadastrado em OUTRA empresa
    IF v_veiculo.id IS NULL THEN
        IF EXISTS (
            SELECT 1
            FROM public.veiculos_motoristas
            WHERE user_id = v_solicitacao.user_id
              AND empresa_id != v_solicitacao.empresa_id
        ) THEN
            -- O condutor possui veículo declarado em outra empresa
            IF p_aprovar_veiculo THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'VEICULO_OUTRA_EMPRESA',
                    'mensagem', 'O condutor possui veículo cadastrado em outra empresa. A gestão não pode aprovar veículo de terceiros.'
                );
            END IF;
        END IF;
    END IF;

    IF p_aprovar_veiculo THEN
        IF v_veiculo.id IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'VEICULO_NAO_ENCONTRADO',
                'mensagem', 'O condutor não possui veículo declarado para esta empresa.'
            );
        END IF;

        -- Validação explícita de consistência de isolamento
        IF v_veiculo.empresa_id != v_solicitacao.empresa_id THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'VEICULO_OUTRA_EMPRESA',
                'mensagem', 'Divergência de isolamento: o veículo pertence a outra empresa.'
            );
        END IF;

        -- Exige revisão obrigatoriamente
        IF p_revisao_esperada_veiculo IS NULL THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'REVISAO_OBRIGATORIA',
                'mensagem', 'A revisão esperada do veículo é obrigatória para aprovar o veículo.'
            );
        END IF;

        -- Confere se a revisão confere com a visualizada pelo gestor
        IF v_veiculo.revisao != p_revisao_esperada_veiculo THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', 'REVISAO_DESATUALIZADA',
                'mensagem', 'O veículo do condutor foi alterado durante a análise (revisão atual: ' || v_veiculo.revisao || ', esperada: ' || p_revisao_esperada_veiculo || '). Atualize e revise a versão atual antes de decidir.',
                'revisao_esperada', p_revisao_esperada_veiculo,
                'revisao_atual', v_veiculo.revisao
            );
        END IF;

        -- Valida completude (4 fotos distintas, CRLV e existência física no Storage)
        v_validacao_veic := public.fn_validar_completude_veiculo(v_veiculo.id);
        IF (v_validacao_veic->>'valido')::boolean != TRUE THEN
            RETURN jsonb_build_object(
                'sucesso', FALSE,
                'codigo', v_validacao_veic->>'codigo',
                'mensagem', 'Veículo não atende aos requisitos para aprovação: ' || (v_validacao_veic->>'mensagem')
            );
        END IF;
    END IF;

    -- --------------------------------------------------------------------------
    -- 6. TODAS AS CONDIÇÕES FORAM APROVADAS -> EXECUTAR MUTAÇÕES ATÔMICAS
    -- --------------------------------------------------------------------------

    IF p_criar_novo_motorista THEN
        -- Busca dados do perfil do usuário para compor dados do motorista
        SELECT * INTO v_perfil FROM public.perfis_usuarios WHERE id = v_solicitacao.user_id;

        v_nome_final := COALESCE(NULLIF(TRIM(p_nome_motorista), ''), v_perfil.nome, 'Motorista Operacional');
        v_telefone_final := COALESCE(NULLIF(TRIM(p_telefone_motorista), ''), v_perfil.telefone, '(00) 00000-0000');
        v_modelo_final := CASE 
            WHEN v_veiculo.id IS NOT NULL THEN (v_veiculo.marca || ' ' || v_veiculo.modelo)
            ELSE 'Veículo Não Declarado'
        END;
        v_placa_final := CASE
            WHEN v_veiculo.id IS NOT NULL THEN v_veiculo.placa
            ELSE 'SEM-PLACA'
        END;

        -- Previne duplicidade de cadastro na retentativa: busca se já existe motorista desta empresa para este user_id
        SELECT id INTO v_motorista_existente_id
        FROM public.motoristas
        WHERE empresa_id = v_solicitacao.empresa_id
          AND user_id = v_solicitacao.user_id
        LIMIT 1;

        IF v_motorista_existente_id IS NOT NULL THEN
            UPDATE public.motoristas
            SET nome = v_nome_final,
                telefone = v_telefone_final,
                email = v_perfil.email,
                veiculo_modelo = v_modelo_final,
                veiculo_placa = v_placa_final,
                status = 'disponivel',
                ativo = TRUE,
                updated_at = timezone('utc'::text, now())
            WHERE id = v_motorista_existente_id;

            v_motorista_final_id := v_motorista_existente_id;
        ELSE
            INSERT INTO public.motoristas (
                empresa_id,
                user_id,
                nome,
                telefone,
                email,
                veiculo_modelo,
                veiculo_placa,
                status,
                ativo
            ) VALUES (
                v_solicitacao.empresa_id,
                v_solicitacao.user_id,
                v_nome_final,
                v_telefone_final,
                v_perfil.email,
                v_modelo_final,
                v_placa_final,
                'disponivel',
                TRUE
            )
            RETURNING id INTO v_motorista_final_id;
        END IF;

    ELSE
        -- Opção B: vincula o motorista selecionado
        UPDATE public.motoristas
        SET user_id = v_solicitacao.user_id,
            ativo = TRUE,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_motorista.id;

        v_motorista_final_id := v_motorista.id;
    END IF;

    -- --------------------------------------------------------------------------
    -- 7. ATUALIZAÇÃO DO VEÍCULO (SE APROVAÇÃO FOI EXPLICITAMENTE CONCEDIDA)
    -- --------------------------------------------------------------------------
    IF p_aprovar_veiculo AND v_veiculo.id IS NOT NULL AND v_veiculo.empresa_id = v_solicitacao.empresa_id THEN
        UPDATE public.veiculos_motoristas
        SET status_analise = 'aprovado',
            revisao = revisao + 1,
            analisado_por = auth.uid(),
            analisado_em = timezone('utc'::text, now()),
            motivo_rejeicao = NULL,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo.id AND empresa_id = v_solicitacao.empresa_id;

        UPDATE public.veiculos_documentos
        SET status_analise = 'aprovado',
            analisado_por = auth.uid(),
            analisado_em = timezone('utc'::text, now()),
            motivo_rejeicao = NULL,
            updated_at = timezone('utc'::text, now())
        WHERE veiculo_id = v_veiculo.id AND empresa_id = v_solicitacao.empresa_id;
    END IF;

    -- --------------------------------------------------------------------------
    -- 8. ATUALIZA A SOLICITAÇÃO DE ACESSO
    -- --------------------------------------------------------------------------
    UPDATE public.solicitacoes_acesso
    SET status = 'aprovado',
        motorista_vinculado_id = v_motorista_final_id,
        motivo_decisao = 'Aprovado pela gestão',
        decidido_por = auth.uid(),
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

    -- --------------------------------------------------------------------------
    -- 9. INSERE OU ATUALIZA O MEMBRO EM EMPRESA_MEMBROS
    -- --------------------------------------------------------------------------
    INSERT INTO public.empresa_membros (
        empresa_id,
        user_id,
        papel,
        status,
        motorista_id,
        motivo_decisao,
        aprovado_por,
        aprovado_em,
        updated_at
    ) VALUES (
        v_solicitacao.empresa_id,
        v_solicitacao.user_id,
        'motorista',
        'aprovado',
        v_motorista_final_id,
        'Aprovado pela gestão',
        auth.uid(),
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    )
    ON CONFLICT (empresa_id, user_id) DO UPDATE SET
        papel = 'motorista',
        status = 'aprovado',
        motorista_id = v_motorista_final_id,
        motivo_decisao = 'Aprovado pela gestão',
        aprovado_por = auth.uid(),
        aprovado_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now());

    -- --------------------------------------------------------------------------
    -- 10. AUDITORIA DA APROVAÇÃO
    -- --------------------------------------------------------------------------
    INSERT INTO public.auditoria_acessos (
        empresa_id,
        user_id,
        acao,
        status_anterior,
        novo_status,
        motorista_id,
        motivo,
        executado_por,
        detalhes
    ) VALUES (
        v_solicitacao.empresa_id,
        v_solicitacao.user_id,
        'aprovacao_motorista',
        v_solicitacao.status,
        'aprovado',
        v_motorista_final_id,
        'Aprovado pela gestão',
        auth.uid(),
        jsonb_build_object(
            'solicitacao_id', v_solicitacao.id,
            'criou_novo_motorista', p_criar_novo_motorista,
            'motorista_id', v_motorista_final_id,
            'veiculo_id', CASE WHEN v_veiculo.id IS NOT NULL THEN v_veiculo.id ELSE NULL END,
            'veiculo_aprovado', p_aprovar_veiculo,
            'revisao_veiculo_analisada', p_revisao_esperada_veiculo
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'APROVADO_COM_SUCESSO',
        'mensagem', 'Motorista aprovado e vinculado com sucesso.',
        'motorista_id', v_motorista_final_id,
        'veiculo_aprovado', p_aprovar_veiculo
    );
END;
$$;
