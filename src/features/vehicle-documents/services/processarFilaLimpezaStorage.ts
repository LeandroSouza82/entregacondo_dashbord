import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface ItemFilaLimpezaClaimed {
  id: string;
  bucket_id: string;
  storage_path: string;
  empresa_id: string;
  user_id: string;
  motivo: string;
  status: 'reservado' | 'vinculado' | 'pendente' | 'em_processamento' | 'concluido' | 'falhou';
  tentativas: number;
  max_tentativas: number;
  claim_token: string;
  lease_expires_at: string;
}

export interface DetalheItemProcessado {
  filaId: string;
  storagePath: string;
  remocaoFisicaSucesso: boolean;
  confirmacaoBancoSucesso: boolean;
  confirmacaoBancoErro: string | null;
  statusFinal: string;
  codigoRecusa?: string;
}

export interface ResultadoProcessamentoFila {
  totalReivindicados: number;
  sucessosCompletos: number;
  removidosFisicoPendenteConfirmacao: number;
  falhasFisicas: number;
  errosConfirmacaoBanco: number;
  itens: DetalheItemProcessado[];
}

export interface EstatisticasFilaLimpeza {
  pendentes: number;
  emProcessamento: number;
  falhas: number;
  concluidos: number;
  total: number;
}

/**
 * Consulta as estatísticas atuais da fila de limpeza do Storage para a empresa/gestão atual.
 */
export async function consultarEstatisticasFilaLimpeza(): Promise<EstatisticasFilaLimpeza> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase
    .from('storage_limpeza_fila')
    .select('status');

  if (error) {
    throw new Error(`Falha ao consultar fila de limpeza: ${error.message}`);
  }

  const stats: EstatisticasFilaLimpeza = {
    pendentes: 0,
    emProcessamento: 0,
    falhas: 0,
    concluidos: 0,
    total: data ? data.length : 0,
  };

  if (data) {
    data.forEach((row: { status: string }) => {
      if (row.status === 'pendente') stats.pendentes++;
      else if (row.status === 'em_processamento') stats.emProcessamento++;
      else if (row.status === 'falhou') stats.falhas++;
      else if (row.status === 'concluido') stats.concluidos++;
    });
  }

  return stats;
}

/**
 * Retoma explicitamente um item com status 'falhou', recolocando-o na fila como 'pendente'.
 */
export async function retomarLimpezaFalha(filaId: string): Promise<{ sucesso: boolean; mensagem: string }> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('retomar_limpeza_falha', {
    p_fila_id: filaId,
  });

  if (error) {
    throw new Error(`Erro de comunicação com o servidor: ${error.message}`);
  }

  const res = (data as unknown) as { sucesso: boolean; codigo?: string; mensagem?: string };
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao retomar item de limpeza falha.');
  }

  return { sucesso: true, mensagem: res.mensagem || 'Limpeza retomada com sucesso.' };
}

/**
 * Processamento robusto e coordenado da fila de limpeza do Storage:
 * 1. Reivindica atomicamente itens com `FOR UPDATE SKIP LOCKED` e recuperação de lease expirado (5 min).
 * 2. Previne processamento concorrente do mesmo item por múltiplos clientes.
 * 3. Distingue remoção física na API de Storage de confirmação no PostgreSQL.
 * 4. Valida erros de transporte PostgREST e payload de recusa `data.sucesso` e `data.codigo`.
 * 5. Garante que itens concluídos não sejam reabertos por chamadas concorrentes ou repetidas.
 */
export async function processarFilaLimpezaStorage(
  limiteItens = 10,
  filaId?: string
): Promise<ResultadoProcessamentoFila> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  // 1. Reivindicação atômica e segura via RPC
  const { data: itensReivindicados, error: claimError } = await supabase.rpc(
    'reivindicar_itens_limpeza_storage',
    { p_limite: limiteItens, p_fila_id: filaId ?? null }
  );

  if (claimError) {
    throw new Error(`Falha ao reivindicar itens da fila de limpeza: ${claimError.message}`);
  }

  const itens = (itensReivindicados as unknown) as ItemFilaLimpezaClaimed[] || [];

  const resultado: ResultadoProcessamentoFila = {
    totalReivindicados: itens.length,
    sucessosCompletos: 0,
    removidosFisicoPendenteConfirmacao: 0,
    falhasFisicas: 0,
    errosConfirmacaoBanco: 0,
    itens: [],
  };

  if (itens.length === 0) {
    return resultado;
  }

  // 2. Processamento individual com validação de dois estágios (físico + confirmação no banco)
  for (const item of itens) {
    let remocaoFisicaSucesso = false;
    let confirmacaoBancoSucesso = false;
    let confirmacaoBancoErro: string | null = null;
    let codigoRecusa: string | undefined;
    let statusFinal = 'desconhecido';
    let erroFisicoMsg: string | null = null;

    // Não iniciar uma remoção usando uma tentativa sem identidade ou expirada.
    // Caminhos descartados nunca voltam a ser vinculados.
    // Estágio A: Remoção física no Storage
    try {
      if (!item.claim_token || !Number.isFinite(Date.parse(item.lease_expires_at)) || Date.parse(item.lease_expires_at) <= Date.now()) {
        throw new Error('Prazo da tentativa de limpeza expirou. Reivindique o item novamente.');
      }
      const { error: storageError } = await supabase.storage
        .from(item.bucket_id || 'veiculos-documentos')
        .remove([item.storage_path]);

      if (storageError) {
        erroFisicoMsg = storageError.message;
        remocaoFisicaSucesso = false;
      } else {
        remocaoFisicaSucesso = true;
      }
    } catch (storageException) {
      erroFisicoMsg = storageException instanceof Error ? storageException.message : 'Falha de rede no Storage';
      remocaoFisicaSucesso = false;
    }

    // Estágio B: Confirmação e registro auditado no PostgreSQL
    try {
      const { data: rpcData, error: rpcError } = await supabase.rpc(
        'registrar_limpeza_storage_executada',
        {
          p_fila_id: item.id,
          p_claim_token: item.claim_token,
          p_sucesso: remocaoFisicaSucesso,
          p_erro: remocaoFisicaSucesso ? null : erroFisicoMsg,
        }
      );

      if (rpcError) {
        confirmacaoBancoSucesso = false;
        confirmacaoBancoErro = `Erro PostgREST: ${rpcError.message}`;
      } else {
        const resp = (rpcData as unknown) as { sucesso: boolean; codigo?: string; mensagem?: string; status?: string };
        if (resp && resp.sucesso) {
          confirmacaoBancoSucesso = true;
          statusFinal = resp.status || (remocaoFisicaSucesso ? 'concluido' : 'pendente');
          codigoRecusa = resp.codigo;
        } else {
          confirmacaoBancoSucesso = false;
          confirmacaoBancoErro = resp?.mensagem || 'Recusa ao registrar limpeza no banco.';
          codigoRecusa = resp?.codigo;
          statusFinal = 'recusado_no_banco';
        }
      }
    } catch (rpcException) {
      confirmacaoBancoSucesso = false;
      confirmacaoBancoErro = rpcException instanceof Error ? rpcException.message : 'Falha desconhecida na RPC';
      statusFinal = 'falha_transporte_banco';
    }

    // Estágio C: Totalização e auditoria precisa
    if (remocaoFisicaSucesso && confirmacaoBancoSucesso) {
      resultado.sucessosCompletos++;
    } else if (remocaoFisicaSucesso && !confirmacaoBancoSucesso) {
      resultado.removidosFisicoPendenteConfirmacao++;
      resultado.errosConfirmacaoBanco++;
    } else if (!remocaoFisicaSucesso) {
      resultado.falhasFisicas++;
      if (!confirmacaoBancoSucesso) {
        resultado.errosConfirmacaoBanco++;
      }
    }

    resultado.itens.push({
      filaId: item.id,
      storagePath: item.storage_path,
      remocaoFisicaSucesso,
      confirmacaoBancoSucesso,
      confirmacaoBancoErro: confirmacaoBancoErro || (remocaoFisicaSucesso ? null : erroFisicoMsg),
      statusFinal,
      codigoRecusa,
    });
  }

  return resultado;
}
