import React, { useState, useMemo } from 'react';

export type DeliveryStatus = 'todas' | 'em_rota' | 'entregue' | 'ocorrencia' | 'pendente';

export interface TodayDeliveryRow {
  id: string;
  cliente: string;
  condominio: string;
  endereco: string;
  motorista: string;
  observacao: string;
  status: 'entregue' | 'em_rota' | 'ocorrencia' | 'pendente';
  recebidoPor: string;
}

const DELIVERIES_DATA: TodayDeliveryRow[] = [
  {
    id: 'd1',
    cliente: 'Ricardo Almeida',
    condominio: 'Res. Vista Mar',
    endereco: 'Av. Beira-Mar Norte, 3400 · Centro',
    motorista: 'Rafael Souza',
    observacao: 'Entregar ao zelador',
    status: 'entregue',
    recebidoPor: 'Zelador · Valdir',
  },
  {
    id: 'd2',
    cliente: 'Maria Fernanda Rocha',
    condominio: 'Ed. Solar das Palmeiras',
    endereco: 'Rua Lauro Linhares, 820 · Trindade',
    motorista: 'Carlos Mendes',
    observacao: 'Cuidado com o cachorro',
    status: 'em_rota',
    recebidoPor: '—',
  },
  {
    id: 'd3',
    cliente: 'Paulo Henrique Dias',
    condominio: 'Cond. Jardim Imperial',
    endereco: 'Av. Madre Benvenuta, 1100 · Itacorubi',
    motorista: 'João Pedro Lima',
    observacao: 'Interfonar no apto 302',
    status: 'em_rota',
    recebidoPor: '—',
  },
  {
    id: 'd4',
    cliente: 'Camila Souza',
    condominio: 'Ed. Bela Vista',
    endereco: 'Rua Bocaiúva, 450 · Centro',
    motorista: 'Rafael Souza',
    observacao: 'Portaria atende só até 17h',
    status: 'entregue',
    recebidoPor: 'Vizinho · Apto 204',
  },
  {
    id: 'd5',
    cliente: 'Fernando Lopes',
    condominio: 'Res. Alameda Park',
    endereco: 'Rua João Pio Duarte Silva, 900 · Córrego Grande',
    motorista: 'Anderson Costa',
    observacao: 'Sem observação',
    status: 'ocorrencia',
    recebidoPor: 'Ninguém no local',
  },
  {
    id: 'd6',
    cliente: 'Luciana Prado',
    condominio: 'Ed. Marina Tower',
    endereco: 'Rua Felipe Schmidt, 1250 · Centro',
    motorista: 'Anderson Costa',
    observacao: 'Deixar com o porteiro',
    status: 'pendente',
    recebidoPor: '—',
  },
];

export const TodayDeliveriesTable: React.FC = () => {
  const [filtroAtivo, setFiltroAtivo] = useState<DeliveryStatus>('todas');

  const entregasFiltradas = useMemo(() => {
    if (filtroAtivo === 'todas') return DELIVERIES_DATA;
    return DELIVERIES_DATA.filter((d) => d.status === filtroAtivo);
  }, [filtroAtivo]);

  const contadores = useMemo(() => {
    return {
      todas: 48,
      em_rota: 15,
      concluidas: 31,
      ocorrencias: 2,
    };
  }, []);

  return (
    <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-4">
      {/* Header com Tabs de Filtro */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">
          Entregas de hoje
        </h2>

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setFiltroAtivo('todas')}
            className={`h-[34px] px-3.5 rounded-full text-[13px] font-semibold transition-all cursor-pointer ${
              filtroAtivo === 'todas'
                ? 'bg-[#0F1B2D] text-white border border-[#0F1B2D] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            Todas {contadores.todas}
          </button>

          <button
            type="button"
            onClick={() => setFiltroAtivo('em_rota')}
            className={`h-[34px] px-3.5 rounded-full text-[13px] font-semibold transition-all cursor-pointer ${
              filtroAtivo === 'em_rota'
                ? 'bg-[#0F1B2D] text-white border border-[#0F1B2D] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            Em rota {contadores.em_rota}
          </button>

          <button
            type="button"
            onClick={() => setFiltroAtivo('entregue')}
            className={`h-[34px] px-3.5 rounded-full text-[13px] font-semibold transition-all cursor-pointer ${
              filtroAtivo === 'entregue'
                ? 'bg-[#0F1B2D] text-white border border-[#0F1B2D] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            Concluídas {contadores.concluidas}
          </button>

          <button
            type="button"
            onClick={() => setFiltroAtivo('ocorrencia')}
            className={`h-[34px] px-3.5 rounded-full text-[13px] font-semibold transition-all cursor-pointer ${
              filtroAtivo === 'ocorrencia'
                ? 'bg-[#0F1B2D] text-white border border-[#0F1B2D] shadow-sm'
                : 'bg-white text-[#0F1B2D] border border-[#D5DCE5] hover:bg-slate-50'
            }`}
          >
            Ocorrências {contadores.ocorrencias}
          </button>
        </div>
      </div>

      {/* Tabela de Entregas */}
      <div className="overflow-x-auto">
        <div className="min-w-[920px]">
          {/* Header da Tabela */}
          <div className="grid grid-cols-[1.5fr_1.6fr_1fr_1.3fr_112px_1.1fr] gap-4 px-3 py-2.5 bg-[#F3F5F8] rounded-[10px] text-xs font-bold text-[#516074] uppercase tracking-wider">
            <div>Cliente</div>
            <div>Endereço</div>
            <div>Motorista</div>
            <div>Observação</div>
            <div>Status</div>
            <div>Recebido por</div>
          </div>

          {/* Linhas de Dados */}
          <div className="divide-y divide-[#EAEFF4]">
            {entregasFiltradas.map((delivery) => {
              const statusConfig = {
                entregue: { label: 'Entregue', bg: 'bg-[#DDF3E4]', text: 'text-[#14532D]' },
                em_rota: { label: 'Em rota', bg: 'bg-[#DCE8FD]', text: 'text-[#1E3A8A]' },
                ocorrencia: { label: 'Ocorrência', bg: 'bg-[#FBDADA]', text: 'text-[#7F1D1D]' },
                pendente: { label: 'Pendente', bg: 'bg-[#FDEFC8]', text: 'text-[#7A4A06]' },
              }[delivery.status];

              return (
                <div
                  key={delivery.id}
                  className="grid grid-cols-[1.5fr_1.6fr_1fr_1.3fr_112px_1.1fr] gap-4 px-3 py-3.5 items-center hover:bg-slate-50/70 transition-colors"
                >
                  <div>
                    <div className="font-bold text-sm text-[#0F1B2D]">
                      {delivery.cliente}
                    </div>
                    <div className="text-xs text-[#516074]">
                      {delivery.condominio}
                    </div>
                  </div>

                  <div className="text-[13px] text-[#2B3A4F] truncate">
                    {delivery.endereco}
                  </div>

                  <div className="text-[13px] text-[#2B3A4F]">
                    {delivery.motorista}
                  </div>

                  <div className="text-[13px] text-[#2B3A4F] truncate">
                    {delivery.observacao}
                  </div>

                  <div>
                    <span
                      className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-bold ${statusConfig.bg} ${statusConfig.text}`}
                    >
                      {statusConfig.label}
                    </span>
                  </div>

                  <div className="text-[13px] text-[#2B3A4F] font-medium">
                    {delivery.recebidoPor}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
};
