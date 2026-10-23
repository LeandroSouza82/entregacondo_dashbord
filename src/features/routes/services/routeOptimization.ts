import { coordenadasValidas, resultadoEnderecoCompativel } from './addressCoordinates';
import type { PontoParada, PontoCoordenada } from '../../../types/logistics';

export interface PontoPartidaItem {
  nome: string;
  endereco: string;
  lat?: number;
  lng?: number;
  coordenadas: PontoCoordenada;
}

export const DEFAULT_START_POINT: PontoPartidaItem = {
  nome: 'Sede da Empresa / Ponto de Partida',
  endereco: 'Centro, Florianópolis - SC',
  lat: -27.5954,
  lng: -48.5480,
  coordenadas: { lat: -27.5954, lng: -48.5480 },
};

const STORAGE_KEY_START_POINT = 'ec_default_start_point';

/**
 * Recupera o ponto de partida padrão salvo nas preferências da empresa / localStorage.
 * Suporta formatos { endereco, lat, lng } e { endereco, coordenadas: { lat, lng } }.
 */
export function obterPontoPartidaPadrao(): PontoPartidaItem {
  if (typeof window === 'undefined' || !window.localStorage) {
    return DEFAULT_START_POINT;
  }
  try {
    const salvo = window.localStorage.getItem(STORAGE_KEY_START_POINT);
    if (salvo) {
      const parsed = JSON.parse(salvo);
      if (parsed) {
        const lat =
          typeof parsed.lat === 'number'
            ? parsed.lat
            : typeof parsed.latitude === 'number'
            ? parsed.latitude
            : typeof parsed.coordenadas?.lat === 'number'
            ? parsed.coordenadas.lat
            : null;

        const lng =
          typeof parsed.lng === 'number'
            ? parsed.lng
            : typeof parsed.longitude === 'number'
            ? parsed.longitude
            : typeof parsed.coordenadas?.lng === 'number'
            ? parsed.coordenadas.lng
            : null;

        if (lat !== null && lng !== null && !isNaN(lat) && !isNaN(lng)) {
          const endereco = parsed.endereco || parsed.endereco_completo || 'Florianópolis - SC';
          const nome =
            parsed.nome ||
            parsed.nome_identificador ||
            endereco.split(',')[0].trim() ||
            'Sede da Empresa';

          return {
            nome,
            endereco,
            lat,
            lng,
            coordenadas: { lat, lng },
          };
        }
      }
    }
  } catch (err) {
    console.warn('[routeOptimization] Falha ao recuperar ponto de partida do storage:', err);
  }
  return DEFAULT_START_POINT;
}

/**
 * Grava o ponto de partida nas preferências / localStorage garantindo o contrato { endereco, lat, lng }.
 */
export function salvarPontoPartidaPadrao(ponto: PontoPartidaItem): void {
  if (typeof window === 'undefined' || !window.localStorage) return;
  try {
    const lat = ponto.coordenadas?.lat ?? ponto.lat ?? -27.5954;
    const lng = ponto.coordenadas?.lng ?? ponto.lng ?? -48.5480;
    const payload = {
      endereco: ponto.endereco,
      lat,
      lng,
      nome: ponto.nome || ponto.endereco.split(',')[0].trim() || 'Sede da Empresa',
      coordenadas: { lat, lng },
    };
    window.localStorage.setItem(STORAGE_KEY_START_POINT, JSON.stringify(payload));
  } catch (err) {
    console.warn('[routeOptimization] Falha ao gravar ponto de partida no storage:', err);
  }
}

/**
 * Geocodifica um endereço em texto para coordenadas (lat/lng) via Google Places ou Nominatim.
 */
export async function geocodificarEndereco(
  endereco: string,
  googleKey?: string
): Promise<{ nome: string; endereco: string; coordenadas: PontoCoordenada } | null> {
  if (!endereco || !endereco.trim()) return null;

  const key = googleKey || '';
  if (key) {
    try {
      const res = await fetch('https://places.googleapis.com/v1/places:autocomplete', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': key,
        },
        body: JSON.stringify({
          input: endereco,
          includedRegionCodes: ['br'],
          languageCode: 'pt-BR',
          locationRestriction: {
            circle: {
              center: { latitude: -27.5954, longitude: -48.5480 },
              radius: 50000.0,
            },
          },
        }),
      });
      const data = await res.json();
      const first = data.suggestions?.[0]?.placePrediction;
      if (first?.placeId) {
        const detRes = await fetch(
          `https://places.googleapis.com/v1/places/${first.placeId}?fields=displayName,formattedAddress,location&key=${key}`
        );
        const detData = await detRes.json();
        if (detRes.ok && coordenadasValidas({ lat: detData.location?.latitude, lng: detData.location?.longitude }) &&
            resultadoEnderecoCompativel(endereco, detData.formattedAddress || '')) {
          return {
            nome: detData.displayName?.text || first.text?.text || endereco,
            endereco: detData.formattedAddress || first.text?.text || endereco,
            coordenadas: {
              lat: detData.location.latitude,
              lng: detData.location.longitude,
            },
          };
        }
      }
    } catch (e) {
      console.warn('[routeOptimization] Falha ao geocodificar via Google:', e);
    }
  }

  // Fallback suave Nominatim para Grande Florianópolis
  try {
    const q = encodeURIComponent(`${endereco}, Santa Catarina, Brasil`);
    const headers = typeof window === 'undefined' ? { 'User-Agent': 'EntregaCondo-Dashboard/1.0' } : undefined;
    const res = await fetch(`https://nominatim.openstreetmap.org/search?format=json&q=${q}&limit=5&addressdetails=1&countrycodes=br`, {
      ...(headers ? { headers } : {}),
    });
    if (!res.ok) return null;
    const items = await res.json();
    const match = Array.isArray(items) ? items.find(item =>
      coordenadasValidas({ lat: Number.parseFloat(item.lat), lng: Number.parseFloat(item.lon) }) &&
      resultadoEnderecoCompativel(endereco, item.display_name || '', item.address)) : null;
    if (match) {
      return {
        nome: endereco.split(',')[0].trim(),
        endereco: match.display_name || endereco,
        coordenadas: { lat: Number.parseFloat(match.lat), lng: Number.parseFloat(match.lon) },
      };
    }
  } catch (err) {
    console.warn('[routeOptimization] Falha no fallback Nominatim:', err);
  }

  return null;
}

/**
 * Calcula a distância viária estimada em km entre duas coordenadas geográficas.
 * Utiliza fórmula de Haversine com fator de correção de malha viária urbana (~1.35).
 */
export function calcularDistanciaKm(c1: PontoCoordenada, c2: PontoCoordenada): number {
  if (!c1 || !c2) return 0;
  if (c1.lat === c2.lat && c1.lng === c2.lng) return 0;

  const R = 6371; // Raio médio da Terra em km
  const dLat = ((c2.lat - c1.lat) * Math.PI) / 180;
  const dLng = ((c2.lng - c1.lng) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((c1.lat * Math.PI) / 180) *
      Math.cos((c2.lat * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const linhaReta = R * c;

  // Fator de correção viária urbana (ruas, avenidas e curvas)
  return Number((linhaReta * 1.35).toFixed(1));
}

export interface MetricasRota {
  distanciaOriginalKm: number;
  tempoOriginalMinutos: number;
  distanciaOtimizadaKm: number;
  tempoOtimizadoMinutos: number;
  economiaKm: number;
  percentualEconomiaKm: number;
  economiaTempoMinutos: number;
  percentualEconomiaTempo: number;
  paradasOtimizadas: PontoParada[];
}

/**
 * Calcula distância total de uma sequência de pontos partindo do ponto inicial.
 */
function calcularDistanciaTotal(
  inicio: PontoCoordenada,
  paradas: PontoParada[]
): number {
  if (paradas.length === 0) return 0;
  let dist = calcularDistanciaKm(inicio, paradas[0].coordenadas);
  for (let i = 0; i < paradas.length - 1; i++) {
    dist += calcularDistanciaKm(paradas[i].coordenadas, paradas[i + 1].coordenadas);
  }
  return Number(dist.toFixed(1));
}

/**
 * Calcula métricas completas de trajeto (ordem de cadastro vs rota inteligente).
 * Utiliza heurística de vizinho mais próximo (Nearest Neighbor) e refinamento 2-opt.
 */
export function otimizarSequenciaERota(
  pontoPartida: PontoPartidaItem,
  paradas: PontoParada[]
): MetricasRota {
  if (paradas.length === 0) {
    return {
      distanciaOriginalKm: 0,
      tempoOriginalMinutos: 0,
      distanciaOtimizadaKm: 0,
      tempoOtimizadoMinutos: 0,
      economiaKm: 0,
      percentualEconomiaKm: 0,
      economiaTempoMinutos: 0,
      percentualEconomiaTempo: 0,
      paradasOtimizadas: [],
    };
  }

  // 1. Ordem original (como cadastrado)
  const distOriginal = calcularDistanciaTotal(pontoPartida.coordenadas, paradas);
  const tempoAtendimentoTotal = paradas.reduce(
    (acc, p) => acc + (p.tempoMedioAtendimentoMinutos || 11),
    0
  );
  // Velocidade urbana média estimada ~ 26 km/h em trânsito urbano com semáforos
  const tempoDeslocamentoOriginal = Math.round((distOriginal / 26) * 60);
  const tempoOriginal = tempoDeslocamentoOriginal + tempoAtendimentoTotal;

  // 2. Otimização Nearest Neighbor partindo de pontoPartida
  const unvisited = [...paradas];
  const otimizadas: PontoParada[] = [];
  let currentCoord = pontoPartida.coordenadas;

  while (unvisited.length > 0) {
    let nearestIdx = 0;
    let minDistance = Infinity;

    for (let i = 0; i < unvisited.length; i++) {
      const d = calcularDistanciaKm(currentCoord, unvisited[i].coordenadas);
      if (d < minDistance) {
        minDistance = d;
        nearestIdx = i;
      }
    }

    const [proxima] = unvisited.splice(nearestIdx, 1);
    otimizadas.push(proxima);
    currentCoord = proxima.coordenadas;
  }

  // 3. Refinamento 2-opt para desenlaçar cruzamentos de rotas (se houver 4+ paradas)
  if (otimizadas.length >= 4) {
    let improved = true;
    let iterations = 0;
    while (improved && iterations < 20) {
      improved = false;
      iterations++;
      for (let i = 0; i < otimizadas.length - 1; i++) {
        for (let k = i + 1; k < otimizadas.length; k++) {
          const prevDist = calcularDistanciaTotal(pontoPartida.coordenadas, otimizadas);
          // Inverte sub-rota entre i e k
          const candidate = [
            ...otimizadas.slice(0, i),
            ...otimizadas.slice(i, k + 1).reverse(),
            ...otimizadas.slice(k + 1),
          ];
          const candidateDist = calcularDistanciaTotal(pontoPartida.coordenadas, candidate);
          if (candidateDist < prevDist - 0.05) {
            otimizadas.splice(0, otimizadas.length, ...candidate);
            improved = true;
          }
        }
      }
    }
  }

  // Atualiza sequência 1..N
  const paradasOtimizadasComSequencia = otimizadas.map((p, idx) => ({
    ...p,
    sequencia: idx + 1,
  }));

  const distOtimizada = calcularDistanciaTotal(
    pontoPartida.coordenadas,
    paradasOtimizadasComSequencia
  );
  const tempoDeslocamentoOtimizado = Math.round((distOtimizada / 26) * 60);
  const tempoOtimizado = tempoDeslocamentoOtimizado + tempoAtendimentoTotal;

  // Economia
  const economiaKm = Math.max(0, Number((distOriginal - distOtimizada).toFixed(1)));
  const percentualEconomiaKm =
    distOriginal > 0 ? Math.round((economiaKm / distOriginal) * 100) : 0;
  const economiaTempo = Math.max(0, tempoOriginal - tempoOtimizado);
  const percentualEconomiaTempo =
    tempoOriginal > 0 ? Math.round((economiaTempo / tempoOriginal) * 100) : 0;

  return {
    distanciaOriginalKm: distOriginal,
    tempoOriginalMinutos: tempoOriginal,
    distanciaOtimizadaKm: distOtimizada,
    tempoOtimizadoMinutos: tempoOtimizado,
    economiaKm,
    percentualEconomiaKm,
    economiaTempoMinutos: economiaTempo,
    percentualEconomiaTempo,
    paradasOtimizadas: paradasOtimizadasComSequencia,
  };
}

/**
 * Formata minutos em texto amigável: "1h 25min" ou "45min".
 */
export function formatarTempoMinutos(minutos: number): string {
  if (!minutos || minutos <= 0) return '0 min';
  const h = Math.floor(minutos / 60);
  const m = Math.round(minutos % 60);
  if (h === 0) return `${m} min`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}min`;
}
