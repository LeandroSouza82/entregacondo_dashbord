import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaRemocaoDocumento {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  storage_path?: string;
  veiculo_id?: string;
}

export async function removerDocumentoVeiculo(
  documentoId: string
): Promise<RespostaRemocaoDocumento> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  // 1. Invoca a RPC atômica que valida permissões, remove os metadados
  // e invalida imediatamente a aprovação do veículo no PostgreSQL
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

  // 2. Limpeza física autorizada no Supabase Storage via API de storage
  // (permitida pela política de storage agora que o registro não está mais aprovado)
  if (res.storage_path) {
    try {
      const { error: storageError } = await supabase.storage
        .from('veiculos-documentos')
        .remove([res.storage_path]);

      if (storageError) {
        console.warn('Aviso: Falha na remoção física do objeto no storage:', storageError.message);
      }
    } catch (err) {
      console.warn('Aviso ao tentar excluir arquivo físico do storage:', err);
    }
  }

  return res;
}
