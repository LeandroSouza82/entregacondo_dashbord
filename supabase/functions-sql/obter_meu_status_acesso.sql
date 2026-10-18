-- ==============================================================================
-- FUNÇÃO SQL: obter_meu_status_acesso.sql
-- RPC Soberana de consulta do estado de acesso do usuário autenticado no app.
-- Diferencia: conta autenticada -> vinculo -> aprovacao -> veiculo -> operacional
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.obter_meu_status_acesso()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_membro RECORD;
    v_solicitacao RECORD;
    v_motorista RECORD;
    v_veiculo RECORD;
    v_empresa RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'autenticado', FALSE,
            'status', 'nao_autenticado',
            'mensagem', 'Nenhuma sessão ativa identificada.'
        );
    END IF;

    -- 1. Busca vínculo na tabela empresa_membros
    SELECT em.*, e.nome AS empresa_nome, e.ativa AS empresa_ativa
    INTO v_membro
    FROM public.empresa_membros em
    JOIN public.empresas e ON e.id = em.empresa_id
    WHERE em.user_id = v_user_id
    ORDER BY em.created_at DESC
    LIMIT 1;

    -- 2. Busca veículo declarado
    SELECT * INTO v_veiculo
    FROM public.veiculos_motoristas
    WHERE user_id = v_user_id;

    -- Caso A: Membro encontrado
    IF v_membro.id IS NOT NULL THEN
        -- Verifica se empresa está ativa
        IF NOT v_membro.empresa_ativa THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'suspenso',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'motivo', 'Empresa desativada pela administração.',
                'mensagem', 'A empresa vinculada está temporariamente inativa.'
            );
        END IF;

        IF v_membro.status = 'suspenso' THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'suspenso',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'motivo', v_membro.motivo_decisao,
                'mensagem', 'Seu acesso foi suspenso pela gestão.'
            );
        ELSIF v_membro.status = 'rejeitado' THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'rejeitado',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'motivo', v_membro.motivo_decisao,
                'mensagem', 'Sua solicitação de acesso foi recusada.'
            );
        ELSIF v_membro.status = 'pendente' THEN
            RETURN jsonb_build_object(
                'autenticado', TRUE,
                'user_id', v_user_id,
                'status', 'pendente',
                'papel', v_membro.papel,
                'empresa_id', v_membro.empresa_id,
                'empresa_nome', v_membro.empresa_nome,
                'veiculo_declarado', v_veiculo.id IS NOT NULL,
                'veiculo_status', v_veiculo.status_analise,
                'mensagem', 'Solicitação aguardando aprovação da gestão.'
            );
        ELSIF v_membro.status = 'aprovado' THEN
            -- Se for gestor ou admin, acesso liberado
            IF v_membro.papel IN ('admin', 'gestor') THEN
                RETURN jsonb_build_object(
                    'autenticado', TRUE,
                    'user_id', v_user_id,
                    'status', 'aprovado',
                    'papel', v_membro.papel,
                    'empresa_id', v_membro.empresa_id,
                    'empresa_nome', v_membro.empresa_nome,
                    'mensagem', 'Acesso administrativo liberado.'
                );
            END IF;

            -- Se for motorista, verifica se já possui motorista_id vinculado na frota
            IF v_membro.motorista_id IS NOT NULL THEN
                SELECT * INTO v_motorista FROM public.motoristas WHERE id = v_membro.motorista_id;
                RETURN jsonb_build_object(
                    'autenticado', TRUE,
                    'user_id', v_user_id,
                    'status', 'aprovado',
                    'papel', 'motorista',
                    'empresa_id', v_membro.empresa_id,
                    'empresa_nome', v_membro.empresa_nome,
                    'motorista_id', v_motorista.id,
                    'motorista_nome', v_motorista.nome,
                    'veiculo', v_motorista.veiculo_modelo || ' (' || v_motorista.veiculo_placa || ')',
                    'veiculo_status', v_veiculo.status_analise,
                    'veiculo_tipo', v_veiculo.tipo_veiculo,
                    'mensagem', 'Acesso operacional liberado com sucesso.'
                );
            ELSE
                RETURN jsonb_build_object(
                    'autenticado', TRUE,
                    'user_id', v_user_id,
                    'status', 'aprovado_sem_cadastro',
                    'papel', 'motorista',
                    'empresa_id', v_membro.empresa_id,
                    'empresa_nome', v_membro.empresa_nome,
                    'veiculo_declarado', v_veiculo.id IS NOT NULL,
                    'veiculo_status', v_veiculo.status_analise,
                    'mensagem', 'Membro aprovado. Aguardando vinculação operacional da frota.'
                );
            END IF;
        END IF;
    END IF;

    -- Caso B: Sem membro, mas com solicitação em solicitacoes_acesso
    SELECT sa.*, e.nome AS empresa_nome
    INTO v_solicitacao
    FROM public.solicitacoes_acesso sa
    JOIN public.empresas e ON e.id = sa.empresa_id
    WHERE sa.user_id = v_user_id
    ORDER BY sa.created_at DESC
    LIMIT 1;

    IF v_solicitacao.id IS NOT NULL THEN
        RETURN jsonb_build_object(
            'autenticado', TRUE,
            'user_id', v_user_id,
            'status', v_solicitacao.status,
            'papel', 'motorista',
            'empresa_id', v_solicitacao.empresa_id,
            'empresa_nome', v_solicitacao.empresa_nome,
            'motivo', v_solicitacao.motivo_decisao,
            'veiculo_declarado', v_veiculo.id IS NOT NULL,
            'veiculo_status', v_veiculo.status_analise,
            'mensagem', CASE 
                WHEN v_solicitacao.status = 'pendente' THEN 'Solicitação aguardando análise da gestão.'
                WHEN v_solicitacao.status = 'rejeitado' THEN 'Solicitação de acesso recusada.'
                ELSE 'Solicitação em análise.'
            END
        );
    END IF;

    -- Caso C: Sem nenhum vínculo ou solicitação
    RETURN jsonb_build_object(
        'autenticado', TRUE,
        'user_id', v_user_id,
        'status', 'sem_vinculo',
        'papel', NULL,
        'empresa_id', NULL,
        'mensagem', 'Conta autenticada sem vínculo empresarial. Insira o código da empresa para solicitar acesso.'
    );
END;
$$;
