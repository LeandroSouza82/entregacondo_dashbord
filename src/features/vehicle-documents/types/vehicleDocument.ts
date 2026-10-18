export type TipoDocumentoVeiculo = 'foto_veiculo' | 'crlv' | 'complementar';
export type AnguloFotoVeiculo = 'frente' | 'lado_direito' | 'lado_esquerdo' | 'traseira';
export type StatusDocumento = 'pendente' | 'aprovado' | 'rejeitado';

export interface DocumentoVeiculoItem {
  id: string;
  veiculo_id: string;
  user_id: string;
  empresa_id: string;
  tipo_documento: TipoDocumentoVeiculo;
  angulo_foto?: AnguloFotoVeiculo | null;
  nome_arquivo: string;
  storage_path: string;
  mime_type: string;
  tamanho_bytes: number;
  status_analise: StatusDocumento;
  motivo_rejeicao?: string | null;
  analisado_por?: string | null;
  analisado_em?: string | null;
  created_at: string;
  updated_at?: string;
}
