import type { 
  PontoCoordenada, 
  PontoParada, 
  MetricasComparativasRota, 
  ResumoOtimizacaoRota,
  HistoricoAtendimento
} from '../types/logistics';

/**
 * Raio da Terra em KM para cálculo geodésico
 */
const EARTH_RADIUS_KM = 6371;

/**
 * Fator de sinuosidade urbana média (as ruas não são em linha reta)
 * Em média no trânsito brasileiro metropolitano, as rotas reais são ~1.28x a distância euclidiana/haversine.
 */
const FACTOR_URBAN_DETOUR = 1.28;

/**
 * Velocidade média urbana em km/h considerando semáforos e tráfego
 */
const AVERAGE_URBAN_SPEED_KMH = 26;

/**
 * Custo médio operacional estimado por km rodado (combustível + depreciação veicular)
 */
const COST_PER_KM_BRL = 1.85;

/**
 * Calcula a distância geodésica entre duas coordenadas usando a fórmula de Haversine
 */
export function calculateHaversineDistance(p1: PontoCoordenada, p2: PontoCoordenada): number {
  const dLat = ((p2.lat - p1.lat) * Math.PI) / 180;
  const dLng = ((p2.lng - p1.lng) * Math.PI) / 180;

  const lat1 = (p1.lat * Math.PI) / 180;
  const lat2 = (p2.lat * Math.PI) / 180;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.sin(dLng / 2) * Math.sin(dLng / 2) * Math.cos(lat1) * Math.cos(lat2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const straightDistanceKm = EARTH_RADIUS_KM * c;

  // Aplica o fator de via urbana
  return straightDistanceKm * FACTOR_URBAN_DETOUR;
}

/**
 * Estima o tempo de viagem em minutos para uma dada distância em km
 */
export function estimateDriveTimeMinutes(distanceKm: number): number {
  if (distanceKm <= 0) return 0;
  const hours = distanceKm / AVERAGE_URBAN_SPEED_KMH;
  return hours * 60;
}

/**
 * 1. CÁLCULO DE TEMPO MÉDIO POR CLIENTE/ENDEREÇO
 * Cruza o histórico de entregas registradas para calcular a média ponderada de tempo gasta em cada local
 */
export function calculateAverageCustomerTime(
  historico: HistoricoAtendimento[],
  clienteEnderecoId: string,
  fallbackMinutos: number = 10
): {
  tempoMedioMinutos: number;
  totalAtendimentos: number;
  taxaSucesso: number;
} {
  const atendimentosDoCliente = historico.filter(
    (h) => h.cliente_endereco_id === clienteEnderecoId
  );

  if (atendimentosDoCliente.length === 0) {
    return {
      tempoMedioMinutos: fallbackMinutos,
      totalAtendimentos: 0,
      taxaSucesso: 100,
    };
  }

  const somaMinutos = atendimentosDoCliente.reduce(
    (acc, curr) => acc + curr.tempo_total_minutos,
    0
  );
  const atendimentosComSucesso = atendimentosDoCliente.filter((h) => h.sucesso).length;

  const tempoMedio = Number((somaMinutos / atendimentosDoCliente.length).toFixed(1));
  const taxaSucesso = Math.round((atendimentosComSucesso / atendimentosDoCliente.length) * 100);

  return {
    tempoMedioMinutos: tempoMedio,
    totalAtendimentos: atendimentosDoCliente.length,
    taxaSucesso,
  };
}

/**
 * Calcula a distância total e tempo de deslocamento de uma sequência de paradas partindo de uma base
 */
export function calculateRouteTraversal(
  pontoPartida: PontoCoordenada,
  paradas: PontoParada[]
): {
  distanciaKm: number;
  tempoDeslocamentoMin: number;
  tempoAtendimentosMin: number;
  tempoTotalMin: number;
} {
  if (paradas.length === 0) {
    return {
      distanciaKm: 0,
      tempoDeslocamentoMin: 0,
      tempoAtendimentosMin: 0,
      tempoTotalMin: 0,
    };
  }

  let totalDistancia = 0;
  let pontoAtual = pontoPartida;

  for (let i = 0; i < paradas.length; i++) {
    const proximoPonto = paradas[i].coordenadas;
    totalDistancia += calculateHaversineDistance(pontoAtual, proximoPonto);
    pontoAtual = proximoPonto;
  }

  const tempoDeslocamentoMin = estimateDriveTimeMinutes(totalDistancia);
  const tempoAtendimentosMin = paradas.reduce(
    (acc, parada) => acc + (parada.tempoMedioAtendimentoMinutos || 10),
    0
  );

  return {
    distanciaKm: Number(totalDistancia.toFixed(2)),
    tempoDeslocamentoMin: Number(tempoDeslocamentoMin.toFixed(1)),
    tempoAtendimentosMin: Number(tempoAtendimentosMin.toFixed(1)),
    tempoTotalMin: Number((tempoDeslocamentoMin + tempoAtendimentosMin).toFixed(1)),
  };
}

/**
 * Algoritmo de Otimização: Vizinho Mais Próximo com Refinamento 2-Opt
 * Garante tempo de resposta instantâneo na UI e redução expressiva de kms rodados
 */
function optimizeSequenceNearestNeighbor(
  pontoPartida: PontoCoordenada,
  paradas: PontoParada[]
): PontoParada[] {
  if (paradas.length <= 2) return [...paradas];

  const naoVisitadas = [...paradas];
  const rotaOrdenada: PontoParada[] = [];
  let pontoAtual = pontoPartida;

  // 1. Prioriza paradas com urgência se existirem, respeitando janela
  while (naoVisitadas.length > 0) {
    let indiceMaisProximo = 0;
    let menorDistancia = Infinity;

    // Procura primeiro entre urgentes, depois normais
    const temUrgentes = naoVisitadas.some((p) => p.prioridade === 'urgente');

    for (let i = 0; i < naoVisitadas.length; i++) {
      const parada = naoVisitadas[i];
      if (temUrgentes && parada.prioridade !== 'urgente') {
        continue;
      }

      const dist = calculateHaversineDistance(pontoAtual, parada.coordenadas);
      if (dist < menorDistancia) {
        menorDistancia = dist;
        indiceMaisProximo = i;
      }
    }

    const [paradaEscolhida] = naoVisitadas.splice(indiceMaisProximo, 1);
    rotaOrdenada.push(paradaEscolhida);
    pontoAtual = paradaEscolhida.coordenadas;
  }

  // 2. Refinamento 2-Opt para desatar cruzamentos de rota
  return applyTwoOpt(pontoPartida, rotaOrdenada);
}

/**
 * Heurística 2-Opt para desatar cruzamentos e diminuir ainda mais o percurso
 */
function applyTwoOpt(pontoPartida: PontoCoordenada, rota: PontoParada[]): PontoParada[] {
  let melhorRota = [...rota];
  let melhorou = true;
  let iteracoes = 0;
  const maxIteracoes = 50;

  const calcularDistanciaTotal = (r: PontoParada[]): number => {
    let d = 0;
    let atual = pontoPartida;
    for (const p of r) {
      d += calculateHaversineDistance(atual, p.coordenadas);
      atual = p.coordenadas;
    }
    return d;
  };

  let melhorDistancia = calcularDistanciaTotal(melhorRota);

  while (melhorou && iteracoes < maxIteracoes) {
    melhorou = false;
    iteracoes++;

    for (let i = 0; i < melhorRota.length - 1; i++) {
      for (let k = i + 1; k < melhorRota.length; k++) {
        // Se alguma das paradas envolvidas for urgente, não inverte se alterar a prioridade de ponta
        if (melhorRota[k].prioridade === 'urgente' && melhorRota[i].prioridade !== 'urgente') {
          continue;
        }

        // Gera a nova rota invertendo o segmento entre i e k
        const novaRota = [
          ...melhorRota.slice(0, i),
          ...melhorRota.slice(i, k + 1).reverse(),
          ...melhorRota.slice(k + 1),
        ];

        const novaDistancia = calcularDistanciaTotal(novaRota);
        if (novaDistancia < melhorDistancia - 0.05) {
          melhorDistancia = novaDistancia;
          melhorRota = novaRota;
          melhorou = true;
          break;
        }
      }
      if (melhorou) break;
    }
  }

  // Reatribui a numeração sequencial
  return melhorRota.map((p, idx) => ({
    ...p,
    sequencia: idx + 1,
  }));
}

/**
 * 2 e 3. MOTOR COMPLETO DE OTIMIZAÇÃO E PREVISÃO TOTAL COMPARATIVA
 * Calcula a rota original vs rota otimizada, exibindo porcentagem de economia e horários previstos
 */
export function optimizeRouteAndCompare(
  motoristaId: string,
  motoristaNome: string,
  pontoPartida: { nome: string; coordenadas: PontoCoordenada },
  paradas: PontoParada[],
  horaInicioRota: Date = new Date()
): ResumoOtimizacaoRota {
  const paradasOriginaisFormatadas = paradas.map((p, idx) => ({
    ...p,
    sequencia: idx + 1,
  }));

  // Executa os cálculos da ordem original
  const statsOriginal = calculateRouteTraversal(pontoPartida.coordenadas, paradasOriginaisFormatadas);

  // Executa o algoritmo de otimização
  const paradasOtimizadasBrutas = optimizeSequenceNearestNeighbor(
    pontoPartida.coordenadas,
    paradasOriginaisFormatadas
  );

  // Atribui horários estimados de chegada e saída para a rota otimizada
  let relogioAtual = new Date(horaInicioRota.getTime());
  let pontoAnterior = pontoPartida.coordenadas;

  const paradasOtimizadasComHorarios: PontoParada[] = paradasOtimizadasBrutas.map((p, idx) => {
    const distTrecho = calculateHaversineDistance(pontoAnterior, p.coordenadas);
    const tempoTrechoMin = estimateDriveTimeMinutes(distTrecho);

    // Chegada estimada
    const horaChegada = new Date(relogioAtual.getTime() + tempoTrechoMin * 60000);
    // Saída estimada após tempo médio no condomínio/cliente
    const tempoAtendimento = p.tempoMedioAtendimentoMinutos || 10;
    const horaSaida = new Date(horaChegada.getTime() + tempoAtendimento * 60000);

    relogioAtual = horaSaida;
    pontoAnterior = p.coordenadas;

    return {
      ...p,
      sequencia: idx + 1,
      horaPrevistaChegada: horaChegada.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }),
      horaPrevistaSaida: horaSaida.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }),
    };
  });

  const statsOtimizado = calculateRouteTraversal(
    pontoPartida.coordenadas,
    paradasOtimizadasComHorarios
  );

  // Calcula economias
  const economiaDistanciaKm = Math.max(0, statsOriginal.distanciaKm - statsOtimizado.distanciaKm);
  const economiaDistanciaPct = statsOriginal.distanciaKm > 0
    ? Math.round((economiaDistanciaKm / statsOriginal.distanciaKm) * 100)
    : 0;

  const economiaTempoMin = Math.max(0, statsOriginal.tempoTotalMin - statsOtimizado.tempoTotalMin);
  const economiaTempoPct = statsOriginal.tempoTotalMin > 0
    ? Math.round((economiaTempoMin / statsOriginal.tempoTotalMin) * 100)
    : 0;

  const economiaFinanceiraEstimada = Number((economiaDistanciaKm * COST_PER_KM_BRL).toFixed(2));

  const metricas: MetricasComparativasRota = {
    distanciaOriginalKm: statsOriginal.distanciaKm,
    distanciaOtimizadaKm: statsOtimizado.distanciaKm,
    economiaDistanciaKm: Number(economiaDistanciaKm.toFixed(2)),
    economiaDistanciaPct,

    tempoDeslocamentoOriginalMin: statsOriginal.tempoDeslocamentoMin,
    tempoDeslocamentoOtimizadoMin: statsOtimizado.tempoDeslocamentoMin,
    tempoTotalAtendimentoMin: statsOtimizado.tempoAtendimentosMin,

    tempoTotalOriginalMin: statsOriginal.tempoTotalMin,
    tempoTotalOtimizadoMin: statsOtimizado.tempoTotalMin,

    economiaTempoMin: Number(economiaTempoMin.toFixed(1)),
    economiaTempoPct,
    economiaFinanceiraEstimada,
  };

  return {
    motoristaId,
    motoristaNome,
    pontoPartida,
    paradasOriginais: paradasOriginaisFormatadas,
    paradasOtimizadas: paradasOtimizadasComHorarios,
    metricas,
    timestampCalculo: new Date().toISOString(),
  };
}
