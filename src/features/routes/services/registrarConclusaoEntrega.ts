import { supabase, isSupabaseConfigured } from '../../../lib/supabase';

export interface ParametrosConclusaoEntrega {
  entregaId: string;
  sucesso: boolean;
  motivoFalha?: string;
  tempoPortariaMinutos?: number;
  tempoDeslocamentoMinutos?: number;
  dataHoraChegada?: string;
  dataHoraConclusao?: string;
}

export interface RespostaConclusaoEntrega {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  entrega_id?: string;
  status?: string;
  historico_id?: string;
}

export async function registrarConclusaoEntrega(
  params: ParametrosConclusaoEntrega
): Promise<RespostaConclusaoEntrega> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('registrar_conclusao_entrega', {
    p_entrega_id: params.entregaId,
    p_sucesso: params.sucesso,
    p_motivo_falha: params.motivoFalha || undefined,
    p_tempo_portaria: params.tempoPortariaMinutos ?? 0,
    p_tempo_deslocamento: params.tempoDeslocamentoMinutos ?? 0,
    p_data_hora_chegada: params.dataHoraChegada || undefined,
    p_data_hora_conclusao: params.dataHoraConclusao || undefined,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaConclusaoEntrega;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao registrar conclusão de entrega.');
  }

  return res;
}
