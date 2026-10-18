import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface RespostaRejeicao {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
}

export async function rejeitarSolicitacaoAcesso(
  solicitacaoId: string,
  motivo: string
): Promise<RespostaRejeicao> {
  if (!motivo || !motivo.trim()) {
    throw new Error('Informe o motivo da rejeição para registro de auditoria.');
  }

  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('rejeitar_solicitacao_acesso', {
    p_solicitacao_id: solicitacaoId,
    p_motivo: motivo.trim(),
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaRejeicao;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao rejeitar solicitação.');
  }

  return res;
}
