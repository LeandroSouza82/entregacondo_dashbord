import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaSuspensao {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
}

export async function suspenderAcessoMembro(
  membroId: string,
  motivo: string
): Promise<RespostaSuspensao> {
  if (!motivo || !motivo.trim()) {
    throw new Error('Informe a justificativa da suspensão de acesso.');
  }

  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('suspender_acesso_membro', {
    p_membro_id: membroId,
    p_motivo: motivo.trim(),
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaSuspensao;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao suspender acesso.');
  }

  return res;
}
