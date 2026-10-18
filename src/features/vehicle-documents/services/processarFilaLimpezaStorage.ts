import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface ItemFilaLimpeza {
  id: string;
  bucket_id: string;
  storage_path: string;
  empresa_id: string;
  user_id: string;
  motivo: string;
  status: 'pendente' | 'em_processamento' | 'concluido' | 'falhou';
  tentativas: number;
  max_tentativas: number;
  ultimo_erro: string | null;
  created_at: string;
}

export interface ResultadoProcessamentoFila {
  totalVerificados: number;
  sucessos: number;
  falhas: number;
  erros: Array<{ filaId: string; storagePath: string; erro: string }>;
}

/**
 * Mecanismo recuperável de limpeza de arquivos pendentes no Storage.
 * Consulta a tabela `storage_limpeza_fila` para itens com status 'pendente'
 * cuja limpeza física não foi concluída na chamada original.
 * Para cada item:
 * 1. Invoca a API de Storage `remove([storage_path])`.
 * 2. Atualiza o status persistentemente via `registrar_limpeza_storage_executada`.
 */
export async function processarFilaLimpezaStorage(
  limiteItens = 20
): Promise<ResultadoProcessamentoFila> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data: itens, error } = await supabase
    .from('storage_limpeza_fila')
    .select('*')
    .eq('status', 'pendente')
    .order('created_at', { ascending: true })
    .limit(limiteItens);

  if (error) {
    throw new Error(`Falha ao consultar fila de limpeza: ${error.message}`);
  }

  const resultado: ResultadoProcessamentoFila = {
    totalVerificados: itens ? itens.length : 0,
    sucessos: 0,
    falhas: 0,
    erros: [],
  };

  if (!itens || itens.length === 0) {
    return resultado;
  }

  for (const item of itens as unknown as ItemFilaLimpeza[]) {
    try {
      const { error: storageError } = await supabase.storage
        .from(item.bucket_id || 'veiculos-documentos')
        .remove([item.storage_path]);

      if (storageError) {
        await supabase.rpc('registrar_limpeza_storage_executada', {
          p_fila_id: item.id,
          p_sucesso: false,
          p_erro: storageError.message,
        });
        resultado.falhas++;
        resultado.erros.push({
          filaId: item.id,
          storagePath: item.storage_path,
          erro: storageError.message,
        });
      } else {
        await supabase.rpc('registrar_limpeza_storage_executada', {
          p_fila_id: item.id,
          p_sucesso: true,
          p_erro: null,
        });
        resultado.sucessos++;
      }
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : 'Falha desconhecida no processamento de limpeza';
      await supabase.rpc('registrar_limpeza_storage_executada', {
        p_fila_id: item.id,
        p_sucesso: false,
        p_erro: errMsg,
      });
      resultado.falhas++;
      resultado.erros.push({
        filaId: item.id,
        storagePath: item.storage_path,
        erro: errMsg,
      });
    }
  }

  return resultado;
}
