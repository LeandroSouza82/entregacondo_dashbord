import React from 'react';

interface DriverProgressItem {
  id: string;
  iniciais: string;
  nome: string;
  veiculo: string;
  totalEntregas: number;
  concluidas: number;
  status: 'em_rota' | 'em_pausa' | 'disponivel';
  corAvatar: string;
  corBarra: string;
  proximaEntrega: string;
}

const DRIVERS_DATA: DriverProgressItem[] = [
  {
    id: 'cm',
    iniciais: 'CM',
    nome: 'Carlos Mendes',
    veiculo: 'Fiorino',
    totalEntregas: 12,
    concluidas: 8,
    status: 'em_rota',
    corAvatar: '#1D4ED8',
    corBarra: 'bg-[#1D4ED8]',
    proximaEntrega: 'Rua Lauro Linhares, 820',
  },
  {
    id: 'rs',
    iniciais: 'RS',
    nome: 'Rafael Souza',
    veiculo: 'Moto',
    totalEntregas: 14,
    concluidas: 11,
    status: 'em_rota',
    corAvatar: '#0F766E',
    corBarra: 'bg-[#0F766E]',
    proximaEntrega: 'Rua Bocaiúva, 450',
  },
  {
    id: 'jp',
    iniciais: 'JP',
    nome: 'João Pedro Lima',
    veiculo: 'Saveiro',
    totalEntregas: 12,
    concluidas: 7,
    status: 'em_rota',
    corAvatar: '#C2410C',
    corBarra: 'bg-[#C2410C]',
    proximaEntrega: 'Av. Madre Benvenuta, 1100',
  },
  {
    id: 'ac',
    iniciais: 'AC',
    nome: 'Anderson Costa',
    veiculo: 'Moto',
    totalEntregas: 10,
    concluidas: 5,
    status: 'em_pausa',
    corAvatar: '#475569',
    corBarra: 'bg-[#475569]',
    proximaEntrega: 'Rua Felipe Schmidt, 1250',
  },
];

interface DriversPanelProps {
  onAssignRoute?: () => void;
}

export const DriversPanel: React.FC<DriversPanelProps> = ({ onAssignRoute }) => {
  return (
    <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-1">
      {/* Header */}
      <div className="flex items-center justify-between gap-2 mb-2">
        <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">Motoristas</h2>
        {onAssignRoute && (
          <button
            type="button"
            onClick={onAssignRoute}
            className="text-[13px] font-bold text-[#1D4ED8] hover:underline cursor-pointer"
          >
            Atribuir rota
          </button>
        )}
      </div>

      {/* Driver List */}
      <div className="divide-y divide-[#EAEFF4]">
        {DRIVERS_DATA.map((driver) => {
          const percent = Math.round((driver.concluidas / driver.totalEntregas) * 100);
          const isEmRota = driver.status === 'em_rota';

          return (
            <div key={driver.id} className="flex flex-col gap-2.5 py-3.5">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2.5">
                  <div
                    style={{ backgroundColor: driver.corAvatar }}
                    className="w-[38px] h-[38px] rounded-full text-white flex items-center justify-center font-bold text-[13px] flex-shrink-0"
                  >
                    {driver.iniciais}
                  </div>
                  <div>
                    <div className="font-bold text-sm text-[#0F1B2D]">{driver.nome}</div>
                    <div className="text-xs text-[#516074]">
                      {driver.veiculo} · {driver.totalEntregas} entregas
                    </div>
                  </div>
                </div>

                <span
                  className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-bold ${
                    isEmRota
                      ? 'bg-[#DCE8FD] text-[#1E3A8A]'
                      : 'bg-[#E7EBF0] text-[#334155]'
                  }`}
                >
                  {isEmRota ? 'Em rota' : 'Em pausa'}
                </span>
              </div>

              {/* Progress bar */}
              <div className="flex items-center gap-2.5">
                <div className="flex-1 h-2 rounded-[4px] bg-[#E4E9F0] overflow-hidden">
                  <div
                    style={{ width: `${percent}%` }}
                    className={`h-full ${driver.corBarra} rounded-[4px] transition-all duration-500`}
                  />
                </div>
                <div className="text-xs font-bold text-[#0F1B2D] min-w-[56px] text-right">
                  {driver.concluidas} de {driver.totalEntregas}
                </div>
              </div>

              <div className="text-xs text-[#516074]">
                Próxima: {driver.proximaEntrega}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
};
