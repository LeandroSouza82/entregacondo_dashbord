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

// Cache em memória para endereços criados durante a sessão do gestor
const CACHE_SESSAO_ENDERECOS: ClienteEnderecoItem[] = [];

export function registrarEnderecoNoCacheLocal(item: ClienteEnderecoItem) {
  if (!pertenceAGrandeFlorianopolis(item)) {
    console.warn('Tentativa de salvar endereço fora da Grande Florianópolis bloqueada:', item.endereco_completo);
    return;
  }

  const index = CACHE_SESSAO_ENDERECOS.findIndex(
    (e) => e.id === item.id || normalizarTexto(e.nome_identificador) === normalizarTexto(item.nome_identificador)
  );
  if (index >= 0) {
    CACHE_SESSAO_ENDERECOS[index] = item;
  } else {
    CACHE_SESSAO_ENDERECOS.unshift(item);
  }
}

// Base local completa de condomínios da Grande Florianópolis (Case-Insensitive & 100% Regional)
const ENDERECOS_LOCAIS_PADRAO: ClienteEnderecoItem[] = [
  {
    id: 'ce-floripa-hamburgo',
    nome_identificador: 'Condomínio Hamburgo',
    destinatario_padrao: 'Portaria Central · Apto 101',
    endereco_completo: 'Rua Koesa, 298 · Kobrasol, São José - SC',
    cidade: 'São José',
    latitude: -27.5950,
    longitude: -48.6180,
    tempo_medio_minutos: 11,
    total_entregas_realizadas: 52,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Acesso rápido pela Rua Koesa. Portaria 24 horas.',
  },
  {
    id: 'ce-floripa-01',
    nome_identificador: 'Condomínio Jardim América',
    destinatario_padrao: 'Portaria Principal · Bloco A',
    endereco_completo: 'Rua Lauro Linhares, 820 · Trindade, Florianópolis - SC',
    cidade: 'Florianópolis',
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
    cidade: 'Florianópolis',
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
    cidade: 'Florianópolis',
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
    cidade: 'Florianópolis',
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
    cidade: 'Florianópolis',
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
    cidade: 'Florianópolis',
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
    cidade: 'Florianópolis',
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
    cidade: 'Florianópolis',
    latitude: -27.5978,
    longitude: -48.5175,
    tempo_medio_minutos: 8,
    total_entregas_realizadas: 3,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Portaria só até as 17h.',
  },
  {
    id: 'ce-palhoca-01',
    nome_identificador: 'Condomínio Residencial Palhoça Garden',
    destinatario_padrao: 'Guarita Social',
    endereco_completo: 'Av. Barão do Rio Branco, 415 · Centro, Palhoça - SC',
    cidade: 'Palhoça',
    latitude: -27.6450,
    longitude: -48.6690,
    tempo_medio_minutos: 10,
    total_entregas_realizadas: 25,
    tipo_local: 'condominio_horizontal',
    observacoes_acesso: 'Identificação rápida na portaria com interfone.',
  },
  {
    id: 'ce-biguacu-01',
    nome_identificador: 'Edifício Biguaçu Executive',
    destinatario_padrao: 'Portaria Comercial',
    endereco_completo: 'Rua Coronel Teixeira de Oliveira, 180 · Centro, Biguaçu - SC',
    cidade: 'Biguaçu',
    latitude: -27.4950,
    longitude: -48.6580,
    tempo_medio_minutos: 7,
    total_entregas_realizadas: 19,
    tipo_local: 'edificio_vertical',
    observacoes_acesso: 'Estacionamento para carga rápida em frente ao prédio.',
  },
  {
    id: 'ce-santoamaro-01',
    nome_identificador: 'Condomínio Vale das Termas',
    destinatario_padrao: 'Portaria 1',
    endereco_completo: 'Rua Frei Caneca, 120 · Centro, Santo Amaro da Imperatriz - SC',
    cidade: 'Santo Amaro da Imperatriz',
    latitude: -27.6890,
    longitude: -48.7750,
    tempo_medio_minutos: 14,
    total_entregas_realizadas: 12,
    tipo_local: 'condominio_horizontal',
    observacoes_acesso: 'Acesso pela guarita principal com controle de placas.',
  },
  {
    id: 'ce-govcelso-01',
    nome_identificador: 'Residencial Palmas do Arvoredo',
    destinatario_padrao: 'Guarita Palmas',
    endereco_completo: 'Av. Aderbal Ramos da Silva, 550 · Governador Celso Ramos - SC',
    cidade: 'Governador Celso Ramos',
    latitude: -27.3250,
    longitude: -48.5580,
    tempo_medio_minutos: 12,
    total_entregas_realizadas: 16,
    tipo_local: 'condominio_horizontal',
    observacoes_acesso: 'Acesso liberado após conferência de endereço na portaria.',
  },
  {
    id: 'ce-tijucas-01',
    nome_identificador: 'Residencial Tijucas Green',
    destinatario_padrao: 'Portaria Central',
    endereco_completo: 'Rua Coronel Buchelle, 320 · Centro, Tijucas - SC',
    cidade: 'Tijucas',
    latitude: -27.2410,
    longitude: -48.6340,
    tempo_medio_minutos: 9,
    total_entregas_realizadas: 21,
    tipo_local: 'condominio_horizontal',
    observacoes_acesso: 'Portaria com locker de encomendas para entrega rápida.',
  },
  {
    id: 'ce-rancho-01',
    nome_identificador: 'Condomínio Serra & Campo',
    destinatario_padrao: 'Guarita da Serra',
    endereco_completo: 'Rodovia BR-282, KM 65 · Rancho Queimado - SC',
    cidade: 'Rancho Queimado',
    latitude: -27.6720,
    longitude: -49.0210,
    tempo_medio_minutos: 15,
    total_entregas_realizadas: 8,
    tipo_local: 'condominio_horizontal',
    observacoes_acesso: 'Portão eletrônico acionado pelo zelador via interfone.',
  },
];

/**
 * Busca dinâmica com operador ILIKE no Supabase, restrita estritamente à Grande Florianópolis
 * e insensível a maiúsculas/minúsculas e acentos.
 */
export async function buscarClientesEnderecos(
  termo: string,
  empresaId?: string
): Promise<ClienteEnderecoItem[]> {
  const normalizado = normalizarTexto(termo);
  if (!normalizado) return [];

  // 1. Tentar consulta no Supabase se configurado (usando ILIKE nativo do PostgreSQL)
  if (isSupabaseConfigured && supabase) {
    try {
      let query = supabase
        .from('clientes_enderecos')
        .select('*')
        .or(`nome_identificador.ilike.%${normalizado}%,endereco_completo.ilike.%${normalizado}%,destinatario_padrao.ilike.%${normalizado}%`)
        .order('total_entregas_realizadas', { ascending: false })
        .limit(15);

      if (empresaId) {
        query = query.eq('empresa_id', empresaId);
      }

      const { data, error } = await query;

      if (!error && data && data.length > 0) {
        // Filtra estritamente dentro da Grande Florianópolis
        const mapeados = data
          .map((d) => ({
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
          }))
          .filter(pertenceAGrandeFlorianopolis);

        if (mapeados.length > 0) {
          return mapeados.slice(0, 8);
        }
      }
    } catch (err) {
      console.warn('Busca no Supabase clientes_enderecos falhou, utilizando fallback local:', err);
    }
  }

  // 2. Fallback local consolidado (base padrão + cache da sessão) restrito à Grande Florianópolis
  const baseCombinada = [...CACHE_SESSAO_ENDERECOS, ...ENDERECOS_LOCAIS_PADRAO];

  // Filtra por termo insensível a maiúsculas/minúsculas e acentos
  const resultados = baseCombinada.filter((item) => {
    if (!pertenceAGrandeFlorianopolis(item)) return false;

    const nomeNorm = normalizarTexto(item.nome_identificador);
    const endNorm = normalizarTexto(item.endereco_completo);
    const destNorm = item.destinatario_padrao ? normalizarTexto(item.destinatario_padrao) : '';

    return nomeNorm.includes(normalizado) || endNorm.includes(normalizado) || destNorm.includes(normalizado);
  });

  // Ordena dando prioridade aos que começam com o termo, e depois por volume de entregas
  resultados.sort((a, b) => {
    const aStartsWith = normalizarTexto(a.nome_identificador).startsWith(normalizado);
    const bStartsWith = normalizarTexto(b.nome_identificador).startsWith(normalizado);
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
