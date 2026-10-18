-- ==============================================================================
-- MIGRATION: 20261018020000_security_hardening_and_vehicle_management.sql
-- Módulo: Endurecimento de Segurança, Quarentena Legada, Cadastro Veicular e RLS Estrito
-- EntregaCondo - Dashboard & Mobile Integration
-- ==============================================================================

-- 1. Quarentena de registros legados sem empresa (sem atribuição arbitrária)
CREATE TABLE IF NOT EXISTS public._quarentena_registros_orfaos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tabela_origem VARCHAR(100) NOT NULL,
    registro_id UUID NOT NULL,
    dados JSONB NOT NULL,
    motivo VARCHAR(255) NOT NULL,
    quarentenado_em TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

DO $$
BEGIN
    -- Isola e remove registros órfãos sem empresa se houver
    IF EXISTS (SELECT 1 FROM public.motoristas WHERE empresa_id IS NULL) THEN
        INSERT INTO public._quarentena_registros_orfaos (tabela_origem, registro_id, dados, motivo)
        SELECT 'motoristas', id, to_jsonb(m), 'empresa_id_nulo_legado'
        FROM public.motoristas m WHERE empresa_id IS NULL;
        DELETE FROM public.motoristas WHERE empresa_id IS NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM public.clientes_enderecos WHERE empresa_id IS NULL) THEN
        INSERT INTO public._quarentena_registros_orfaos (tabela_origem, registro_id, dados, motivo)
        SELECT 'clientes_enderecos', id, to_jsonb(c), 'empresa_id_nulo_legado'
        FROM public.clientes_enderecos c WHERE empresa_id IS NULL;
        DELETE FROM public.clientes_enderecos WHERE empresa_id IS NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM public.entregas WHERE empresa_id IS NULL) THEN
        INSERT INTO public._quarentena_registros_orfaos (tabela_origem, registro_id, dados, motivo)
        SELECT 'entregas', id, to_jsonb(e), 'empresa_id_nulo_legado'
        FROM public.entregas e WHERE empresa_id IS NULL;
        DELETE FROM public.entregas WHERE empresa_id IS NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM public.rotas_planejadas WHERE empresa_id IS NULL) THEN
        INSERT INTO public._quarentena_registros_orfaos (tabela_origem, registro_id, dados, motivo)
        SELECT 'rotas_planejadas', id, to_jsonb(r), 'empresa_id_nulo_legado'
        FROM public.rotas_planejadas r WHERE empresa_id IS NULL;
        DELETE FROM public.rotas_planejadas WHERE empresa_id IS NULL;
    END IF;
END $$;

-- 2. Aplicação de NOT NULL estrito em empresa_id
ALTER TABLE public.motoristas ALTER COLUMN empresa_id SET NOT NULL;
ALTER TABLE public.clientes_enderecos ALTER COLUMN empresa_id SET NOT NULL;
ALTER TABLE public.rotas_planejadas ALTER COLUMN empresa_id SET NOT NULL;
ALTER TABLE public.entregas ALTER COLUMN empresa_id SET NOT NULL;

-- 3. Idempotência sob concorrência em rotas_planejadas
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(100);
ALTER TABLE public.rotas_planejadas ADD COLUMN IF NOT EXISTS payload_hash VARCHAR(64);

-- Preenche idempotency_key legado se necessário
UPDATE public.rotas_planejadas 
SET idempotency_key = id::text 
WHERE idempotency_key IS NULL;

ALTER TABLE public.rotas_planejadas ALTER COLUMN idempotency_key SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_rota_empresa_idempotency'
    ) THEN
        ALTER TABLE public.rotas_planejadas 
        ADD CONSTRAINT uq_rota_empresa_idempotency UNIQUE (empresa_id, idempotency_key);
    END IF;
END $$;

-- 4. Tabela de Veículos Declarados (Carro / Moto)
CREATE TABLE IF NOT EXISTS public.veiculos_motoristas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    tipo_veiculo VARCHAR(20) NOT NULL CHECK (tipo_veiculo IN ('carro', 'moto')),
    marca VARCHAR(100) NOT NULL,
    modelo VARCHAR(100) NOT NULL,
    placa VARCHAR(20) NOT NULL,
    compartimento VARCHAR(20) CHECK (compartimento IN ('bau', 'mochila')),
    volume_litros NUMERIC(7, 2),
    largura_cm NUMERIC(6, 2),
    altura_cm NUMERIC(6, 2),
    profundidade_cm NUMERIC(6, 2),
    capacidade_kg NUMERIC(6, 2),
    status_aprovacao VARCHAR(30) NOT NULL DEFAULT 'pendente' CHECK (status_aprovacao IN ('pendente', 'aprovado', 'rejeitado')),
    motivo_rejeicao TEXT,
    aprovado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    aprovado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_veiculo_user_empresa UNIQUE (empresa_id, user_id),
    CONSTRAINT ck_veiculo_regras_tipo CHECK (
        (tipo_veiculo = 'carro' AND compartimento IS NULL AND volume_litros IS NULL AND largura_cm IS NULL AND altura_cm IS NULL AND profundidade_cm IS NULL AND capacidade_kg IS NULL)
        OR
        (tipo_veiculo = 'moto' AND compartimento IS NOT NULL AND volume_litros > 0 AND largura_cm > 0 AND altura_cm > 0 AND profundidade_cm > 0 AND capacidade_kg > 0)
    )
);

-- 5. Remoção de assinaturas antigas inseguras
DROP FUNCTION IF EXISTS public.solicitar_acesso_empresa(TEXT, TEXT);

-- 6. RPC: Cadastro de Veículo pelo Motorista
CREATE OR REPLACE FUNCTION public.cadastrar_meu_veiculo(
    p_dados JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_empresa_id UUID;
    v_tipo_veiculo TEXT;
    v_marca TEXT;
    v_modelo TEXT;
    v_placa TEXT;
    v_compartimento TEXT;
    v_volume_litros NUMERIC;
    v_largura_cm NUMERIC;
    v_altura_cm NUMERIC;
    v_profundidade_cm NUMERIC;
    v_capacidade_kg NUMERIC;
    v_veiculo_existente RECORD;
    v_novo_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'NAO_AUTORIZADO', 'mensagem', 'Autentique-se primeiro.');
    END IF;

    SELECT empresa_id INTO v_empresa_id
    FROM public.empresa_membros
    WHERE user_id = v_user_id
    LIMIT 1;

    IF v_empresa_id IS NULL THEN
        SELECT empresa_id INTO v_empresa_id
        FROM public.solicitacoes_acesso
        WHERE user_id = v_user_id
        LIMIT 1;
    END IF;

    IF v_empresa_id IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'SEM_EMPRESA', 'mensagem', 'Você precisa primeiro solicitar vínculo com uma empresa antes de cadastrar seu veículo.');
    END IF;

    v_tipo_veiculo := LOWER(TRIM(p_dados->>'tipo_veiculo'));
    IF v_tipo_veiculo NOT IN ('carro', 'moto') THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'TIPO_VEICULO_INVALIDO', 'mensagem', 'Tipo de veículo inválido. Escolha "carro" ou "moto".');
    END IF;

    v_marca := TRIM(p_dados->>'marca');
    v_modelo := TRIM(p_dados->>'modelo');
    v_placa := UPPER(REGEXP_REPLACE(TRIM(p_dados->>'placa'), '[^a-zA-Z0-9]', '', 'g'));

    IF v_marca IS NULL OR v_marca = '' OR v_modelo IS NULL OR v_modelo = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'DADOS_INCOMPLETOS', 'mensagem', 'Marca e modelo são obrigatórios.');
    END IF;

    IF LENGTH(v_placa) != 7 THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'PLACA_INVALIDA', 'mensagem', 'Placa inválida. Deve conter 7 caracteres alfanuméricos.');
    END IF;

    IF v_tipo_veiculo = 'carro' THEN
        v_compartimento := NULL;
        v_volume_litros := NULL;
        v_largura_cm := NULL;
        v_altura_cm := NULL;
        v_profundidade_cm := NULL;
        v_capacidade_kg := NULL;
    ELSE
        v_compartimento := LOWER(TRIM(p_dados->>'compartimento'));
        IF v_compartimento NOT IN ('bau', 'mochila') THEN
            RETURN jsonb_build_object('sucesso', false, 'codigo', 'COMPARTIMENTO_OBRIGATORIO', 'mensagem', 'Para moto, é obrigatório selecionar o compartimento ("bau" ou "mochila").');
        END IF;

        v_volume_litros := (p_dados->>'volume_litros')::NUMERIC;
        v_largura_cm := (p_dados->>'largura_cm')::NUMERIC;
        v_altura_cm := (p_dados->>'altura_cm')::NUMERIC;
        v_profundidade_cm := (p_dados->>'profundidade_cm')::NUMERIC;
        v_capacidade_kg := (p_dados->>'capacidade_kg')::NUMERIC;

        IF v_volume_litros IS NULL OR v_volume_litros <= 0 OR
           v_largura_cm IS NULL OR v_largura_cm <= 0 OR
           v_altura_cm IS NULL OR v_altura_cm <= 0 OR
           v_profundidade_cm IS NULL OR v_profundidade_cm <= 0 OR
           v_capacidade_kg IS NULL OR v_capacidade_kg <= 0 THEN
            RETURN jsonb_build_object('sucesso', false, 'codigo', 'MEDIDAS_INVALIDAS', 'mensagem', 'Para moto, informe valores válidos e estritamente positivos para volume, dimensões e capacidade.');
        END IF;
    END IF;

    SELECT * INTO v_veiculo_existente
    FROM public.veiculos_motoristas
    WHERE user_id = v_user_id AND empresa_id = v_empresa_id;

    IF v_veiculo_existente IS NOT NULL THEN
        UPDATE public.veiculos_motoristas
        SET tipo_veiculo = v_tipo_veiculo,
            marca = v_marca,
            modelo = v_modelo,
            placa = v_placa,
            compartimento = v_compartimento,
            volume_litros = v_volume_litros,
            largura_cm = v_largura_cm,
            altura_cm = v_altura_cm,
            profundidade_cm = v_profundidade_cm,
            capacidade_kg = v_capacidade_kg,
            status_aprovacao = 'pendente',
            motivo_rejeicao = NULL,
            aprovado_por = NULL,
            aprovado_em = NULL,
            updated_at = timezone('utc'::text, now())
        WHERE id = v_veiculo_existente.id
        RETURNING id INTO v_novo_id;
    ELSE
        INSERT INTO public.veiculos_motoristas (
            empresa_id, user_id, tipo_veiculo, marca, modelo, placa,
            compartimento, volume_litros, largura_cm, altura_cm, profundidade_cm, capacidade_kg,
            status_aprovacao
        )
        VALUES (
            v_empresa_id, v_user_id, v_tipo_veiculo, v_marca, v_modelo, v_placa,
            v_compartimento, v_volume_litros, v_largura_cm, v_altura_cm, v_profundidade_cm, v_capacidade_kg,
            'pendente'
        )
        RETURNING id INTO v_novo_id;
    END IF;

    INSERT INTO public.auditoria_acessos (
        empresa_id, user_id, acao, status_anterior, novo_status, motivo, executado_por, detalhes
    )
    VALUES (
        v_empresa_id, v_user_id, 'cadastro_veiculo_declarado', NULL, 'pendente',
        'Cadastro veicular enviado pelo motorista para aprovação (' || v_tipo_veiculo || ' ' || v_modelo || ')',
        v_user_id,
        jsonb_build_object('veiculo_id', v_novo_id, 'tipo', v_tipo_veiculo, 'placa', v_placa)
    );

    RETURN jsonb_build_object(
        'sucesso', true,
        'codigo', 'VEICULO_REGISTRADO',
        'veiculo_id', v_novo_id,
        'tipo_veiculo', v_tipo_veiculo,
        'placa', v_placa,
        'status_aprovacao', 'pendente',
        'mensagem', 'Veículo cadastrado com sucesso. Aguardando análise e aprovação pela gestão.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 7. RPCs de Operação do Motorista (Iniciar e Concluir Rota)
CREATE OR REPLACE FUNCTION public.iniciar_rota(
    p_rota_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_rota RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado.';
    END IF;

    SELECT r.* INTO v_rota
    FROM public.rotas_planejadas r
    JOIN public.motoristas m ON m.id = r.motorista_id
    JOIN public.empresa_membros em ON em.user_id = v_user_id AND em.motorista_id = m.id AND em.status = 'aprovado'
    WHERE r.id = p_rota_id
      AND m.user_id = v_user_id;

    IF v_rota IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Rota não encontrada ou não atribuída a você.');
    END IF;

    IF v_rota.status = 'em_execucao' THEN
        RETURN jsonb_build_object('sucesso', true, 'codigo', 'JA_INICIADA', 'status', 'em_execucao', 'mensagem', 'Rota já está em execução.');
    END IF;

    IF v_rota.status != 'planejada' THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'STATUS_INVALIDO', 'mensagem', 'Apenas rotas planejadas podem ser iniciadas.');
    END IF;

    UPDATE public.rotas_planejadas
    SET status = 'em_execucao',
        iniciada_em = timezone('utc'::text, now())
    WHERE id = p_rota_id;

    UPDATE public.entregas
    SET status = 'em_transito', updated_at = timezone('utc'::text, now())
    WHERE rota_id = p_rota_id AND status = 'atribuida';

    RETURN jsonb_build_object('sucesso', true, 'codigo', 'SUCESSO', 'status', 'em_execucao', 'mensagem', 'Rota iniciada com sucesso.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.concluir_rota(
    p_rota_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_rota RECORD;
    v_pendencias INT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado.';
    END IF;

    SELECT r.* INTO v_rota
    FROM public.rotas_planejadas r
    JOIN public.motoristas m ON m.id = r.motorista_id
    JOIN public.empresa_membros em ON em.user_id = v_user_id AND em.motorista_id = m.id AND em.status = 'aprovado'
    WHERE r.id = p_rota_id
      AND m.user_id = v_user_id;

    IF v_rota IS NULL THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ACESSO_NEGADO', 'mensagem', 'Rota não encontrada ou não atribuída a você.');
    END IF;

    IF v_rota.status = 'concluida' THEN
        RETURN jsonb_build_object('sucesso', true, 'codigo', 'JA_CONCLUIDA', 'status', 'concluida', 'mensagem', 'Rota já está concluída.');
    END IF;

    SELECT COUNT(*) INTO v_pendencias
    FROM public.entregas
    WHERE rota_id = p_rota_id
      AND status IN ('atribuida', 'em_transito', 'pendente');

    IF v_pendencias > 0 THEN
        RETURN jsonb_build_object('sucesso', false, 'codigo', 'ENTREGAS_PENDENTES', 'mensagem', 'Não é possível concluir a rota. Existem ' || v_pendencias || ' entregas pendentes.');
    END IF;

    UPDATE public.rotas_planejadas
    SET status = 'concluida',
        concluida_em = timezone('utc'::text, now())
    WHERE id = p_rota_id;

    UPDATE public.motoristas
    SET status = 'disponivel', updated_at = timezone('utc'::text, now())
    WHERE id = v_rota.motorista_id;

    RETURN jsonb_build_object('sucesso', true, 'codigo', 'SUCESSO', 'status', 'concluida', 'mensagem', 'Rota finalizada com sucesso!');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 8. Atualização das Políticas RLS
ALTER TABLE public.veiculos_motoristas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Gestores gerenciam membros da empresa" ON public.empresa_membros;
DROP POLICY IF EXISTS "Gestores gerenciam solicitacoes de sua empresa" ON public.solicitacoes_acesso;
DROP POLICY IF EXISTS "Gestores visualizam solicitacoes de sua empresa" ON public.solicitacoes_acesso;
DROP POLICY IF EXISTS "Gestores visualizam membros da empresa" ON public.empresa_membros;
DROP POLICY IF EXISTS "Gestores gerenciam motoristas da sua empresa" ON public.motoristas;
DROP POLICY IF EXISTS "Gestores gerenciam clientes da empresa" ON public.clientes_enderecos;
DROP POLICY IF EXISTS "Gestores gerenciam rotas da empresa" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Motorista aprovado atualiza apenas suas rotas" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Motorista aprovado atualiza status de suas rotas" ON public.rotas_planejadas;
DROP POLICY IF EXISTS "Gestores gerenciam entregas da empresa" ON public.entregas;
DROP POLICY IF EXISTS "Motorista aprovado atualiza status de suas entregas" ON public.entregas;
DROP POLICY IF EXISTS "Gestores gerenciam historico" ON public.historico_atendimentos;
DROP POLICY IF EXISTS "Motoristas aprovados inserem historico de suas entregas" ON public.historico_atendimentos;

-- Novas políticas restritas
CREATE POLICY "Gestores visualizam solicitacoes de sua empresa" ON public.solicitacoes_acesso
FOR SELECT TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Gestores visualizam membros da empresa" ON public.empresa_membros
FOR SELECT TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Usuario visualiza seu veiculo" ON public.veiculos_motoristas
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Gestores visualizam veiculos de sua empresa" ON public.veiculos_motoristas
FOR SELECT TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Gestores gerenciam motoristas da sua empresa" ON public.motoristas
FOR ALL TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Gestores gerenciam clientes da empresa" ON public.clientes_enderecos
FOR ALL TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Gestores gerenciam rotas da empresa" ON public.rotas_planejadas
FOR ALL TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Gestores gerenciam entregas da empresa" ON public.entregas
FOR ALL TO authenticated
USING (public.fn_usuario_e_gestor_empresa(empresa_id))
WITH CHECK (public.fn_usuario_e_gestor_empresa(empresa_id));

CREATE POLICY "Gestores gerenciam historico" ON public.historico_atendimentos
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.entregas e
        WHERE e.id = public.historico_atendimentos.entrega_id
          AND public.fn_usuario_e_gestor_empresa(e.empresa_id)
    )
);

-- 9. Revogações de escrita direta da API cliente
REVOKE INSERT, UPDATE, DELETE ON public.empresa_membros FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.solicitacoes_acesso FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.veiculos_motoristas FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.auditoria_acessos FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.historico_atendimentos FROM anon, authenticated;
