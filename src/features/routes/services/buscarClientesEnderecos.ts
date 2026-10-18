import { requireCompanyId } from '../../../lib/company';
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
 * Validação rigorosa: verifica se o endereço pertence à Grande Florianópolis
 */
export function pertenceAGrandeFlorianopolis(item: {
  cidade?: string;
  endereco_completo?: string;
}): boolean {
  const cidNorm = item.cidade ? normalizarTexto(item.cidade) : '';
  const endNorm = item.endereco_completo ? normalizarTexto(item.endereco_completo) : '';

  // Rejeita categoricamente outros estados
  if (
    /\b(sp|rj|pr|rs|mg|ba|df|pe|ce|go|es)\b/i.test(cidNorm) ||
    /\b(sp|rj|pr|rs|mg|ba|df|pe|ce|go|es)\b/i.test(endNorm)
  ) {
    return false;
  }

  // Deve conter explicitamente um dos municípios da Grande Florianópolis
  return CIDADES_GRANDE_FLORIANOPOLIS.some(
    (cidadeAlvo) => cidNorm.includes(cidadeAlvo) || endNorm.includes(cidadeAlvo)
  );
}

export async function buscarClientesEnderecos(termo: string, empresaId?: string): Promise<ClienteEnderecoItem[]> {
  const cleaned = termo.trim().replace(/[%_,().]/g, ' ');
  if (!cleaned) return [];
  if (!isSupabaseConfigured) throw new Error('Conexão não configurada.');
  const id = empresaId || await requireCompanyId();
  const { data, error } = await supabase.from('clientes_enderecos').select('*').eq('empresa_id', id)
    .or('nome_identificador.ilike.%' + cleaned + '%,endereco_completo.ilike.%' + cleaned + '%')
    .order('total_entregas_realizadas', { ascending: false }).limit(15);
  if (error) throw new Error(error.message);
  return data || [];
}
