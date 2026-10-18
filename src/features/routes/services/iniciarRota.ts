import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaIniciarRota {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  rota_id?: string;
}

export async function iniciarRota(rotaId: string): Promise<RespostaIniciarRota> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('iniciar_rota', {
    p_rota_id: rotaId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaIniciarRota;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao iniciar rota.');
  }

  return res;
}
