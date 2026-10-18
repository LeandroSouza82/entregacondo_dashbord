import React from 'react';
import { Search } from 'lucide-react';
import type { FiltroStatusAcesso } from '../types/accessApproval';

interface FiltrosSolicitacoesProps {
  filtroStatus: FiltroStatusAcesso;
  onSelecionarFiltro: (filtro: FiltroStatusAcesso) => void;
  buscaTexto: string;
  onMudarBusca: (texto: string) => void;
  totalPendentes: number;
  totalAprovados: number;
  totalSuspensos: number;
  totalGeral: number;
}

export const FiltrosSolicitacoes: React.FC<FiltrosSolicitacoesProps> = ({
  filtroStatus,
  onSelecionarFiltro,
  buscaTexto,
  onMudarBusca,
  totalPendentes,
  totalAprovados,
  totalSuspensos,
  totalGeral,
}) => {
  return (
    <div className="bg-white border border-[#E1E6ED] rounded-2xl p-4 shadow-card flex flex-wrap items-center justify-between gap-4">
      {/* Abas de Status */}
      <div className="flex flex-wrap items-center gap-1.5 p-1 bg-slate-100/80 rounded-xl">
        <button
          type="button"
          onClick={() => onSelecionarFiltro('pendente')}
          className={`px-3.5 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
            filtroStatus === 'pendente'
              ? 'bg-white text-[#C2410C] shadow-sm'
              : 'text-[#516074] hover:text-[#0F1B2D]'
          }`}
        >
          Pendentes ({totalPendentes})
        </button>

        <button
          type="button"
          onClick={() => onSelecionarFiltro('aprovado')}
          className={`px-3.5 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
            filtroStatus === 'aprovado'
              ? 'bg-white text-emerald-800 shadow-sm'
              : 'text-[#516074] hover:text-[#0F1B2D]'
          }`}
        >
          Aprovados ({totalAprovados})
        </button>

        <button
          type="button"
          onClick={() => onSelecionarFiltro('suspenso')}
          className={`px-3.5 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
            filtroStatus === 'suspenso'
              ? 'bg-white text-slate-800 shadow-sm'
              : 'text-[#516074] hover:text-[#0F1B2D]'
          }`}
        >
          Suspensos / Rejeitados ({totalSuspensos})
        </button>

        <button
          type="button"
          onClick={() => onSelecionarFiltro('todos')}
          className={`px-3.5 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
            filtroStatus === 'todos'
              ? 'bg-white text-[#0F1B2D] shadow-sm'
              : 'text-[#516074] hover:text-[#0F1B2D]'
          }`}
        >
          Todos ({totalGeral})
        </button>
      </div>

      {/* Input de Busca */}
      <div className="relative min-w-[280px]">
        <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none" />
        <input
          type="text"
          value={buscaTexto}
          onChange={(e) => onMudarBusca(e.target.value)}
          placeholder="Buscar por nome, e-mail ou placa..."
          className="h-10 pl-9 pr-3 text-xs border border-[#CBD5E1] rounded-xl bg-slate-50/50 w-full text-[#0F1B2D] focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 focus:border-[#1D4ED8]"
        />
      </div>
    </div>
  );
};
