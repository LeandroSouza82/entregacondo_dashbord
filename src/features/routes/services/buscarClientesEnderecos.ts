import { coordenadasValidas, resultadoEnderecoCompativel } from './addressCoordinates';
import { requireCompanyId, hasActiveSupabaseSession } from '../../../lib/company';
import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { ClienteEnderecoItem } from '../types/clienteEndereco';

// Lista oficial dos municípios que compõem a região da Grande Florianópolis atendida
export const CIDADES_GRANDE_FLORIANOPOLIS = [
  'florianopolis',
  'sao jose',
  'palhoca',
  'biguacu',
  'santo amaro da imperatriz',
  'rancho queimado',
  'governador celso ramos',
  'tijucas',
  'aguas mornas',
  'antonio carlos',
  'sao pedro de alcantara',
];

/**
 * Função utilitária para busca estritamente insensível a maiúsculas/minúsculas e acentos
 */
export function normalizarTexto(texto: string): string {
  return texto
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim();
}

/**
 * Validação flexível e segura: prioriza Grande Florianópolis e Santa Catarina, rejeitando outros estados
 */
export function pertenceAGrandeFlorianopolis(item: {
  cidade?: string;
  endereco_completo?: string;
}): boolean {
  const cidNorm = item.cidade ? normalizarTexto(item.cidade) : '';
  const endNorm = item.endereco_completo ? normalizarTexto(item.endereco_completo) : '';

  // Rejeita categoricamente outros estados quando explicitamente identificados
  if (
    /\b(sao paulo|rio de janeiro|curitiba|porto alegre|belo horizonte|salvador|brasilia)\b/i.test(cidNorm) ||
    /\b(sao paulo|rio de janeiro|curitiba|porto alegre|belo horizonte|salvador|brasilia)\b/i.test(endNorm)
  ) {
    return false;
  }

  // Se contiver explicitamente SC ou Santa Catarina ou município da região, aceita imediatamente
  if (
    endNorm.includes('santa catarina') ||
    endNorm.includes(', sc') ||
    endNorm.includes(' - sc') ||
    cidNorm.includes('sc') ||
    cidNorm.includes('santa catarina')
  ) {
    return true;
  }

  // Aceita se corresponder a um dos municípios atendidos
  return CIDADES_GRANDE_FLORIANOPOLIS.some(
    (cidadeAlvo) => cidNorm.includes(cidadeAlvo) || endNorm.includes(cidadeAlvo)
  );
}

export interface SugestaoEndereco {
  placeId: string;
  mainText: string;
  secondaryText: string;
  fullText: string;
  coordenadas?: { lat: number; lng: number };
  origem: 'google' | 'nominatim' | 'banco';
}

/**
 * Busca sugestões abertas resilientes via OpenStreetMap / Nominatim com bounding box da Grande Florianópolis
 */
export async function buscarSugestoesNominatim(termo: string): Promise<SugestaoEndereco[]> {
  const limpo = termo.trim();
  if (!limpo || limpo.length < 2) return [];

  try {
    const q = encodeURIComponent(`${limpo}, Santa Catarina, Brasil`);
    // Bounding box cobrindo Grande Florianópolis (Florianópolis, São José, Palhoça, Biguaçu, Santo Amaro, etc.)
    const url = `https://nominatim.openstreetmap.org/search?format=json&q=${q}&viewbox=-48.85,-27.35,-48.30,-27.85&bounded=0&limit=6&addressdetails=1`;
    
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 3500);

    const headers = typeof window === 'undefined' ? { 'User-Agent': 'EntregaCondo-Dashboard/1.0' } : undefined;
    const res = await fetch(url, { signal: controller.signal, ...(headers ? { headers } : {}) });
    clearTimeout(timeoutId);

    if (!res.ok) return [];
    const items = await res.json();
    if (!Array.isArray(items)) return [];

    return items
      .filter((item: any) => {
        const city = item.address?.city || item.address?.town || item.address?.municipality || '';
        return CIDADES_GRANDE_FLORIANOPOLIS.includes(normalizarTexto(city)) &&
          resultadoEnderecoCompativel(limpo, item.display_name || '', item.address) &&
          coordenadasValidas({lat: Number.parseFloat(item.lat), lng: Number.parseFloat(item.lon)});
      })
      .map((item: any) => {
        const lat = parseFloat(item.lat);
        const lng = parseFloat(item.lon);
        const display: string = item.display_name || '';
        const parts = display.split(',').map((s: string) => s.trim());
        const mainText = item.name || parts[0] || limpo;
        const secondaryText = parts.slice(1, 4).join(', ') || 'Santa Catarina, Brasil';

        return {
          placeId: String(item.place_id || item.osm_id || Math.random()),
          mainText,
          secondaryText,
          fullText: display || `${mainText}, ${secondaryText}`,
          coordenadas: { lat, lng },
          origem: 'nominatim' as const,
        };
      })
      .filter((s: SugestaoEndereco) => {
        return pertenceAGrandeFlorianopolis({
          cidade: s.secondaryText,
          endereco_completo: s.fullText,
        });
      });
  } catch (e) {
    console.warn('[buscarClientesEnderecos] Fallback Nominatim silencioso:', e);
    return [];
  }
}

export async function buscarClientesEnderecos(termo: string, empresaId?: string): Promise<ClienteEnderecoItem[]> {
  const cleaned = termo.trim().replace(/[%_(),]/g, ' ').replace(/\s+/g, ' ').trim();
  if (!cleaned) return [];
  if (!isSupabaseConfigured) return [];
  try {
    if (!(await hasActiveSupabaseSession())) {
      return [];
    }

    let id = empresaId;
    if (!id && typeof window !== 'undefined') {
      id = localStorage.getItem('ec_active_company_id') || undefined;
    }
    if (!id) {
      try {
        id = await requireCompanyId();
      } catch {
        id = undefined;
      }
    }

    let safeQuery = supabase.from('clientes_enderecos').select('*');
    if (id) {
      safeQuery = safeQuery.eq('empresa_id', id);
    }

    const { data: dadosCanonica, error: errCanonica } = await safeQuery
      .or(`nome_identificador.ilike.%${cleaned}%,endereco_completo.ilike.%${cleaned}%`)
      .order('total_entregas_realizadas', { ascending: false })
      .limit(15);

    if (errCanonica) {
      return [];
    }

    return dadosCanonica || [];
  } catch {
    return [];
  }
}
