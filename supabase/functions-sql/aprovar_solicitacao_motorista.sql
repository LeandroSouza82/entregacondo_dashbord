-- ==============================================================================
-- FUNÇÃO SQL: aprovar_solicitacao_motorista.sql
-- Aprovação auditada de motorista pela gestão da empresa.
-- Atômica e consistente sob concorrência (FOR UPDATE).
-- Suporta:
--   Opção A: Criar cadastro de motorista novo a partir da solicitação real.
--   Opção B: Vincular a um cadastro existente desocupado da frota.
-- Valida autorização de gestão ANTES da resposta de idempotência.
-- Valida concorrência via p_revisao_esperada_veiculo.
-- Valida obrigatoriedades e impede aprovação indevida de veículos incompletos.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.aprovar_solicitacao_motorista(
    p_solicitacao_id UUID,
    p_motorista_id UUID DEFAULT NULL,
    p_criar_novo_motorista BOOLEAN DEFAULT FALSE,
    p_nome_motorista TEXT DEFAULT NULL,
    p_telefone_motorista VARCHAR DEFAULT NULL,
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
    v_motorista_final_id UUID;
    v_nome_final TEXT;
    v_telefone_final VARCHAR(30);
    v_modelo_final VARCHAR(100);
    v_placa_final VARCHAR(20);
    v_validacao_veic JSONB;
BEGIN
    -- 1. Localiza e bloqueia a solicitação para concorrência
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

    -- 2. Valida autorização do executor PRIMEIRO (gestor ou admin da empresa)
    -- Impede vazamento de informações para chamadas não autorizadas
    IF NOT public.fn_usuario_e_gestor_empresa(v_solicitacao.empresa_id) THEN
        RETURN jsonb_build_object(
            'sucesso', FALSE,
            'codigo', 'ACESSO_NEGADO',
            'mensagem', 'Apenas gestores ou administradores desta empresa podem aprovar solicitações.'
        );
    END IF;

    -- 3. Idempotência autorizada: se já aprovada por esta empresa, retorna sucesso sem duplicar
    IF v_solicitacao.status = 'aprovado' THEN
        RETURN jsonb_build_object(
            'sucesso', TRUE,
            'codigo', 'JA_APROVADO',
            'mensagem', 'Esta solicitação já foi aprovada anteriormente.',
            'motorista_id', v_solicitacao.motorista_vinculado_id
        );
    END IF;

    -- 4. Definição do motorista (Opção A: Criar Novo | Opção B: Vincular Existente)
    IF p_criar_novo_motorista THEN
        -- Busca dados do perfil do usuário
        SELECT * INTO v_perfil FROM public.perfis_usuarios WHERE id = v_solicitacao.user_id;
        -- Busca veículo declarado se houver
        SELECT * INTO v_veiculo FROM public.veiculos_motoristas WHERE user_id = v_solicitacao.user_id FOR UPDATE;

        v_nome_final := COALESCE(NULLIF(TRIM(p_nome_motorista), ''), v_perfil.nome, 'Motorista Operacional');
        v_telefone_final := COALESCE(NULLIF(TRIM(p_telefone_motorista), ''), v_perfil.telefone, '(00) 00000-0000');
        v_modelo_final := CASE 
            WHEN v_veiculo.id IS NOT NULL THEN (v_veiculo.marca || ' ' || v_veiculo.modelo)
            ELSE 'Veículo Declarado'
        END;
        v_placa_final := COALESCE(v_veiculo.placa, 'SEM-PLACA');

        -- Insere novo registro de motorista na frota da empresa
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

        -- Validação condicional do veículo com conferência de revisão
        IF v_veiculo.id IS NOT NULL THEN
            IF p_revisao_esperada_veiculo IS NOT NULL AND v_veiculo.revisao != p_revisao_esperada_veiculo THEN
                RETURN jsonb_build_object(
                    'sucesso', FALSE,
                    'codigo', 'REVISAO_DESATUALIZADA',
                    'mensagem', 'O veículo do condutor foi alterado durante a análise (revisão atual: ' || v_veiculo.revisao || ', esperada: ' || p_revisao_esperada_veiculo || '). Atualize e revise a versão atual antes de aprovar.',
                    'revisao_esperada', p_revisao_esperada_veiculo,
                    'revisao_atual', v_veiculo.revisao
                );
            END IF;

            v_validacao_veic := public.fn_validar_completude_veiculo(v_veiculo.id);

            IF (v_validacao_veic->>'valido')::boolean = TRUE THEN
                UPDATE public.veiculos_motoristas
                SET status_analise = 'aprovado',
                    revisao = revisao + 1,
                    analisado_por = auth.uid(),
                    analisado_em = timezone('utc'::text, now()),
                    motivo_rejeicao = NULL,
                    updated_at = timezone('utc'::text, now())
                WHERE id = v_veiculo.id;

                UPDATE public.veiculos_documentos
                SET status_analise = 'aprovado',
                    analisado_por = auth.uid(),
                    analisado_em = timezone('utc'::text, now()),
                    motivo_rejeicao = NULL,
                    updated_at = timezone('utc'::text, now())
                WHERE veiculo_id = v_veiculo.id;
            ELSE
                -- Veículo incompleto ou sem arquivo no Storage NÃO pode ser marcado como aprovado
                UPDATE public.veiculos_motoristas
                SET status_analise = 'pendente',
                    updated_at = timezone('utc'::text, now())
                WHERE id = v_veiculo.id;
            END IF;
        END IF;

    ELSE
        -- Opção B: Vinculação a cadastro pré-existente
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

        -- Atualiza o motorista existente com o user_id do condutor
        UPDATE public.motoristas
        SET user_id = v_solicitacao.user_id,
            ativo = TRUE,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_motorista.id;

        v_motorista_final_id := v_motorista.id;
    END IF;

    -- 5. Atualiza a solicitação de acesso
    UPDATE public.solicitacoes_acesso
    SET status = 'aprovado',
        motorista_vinculado_id = v_motorista_final_id,
        motivo_decisao = 'Aprovado pela gestão',
        decidido_por = auth.uid(),
        decidido_em = timezone('utc'::text, now()),
        updated_at = timezone('utc'::text, now())
    WHERE id = v_solicitacao.id;

    -- 6. Insere ou atualiza o membro em empresa_membros
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

    -- 7. Auditoria com revisão analisada
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
            'revisao_veiculo_analisada', p_revisao_esperada_veiculo,
            'veiculo_aprovado', CASE WHEN v_validacao_veic IS NOT NULL THEN (v_validacao_veic->>'valido')::boolean ELSE FALSE END
        )
    );

    RETURN jsonb_build_object(
        'sucesso', TRUE,
        'codigo', 'APROVADO_COM_SUCESSO',
        'mensagem', 'Motorista aprovado e vinculado com sucesso.',
        'motorista_id', v_motorista_final_id
    );
END;
$$;
