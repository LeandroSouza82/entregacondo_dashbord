import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { CadastroVeiculoInput } from '../types/vehicle';
import { validarCadastroVeiculo } from '../validators/vehicleValidator';

export interface RespostaCadastroVeiculo {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  veiculo_id?: string;
}

export async function cadastrarMeuVeiculo(input: CadastroVeiculoInput): Promise<RespostaCadastroVeiculo> {
  const validacao = validarCadastroVeiculo(input);
  if (!validacao.valido || !validacao.dadosNormalizados) {
    throw new Error(validacao.erros.join(' '));
  }

  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('cadastrar_meu_veiculo', {
    p_dados: validacao.dadosNormalizados as unknown as never,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaCadastroVeiculo;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao cadastrar veículo.');
  }

  return res;
}
