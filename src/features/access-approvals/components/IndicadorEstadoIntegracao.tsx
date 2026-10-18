import React from 'react';
import { Database, ShieldCheck, AlertCircle, Sparkles } from 'lucide-react';
import { isSupabaseConfigured } from '../../../lib/supabase';

interface IndicadorEstadoIntegracaoProps {
  modoDemo: boolean;
  onAlternarModoDemo: (demo: boolean) => void;
}

export const IndicadorEstadoIntegracao: React.FC<IndicadorEstadoIntegracaoProps> = ({
  modoDemo,
  onAlternarModoDemo,
}) => {
  return (
    <div className="flex items-center justify-between flex-wrap gap-3 p-3 bg-white border border-[#E1E6ED] rounded-2xl shadow-xs">
      <div className="flex items-center gap-3">
        {isSupabaseConfigured ? (
          <div className="flex items-center gap-2 text-xs font-semibold text-emerald-800 bg-emerald-50 px-3 py-1.5 rounded-xl border border-emerald-200">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            <Database className="w-3.5 h-3.5 text-emerald-600" />
            <span>Supabase Conectado (vblwuvhdqgzdjnoscyqo)</span>
          </div>
        ) : (
          <div className="flex items-center gap-2 text-xs font-semibold text-amber-800 bg-amber-50 px-3 py-1.5 rounded-xl border border-amber-200">
            <AlertCircle className="w-3.5 h-3.5 text-amber-600" />
            <span>Supabase não configurado localmente</span>
          </div>
        )}

        <div className="flex items-center gap-1.5 text-xs text-slate-500">
          <ShieldCheck className="w-3.5 h-3.5 text-slate-400" />
          <span>RLS Soberano Ativo</span>
        </div>
      </div>

      {/* Seletor Explícito: Modo Real vs Modo Demonstração */}
      <div className="flex items-center gap-2">
        <span className="text-[11px] font-semibold text-[#516074]">Visualização:</span>
        <div className="flex items-center p-0.5 bg-slate-100 rounded-xl border border-slate-200">
          <button
            type="button"
            onClick={() => onAlternarModoDemo(false)}
            className={`px-3 py-1 rounded-lg text-xs font-bold transition-all cursor-pointer ${
              !modoDemo
                ? 'bg-white text-[#0F1B2D] shadow-xs'
                : 'text-slate-500 hover:text-slate-700'
            }`}
          >
            Modo Real (Servidor)
          </button>
          <button
            type="button"
            onClick={() => onAlternarModoDemo(true)}
            className={`px-3 py-1 rounded-lg text-xs font-bold transition-all flex items-center gap-1 cursor-pointer ${
              modoDemo
                ? 'bg-[#C2410C] text-white shadow-xs'
                : 'text-slate-500 hover:text-slate-700'
            }`}
          >
            <Sparkles className="w-3 h-3" />
            Demonstração (Fictício)
          </button>
        </div>
      </div>
    </div>
  );
};
