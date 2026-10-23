import React from 'react';
import { Marker } from 'react-map-gl/mapbox';
import { ObterIconeVeiculo } from '../../assets/icons/vehicles/VehicleIcons';
import type { MotoristaVeiculoMapa } from '../../features/routes/utils/vehicleMovement';

interface VehicleMapMarkerProps {
  veiculo: MotoristaVeiculoMapa;
  onClick?: (veiculo: MotoristaVeiculoMapa) => void;
  selecionado?: boolean;
}

export const VehicleMapMarker: React.FC<VehicleMapMarkerProps> = ({
  veiculo,
  onClick,
  selecionado = false,
}) => {
  const { coordenadas, nome, veiculo_tipo, veiculo_placa, status } = veiculo;
  const bearing = coordenadas.bearing ?? 0;
  const isEmRota = status === 'em_rota';
  const primeiroNome = (nome || 'Motorista').split(' ')[0];
  const rotuloTipo =
    veiculo_tipo === 'caminhao' ? 'VUC' : veiculo_tipo === 'carro' ? 'CAR' : 'MOTO';

  return (
    <Marker
      longitude={coordenadas.lng}
      latitude={coordenadas.lat}
      anchor="center"
      style={{
        transition: 'all 1.2s cubic-bezier(0.25, 1, 0.5, 1)',
        willChange: 'transform',
        zIndex: selecionado ? 40 : 30,
      }}
      onClick={(e: { originalEvent: MouseEvent }) => {
        e.originalEvent.stopPropagation();
        onClick?.(veiculo);
      }}
    >
      <div className="relative group cursor-pointer select-none flex flex-col items-center">
        {/* Tag flutuante com nome, status em tempo real e placa */}
        <div
          className={`absolute -top-8 left-1/2 -translate-x-1/2 px-2.5 py-0.5 rounded-full bg-[#0B1320]/95 backdrop-blur-md text-white text-[10px] font-bold whitespace-nowrap shadow-lg border transition-all flex items-center gap-1.5 z-30 pointer-events-none ${
            selecionado
              ? 'border-[#EA580C] ring-2 ring-[#EA580C]/25 scale-105'
              : 'border-white/20 opacity-95 group-hover:opacity-100 group-hover:scale-105'
          }`}
        >
          <span
            className={`w-1.5 h-1.5 rounded-full ${
              isEmRota ? 'bg-emerald-400 animate-pulse' : 'bg-amber-400'
            }`}
          />
          <span className="tracking-tight">{primeiroNome}</span>
          {veiculo_placa && (
            <span className="text-[9px] text-slate-300 font-mono font-semibold bg-white/10 px-1 rounded">
              {veiculo_placa}
            </span>
          )}
        </div>

        {/* Núcleo do Marcador do Veículo */}
        <div className="relative w-12 h-12 flex items-center justify-center">
          {/* Anel de radar pulsante para motoristas em rota */}
          {isEmRota && (
            <span className="absolute inset-0.5 rounded-2xl bg-[#EA580C]/25 animate-ping pointer-events-none" />
          )}

          {/* Anel orbital de direção da via (Heading/Bearing rotacionando em torno do centro) */}
          <div
            className="absolute -inset-1.5 pointer-events-none transition-transform duration-700 ease-out z-20"
            style={{ transform: `rotate(${bearing}deg)` }}
          >
            <div className="absolute -top-1 left-1/2 -translate-x-1/2 flex flex-col items-center">
              <svg
                width="14"
                height="12"
                viewBox="0 0 14 12"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
                className="drop-shadow-sm"
              >
                <path
                  d="M7 1L13 10.5L7 8.2L1 10.5L7 1Z"
                  fill="#EA580C"
                  stroke="#FFFFFF"
                  strokeWidth="1.4"
                  strokeLinejoin="round"
                />
              </svg>
            </div>
          </div>

          {/* Squircle Principal no Padrão EntregaCondo (Navy + Terracotta) */}
          <div
            className={`relative w-11 h-11 rounded-2xl flex items-center justify-center shadow-xl border-2 transition-all duration-300 ${
              selecionado
                ? 'bg-gradient-to-br from-[#0F1B2D] to-[#1E293B] border-[#EA580C] scale-110 ring-4 ring-[#EA580C]/25'
                : 'bg-gradient-to-br from-[#0F1B2D] to-[#132137] hover:from-[#132137] hover:to-[#1E293B] border-white group-hover:scale-105'
            }`}
          >
            {/* Brilho interno sutil no topo */}
            <div className="absolute inset-x-1.5 top-1 h-2.5 rounded-t-xl bg-gradient-to-b from-white/12 to-transparent pointer-events-none" />

            {/* Ícone SVG do Veículo */}
            <ObterIconeVeiculo
              tipo={veiculo_tipo}
              size={27}
              primaryColor="#F8FAFC"
              accentColor="#EA580C"
              className="drop-shadow-xs"
            />

            {/* Badge Inferior Indicadora da Categoria */}
            <div className="absolute -bottom-1.5 -right-1.5 px-1.5 py-0.2 rounded-full bg-gradient-to-r from-[#EA580C] to-[#C2410C] text-[8px] font-black text-white uppercase tracking-wider shadow-md border border-white">
              {rotuloTipo}
            </div>
          </div>
        </div>
      </div>
    </Marker>
  );
};
