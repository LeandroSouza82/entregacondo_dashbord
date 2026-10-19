import React from 'react';
import { Marker } from 'react-map-gl/mapbox';
import { ObterIconeVeiculo } from '../../assets/icons/vehicles/VehicleIcons';
import type { MotoristaVeiculoMapa } from '../../features/routes/utils/vehicleMovement';
import { Navigation } from 'lucide-react';

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

  return (
    <Marker
      longitude={coordenadas.lng}
      latitude={coordenadas.lat}
      anchor="center"
      style={{
        transition: 'all 1.2s cubic-bezier(0.25, 1, 0.5, 1)',
        willChange: 'transform',
      }}
      onClick={(e: { originalEvent: MouseEvent }) => {
        e.originalEvent.stopPropagation();
        onClick?.(veiculo);
      }}
    >
      <div className="relative group cursor-pointer select-none">
        {/* Efeito de radar pulsante para motoristas em rota */}
        {isEmRota && (
          <span className="absolute -inset-2 rounded-full bg-[#D94E1F]/25 animate-ping pointer-events-none" />
        )}

        {/* Tag com nome e placa do motorista */}
        <div className="absolute -top-7 left-1/2 -translate-x-1/2 px-2 py-0.5 rounded-md bg-[#0F172A] text-white text-[10px] font-bold whitespace-nowrap shadow-md border border-slate-700/80 pointer-events-none opacity-90 group-hover:opacity-100 transition-opacity flex items-center gap-1.5 z-20">
          <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
          <span>{nome.split(' ')[0]}</span>
          {veiculo_placa && (
            <span className="text-[9px] text-slate-300 font-mono font-normal opacity-85">
              · {veiculo_placa}
            </span>
          )}
        </div>

        {/* Container Principal do Veículo */}
        <div
          className={`relative w-11 h-11 rounded-2xl flex items-center justify-center shadow-xl border-2 transition-all duration-300 ${
            selecionado
              ? 'bg-[#0F172A] border-amber-400 scale-110 shadow-amber-500/20 ring-4 ring-amber-400/30'
              : 'bg-[#0F172A] hover:bg-[#1E293B] border-white group-hover:scale-105'
          }`}
        >
          {/* Seta indicadora de direção da via (Heading/Bearing) */}
          <div
            className="absolute -top-1.5 w-full flex justify-center pointer-events-none transition-transform duration-700"
            style={{ transform: `rotate(${bearing}deg)` }}
          >
            <div className="w-3.5 h-3.5 rounded-full bg-[#D94E1F] flex items-center justify-center shadow-xs border border-white">
              <Navigation className="w-2.5 h-2.5 text-white fill-white -rotate-45" />
            </div>
          </div>

          {/* SVG Oficial do Veículo (Moto, Carro ou Caminhão) */}
          <div className="p-1">
            <ObterIconeVeiculo
              tipo={veiculo_tipo}
              size={26}
              primaryColor="#FFFFFF"
              accentColor="#D94E1F"
            />
          </div>

          {/* Badge Inferior Indicadora do Tipo */}
          <div className="absolute -bottom-1 -right-1 px-1 py-0.2 rounded-full bg-[#D94E1F] text-[8px] font-black text-white uppercase tracking-tighter shadow-xs border border-white">
            {veiculo_tipo === 'caminhao' ? 'CAM' : veiculo_tipo === 'carro' ? 'CAR' : 'MOT'}
          </div>
        </div>
      </div>
    </Marker>
  );
};
