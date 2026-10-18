import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { ClienteEnderecoItem } from '../types/clienteEndereco';
import { MOCK_CLIENTES_ENDERECOS } from '../../../services/mockData';

// Cache em memória para endereços criados durante a sessão do gestor
const CACHE_SESSAO_ENDERECOS: ClienteEnderecoItem[] = [];

export function registrarEnderecoNoCacheLocal(item: ClienteEnderecoItem) {
  const index = CACHE_SESSAO_ENDERECOS.findIndex((e) => e.id === item.id || e.nome_identificador.toLowerCase() === item.nome_identificador.toLowerCase());
  if (index >= 0) {
    CACHE_SESSAO_ENDERECOS[index] = item;
  } else {
    CACHE_SESSAO_ENDERECOS.unshift(item);
  }
}

// Base local completa de condomínios e clientes para busca instantânea e offline
const ENDERECOS_LOCAIS_PADRAO: ClienteEnderecoItem[] = [
  {
    id: 'ce-floripa-01',
    nome_identificador: 'Condomínio Jardim América',
    destinatario_padrao: 'Portaria Principal · Bloco A',
    endereco_completo: 'Rua Lauro Linhares, 820 · Trindade, Florianópolis - SC',
    latitude: -27.5992,
    longitude: -48.5205,
    tempo_medio_minutos: 12,
    total_entregas_realizadas: 38,
    tipo_local: 'condominio_horizontal',
    observacoes_acesso: 'Interfonar na portaria. Zelador autoriza acesso das 08h às 18h.',
  },
  {
    id: 'ce-floripa-02',
    nome_identificador: 'Ed. Solar das Palmeiras',
    destinatario_padrao: 'Bloco B · Apto 302',
    endereco_completo: 'Rua Lauro Linhares, 820 · Trindade, Florianópolis - SC',
    latitude: -27.5992,
    longitude: -48.5205,
    tempo_medio_minutos: 10,
    total_entregas_realizadas: 14,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Cuidado com o cachorro. Entregar ao zelador.',
  },
  {
    id: 'ce-floripa-03',
    nome_identificador: 'Cond. Jardim Imperial',
    destinatario_padrao: 'Administração / Guarita',
    endereco_completo: 'Av. Madre Benvenuta, 1100 · Itacorubi, Florianópolis - SC',
    latitude: -27.5880,
    longitude: -48.5110,
    tempo_medio_minutos: 14,
    total_entregas_realizadas: 41,
    tipo_local: 'condominio_horizontal',
    observacoes_acesso: 'Portaria com triagem de encomendas. Exige crachá de identificação.',
  },
  {
    id: 'ce-floripa-04',
    nome_identificador: 'Res. Vista Mar',
    destinatario_padrao: 'Portaria 24h · Torre Sul',
    endereco_completo: 'Av. Beira-Mar Norte, 3400 · Centro, Florianópolis - SC',
    latitude: -27.5854,
    longitude: -48.5440,
    tempo_medio_minutos: 11,
    total_entregas_realizadas: 29,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Vaga rápida para carga e descarga em frente à guarita.',
  },
  {
    id: 'ce-floripa-05',
    nome_identificador: 'Ed. Marina Tower',
    destinatario_padrao: 'Recepção Comercial',
    endereco_completo: 'Rua Felipe Schmidt, 1250 · Centro, Florianópolis - SC',
    latitude: -27.5912,
    longitude: -48.5510,
    tempo_medio_minutos: 8,
    total_entregas_realizadas: 18,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Acesso liberado pela catraca eletrônica da portaria.',
  },
  {
    id: 'ce-floripa-06',
    nome_identificador: 'Ed. Bela Vista',
    destinatario_padrao: 'Portaria Central',
    endereco_completo: 'Rua Bocaiúva, 450 · Centro, Florianópolis - SC',
    latitude: -27.5890,
    longitude: -48.5495,
    tempo_medio_minutos: 15,
    total_entregas_realizadas: 22,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Interfonar antes de descarregar. Entregar ao síndico.',
  },
  {
    id: 'ce-floripa-07',
    nome_identificador: 'Res. Alameda Park',
    destinatario_padrao: 'Zeladoria',
    endereco_completo: 'Rua João Pio Duarte Silva, 900 · Córrego Grande, Florianópolis - SC',
    latitude: -27.5970,
    longitude: -48.5080,
    tempo_medio_minutos: 9,
    total_entregas_realizadas: 31,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Portão automático com interfone no pilar esquerdo.',
  },
  {
    id: 'ce-floripa-08',
    nome_identificador: 'Res. Lauro Park',
    destinatario_padrao: 'Bloco A',
    endereco_completo: 'Rua Lauro Linhares, 1120 · Trindade, Florianópolis - SC',
    latitude: -27.5978,
    longitude: -48.5175,
    tempo_medio_minutos: 8,
    total_entregas_realizadas: 3,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Portaria só até as 17h.',
  },
  // Integração com mockData existente
  ...MOCK_CLIENTES_ENDERECOS.map((m) => ({
    id: m.id,
    empresa_id: m.empresa_id,
    nome_identificador: m.nome_identificador,
    destinatario_padrao: m.destinatario_padrao,
    endereco_completo: `${m.endereco_completo}, ${m.numero} - ${m.bairro}, ${m.cidade}`,
    numero: m.numero,
    bairro: m.bairro,
    cidade: m.cidade,
    cep: m.cep,
    latitude: Number(m.latitude),
    longitude: Number(m.longitude),
    tempo_medio_minutos: Number(m.tempo_medio_minutos),
    total_entregas_realizadas: m.total_entregas_realizadas,
    tipo_local: m.tipo_local as ClienteEnderecoItem['tipo_local'],
    observacoes_acesso: m.observacoes_acesso,
  })),
];

/**
 * Busca dinâmica com prioridade no Supabase, com fallback instantâneo na base local
 */
export async function buscarClientesEnderecos(
  termo: string,
  empresaId?: string
): Promise<ClienteEnderecoItem[]> {
  const normalizado = termo.trim().toLowerCase();
  if (!normalizado) return [];

  // 1. Tentar consulta no Supabase se configurado
  if (isSupabaseConfigured && supabase) {
    try {
      let query = supabase
        .from('clientes_enderecos')
        .select('*')
        .or(`nome_identificador.ilike.%${normalizado}%,endereco_completo.ilike.%${normalizado}%,destinatario_padrao.ilike.%${normalizado}%`)
        .order('total_entregas_realizadas', { ascending: false })
        .limit(8);

      if (empresaId) {
        query = query.eq('empresa_id', empresaId);
      }

      const { data, error } = await query;

      if (!error && data && data.length > 0) {
        return data.map((d) => ({
          id: d.id,
          empresa_id: d.empresa_id,
          nome_identificador: d.nome_identificador,
          destinatario_padrao: d.destinatario_padrao,
          endereco_completo: d.endereco_completo,
          numero: d.numero,
          bairro: d.bairro,
          cidade: d.cidade,
          cep: d.cep,
          latitude: Number(d.latitude),
          longitude: Number(d.longitude),
          tempo_medio_minutos: Number(d.tempo_medio_minutos),
          total_entregas_realizadas: d.total_entregas_realizadas || 0,
          tipo_local: d.tipo_local,
          observacoes_acesso: d.observacoes_acesso,
        }));
      }
    } catch (err) {
      console.warn('Busca no Supabase clientes_enderecos falhou, utilizando fallback local:', err);
    }
  }

  // 2. Fallback local consolidado (base padrão + cache da sessão)
  const baseCombinada = [...CACHE_SESSAO_ENDERECOS, ...ENDERECOS_LOCAIS_PADRAO];

  // Filtra por termo na identificação, endereço ou destinatário
  const resultados = baseCombinada.filter((item) => {
    const nomeMatch = item.nome_identificador.toLowerCase().includes(normalizado);
    const endMatch = item.endereco_completo.toLowerCase().includes(normalizado);
    const destMatch = item.destinatario_padrao?.toLowerCase().includes(normalizado) || false;
    return nomeMatch || endMatch || destMatch;
  });

  // Ordena dando prioridade aos que começam com o termo, e depois por volume de entregas
  resultados.sort((a, b) => {
    const aStartsWith = a.nome_identificador.toLowerCase().startsWith(normalizado);
    const bStartsWith = b.nome_identificador.toLowerCase().startsWith(normalizado);
    if (aStartsWith && !bStartsWith) return -1;
    if (!aStartsWith && bStartsWith) return 1;
    return (b.total_entregas_realizadas || 0) - (a.total_entregas_realizadas || 0);
  });

  // Retorna os top 8 resultados únicos por id
  const vistos = new Set<string>();
  const unicos: ClienteEnderecoItem[] = [];

  for (const item of resultados) {
    if (!vistos.has(item.id)) {
      vistos.add(item.id);
      unicos.push(item);
      if (unicos.length >= 8) break;
    }
  }

  return unicos;
}
