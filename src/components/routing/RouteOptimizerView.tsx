import { useState, useMemo } from 'react';
import { 
  Sparkles, 
  MapPin, 
  Clock, 
  TrendingDown, 
  CheckCircle2, 
  Shuffle, 
  Send,
  Building,
  Navigation,
  Compass,
  Zap,
  Info,
  Route
} from 'lucide-react';
import { 
  MOCK_MOTORISTAS, 
  MOCK_PARADAS_INICIAIS, 
  PONTO_BASE_DISTRIBUICAO,
  MOCK_HISTORICO_ATENDIMENTOS
} from '../../services/mockData';
import { 
  optimizeRouteAndCompare, 
  calculateAverageCustomerTime 
} from '../../services/logisticsEngine';
import { formatMinutes, formatDistanceKm, formatBRL } from '../../lib/utils';
import type { PontoParada, ResumoOtimizacaoRota } from '../../types/logistics';

export const RouteOptimizerView: React.FC = () => {
  const [motoristaSelecionadoId, setMotoristaSelecionadoId] = useState<string>(MOCK_MOTORISTAS[0].id);
  const [paradas, setParadas] = useState<PontoParada[]>(MOCK_PARADAS_INICIAIS);
  const [resumoCalculado, setResumoCalculado] = useState<ResumoOtimizacaoRota | null>(null);
  const [isCalculando, setIsCalculando] = useState<boolean>(false);
  const [alertaEnvio, setAlertaEnvio] = useState<string | null>(null);

  const motoristaAtual = useMemo(() => {
    return MOCK_MOTORISTAS.find((m) => m.id === motoristaSelecionadoId) || MOCK_MOTORISTAS[0];
  }, [motoristaSelecionadoId]);

  // Executa o cálculo de otimização e previsão comparativa
  const handleExecutarOtimizacao = () => {
    setIsCalculando(true);
    setAlertaEnvio(null);

    // Pequeno delay para feedback tátil da UI
    setTimeout(() => {
      const resultado = optimizeRouteAndCompare(
        motoristaAtual.id,
        motoristaAtual.nome,
        PONTO_BASE_DISTRIBUICAO,
        paradas,
        new Date()
      );
      setResumoCalculado(resultado);
      setIsCalculando(false);
    }, 400);
  };

  // Simula o envio direto para o App Flutter do Motorista
  const handleEnviarParaMotorista = () => {
    if (!resumoCalculado) return;
    setAlertaEnvio(`Rota otimizada despachada com sucesso para o motorista ${motoristaAtual.nome}! O aplicativo móvel Flutter receberá a nova ordem de entrega.`);
    setTimeout(() => {
      setAlertaEnvio(null);
    }, 6000);
  };

  // Permite embaralhar ou simular nova ordem de cadastro desordenada
  const handleSimularOrdemAleatoria = () => {
    const embaralhada = [...paradas].sort(() => Math.random() - 0.5);
    setParadas(embaralhada);
    setResumoCalculado(null);
  };

  return (
    <div className="space-y-8 animate-fadeIn">
      {/* Top Banner / Hero Title */}
      <div className="bg-white rounded-2xl p-6 border border-slate-200/90 shadow-card flex flex-col lg:flex-row lg:items-center justify-between gap-6">
        <div>
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-terracotta-50 border border-terracotta-200/80 text-terracotta-700 text-xs font-semibold mb-2">
            <Sparkles className="w-3.5 h-3.5 text-terracotta-600" />
            <span>Motor de Inteligência e Roteirização Logística</span>
          </div>
          <h1 className="text-2xl font-extrabold text-navy-900 tracking-tight">
            Otimizador de Rotas com Tempo Médio em Condomínio
          </h1>
          <p className="text-sm text-slate-500 mt-1 max-w-2xl">
            Calcula a menor distância em malha viária urbana cruzando o histórico real de tempo de espera e descarga de cada portaria.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <button
            onClick={handleSimularOrdemAleatoria}
            className="px-4 py-2.5 rounded-xl border border-slate-200 hover:bg-slate-50 text-slate-700 text-xs font-semibold flex items-center gap-2 transition-colors shadow-sm"
            title="Reordenar para testar poder do algoritmo"
          >
            <Shuffle className="w-3.5 h-3.5 text-slate-500" />
            <span>Embaralhar Paradas</span>
          </button>

          <button
            onClick={handleExecutarOtimizacao}
            disabled={isCalculando || paradas.length === 0}
            className={`px-5 py-2.5 rounded-xl text-xs font-bold text-white flex items-center gap-2 shadow-md transition-all ${
              isCalculando
                ? 'bg-slate-400 cursor-not-allowed'
                : 'bg-terracotta-600 hover:bg-terracotta-700 active:scale-95 shadow-terracotta-600/30 ring-2 ring-terracotta-600/20'
            }`}
          >
            <Zap className={`w-4 h-4 ${isCalculando ? 'animate-spin' : ''}`} />
            <span>{isCalculando ? 'Calculando Matriz...' : 'Calcular Rota Otimizada'}</span>
          </button>
        </div>
      </div>

      {/* Alerta de despacho para o App Mobile */}
      {alertaEnvio && (
        <div className="p-4 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm flex items-start gap-3 shadow-sm animate-fadeIn">
          <CheckCircle2 className="w-5 h-5 text-emerald-600 flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            <span className="font-semibold">Despacho Concluído: </span>
            {alertaEnvio}
          </div>
        </div>
      )}

      {/* Grid: Configuração do Motorista + Ponto de Partida */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Seletor de Motorista */}
        <div className="bg-white p-5 rounded-2xl border border-slate-200/90 shadow-card">
          <label className="text-xs font-bold uppercase tracking-wider text-slate-400 block mb-2">
            1. Motorista Responsável
          </label>
          <div className="relative">
            <select
              value={motoristaSelecionadoId}
              onChange={(e) => {
                setMotoristaSelecionadoId(e.target.value);
                setResumoCalculado(null);
              }}
              className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3.5 py-2.5 text-sm font-semibold text-navy-900 focus:outline-none focus:ring-2 focus:ring-terracotta-500/20"
            >
              {MOCK_MOTORISTAS.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.nome} — {m.veiculo_modelo} ({m.veiculo_placa})
                </option>
              ))}
            </select>
          </div>
          <div className="mt-3 flex items-center justify-between text-xs text-slate-500">
            <span>Status: <strong className="text-emerald-700 capitalize">{motoristaAtual.status}</strong></span>
            <span>Avaliação: <strong>★ {motoristaAtual.avaliacao_media}</strong></span>
          </div>
        </div>

        {/* Ponto de Origem / Hub */}
        <div className="bg-white p-5 rounded-2xl border border-slate-200/90 shadow-card">
          <label className="text-xs font-bold uppercase tracking-wider text-slate-400 block mb-2">
            2. Ponto de Partida da Frota
          </label>
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-navy-100 flex items-center justify-center text-navy-800 flex-shrink-0">
              <Navigation className="w-5 h-5" />
            </div>
            <div className="min-w-0">
              <div className="text-sm font-bold text-navy-900 truncate">
                {PONTO_BASE_DISTRIBUICAO.nome}
              </div>
              <div className="text-xs text-slate-500">
                Coordenadas: {PONTO_BASE_DISTRIBUICAO.coordenadas.lat}, {PONTO_BASE_DISTRIBUICAO.coordenadas.lng}
              </div>
            </div>
          </div>
        </div>

        {/* Total de Paradas Selecionadas */}
        <div className="bg-white p-5 rounded-2xl border border-slate-200/90 shadow-card flex items-center justify-between">
          <div>
            <label className="text-xs font-bold uppercase tracking-wider text-slate-400 block mb-1">
              3. Paradas na Rota
            </label>
            <div className="text-2xl font-black text-navy-900">
              {paradas.length} <span className="text-sm font-medium text-slate-500">locais</span>
            </div>
            <p className="text-xs text-slate-500 mt-1">
              {paradas.filter(p => p.prioridade === 'urgente').length > 0 && (
                <span className="text-terracotta-600 font-semibold">
                  ⚠️ Inclui entregas prioritárias
                </span>
              )}
            </p>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-terracotta-50 border border-terracotta-100 flex items-center justify-center text-terracotta-600">
            <MapPin className="w-6 h-6" />
          </div>
        </div>
      </div>

      {/* PAINEL COMPARATIVO DE ALTO IMPACTO (QUANDO CALCULADO) */}
      {resumoCalculado ? (
        <div className="space-y-6 animate-fadeIn">
          {/* Card Resumo com Destaques de Economia */}
          <div className="bg-gradient-to-r from-navy-900 via-navy-800 to-navy-900 text-white p-7 rounded-3xl shadow-floating border border-navy-700/80 relative overflow-hidden">
            {/* Background Glow */}
            <div className="absolute -right-16 -top-16 w-64 h-64 bg-terracotta-600/20 rounded-full blur-3xl pointer-events-none" />

            <div className="relative z-10 flex flex-col lg:flex-row lg:items-center justify-between gap-6 pb-6 border-b border-navy-700/80">
              <div>
                <span className="text-xs uppercase font-bold tracking-wider text-terracotta-400">
                  Resultado da Roteirização Inteligente
                </span>
                <h2 className="text-2xl font-extrabold text-white mt-1">
                  Comparativo de Eficiência Operacional
                </h2>
                <p className="text-xs text-slate-300 mt-1">
                  Motorista designado: <span className="text-white font-semibold">{resumoCalculado.motoristaNome}</span> • Partida: Hub Central
                </p>
              </div>

              <div className="flex items-center gap-3">
                <button
                  onClick={handleEnviarParaMotorista}
                  className="px-5 py-3 rounded-xl bg-gradient-to-r from-terracotta-600 to-terracotta-500 hover:from-terracotta-500 hover:to-terracotta-600 text-white font-bold text-xs flex items-center gap-2 shadow-lg shadow-terracotta-600/40 transition-all hover:scale-105 active:scale-95"
                >
                  <Send className="w-4 h-4" />
                  <span>Despachar p/ App do Motorista</span>
                </button>
              </div>
            </div>

            {/* Métricas Principais Comparativas em 4 colunas */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-6 pt-6">
              {/* Economia de Distância */}
              <div className="bg-navy-850/80 border border-navy-700/70 p-4 rounded-2xl backdrop-blur">
                <div className="flex items-center justify-between text-slate-400 text-xs font-semibold mb-2">
                  <span>Km Total</span>
                  <span className="text-emerald-400 font-bold bg-emerald-500/10 px-2 py-0.5 rounded-full">
                    -{resumoCalculado.metricas.economiaDistanciaPct}%
                  </span>
                </div>
                <div className="text-2xl font-black text-white">
                  {formatDistanceKm(resumoCalculado.metricas.distanciaOtimizadaKm)}
                </div>
                <div className="text-xs text-slate-400 mt-1 line-through">
                  Original: {formatDistanceKm(resumoCalculado.metricas.distanciaOriginalKm)}
                </div>
                <div className="text-[11px] text-emerald-400 font-medium mt-1">
                  ↓ Economia de {formatDistanceKm(resumoCalculado.metricas.economiaDistanciaKm)}
                </div>
              </div>

              {/* Tempo Total de Rota */}
              <div className="bg-navy-850/80 border border-navy-700/70 p-4 rounded-2xl backdrop-blur">
                <div className="flex items-center justify-between text-slate-400 text-xs font-semibold mb-2">
                  <span>Duração Estimada</span>
                  <span className="text-emerald-400 font-bold bg-emerald-500/10 px-2 py-0.5 rounded-full">
                    -{formatMinutes(resumoCalculado.metricas.economiaTempoMin)}
                  </span>
                </div>
                <div className="text-2xl font-black text-white">
                  {formatMinutes(resumoCalculado.metricas.tempoTotalOtimizadoMin)}
                </div>
                <div className="text-xs text-slate-400 mt-1 line-through">
                  Original: {formatMinutes(resumoCalculado.metricas.tempoTotalOriginalMin)}
                </div>
                <div className="text-[11px] text-slate-300 font-medium mt-1">
                  Trânsito: {formatMinutes(resumoCalculado.metricas.tempoDeslocamentoOtimizadoMin)}
                </div>
              </div>

              {/* Tempo Total em Portarias (Histórico) */}
              <div className="bg-navy-850/80 border border-navy-700/70 p-4 rounded-2xl backdrop-blur">
                <div className="flex items-center justify-between text-slate-400 text-xs font-semibold mb-2">
                  <span>Espera em Portarias</span>
                  <Building className="w-3.5 h-3.5 text-terracotta-400" />
                </div>
                <div className="text-2xl font-black text-white">
                  {formatMinutes(resumoCalculado.metricas.tempoTotalAtendimentoMin)}
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  Baseado em histórico real
                </div>
                <div className="text-[11px] text-terracotta-400 font-medium mt-1">
                  Média de {(resumoCalculado.metricas.tempoTotalAtendimentoMin / paradas.length).toFixed(1)} min/local
                </div>
              </div>

              {/* Economia Financeira de Combustível */}
              <div className="bg-navy-850/80 border border-navy-700/70 p-4 rounded-2xl backdrop-blur">
                <div className="flex items-center justify-between text-slate-400 text-xs font-semibold mb-2">
                  <span>Economia Operacional</span>
                  <TrendingDown className="w-3.5 h-3.5 text-emerald-400" />
                </div>
                <div className="text-2xl font-black text-emerald-400">
                  {formatBRL(resumoCalculado.metricas.economiaFinanceiraEstimada)}
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  Menor desgaste de frota
                </div>
                <div className="text-[11px] text-slate-300 font-medium mt-1">
                  Por rota única realizada
                </div>
              </div>
            </div>
          </div>

          {/* Comparativo Visual Detalhado: "Ordem de Cadastro" vs "Rota Otimizada" */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
            {/* Coluna 1: Ordem de Cadastro Original */}
            <div className="bg-white rounded-2xl p-6 border border-slate-200/90 shadow-card">
              <div className="flex items-center justify-between pb-4 border-b border-slate-100 mb-4">
                <div className="flex items-center gap-2.5">
                  <span className="w-3 h-3 rounded-full bg-slate-400" />
                  <h3 className="font-extrabold text-navy-900 text-base">
                    Ordem de Cadastro (Não Otimizada)
                  </h3>
                </div>
                <span className="text-xs px-2.5 py-1 rounded-full bg-slate-100 text-slate-600 font-semibold">
                  Sequência Original
                </span>
              </div>

              <div className="mb-4 text-xs text-slate-500 bg-slate-50 p-3 rounded-xl border border-slate-200/80 flex items-center justify-between">
                <span>Distância: <strong>{formatDistanceKm(resumoCalculado.metricas.distanciaOriginalKm)}</strong></span>
                <span>Tempo Total: <strong>{formatMinutes(resumoCalculado.metricas.tempoTotalOriginalMin)}</strong></span>
              </div>

              <div className="space-y-3">
                {resumoCalculado.paradasOriginais.map((parada, idx) => (
                  <div
                    key={`orig-${parada.id}`}
                    className="p-3.5 rounded-xl border border-slate-200/80 bg-slate-50/50 hover:bg-slate-50 flex items-start gap-3 transition-colors"
                  >
                    <div className="w-6 h-6 rounded-full bg-slate-200 text-slate-700 text-xs font-bold flex items-center justify-center flex-shrink-0 mt-0.5">
                      {idx + 1}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <h4 className="text-xs font-bold text-navy-900 truncate">
                          {parada.nomeLocal}
                        </h4>
                        <span className="text-[10px] text-slate-400">
                          {parada.codigoRastreio}
                        </span>
                      </div>
                      <p className="text-[11px] text-slate-500 truncate mt-0.5">
                        {parada.enderecoFormatado}
                      </p>
                      <div className="mt-2 flex items-center gap-2 text-[10px] text-slate-600">
                        <Clock className="w-3 h-3 text-slate-400" />
                        <span>Média portaria: <strong>{parada.tempoMedioAtendimentoMinutos} min</strong></span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Coluna 2: Rota Otimizada EntregaCondo */}
            <div className="bg-white rounded-2xl p-6 border-2 border-terracotta-500/40 shadow-card relative">
              <div className="absolute -top-3 right-6 bg-terracotta-600 text-white text-[11px] font-bold uppercase tracking-wider px-3 py-0.5 rounded-full shadow-md">
                Recomendação da IA
              </div>

              <div className="flex items-center justify-between pb-4 border-b border-slate-100 mb-4">
                <div className="flex items-center gap-2.5">
                  <span className="w-3 h-3 rounded-full bg-terracotta-600" />
                  <h3 className="font-extrabold text-navy-900 text-base">
                    Rota Otimizada EntregaCondo
                  </h3>
                </div>
                <span className="text-xs px-2.5 py-1 rounded-full bg-emerald-50 text-emerald-700 font-bold border border-emerald-200">
                  {resumoCalculado.metricas.economiaDistanciaPct}% menor percurso
                </span>
              </div>

              <div className="mb-4 text-xs text-navy-900 bg-terracotta-50/60 p-3 rounded-xl border border-terracotta-200/80 flex items-center justify-between font-medium">
                <span>Distância: <strong className="text-terracotta-700">{formatDistanceKm(resumoCalculado.metricas.distanciaOtimizadaKm)}</strong></span>
                <span>Tempo Total: <strong className="text-terracotta-700">{formatMinutes(resumoCalculado.metricas.tempoTotalOtimizadoMin)}</strong></span>
              </div>

              <div className="space-y-3">
                {resumoCalculado.paradasOtimizadas.map((parada, idx) => (
                  <div
                    key={`otim-${parada.id}`}
                    className="p-3.5 rounded-xl border border-terracotta-100 bg-white hover:border-terracotta-300 flex items-start gap-3 transition-colors shadow-subtle group"
                  >
                    <div className="w-6 h-6 rounded-full bg-terracotta-600 text-white text-xs font-black flex items-center justify-center flex-shrink-0 mt-0.5 shadow-sm shadow-terracotta-600/30">
                      {idx + 1}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <h4 className="text-xs font-bold text-navy-900 truncate">
                          {parada.nomeLocal}
                        </h4>
                        {parada.prioridade === 'urgente' && (
                          <span className="text-[10px] font-bold bg-red-100 text-red-700 px-2 py-0.5 rounded-full">
                            URGENTE
                          </span>
                        )}
                      </div>
                      <p className="text-[11px] text-slate-500 truncate mt-0.5">
                        {parada.destinatario} • {parada.unidade || 'Portaria Principal'}
                      </p>

                      {/* Horários previstos e tempo histórico de atendimento */}
                      <div className="mt-2.5 pt-2 border-t border-slate-100 flex flex-wrap items-center justify-between gap-2 text-[11px]">
                        <div className="flex items-center gap-1.5 text-navy-800 font-semibold">
                          <Compass className="w-3 h-3 text-terracotta-600" />
                          <span>Chegada prev.: {parada.horaPrevistaChegada || '--:--'}</span>
                          <span className="text-slate-300">→</span>
                          <span>Saída: {parada.horaPrevistaSaida || '--:--'}</span>
                        </div>
                        <span className="px-2 py-0.5 rounded bg-slate-100 text-slate-600 text-[10px] font-medium">
                          Tempo local: <strong>{parada.tempoMedioAtendimentoMinutos} min</strong>
                        </span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      ) : (
        /* Estado inicial antes do cálculo */
        <div className="bg-white rounded-3xl p-8 border border-slate-200/90 shadow-card text-center">
          <div className="w-16 h-16 rounded-3xl bg-terracotta-50 text-terracotta-600 mx-auto flex items-center justify-center mb-4 border border-terracotta-100">
            <Route className="w-8 h-8" />
          </div>
          <h2 className="text-xl font-black text-navy-900 tracking-tight">
            Pronto para Otimizar as Entregas do Dia
          </h2>
          <p className="text-sm text-slate-500 max-w-lg mx-auto mt-2">
            Existem {paradas.length} paradas configuradas aguardando processamento. Clique no botão abaixo para cruzar distâncias geodésicas urbanas e histórico de tempo de cada condomínio.
          </p>
          <div className="mt-6 flex justify-center">
            <button
              onClick={handleExecutarOtimizacao}
              className="px-6 py-3 rounded-xl bg-terracotta-600 hover:bg-terracotta-700 text-white font-bold text-sm flex items-center gap-2 shadow-lg shadow-terracotta-600/30 transition-all hover:scale-105 active:scale-95"
            >
              <Zap className="w-4 h-4" />
              <span>Calcular Rota e Comparar Economia</span>
            </button>
          </div>
        </div>
      )}

      {/* Tabela de Inteligência de Condomínios / Endereços e Tempo Médio Histórico */}
      <div className="bg-white rounded-2xl p-6 border border-slate-200/90 shadow-card">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h3 className="text-base font-extrabold text-navy-900">
              Inteligência de Condomínios & Tempos Médios de Atendimento
            </h3>
            <p className="text-xs text-slate-500 mt-0.5">
              Dados extraídos e atualizados dinamicamente a partir dos atendimentos históricos registrados pelos motoristas
            </p>
          </div>
          <div className="flex items-center gap-1.5 text-xs text-slate-500 font-medium">
            <Info className="w-4 h-4 text-slate-400" />
            <span>Fórmula ponderada com taxa de sucesso</span>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead>
              <tr className="border-b border-slate-200 bg-slate-50/70 text-slate-500 uppercase font-semibold tracking-wider">
                <th className="py-3 px-4">Local / Condomínio</th>
                <th className="py-3 px-4">Tipo</th>
                <th className="py-3 px-4">Endereço</th>
                <th className="py-3 px-4 text-center">Tempo Médio</th>
                <th className="py-3 px-4 text-center">Total Histórico</th>
                <th className="py-3 px-4">Instruções de Acesso</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 text-slate-700">
              {paradas.map((parada) => {
                const metricasLocal = calculateAverageCustomerTime(
                  MOCK_HISTORICO_ATENDIMENTOS,
                  parada.clienteEnderecoId,
                  parada.tempoMedioAtendimentoMinutos
                );

                return (
                  <tr key={parada.id} className="hover:bg-slate-50/70 transition-colors">
                    <td className="py-3.5 px-4 font-bold text-navy-900">
                      {parada.nomeLocal}
                    </td>
                    <td className="py-3.5 px-4">
                      <span className="px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 font-medium text-[10px]">
                        Condomínio
                      </span>
                    </td>
                    <td className="py-3.5 px-4 text-slate-500 max-w-xs truncate">
                      {parada.enderecoFormatado}
                    </td>
                    <td className="py-3.5 px-4 text-center">
                      <span className={`inline-flex items-center px-2.5 py-1 rounded-full font-bold text-xs ${
                        parada.tempoMedioAtendimentoMinutos > 15
                          ? 'bg-amber-100 text-amber-800'
                          : 'bg-emerald-100 text-emerald-800'
                      }`}>
                        {parada.tempoMedioAtendimentoMinutos} min
                      </span>
                    </td>
                    <td className="py-3.5 px-4 text-center font-semibold text-slate-600">
                      {metricasLocal.totalAtendimentos > 0 ? `${metricasLocal.totalAtendimentos} entregas` : 'Primeiras entregas'}
                    </td>
                    <td className="py-3.5 px-4 text-slate-500 text-[11px] max-w-sm truncate">
                      Acesso pela guarita com identificação obrigatória
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
