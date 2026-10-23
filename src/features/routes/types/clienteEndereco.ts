import type { PontoCoordenada } from '../../../types/logistics';

export interface ClienteEnderecoItem {
  id: string;
  empresa_id?: string;
  nome_identificador: string;
  destinatario_padrao?: string | null;
  whatsapp_cliente?: string | null;
  endereco_completo: string;
  numero?: string;
  bairro?: string;
  cidade?: string;
  cep?: string;
  latitude: number;
  longitude: number;
  place_id?: string | null;
  tempo_medio_minutos?: number;
  total_entregas_realizadas: number;
  tipo_local?: 'condominio_horizontal' | 'edificio_vertical' | 'comercial' | 'casa_rua';
  observacoes_acesso?: string | null;
  created_at?: string;
}

export interface SavedAddressItem {
  id: string;
  label: string;
  full_address: string;
  lat: number;
  lng: number;
  place_id?: string | null;
  created_at?: string;
  empresa_id?: string;
}

export interface NovoClienteEnderecoPayload {
  empresa_id?: string;
  nome_identificador?: string;
  label?: string;
  destinatario_padrao?: string | null;
  whatsapp_cliente?: string | null;
  endereco_completo?: string;
  full_address?: string;
  coordenadas?: PontoCoordenada;
  lat?: number;
  lng?: number;
  observacoes_acesso?: string | null;
  tipo_local?: 'condominio_horizontal' | 'edificio_vertical' | 'comercial' | 'casa_rua';
  place_id?: string | null;
}
