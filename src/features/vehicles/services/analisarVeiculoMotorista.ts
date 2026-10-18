import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaAnaliseVeiculo {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  status_analise?: 'aprovado' | 'rejeitado';
  revisao?: number;
  revisao_esperada?: number;
  revisao_atual?: number;
}

export async function analisarVeiculoMotorista(
  veiculoId: string,
  aprovar: boolean,
  revisaoEsperada: number,
  motivoRejeicao?: string
): Promise<RespostaAnaliseVeiculo> {
  if (revisaoEsperada === undefined || revisaoEsperada === null || revisaoEsperada < 1) {
    throw new Error('A revisão visualizada do veículo é obrigatória para registrar a análise.');
  }

  if (!aprovar && (!motivoRejeicao || !motivoRejeicao.trim())) {
    throw new Error('Informe o motivo da rejeição do veículo.');
  }

  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('analisar_veiculo_motorista', {
    p_veiculo_id: veiculoId,
    p_aprovar: aprovar,
    p_revisao_esperada: revisaoEsperada,
    p_motivo_rejeicao: motivoRejeicao ? motivoRejeicao.trim() : undefined,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaAnaliseVeiculo;
  if (!res || !res.sucesso) {
    if (res?.codigo === 'REVISAO_DESATUALIZADA') {
      throw new Error(
        'O cadastro ou evidências do veículo foram alterados durante a sua conferência. A página precisa ser atualizada para verificar a nova versão antes de decidir.'
      );
    }
    throw new Error(res?.mensagem || 'Falha ao processar análise do veículo.');
  }

  return res;
}
