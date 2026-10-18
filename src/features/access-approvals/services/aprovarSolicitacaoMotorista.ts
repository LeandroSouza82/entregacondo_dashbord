import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface ParametrosAprovacao {
  solicitacaoId: string;
  criarNovoMotorista: boolean;
  motoristaId?: string | null;
  nomeMotorista?: string;
  telefoneMotorista?: string;
  revisaoEsperadaVeiculo?: number | null;
}

export interface RespostaAprovacao {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  motorista_id?: string;
}

export async function aprovarSolicitacaoMotorista(
  params: ParametrosAprovacao
): Promise<RespostaAprovacao> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  if (!params.criarNovoMotorista && !params.motoristaId) {
    throw new Error('Selecione um motorista existente da frota ou marque a opção de criar novo cadastro.');
  }

  const { data, error } = await supabase.rpc('aprovar_solicitacao_motorista', {
    p_solicitacao_id: params.solicitacaoId,
    p_motorista_id: params.motoristaId || null,
    p_criar_novo_motorista: params.criarNovoMotorista,
    p_nome_motorista: params.nomeMotorista ? params.nomeMotorista.trim() : null,
    p_telefone_motorista: params.telefoneMotorista ? params.telefoneMotorista.trim() : null,
    p_revisao_esperada_veiculo: params.revisaoEsperadaVeiculo || null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaAprovacao;
  if (!res || !res.sucesso) {
    if (res?.codigo === 'REVISAO_DESATUALIZADA') {
      throw new Error(
        'O veículo do condutor foi alterado durante a análise. A página precisa ser atualizada para conferência da nova versão antes de decidir.'
      );
    }
    throw new Error(res?.mensagem || 'Falha ao processar aprovação.');
  }

  return res;
}
