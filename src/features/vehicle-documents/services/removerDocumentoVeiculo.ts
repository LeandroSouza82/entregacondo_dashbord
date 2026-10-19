import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import { processarFilaLimpezaStorage } from './processarFilaLimpezaStorage';

export interface RespostaRemocaoDocumento {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  storage_path?: string;
  fila_id?: string;
  veiculo_id?: string;
  limpeza_fisica_sucesso?: boolean;
  confirmacao_banco_sucesso?: boolean;
  detalhe_confirmacao?: string;
}

/** Desvincula e só remove o objeto depois de reivindicar uma tentativa exclusiva. */
export async function removerDocumentoVeiculo(documentoId: string): Promise<RespostaRemocaoDocumento> {
  if (!isSupabaseConfigured) throw new Error('Supabase não configurado no ambiente.');
  const { data, error } = await supabase.rpc('remover_documento_veiculo', { p_documento_id: documentoId });
  if (error) throw new Error(error.message);
  const res = data as unknown as RespostaRemocaoDocumento;
  if (!res?.sucesso) throw new Error(res?.mensagem || 'Falha ao remover evidência.');
  res.limpeza_fisica_sucesso = false;
  res.confirmacao_banco_sucesso = false;
  res.detalhe_confirmacao = 'Documento desvinculado; limpeza pendente na fila.';
  if (!res.fila_id) return res;
  try {
    const resultado = await processarFilaLimpezaStorage(1, res.fila_id);
    const item = resultado.itens.find((i) => i.filaId === res.fila_id);
    if (item) {
      res.limpeza_fisica_sucesso = item.remocaoFisicaSucesso;
      res.confirmacao_banco_sucesso = item.confirmacaoBancoSucesso && item.statusFinal === 'concluido';
      res.detalhe_confirmacao = item.confirmacaoBancoErro || (res.confirmacao_banco_sucesso ? 'Limpeza concluída.' : 'Limpeza pendente de recuperação.');
    }
  } catch (erro) {
    res.detalhe_confirmacao = 'Desvinculação salva; limpeza pendente: ' + (erro instanceof Error ? erro.message : 'falha de comunicação');
  }
  return res;
}
