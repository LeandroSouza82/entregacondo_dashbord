import { supabase, isSupabaseConfigured } from '../../../lib/supabase';
import type { TipoDocumentoVeiculo, AnguloFotoVeiculo } from '../types/vehicleDocument';

export interface ParametrosAnexoVeiculo {
  veiculoId: string;
  tipoDocumento: TipoDocumentoVeiculo;
  nomeArquivo: string;
  storagePath: string;
  tamanhoBytes: number;
  anguloFoto?: AnguloFotoVeiculo | null;
}

export interface RespostaAnexoVeiculo {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  documento_id?: string;
  angulo_foto?: string | null;
  tipo_documento?: string;
}

export async function anexarDocumentoVeiculo(
  params: ParametrosAnexoVeiculo
): Promise<RespostaAnexoVeiculo> {
  if (!isSupabaseConfigured) {
    throw new Error('Supabase não configurado no ambiente.');
  }

  const { data, error } = await supabase.rpc('anexar_documento_veiculo', {
    p_veiculo_id: params.veiculoId,
    p_tipo_documento: params.tipoDocumento,
    p_nome_arquivo: params.nomeArquivo,
    p_storage_path: params.storagePath,
    p_tamanho_bytes: params.tamanhoBytes,
    p_angulo_foto: params.anguloFoto || null,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = (data as unknown) as RespostaAnexoVeiculo;
  if (!res || !res.sucesso) {
    throw new Error(res?.mensagem || 'Falha ao anexar documento do veículo.');
  }

  return res;
}
