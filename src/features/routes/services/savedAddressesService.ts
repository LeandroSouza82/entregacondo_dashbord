import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import { requireCompanyId, hasActiveSupabaseSession } from '../../../lib/company';
import type { ClienteEnderecoItem, NovoClienteEnderecoPayload } from '../types/clienteEndereco';
import { salvarClienteEndereco } from './salvarClienteEndereco';

/**
 * Normaliza strings para comparações seguras sem acentos e minúsculas
 */
function normalizarTexto(txt: string): string {
  return txt
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim();
}

/**
 * Consulta local no Supabase com prioridade máxima (sem custo de API)
 */
export async function buscarEnderecosNoBanco(
  termo: string, 
  empresaId?: string
): Promise<ClienteEnderecoItem[]> {
  const limpo = termo.trim().replace(/[%_(),]/g, ' ').replace(/\s+/g, ' ').trim();
  if (!limpo || limpo.length < 2 || !isSupabaseConfigured) {
    return [];
  }

  try {
    if (!(await hasActiveSupabaseSession())) {
      return [];
    }

    let resolvedId = empresaId;
    if (!resolvedId && typeof window !== 'undefined') {
      resolvedId = localStorage.getItem('ec_active_company_id') || undefined;
    }
    if (!resolvedId) {
      try {
        resolvedId = await requireCompanyId();
      } catch {
        resolvedId = undefined;
      }
    }

    let query = supabase.from('clientes_enderecos').select('*');
    if (resolvedId) {
      query = query.eq('empresa_id', resolvedId);
    }

    const { data, error } = await query
      .or(`nome_identificador.ilike.%${limpo}%,endereco_completo.ilike.%${limpo}%`)
      .order('total_entregas_realizadas', { ascending: false })
      .limit(10);

    if (error || !data) {
      return [];
    }

    return data as ClienteEnderecoItem[];
  } catch {
    return [];
  }
}

/**
 * Verifica se um endereço já está gravado no banco de dados da empresa
 */
export async function verificarEnderecoJaSalvo(
  endereco: string,
  empresaId?: string
): Promise<ClienteEnderecoItem | null> {
  const limpo = endereco.trim();
  if (!limpo || limpo.length < 4 || !isSupabaseConfigured) {
    return null;
  }

  try {
    if (!(await hasActiveSupabaseSession())) {
      return null;
    }

    let resolvedId = empresaId;
    if (!resolvedId && typeof window !== 'undefined') {
      resolvedId = localStorage.getItem('ec_active_company_id') || undefined;
    }
    if (!resolvedId) {
      try {
        resolvedId = await requireCompanyId();
      } catch {
        resolvedId = undefined;
      }
    }

    // Busca exata ou por termo principal
    const primeiroSegmento = limpo.split(',')[0].trim().replace(/[%_()]/g, '');
    let query = supabase.from('clientes_enderecos').select('*');
    if (resolvedId) {
      query = query.eq('empresa_id', resolvedId);
    }

    const { data } = await query
      .or(`endereco_completo.ilike.%${primeiroSegmento}%,nome_identificador.ilike.%${primeiroSegmento}%`)
      .limit(10);

    if (!data || data.length === 0) {
      return null;
    }

    const normBuscado = normalizarTexto(limpo);
    const encontrado = data.find((item: ClienteEnderecoItem) => {
      const normSalvo = normalizarTexto(item.endereco_completo || '');
      const normNome = normalizarTexto(item.nome_identificador || '');
      return normSalvo === normBuscado || 
             normSalvo.includes(normBuscado) || 
             normBuscado.includes(normSalvo) ||
             (normNome.length > 3 && normBuscado.includes(normNome));
    });

    return encontrado || null;
  } catch {
    return null;
  }
}

/**
 * Salva diretamente o endereço no cache do Supabase
 */
export async function salvarEnderecoCache(
  payload: NovoClienteEnderecoPayload
): Promise<ClienteEnderecoItem> {
  return salvarClienteEndereco(payload);
}
