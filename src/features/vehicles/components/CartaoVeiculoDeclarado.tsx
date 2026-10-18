import React from 'react';
import { AlertCircle, CheckCircle2, Clock, XCircle, FileText } from 'lucide-react';
import type { VeiculoDeclarado } from '../types/vehicle';

interface CartaoVeiculoDeclaradoProps {
  veiculo: VeiculoDeclarado | null | undefined;
  onVerDocumentos?: () => void;
  compacto?: boolean;
}

export const CartaoVeiculoDeclarado: React.FC<CartaoVeiculoDeclaradoProps> = ({
  veiculo,
  onVerDocumentos,
  compacto = false,
}) => {
  if (!veiculo) {
    return (
      <span className="text-slate-400 italic text-[11px] flex items-center gap-1">
        <AlertCircle className="w-3.5 h-3.5" />
        Nenhum veículo cadastrado
      </span>
    );
  }

  const ehCarro = veiculo.tipo_veiculo === 'carro';
  const ehMoto = veiculo.tipo_veiculo === 'moto';

  const rotuloCompartimento = () => {
    if (veiculo.compartimento === 'bau') {
      return `📦 Baú (${veiculo.volume_litros ? `${veiculo.volume_litros} L` : 'Litros n/i'})`;
    }
    if (veiculo.compartimento === 'mochila') {
      return `🎒 Mochila (${veiculo.tamanho_compartimento ? `Tam. ${veiculo.tamanho_compartimento}` : 'Padrão'})`;
    }
    if (veiculo.compartimento === 'bag') {
      return `🛍️ Bag (${veiculo.tamanho_compartimento ? `Tam. ${veiculo.tamanho_compartimento}` : 'Padrão'})`;
    }
    return 'Compartimento n/i';
  };

  return (
    <div className={`space-y-1.5 ${compacto ? 'text-xs' : 'p-3 bg-slate-50 border border-slate-200 rounded-xl text-xs'}`}>
      {/* Cabeçalho do Veículo */}
      <div className="flex items-center gap-1.5 flex-wrap">
        <span
          className={`px-1.5 py-0.5 rounded text-[10px] font-extrabold uppercase tracking-wide ${
            ehCarro ? 'bg-blue-100 text-blue-800' : 'bg-amber-100 text-amber-800'
          }`}
        >
          {veiculo.tipo_veiculo}
        </span>
        <span className="font-bold text-[#0F1B2D]">
          {veiculo.marca} {veiculo.modelo}
        </span>
        <span className="font-mono text-[10px] font-semibold text-slate-700 bg-white border border-slate-200 px-1.5 py-0.2 rounded">
          {veiculo.placa}
        </span>
        {veiculo.revisao ? (
          <span className="font-mono text-[9px] font-bold text-slate-500 bg-slate-100 border border-slate-200 px-1 py-0.2 rounded" title={`Revisão cadastral: ${veiculo.revisao}`}>
            v{veiculo.revisao}
          </span>
        ) : null}
      </div>

      {/* Detalhes de Carga por Tipo */}
      {ehMoto && (
        <div className="text-[11px] text-[#516074] space-y-0.5 bg-white p-2 rounded-lg border border-slate-100">
          <div className="flex items-center justify-between flex-wrap gap-1">
            <span className="font-semibold text-slate-700">{rotuloCompartimento()}</span>
            {veiculo.capacidade_kg && (
              <span className="font-bold text-emerald-700 bg-emerald-50 px-1.5 py-0.5 rounded text-[10px]">
                {veiculo.capacidade_kg} kg máx
              </span>
            )}
          </div>
        </div>
      )}

      {ehCarro && (
        <div className="text-[10px] text-slate-400 italic">
          Medidas de carga não aplicáveis a carros nesta versão.
        </div>
      )}

      {/* Status da Análise */}
      <div className="flex items-center justify-between pt-0.5 flex-wrap gap-1">
        <div>
          {veiculo.status_analise === 'pendente' && (
            <span className="inline-flex items-center gap-1 text-[10px] text-amber-700 font-semibold">
              <Clock className="w-3 h-3 text-amber-500" />
              Análise de veículo pendente
            </span>
          )}
          {veiculo.status_analise === 'aprovado' && (
            <span className="inline-flex items-center gap-1 text-[10px] text-emerald-700 font-semibold">
              <CheckCircle2 className="w-3 h-3 text-emerald-600" />
              Veículo aprovado
            </span>
          )}
          {veiculo.status_analise === 'rejeitado' && (
            <div className="text-[10px] text-red-600 font-semibold">
              <span className="inline-flex items-center gap-1">
                <XCircle className="w-3 h-3 text-red-500" />
                Veículo rejeitado
              </span>
              {veiculo.motivo_rejeicao && (
                <span className="block text-[9px] text-red-500 italic font-normal">
                  "{veiculo.motivo_rejeicao}"
                </span>
              )}
            </div>
          )}
        </div>

        {onVerDocumentos && (
          <button
            type="button"
            onClick={onVerDocumentos}
            className="text-[10px] font-semibold text-[#1D4ED8] hover:text-[#1E40AF] inline-flex items-center gap-1 hover:underline cursor-pointer"
          >
            <FileText className="w-3 h-3" />
            Ver Documentos
          </button>
        )}
      </div>
    </div>
  );
};
