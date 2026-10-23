export interface TrackingPoint { latitude: number; longitude: number }
export interface ArrivalTracking {
  estado: 'ativo' | 'encerrado' | 'indisponivel';
  empresa?: string;
  tipo_tarefa?: string;
  destino?: TrackingPoint;
  posicao?: TrackingPoint | null;
  atualizada_em?: string | null;
  previsao_chegada_em?: string | null;
  previsao_atualizada_em?: string | null;
  servidor_em?: string;
}
export function trackingIsStale(data: ArrivalTracking, now: number): boolean {
  const updated = Date.parse(data.atualizada_em || '');
  return !Number.isFinite(updated) || now - updated > 120_000;
}
export function trackingETA(data: ArrivalTracking, now: number): string | null {
  const observed = Date.parse(data.previsao_atualizada_em || '');
  const eta = Date.parse(data.previsao_chegada_em || '');
  if (trackingIsStale(data, now) || !Number.isFinite(observed) || now - observed > 120_000 || !Number.isFinite(eta) || eta < now) return null;
  return new Date(eta).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'});
}
