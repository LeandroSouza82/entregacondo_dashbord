import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaConcluirRota {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  rota_id?: string;
}

export async function concluirRota(rotaId: string): Promise<RespostaConcluirRota> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('concluir_rota', {
    p_rota_id: rotaId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaConcluirRota;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao concluir rota.');
  }

  return res;
}
