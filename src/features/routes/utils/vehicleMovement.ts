import type { TipoVeiculoIcone } from '../../../assets/icons/vehicles/VehicleIcons';

export interface PosicaoVeiculo {
  lat: number;
  lng: number;
  bearing?: number; // Ângulo de rotação de 0 a 360 graus
}

export interface MotoristaVeiculoMapa {
  id: string;
  nome: string;
  veiculo_tipo: TipoVeiculoIcone;
  veiculo_modelo: string;
  veiculo_placa: string;
  status: 'disponivel' | 'em_rota' | 'pausado' | 'offline';
  coordenadas: PosicaoVeiculo;
  coordenadasAnteriores?: PosicaoVeiculo;
  localizacao_atualizada_em?: string;
  rota_id?: string;
  velocidadeKmH?: number;
}

/**
 * Normaliza o tipo de veículo a partir de campos crus do banco (veiculo_tipo, modelo, etc.)
 */
export function normalizarTipoVeiculo(
  tipoRaw?: string | null,
  modeloRaw?: string | null
): TipoVeiculoIcone {
  const combinado = `${tipoRaw || ''} ${modeloRaw || ''}`.toLowerCase();

  if (combinado.includes('caminh') || combinado.includes('truck') || combinado.includes('bau grande')) {
    return 'caminhao';
  }
  if (
    combinado.includes('carro') ||
    combinado.includes('fiorino') ||
    combinado.includes('strada') ||
    combinado.includes('van') ||
    combinado.includes('partner') ||
    combinado.includes('kangoo') ||
    combinado.includes('utilitario')
  ) {
    return 'carro';
  }
  return 'moto';
}

/**
 * Calcula o ângulo de direção (bearing/heading) entre dois pontos geográficos em graus (0 - 360)
 */
export function calcularBearing(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  if (lat1 === lat2 && lon1 === lon2) return 0;

  const toRad = (graus: number) => (graus * Math.PI) / 180;
  const toGraus = (rad: number) => (rad * 180) / Math.PI;

  const φ1 = toRad(lat1);
  const φ2 = toRad(lat2);
  const Δλ = toRad(lon2 - lon1);

  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x =
    Math.cos(φ1) * Math.sin(φ2) -
    Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);

  const bearing = toGraus(Math.atan2(y, x));
  return (bearing + 360) % 360;
}

/**
 * Interpolação linear de coordenadas com suavização
 */
export function interpolarCoordenadas(
  p1: PosicaoVeiculo,
  p2: PosicaoVeiculo,
  t: number // 0.0 a 1.0
): PosicaoVeiculo {
  const clampT = Math.max(0, Math.min(1, t));
  const lat = p1.lat + (p2.lat - p1.lat) * clampT;
  const lng = p1.lng + (p2.lng - p1.lng) * clampT;
  const bearing = p2.bearing !== undefined ? p2.bearing : calcularBearing(p1.lat, p1.lng, p2.lat, p2.lng);

  return { lat, lng, bearing };
}
