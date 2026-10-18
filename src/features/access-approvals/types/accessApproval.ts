import type { VeiculoDeclarado } from '../../vehicles/types/vehicle';
import type { DocumentoVeiculoItem } from '../../vehicle-documents/types/vehicleDocument';

export type StatusAcesso = 'pendente' | 'aprovado' | 'rejeitado' | 'suspenso';
export type FiltroStatusAcesso = 'todos' | 'pendente' | 'aprovado' | 'suspenso' | 'rejeitado';

export interface SolicitacaoAcessoItem {
  id: string;
  empresa_id: string;
  empresa_nome: string;
  user_id: string;
  usuario_nome: string;
  usuario_email: string;
  usuario_telefone?: string | null;
  usuario_avatar?: string | null;
  papel_solicitado: 'motorista';
  status: StatusAcesso;
  motorista_vinculado_id?: string | null;
  motorista_nome?: string | null;
  motorista_veiculo?: string | null;
  motorista_placa?: string | null;
  veiculo_declarado?: VeiculoDeclarado | null;
  documentos?: DocumentoVeiculoItem[];
  motivo_decisao?: string | null;
  decidido_por_nome?: string | null;
  decidido_em?: string | null;
  created_at: string;
}

export interface MotoristaFrotaItem {
  id: string;
  empresa_id: string;
  user_id: string | null;
  nome: string;
  telefone: string;
  email: string | null;
  veiculo_modelo: string;
  veiculo_placa: string;
  status: string;
  ativo: boolean;
}
