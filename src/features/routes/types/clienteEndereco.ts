import type { PontoCoordenada } from '../../../types/logistics';

export interface ClienteEnderecoItem {
  id: string;
  empresa_id?: string;
  nome_identificador: string;
  destinatario_padrao?: string | null;
  endereco_completo: string;
  numero?: string;
  bairro?: string;
  cidade?: string;
  cep?: string;
  latitude: number;
  longitude: number;
  tempo_medio_minutos?: number;
  total_entregas_realizadas: number;
  tipo_local?: 'condominio_horizontal' | 'edificio_vertical' | 'comercial' | 'casa_rua';
  observacoes_acesso?: string | null;
}

export interface NovoClienteEnderecoPayload {
  empresa_id?: string;
  nome_identificador: string;
  destinatario_padrao?: string | null;
  endereco_completo: string;
  coordenadas: PontoCoordenada;
  observacoes_acesso?: string | null;
  tipo_local?: 'condominio_horizontal' | 'edificio_vertical' | 'comercial' | 'casa_rua';
}
