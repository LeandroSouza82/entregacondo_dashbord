import type { Database } from './database';

export type Motorista = Database['public']['Tables']['motoristas']['Row'];
export type ClienteEndereco = Database['public']['Tables']['clientes_enderecos']['Row'];
export type Entrega = Database['public']['Tables']['entregas']['Row'];
export type HistoricoAtendimento = Database['public']['Tables']['historico_atendimentos']['Row'];
export type RotaPlanejada = Database['public']['Tables']['rotas_planejadas']['Row'];
export type Empresa = Database['public']['Tables']['empresas']['Row'];
export type PerfilUsuario = Database['public']['Tables']['perfis_usuarios']['Row'];
export type EmpresaMembro = Database['public']['Tables']['empresa_membros']['Row'];
export type SolicitacaoAcesso = Database['public']['Tables']['solicitacoes_acesso']['Row'];
export type AuditoriaAcesso = Database['public']['Tables']['auditoria_acessos']['Row'];
export type VeiculoMotorista = Database['public']['Tables']['veiculos_motoristas']['Row'];
export type VeiculoDocumento = Database['public']['Tables']['veiculos_documentos']['Row'];

export interface SolicitacaoDetalhada extends SolicitacaoAcesso {
  usuario?: {
    id: string;
    nome: string;
    nome_completo?: string | null;
    email: string;
    telefone: string | null;
    avatar_url: string | null;
  };
  motorista?: Motorista | null;
  veiculo?: VeiculoMotorista | null;
  documentos?: VeiculoDocumento[];
  decidido_por_usuario?: {
    nome: string;
    nome_completo?: string | null;
    email: string;
  } | null;
}

export interface PontoCoordenada {
  lat: number;
  lng: number;
}

export interface PontoParada {
  status?: string;
  rotaId?: string;
  id: string; // id da entrega
  sequencia: number;
  clienteEnderecoId: string;
  nomeLocal: string;
  destinatario: string;
  unidade?: string;
  enderecoFormatado: string;
  coordenadas: PontoCoordenada;
  tempoMedioAtendimentoMinutos: number; // Histórico do condomínio/local
  prioridade: 'baixa' | 'normal' | 'alta' | 'urgente';
  codigoRastreio: string;
  tipoTarefa?: 'entrega' | 'coleta' | 'outros';
  descricaoOutro?: string;
  horaPrevistaChegada?: string;
  horaPrevistaSaida?: string;
}

export interface MetricasComparativasRota {
  distanciaOriginalKm: number;
  distanciaOtimizadaKm: number;
  economiaDistanciaKm: number;
  economiaDistanciaPct: number;

  tempoDeslocamentoOriginalMin: number;
  tempoDeslocamentoOtimizadoMin: number;
  tempoTotalAtendimentoMin: number; // soma dos tempos médios nos condomínios

  tempoTotalOriginalMin: number; // deslocamento + atendimentos
  tempoTotalOtimizadoMin: number; // deslocamento otimizado + atendimentos

  economiaTempoMin: number;
  economiaTempoPct: number;

  economiaFinanceiraEstimada: number; // Economia em combustível e horas
}

export interface ResumoOtimizacaoRota {
  motoristaId: string;
  motoristaNome: string;
  pontoPartida: {
    nome: string;
    coordenadas: PontoCoordenada;
  };
  paradasOriginais: PontoParada[];
  paradasOtimizadas: PontoParada[];
  metricas: MetricasComparativasRota;
  timestampCalculo: string;
}
