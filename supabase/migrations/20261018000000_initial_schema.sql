-- ==============================================================================
-- ENTREGA CONDO - MODELAGEM DE DADOS DO BANCO SUPABASE
-- Data: 2026-10-18
-- Descrição: Tabelas essenciais, índices, triggers de recálculo de tempo médio 
-- e Row Level Security (RLS) para o painel de gestão logística.
-- ==============================================================================

-- 1. Habilitar extensões úteis
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- TABELA: motoristas
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.motoristas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(255) NOT NULL,
    telefone VARCHAR(30) NOT NULL,
    email VARCHAR(255) UNIQUE,
    veiculo_modelo VARCHAR(100) NOT NULL,
    veiculo_placa VARCHAR(20) NOT NULL UNIQUE,
    status VARCHAR(30) NOT NULL DEFAULT 'disponivel' 
        CHECK (status IN ('disponivel', 'em_rota', 'pausado', 'offline')),
    latitude_atual NUMERIC(10, 7),
    longitude_atual NUMERIC(10, 7),
    capacidade_max_pacotes INT NOT NULL DEFAULT 60,
    avaliacao_media NUMERIC(3, 2) NOT NULL DEFAULT 5.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- TABELA: clientes_enderecos (Condomínios, Prédios e Endereços Salvos)
-- Armazena o tempo médio histórico de atendimento em cada condomínio/endereço
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.clientes_enderecos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome_identificador VARCHAR(255) NOT NULL,
    destinatario_padrao VARCHAR(255),
    endereco_completo TEXT NOT NULL,
    numero VARCHAR(50) NOT NULL,
    bairro VARCHAR(100) NOT NULL,
    cidade VARCHAR(100) NOT NULL,
    cep VARCHAR(20) NOT NULL,
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    tempo_medio_minutos NUMERIC(5, 2) NOT NULL DEFAULT 10.00,
    total_entregas_realizadas INT NOT NULL DEFAULT 0,
    tipo_local VARCHAR(50) NOT NULL DEFAULT 'condominio_horizontal'
        CHECK (tipo_local IN ('condominio_horizontal', 'edificio_vertical', 'comercial', 'casa_rua')),
    observacoes_acesso TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- TABELA: entregas
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.entregas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    codigo_rastreio VARCHAR(50) NOT NULL UNIQUE,
    cliente_endereco_id UUID NOT NULL REFERENCES public.clientes_enderecos(id) ON DELETE RESTRICT,
    destinatario_nome VARCHAR(255) NOT NULL,
    destinatario_telefone VARCHAR(30),
    unidade_apartamento VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'pendente'
        CHECK (status IN ('pendente', 'atribuida', 'em_transito', 'entregue', 'tentativa_falha', 'cancelada')),
    prioridade VARCHAR(20) NOT NULL DEFAULT 'normal'
        CHECK (prioridade IN ('baixa', 'normal', 'alta', 'urgente')),
    tipo_tarefa VARCHAR(30) NOT NULL DEFAULT 'entrega'
        CHECK (tipo_tarefa IN ('entrega', 'coleta', 'outros')),
    descricao_outro VARCHAR(255),
    peso_kg NUMERIC(6, 2),
    volumes_qtd INT NOT NULL DEFAULT 1,
    motorista_id UUID REFERENCES public.motoristas(id) ON DELETE SET NULL,
    rota_id UUID,
    ordem_na_rota INT,
    janela_inicio TIME,
    janela_fim TIME,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- TABELA: historico_atendimentos
-- Base analítica para cálculo contínuo do tempo real gasto em cada condomínio
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.historico_atendimentos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entrega_id UUID NOT NULL REFERENCES public.entregas(id) ON DELETE CASCADE,
    cliente_endereco_id UUID NOT NULL REFERENCES public.clientes_enderecos(id) ON DELETE CASCADE,
    motorista_id UUID NOT NULL REFERENCES public.motoristas(id) ON DELETE CASCADE,
    tempo_portaria_espera_minutos NUMERIC(5, 2) NOT NULL DEFAULT 0.00,
    tempo_deslocamento_interno_minutos NUMERIC(5, 2) NOT NULL DEFAULT 0.00,
    tempo_total_minutos NUMERIC(5, 2) NOT NULL,
    data_hora_chegada TIMESTAMPTZ NOT NULL,
    data_hora_conclusao TIMESTAMPTZ NOT NULL,
    sucesso BOOLEAN NOT NULL DEFAULT TRUE,
    motivo_falha TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- TABELA: rotas_planejadas
-- Registra a otimização calculada pelo dashboard para comparação e auditoria
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rotas_planejadas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    motorista_id UUID NOT NULL REFERENCES public.motoristas(id) ON DELETE CASCADE,
    status VARCHAR(30) NOT NULL DEFAULT 'planejada'
        CHECK (status IN ('planejada', 'em_execucao', 'concluida', 'cancelada')),
    distancia_original_km NUMERIC(7, 2) NOT NULL,
    tempo_original_minutos NUMERIC(7, 2) NOT NULL,
    distancia_otimizada_km NUMERIC(7, 2) NOT NULL,
    tempo_otimizado_minutos NUMERIC(7, 2) NOT NULL,
    percentual_economia_km NUMERIC(5, 2) NOT NULL,
    percentual_economia_tempo NUMERIC(5, 2) NOT NULL,
    ordem_paradas_json JSONB NOT NULL,
    iniciada_em TIMESTAMPTZ,
    concluida_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ------------------------------------------------------------------------------
-- ÍNDICES DE PERFORMANCE
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_motoristas_status ON public.motoristas(status);
CREATE INDEX IF NOT EXISTS idx_entregas_status ON public.entregas(status);
CREATE INDEX IF NOT EXISTS idx_entregas_motorista ON public.entregas(motorista_id);
CREATE INDEX IF NOT EXISTS idx_entregas_cliente ON public.entregas(cliente_endereco_id);
CREATE INDEX IF NOT EXISTS idx_hist_cliente ON public.historico_atendimentos(cliente_endereco_id);
CREATE INDEX IF NOT EXISTS idx_clientes_coords ON public.clientes_enderecos(latitude, longitude);

-- ------------------------------------------------------------------------------
-- TRIGGER LOGÍSTICO INTELIGENTE:
-- Recalcula automaticamente a média de tempo no condomínio após cada atendimento
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_recalcular_tempo_medio_condominio()
RETURNS TRIGGER AS $$
DECLARE
    v_media NUMERIC(5, 2);
    v_total INT;
BEGIN
    SELECT 
        ROUND(AVG(tempo_total_minutos), 2),
        COUNT(*)
    INTO 
        v_media,
        v_total
    FROM public.historico_atendimentos
    WHERE cliente_endereco_id = NEW.cliente_endereco_id;

    UPDATE public.clientes_enderecos
    SET 
        tempo_medio_minutos = COALESCE(v_media, 10.00),
        total_entregas_realizadas = COALESCE(v_total, 0),
        updated_at = timezone('utc'::text, now())
    WHERE id = NEW.cliente_endereco_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_atualiza_tempo_medio ON public.historico_atendimentos;
CREATE TRIGGER trg_atualiza_tempo_medio
AFTER INSERT OR UPDATE ON public.historico_atendimentos
FOR EACH ROW
EXECUTE FUNCTION public.fn_recalcular_tempo_medio_condominio();

-- ------------------------------------------------------------------------------
-- HABILITAÇÃO DO ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------------------------
ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes_enderecos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historico_atendimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rotas_planejadas ENABLE ROW LEVEL SECURITY;

-- Políticas de Leitura/Escrita para Usuários Autenticados
CREATE POLICY "Permitir leitura geral a autenticados" ON public.motoristas FOR SELECT TO authenticated USING (true);
CREATE POLICY "Permitir edicao geral a autenticados" ON public.motoristas FOR ALL TO authenticated USING (true);

CREATE POLICY "Permitir leitura clientes a autenticados" ON public.clientes_enderecos FOR SELECT TO authenticated USING (true);
CREATE POLICY "Permitir edicao clientes a autenticados" ON public.clientes_enderecos FOR ALL TO authenticated USING (true);

CREATE POLICY "Permitir leitura entregas a autenticados" ON public.entregas FOR SELECT TO authenticated USING (true);
CREATE POLICY "Permitir edicao entregas a autenticados" ON public.entregas FOR ALL TO authenticated USING (true);

CREATE POLICY "Permitir leitura historico a autenticados" ON public.historico_atendimentos FOR SELECT TO authenticated USING (true);
CREATE POLICY "Permitir edicao historico a autenticados" ON public.historico_atendimentos FOR ALL TO authenticated USING (true);

CREATE POLICY "Permitir leitura rotas a autenticados" ON public.rotas_planejadas FOR SELECT TO authenticated USING (true);
CREATE POLICY "Permitir edicao rotas a autenticados" ON public.rotas_planejadas FOR ALL TO authenticated USING (true);
