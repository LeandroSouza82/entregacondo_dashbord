import type { PontoCoordenada } from '../../../types/logistics';

/** Missing/invalid coordinates must never become a fictitious delivery point. */
export function coordenadasValidas(value: unknown): value is PontoCoordenada {
  if (!value || typeof value !== 'object') return false;
  const { lat, lng } = value as PontoCoordenada;
  return typeof lat === 'number' && typeof lng === 'number' &&
    Number.isFinite(lat) && Number.isFinite(lng) &&
    Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
}

export const erroLocalizacaoEndereco =
  'Não foi possível localizar este endereço no mapa. Confira a rua, o número e a cidade e selecione uma sugestão antes de continuar.';

/** Preserve the municipality written in the address instead of forcing Florianópolis. */
export function cidadeDoEndereco(address: string): string {
  const cities = ['Florianópolis', 'São José', 'Palhoça', 'Biguaçu',
    'Santo Amaro da Imperatriz', 'Rancho Queimado', 'Governador Celso Ramos',
    'Tijucas', 'Águas Mornas', 'Antônio Carlos', 'São Pedro de Alcântara'];
  const normalize = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  for (const segment of address.split(',')) {
    const text = normalize(segment.trim()).replace(/\s*[-/]\s*sc$/, '').trim();
    const city = cities.find(city => normalize(city) === text);
    if (city) return city;
  }
  return '';
}

/** A street centroid or a same-name place in another city is not a numbered address. */
export function numeroDoEndereco(address: string): string {
  return address.match(/,\s*(\d{1,5}[a-z]?)(?![\w-])/i)?.[1].toLowerCase() || '';
}

export function resultadoEnderecoCompativel(
  requested: string,
  resolved: string,
  details?: { city?: string; town?: string; municipality?: string; house_number?: string },
): boolean {
  const normalize = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase();
  const city = cidadeDoEndereco(requested);
  const resolvedCity = details?.city || details?.town || details?.municipality || cidadeDoEndereco(resolved);
  if (city && normalize(city) !== normalize(resolvedCity)) return false;
  const number = numeroDoEndereco(requested);
  const resolvedNumber = details?.house_number?.trim().toLowerCase() || numeroDoEndereco(resolved);
  return !number || number === resolvedNumber;
}
