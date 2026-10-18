const CHIPS_STORAGE_KEY = 'entregacondo_chips_customizados';

const CHIPS_PADROES_LOWER = [
  'documentos',
  'balancete',
  'interfonar antes',
  'portaria só até às 17h',
  'portaria só até 17h',
];

const DEFAULT_CHIPS_INICIAIS = [
  'Vistoria Predial',
  'Notificação Notarial',
];

/**
 * Obtém a lista de chips customizados persistidos no localStorage
 */
export function obterChipsCustomizados(): string[] {
  try {
    const raw = localStorage.getItem(CHIPS_STORAGE_KEY);
    if (!raw) {
      // Inicializa com sugestões iniciais úteis
      localStorage.setItem(CHIPS_STORAGE_KEY, JSON.stringify(DEFAULT_CHIPS_INICIAIS));
      return DEFAULT_CHIPS_INICIAIS;
    }
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      return parsed
        .filter((item): item is string => typeof item === 'string' && item.trim().length > 0)
        .map(item => item.trim());
    }
    return DEFAULT_CHIPS_INICIAIS;
  } catch (err) {
    console.warn('Erro ao ler chips customizados do localStorage:', err);
    return DEFAULT_CHIPS_INICIAIS;
  }
}

/**
 * Salva um novo chip na memória persistente evitando duplicatas
 */
export function salvarChipCustomizado(termo: string): string[] {
  const limpo = termo.trim();
  if (!limpo || limpo.length < 2) return obterChipsCustomizados();

  // Não duplica se for um dos chips fixos padrão
  if (CHIPS_PADROES_LOWER.includes(limpo.toLowerCase())) {
    return obterChipsCustomizados();
  }

  const atuais = obterChipsCustomizados();
  // Não duplica se já existir
  if (atuais.some(c => c.toLowerCase() === limpo.toLowerCase())) {
    return atuais;
  }

  // Adiciona ao topo e limita aos 12 mais recentes para manter o layout limpo
  const atualizados = [limpo, ...atuais].slice(0, 12);
  try {
    localStorage.setItem(CHIPS_STORAGE_KEY, JSON.stringify(atualizados));
  } catch (err) {
    console.warn('Erro ao persistir chip customizado no localStorage:', err);
  }
  return atualizados;
}

/**
 * Remove um chip customizado da memória persistente
 */
export function removerChipCustomizado(termo: string): string[] {
  const atuais = obterChipsCustomizados();
  const atualizados = atuais.filter(c => c.toLowerCase() !== termo.trim().toLowerCase());
  try {
    localStorage.setItem(CHIPS_STORAGE_KEY, JSON.stringify(atualizados));
  } catch (err) {
    console.warn('Erro ao remover chip customizado do localStorage:', err);
  }
  return atualizados;
}
