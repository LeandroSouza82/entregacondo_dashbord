import React from 'react';
import { MAP_STYLES } from './mapStyles';

interface MapStyleSelectorProps {
  value: string;
  onChange: (styleUrl: string) => void;
  className?: string;
}

/** Seletor segmentado de estilo do mapa (Ruas, Satélite, Noturno). Componente controlado. */
export const MapStyleSelector: React.FC<MapStyleSelectorProps> = ({ value, onChange, className = '' }) => (
  <div
    role="group"
    aria-label="Estilo do mapa"
    className={`inline-flex items-center p-1 bg-slate-100 border border-slate-200 rounded-xl gap-1 ${className}`}
  >
    {MAP_STYLES.map((st) => {
      const Icon = st.icon;
      const isActive = value === st.styleUrl;
      return (
        <button
          key={st.id}
          data-testid={`map-style-${st.id}`}
          type="button"
          aria-pressed={isActive}
          onClick={() => onChange(st.styleUrl)}
          className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-bold transition-all cursor-pointer ${
            isActive
              ? 'bg-navy-900 text-white shadow-xs'
              : 'text-slate-600 hover:text-navy-900 hover:bg-white'
          }`}
          title={`Alternar visualização para ${st.label}`}
        >
          <Icon className={`w-3.5 h-3.5 ${isActive ? 'text-amber-400' : 'text-slate-400'}`} />
          <span>{st.label}</span>
        </button>
      );
    })}
  </div>
);
