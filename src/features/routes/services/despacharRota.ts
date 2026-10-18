import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { DespachoRotaInput, RespostaDespachoRota } from '../types/route';
import { validarDespachoRota } from '../validators/routeValidator';

export async function despacharRota(input: DespachoRotaInput): Promise<RespostaDespachoRota> {
  const validacao = validarDespachoRota(input);
  if (!validacao.valido) {
    throw new Error(validacao.erros.join(' '));
  }

  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('despachar_rota_transacional', {
    p_dados: input as unknown as never,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaDespachoRota;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao despachar rota transacional.');
  }

  return res;
}
