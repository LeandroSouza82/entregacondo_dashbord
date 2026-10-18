import React, { useState } from 'react';
import { KPICard } from './KPICard';
import { LiveFleetMap } from './LiveFleetMap';
import { DriversPanel } from './DriversPanel';
import { TodayDeliveriesTable } from './TodayDeliveriesTable';
import { Search, Plus } from 'lucide-react';

interface OverviewViewProps {
  onGoToOptimizer?: () => void;
  onOpenNewDelivery?: () => void;
}

export const OverviewView: React.FC<OverviewViewProps> = ({ 
  onGoToOptimizer,
  onOpenNewDelivery 
}) => {
  const [buscaTexto, setBuscaTexto] = useState('');

  // Data atual formatada idêntica ao design (ex: "Sábado, 17 de outubro · atualizado agora")
  const dataAtualFormatada = `${new Date().toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  })} · atualizado agora`;

  const handleNovaEntrega = () => {
    if (onGoToOptimizer) {
      onGoToOptimizer();
    } else if (onOpenNewDelivery) {
      onOpenNewDelivery();
    }
  };

  return (
    <div className="space-y-6 text-[#0F1B2D] animate-fadeIn">
      {/* Header Principal da Visão Geral */}
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-[26px] font-extrabold text-[#0F1B2D] tracking-tight m-0">
            Visão geral
          </h1>
          <p className="text-[#516074] text-sm mt-1 capitalize">
            {dataAtualFormatada}
          </p>
        </div>

        <div className="flex flex-wrap gap-3 items-center">
          {/* Barra de Busca rápida */}
          <div className="flex items-center gap-2 bg-white border border-[#D5DCE5] rounded-[10px] px-3 h-11 min-w-[260px] shadow-sm">
            <Search className="w-4 h-4 text-[#516074] flex-shrink-0" />
            <input
              type="text"
              value={buscaTexto}
              onChange={(e) => setBuscaTexto(e.target.value)}
              placeholder="Buscar cliente, endereço ou pedido"
              className="border-0 outline-none flex-1 min-w-0 text-sm bg-transparent text-[#0F1B2D] placeholder-[#516074] font-medium"
            />
          </div>

          {/* Botão Nova Entrega Terracota #C2410C */}
          <button
            type="button"
            onClick={handleNovaEntrega}
            className="inline-flex items-center gap-2 h-11 px-[18px] rounded-[10px] bg-[#C2410C] hover:bg-[#9A3412] active:scale-95 text-white font-bold text-sm shadow-md shadow-[#C2410C]/25 transition-all cursor-pointer"
          >
            <Plus className="w-[18px] h-[18px]" />
            <span>Nova entrega</span>
          </button>
        </div>
      </header>

      {/* Seção dos 5 Cartões de Indicadores (KPIs do Dia) */}
      <section 
        aria-label="Indicadores do dia" 
        className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4"
      >
        {/* KPI 1: Entregas hoje */}
        <KPICard
          label="Entregas hoje"
          value={48}
          subtext="+6 em relação a ontem"
          subtextColor="text-[#14532D] font-semibold"
        />

        {/* KPI 2: Concluídas com barra verde */}
        <KPICard
          label="Concluídas"
          value={31}
          progressPercent={65}
          progressBarColor="bg-[#15803D]"
          subtext="65% do total do dia"
          subtextColor="text-[#516074]"
        />

        {/* KPI 3: Em rota agora */}
        <KPICard
          label="Em rota agora"
          value={15}
          subtext="3 motoristas em rota"
          subtextColor="text-[#516074]"
        />

        {/* KPI 4: Km economizados */}
        <KPICard
          label="Km economizados"
          value="38 km"
          subtext="pela rota inteligente"
          subtextColor="text-[#516074]"
        />

        {/* KPI 5: Ocorrências (Alerta Vermelho) */}
        <KPICard
          label="Ocorrências"
          value={2}
          valueColor="text-[#991B1B]"
          subtext="exigem sua atenção"
          subtextColor="text-[#991B1B] font-semibold"
        />
      </section>

      {/* Grid Principal: Mapa da Frota ao Vivo (flex: 2) + Painel de Motoristas (flex: 1) */}
      <div className="flex flex-col lg:flex-row gap-6 items-stretch">
        <div className="flex-1 w-full lg:max-w-[66%]">
          <LiveFleetMap />
        </div>

        <div className="w-full lg:w-[34%]">
          <DriversPanel onAssignRoute={handleNovaEntrega} />
        </div>
      </div>

      {/* Tabela de Entregas de Hoje com Abas de Filtro */}
      <TodayDeliveriesTable />
    </div>
  );
};
