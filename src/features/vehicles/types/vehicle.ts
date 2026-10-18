export type TipoVeiculo = 'moto' | 'carro';
export type TipoCompartimentoMoto = 'bau' | 'mochila' | 'bag';
export type TamanhoCompartimento = 'pequeno' | 'medio' | 'grande';
export type StatusAnaliseVeiculo = 'pendente' | 'aprovado' | 'rejeitado';

export interface VeiculoDeclarado {
  id: string;
  user_id: string;
  empresa_id: string;
  tipo_veiculo: TipoVeiculo;
  marca: string;
  modelo: string;
  placa: string;
  compartimento?: TipoCompartimentoMoto | null;
  volume_litros?: number | null;
  tamanho_compartimento?: TamanhoCompartimento | null;
  capacidade_kg?: number | null;
  status_analise: StatusAnaliseVeiculo;
  revisao: number;
  motivo_rejeicao?: string | null;
  analisado_por?: string | null;
  analisado_em?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface CadastroVeiculoInput {
  tipo_veiculo: TipoVeiculo;
  marca: string;
  modelo: string;
  placa: string;
  compartimento?: TipoCompartimentoMoto | null;
  volume_litros?: number | null;
  tamanho_compartimento?: TamanhoCompartimento | null;
  capacidade_kg?: number | null;
}
