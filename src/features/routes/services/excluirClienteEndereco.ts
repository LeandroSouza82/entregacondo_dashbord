import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

/**
 * Exclui permanentemente um endereço salvo de `clientes_enderecos`.
 * A tabela não permite DELETE direto ao papel `authenticated`; a exclusão
 * passa pela RPC `excluir_cliente_endereco`, que valida empresa e papel de gestão.
 */
export async function excluirClienteEndereco(id: string): Promise<void> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado.');
  }

  const { data, error } = await supabase.rpc('excluir_cliente_endereco', { p_id: id });

  if (error) {
    throw new Error(error.message);
  }
  const resultado = data as { sucesso?: boolean; mensagem?: string } | null;
  if (!resultado?.sucesso) {
    throw new Error(resultado?.mensagem || 'Não foi possível excluir o endereço.');
  }
}
