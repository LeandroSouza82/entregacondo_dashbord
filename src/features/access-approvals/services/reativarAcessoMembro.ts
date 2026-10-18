import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaReativacao {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
}

export async function reativarAcessoMembro(membroId: string): Promise<RespostaReativacao> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('reativar_acesso_membro', {
    p_membro_id: membroId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaReativacao;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao reativar acesso.');
  }

  return res;
}
