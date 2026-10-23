import type { PontoParada } from '../types/logistics';

/**
 * Mapeamento visual e amigável por Tipo de Serviço para WhatsApp:
 * - Entrega: 📦 Entrega
 * - Coleta: 🔄 Coleta
 * - Outros: 📌 [Nome customizado ou 'Outros']
 */
export function formatServiceType(tipoTarefa?: string, descricaoOutro?: string): string {
  const tipo = (tipoTarefa || 'entrega').trim().toLowerCase();
  if (tipo === 'coleta') {
    return '🔄 Coleta';
  }
  if (tipo === 'outros') {
    const desc = descricaoOutro?.trim();
    return desc ? `📌 ${desc}` : '📌 Outros';
  }
  if (tipo !== 'entrega') {
    const formatado = tipo.charAt(0).toUpperCase() + tipo.slice(1);
    return `📌 ${formatado}`;
  }
  return '📦 Entrega';
}

/**
 * Formata a lista de paradas da rota no padrão estrito para WhatsApp.
 * Padrão visual por item:
 * *1 - [Nome do Cliente/Condomínio]*
 * 📦 Entrega
 * 📍 [Endereço completo]
 * 
 * Obs:
 * [Texto da observação]
 * 
 * --------------------
 */
export function formatRouteForWhatsApp(paradas: PontoParada[]): string {
  if (!paradas || paradas.length === 0) {
    return '';
  }

  return paradas
    .map((parada, index) => {
      const numero = index + 1;
      const nomeCliente = (parada.nomeLocal && parada.destinatario && parada.nomeLocal.trim() !== parada.destinatario.trim())
        ? `${parada.nomeLocal.trim()} - ${parada.destinatario.trim()}`
        : (parada.nomeLocal?.trim() || parada.destinatario?.trim() || 'Cliente');

      const tipoFormatado = formatServiceType(parada.tipoTarefa, parada.descricaoOutro);
      const endereco = parada.enderecoFormatado || (parada as { endereco?: string }).endereco || '';
      const observacao = (parada.observacoesGestor || (parada as { observacoes_gestor?: string }).observacoes_gestor || '').trim();

      const blocos = [
        `*${numero} - ${nomeCliente}*`,
        tipoFormatado,
        `📍 ${endereco}`,
      ];

      if (observacao) {
        blocos.push('', `Obs:\n${observacao}`);
      }

      blocos.push('', '--------------------');
      return blocos.join('\n');
    })
    .join('\n\n');
}

/**
 * Abre o link oficial do WhatsApp em uma nova aba com o texto codificado.
 * Usa api.whatsapp.com/send para preservar emojis UTF-8 (o wa.me corrompe emojis 4-bytes durante o redirect 302).
 */
export function sendRouteToWhatsApp(paradas: PontoParada[]): boolean {
  const textoFormatado = formatRouteForWhatsApp(paradas);
  if (!textoFormatado) {
    return false;
  }
  const url = `https://api.whatsapp.com/send?text=${encodeURIComponent(textoFormatado)}`;
  window.open(url, '_blank', 'noopener,noreferrer');
  return true;
}

/**
 * Copia a lista formatada para a área de transferência com callback de feedback.
 */
export async function copyRouteToClipboard(
  paradas: PontoParada[],
  onFeedback?: (mensagem: string) => void
): Promise<boolean> {
  const textoFormatado = formatRouteForWhatsApp(paradas);
  if (!textoFormatado) {
    return false;
  }

  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(textoFormatado);
    } else {
      const textarea = document.createElement('textarea');
      textarea.value = textoFormatado;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
    }

    onFeedback?.('Lista de entregas copiada para a área de transferência!');
    return true;
  } catch {
    return false;
  }
}
