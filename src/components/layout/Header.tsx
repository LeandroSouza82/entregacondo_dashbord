import React from 'react';
import { 
  Search, 
  Bell, 
  Plus, 
  Sparkles,
  Truck,
  CheckCircle2,
  Clock
} from 'lucide-react';

interface HeaderProps {
  onOpenNewDelivery?: () => void;
  onOpenOptimizer?: () => void;
  driversActiveCount: number;
  driversInRouteCount: number;
}

export const Header: React.FC<HeaderProps> = ({
  onOpenNewDelivery,
  onOpenOptimizer,
  driversActiveCount = 3,
  driversInRouteCount = 2,
}) => {
  const currentDate = new Date().toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });

  return (
    <header className="h-20 bg-white/90 backdrop-blur-md border-b border-slate-200/80 px-8 flex items-center justify-between sticky top-0 z-20 shadow-subtle">
      {/* Left: Search input */}
      <div className="flex items-center gap-4 flex-1 max-w-lg">
        <div className="relative w-full">
          <Search className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
          <input
            type="text"
            placeholder="Buscar por código de rastreio, condomínio, motorista ou cliente..."
            className="w-full bg-slate-50 border border-slate-200/90 text-sm text-slate-800 placeholder-slate-400 rounded-xl pl-10 pr-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-terracotta-500/30 focus:border-terracotta-600 transition-all shadow-inner"
          />
        </div>
      </div>

      {/* Right: Actions, Driver Status, Notifications */}
      <div className="flex items-center gap-4">
        {/* Fleet mini summary badge */}
        <div className="hidden lg:flex items-center gap-3 px-3.5 py-1.5 rounded-xl bg-slate-100/90 border border-slate-200 text-xs text-slate-600">
          <div className="flex items-center gap-1.5 font-medium">
            <Truck className="w-4 h-4 text-navy-800" />
            <span>Frota:</span>
            <span className="font-bold text-navy-800">{driversActiveCount} ativos</span>
          </div>
          <span className="h-3 w-[1px] bg-slate-300" />
          <div className="flex items-center gap-1 text-emerald-700 font-medium">
            <CheckCircle2 className="w-3.5 h-3.5" />
            <span>{driversInRouteCount} em rota</span>
          </div>
        </div>

        {/* Date display */}
        <div className="hidden md:flex items-center gap-1.5 text-xs text-slate-500 font-medium capitalize">
          <Clock className="w-3.5 h-3.5 text-slate-400" />
          <span>{currentDate}</span>
        </div>

        {/* Action Button: Otimizar Agora */}
        {onOpenOptimizer && (
          <button
            onClick={onOpenOptimizer}
            className="hidden sm:inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold text-terracotta-700 bg-terracotta-50 hover:bg-terracotta-100/80 border border-terracotta-200 transition-colors shadow-sm"
          >
            <Sparkles className="w-3.5 h-3.5 text-terracotta-600" />
            <span>Roteirizar Hoje</span>
          </button>
        )}

        {/* Action Button: Nova Entrega */}
        <button
          onClick={onOpenNewDelivery}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-bold text-white bg-terracotta-600 hover:bg-terracotta-700 active:bg-terracotta-800 shadow-md shadow-terracotta-600/25 transition-all hover:scale-[1.02] active:scale-[0.98]"
        >
          <Plus className="w-4 h-4" />
          <span>Nova Entrega</span>
        </button>

        {/* Notifications */}
        <button 
          className="relative p-2.5 rounded-xl text-slate-500 hover:text-slate-700 hover:bg-slate-100 transition-colors border border-slate-200/70"
          aria-label="Notificações"
        >
          <Bell className="w-4 h-4" />
          <span className="absolute top-2 right-2 w-2 h-2 rounded-full bg-terracotta-600 ring-2 ring-white" />
        </button>
      </div>
    </header>
  );
};
