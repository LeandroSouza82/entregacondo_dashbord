import type { DespachoRotaInput } from '../types/route';

export interface ValidacaoRotaResultado {
  valido: boolean;
  erros: string[];
}

export function validarDespachoRota(input: Partial<DespachoRotaInput>): ValidacaoRotaResultado {
  const erros: string[] = [];

  if (!input.empresa_id) {
    erros.push('Empresa é obrigatória para o despacho.');
  }

  if (!input.motorista_id) {
    erros.push('Motorista da frota é obrigatório.');
  }

  if (!input.idempotency_key || !input.idempotency_key.trim()) {
    erros.push('Chave de idempotência (idempotency_key) é obrigatória.');
  }

  if (!input.paradas || input.paradas.length === 0) {
    erros.push('A rota deve conter pelo menos uma parada de entrega.');
  } else {
    input.paradas.forEach((p, idx) => {
      if (!p.cliente_endereco_id) {
        erros.push(`Parada #${idx + 1}: endereço do cliente não selecionado.`);
      }
      if (!p.destinatario_nome || !p.destinatario_nome.trim()) {
        erros.push(`Parada #${idx + 1}: nome do destinatário é obrigatório.`);
      }
    });
  }

  return {
    valido: erros.length === 0,
    erros,
  };
}
