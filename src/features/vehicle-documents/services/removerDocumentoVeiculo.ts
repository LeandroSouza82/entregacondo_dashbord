import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaRemocaoDocumento {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  storage_path?: string;
  fila_id?: string;
  veiculo_id?: string;
  limpeza_fisica_sucesso?: boolean;
}

/**
 * Remove uma evidência de veículo de forma atômica e coordenada:
 * 1. Desvincula o metadado no banco e invalida a aprovação do veículo.
 * 2. Enfileira o caminho na tabela auditável `storage_limpeza_fila`.
 * 3. Tenta a exclusão física via API oficial do Storage.
 * 4. Registra persistentemente o resultado (sucesso ou falha) via RPC registrar_limpeza_storage_executada.
 */
export async function removerDocumentoVeiculo(
  documentoId: string
): Promise<RespostaRemocaoDocumento> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  // 1. Invoca a RPC atômica que valida autorização, remove os metadados,
  // enfileira o storage_path em storage_limpeza_fila e invalida a aprovação
  const { data, error } = await supabase.rpc('remover_documento_veiculo', {
    p_documento_id: documentoId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaRemocaoDocumento;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao remover evidência do veículo.');
  }

  // 2. Limpeza física no Supabase Storage via API oficial de Storage (sem DELETE SQL direto)
  let limpezaSucesso = false;
  if (res.storage_path && res.fila_id) {
    try {
      const { error: storageError } = await supabase.storage
        .from('veiculos-documentos')
        .remove([res.storage_path]);

      if (storageError) {
        // Registra formalmente a falha na fila persistente para auditoria e retentativa
        await supabase.rpc('registrar_limpeza_storage_executada', {
          p_fila_id: res.fila_id,
          p_sucesso: false,
          p_erro: storageError.message,
        });
        console.warn('Falha registrada na fila de limpeza do storage:', storageError.message);
      } else {
        // Registra formalmente a conclusão da limpeza física
        limpezaSucesso = true;
        await supabase.rpc('registrar_limpeza_storage_executada', {
          p_fila_id: res.fila_id,
          p_sucesso: true,
          p_erro: null,
        });
      }
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : 'Erro desconhecido ao excluir arquivo do storage';
      await supabase.rpc('registrar_limpeza_storage_executada', {
        p_fila_id: res.fila_id,
        p_sucesso: false,
        p_erro: errMsg,
      });
      console.warn('Erro de rede/transporte registrado na fila de limpeza:', errMsg);
    }
  }

  res.limpeza_fisica_sucesso = limpezaSucesso;
  return res;
}
