export interface ParadaDespachoInput {
  cliente_endereco_id: string;
  destinatario_nome: string;
  destinatario_telefone?: string | null;
  unidade_apartamento?: string | null;
  codigo_rastreio?: string;
  tipo_tarefa?: 'entrega' | 'coleta' | 'outros';
  descricao_outro?: string | null;
  peso_kg?: number | null;
  volumes_qtd?: number;
  prioridade?: 'baixa' | 'normal' | 'alta' | 'urgente';
  ordem_na_rota?: number;
  observacoes_gestor?: string | null;
}

export interface DespachoRotaInput {
  empresa_id: string;
  motorista_id: string;
  idempotency_key: string;
  distancia_original_km: number;
  tempo_original_minutos: number;
  distancia_otimizada_km: number;
  tempo_otimizado_minutos: number;
  ordem_paradas_json?: unknown;
  paradas: ParadaDespachoInput[];
}

export interface RespostaDespachoRota {
  sucesso: boolean;
  mensagem: string;
  codigo?: string;
  rota_id?: string;
  total_paradas?: number;
  idempotente?: boolean;
}
