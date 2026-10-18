import React from 'react';
import { 
  LayoutDashboard, 
  Route, 
  PackageCheck, 
  Truck, 
  Building2, 
  History, 
  Settings, 
  ChevronRight, 
  ShieldCheck, 
  Sparkles,
  Database as DatabaseIcon,
  UserCheck
} from 'lucide-react';
import { isSupabaseConfigured } from '../../lib/supabase';

export type ActiveTab = 'overview' | 'new_route' | 'routing' | 'deliveries' | 'drivers' | 'approvals' | 'condos' | 'history' | 'settings';

interface SidebarProps {
  activeTab: ActiveTab;
  onTabChange: (tab: ActiveTab) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, onTabChange }) => {
  const menuItems = [
    {
      id: 'overview' as ActiveTab,
      label: 'Visão geral',
      icon: LayoutDashboard,
      badge: null,
    },
    {
      id: 'new_route' as ActiveTab,
      label: 'Nova rota de entregas',
      icon: Route,
      badge: 'Design Exato',
      highlight: true,
    },
    {
      id: 'routing' as ActiveTab,
      label: 'Comparador de Rotas',
      icon: Route,
      badge: 'IA Logística',
      highlight: false,
    },
    {
      id: 'deliveries' as ActiveTab,
      label: 'Gestão de entregas',
      icon: PackageCheck,
      badge: '20 na fila',
    },
    {
      id: 'approvals' as ActiveTab,
      label: 'Aprovações de Acesso',
      icon: UserCheck,
      badge: 'App Flutter',
      highlight: true,
    },
    {
      id: 'drivers' as ActiveTab,
      label: 'Motoristas',
      icon: Truck,
      badge: '3 ativos',
    },
    {
      id: 'condos' as ActiveTab,
      label: 'Endereços salvos',
      icon: Building2,
      badge: '128 salvos',
    },
    {
      id: 'history' as ActiveTab,
      label: 'Relatórios & Histórico',
      icon: History,
      badge: null,
    },
  ];

  return (
    <aside className="w-64 bg-navy-800 text-slate-200 flex flex-col flex-shrink-0 border-r border-navy-700/70 select-none h-screen sticky top-0 z-30 transition-all">
      {/* Brand Header */}
      <div className="h-20 flex items-center px-6 border-b border-navy-700/60 bg-navy-850/60 backdrop-blur">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-terracotta-500 to-terracotta-700 flex items-center justify-center shadow-lg shadow-terracotta-600/30 text-white font-bold ring-2 ring-terracotta-500/20">
            <Truck className="w-5 h-5 text-white" />
          </div>
          <div className="flex flex-col">
            <div className="flex items-center gap-1.5">
              <span className="font-extrabold text-lg text-white tracking-tight">Entrega</span>
              <span className="font-extrabold text-lg text-terracotta-500 tracking-tight">Condo</span>
            </div>
            <span className="text-[10px] uppercase font-semibold tracking-wider text-slate-400">
              Gestão Logística Pro
            </span>
          </div>
        </div>
      </div>

      {/* Main Navigation */}
      <div className="flex-1 py-6 px-3 space-y-1.5 overflow-y-auto">
        <div className="px-3 pb-2 text-[11px] font-bold uppercase tracking-wider text-slate-400">
          Navegação Principal
        </div>

        {menuItems.map((item) => {
          const Icon = item.icon;
          const isActive = activeTab === item.id;

          return (
            <button
              key={item.id}
              onClick={() => onTabChange(item.id)}
              className={`w-full flex items-center justify-between px-3.5 py-3 rounded-xl text-sm font-medium transition-all group duration-150 ${
                isActive
                  ? 'bg-gradient-to-r from-terracotta-600 to-terracotta-500 text-white shadow-md shadow-terracotta-600/25 font-semibold'
                  : 'text-slate-300 hover:text-white hover:bg-navy-700/60'
              }`}
            >
              <div className="flex items-center gap-3">
                <Icon
                  className={`w-5 h-5 transition-colors ${
                    isActive ? 'text-white' : 'text-slate-400 group-hover:text-slate-200'
                  }`}
                />
                <span>{item.label}</span>
              </div>

              <div className="flex items-center gap-1.5">
                {item.badge && (
                  <span
                    className={`text-[10px] px-2 py-0.5 rounded-full font-semibold ${
                      isActive
                        ? 'bg-white/20 text-white'
                        : item.highlight
                        ? 'bg-terracotta-500/20 text-terracotta-300 border border-terracotta-500/30'
                        : 'bg-navy-700 text-slate-300'
                    }`}
                  >
                    {item.highlight && <Sparkles className="w-2.5 h-2.5 inline mr-1" />}
                    {item.badge}
                  </span>
                )}
                {isActive && <ChevronRight className="w-4 h-4 text-white/80" />}
              </div>
            </button>
          );
        })}

        <div className="pt-6 px-3 pb-2 text-[11px] font-bold uppercase tracking-wider text-slate-400">
          Sistema & Conexões
        </div>

        <button
          onClick={() => onTabChange('settings')}
          className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all ${
            activeTab === 'settings'
              ? 'bg-navy-700 text-white'
              : 'text-slate-300 hover:text-white hover:bg-navy-700/50'
          }`}
        >
          <div className="flex items-center gap-3">
            <Settings className="w-5 h-5 text-slate-400" />
            <span>Configurações</span>
          </div>
        </button>
      </div>

      {/* Database Connection Status Card */}
      <div className="p-3 mx-3 mb-4 rounded-xl bg-navy-850 border border-navy-700/70 text-xs">
        <div className="flex items-center justify-between mb-1.5">
          <div className="flex items-center gap-2 font-semibold text-slate-200">
            <DatabaseIcon className="w-3.5 h-3.5 text-terracotta-400" />
            <span>Banco Supabase</span>
          </div>
          <span className="flex h-2 w-2 relative">
            <span
              className={`animate-ping absolute inline-flex h-full w-full rounded-full opacity-75 ${
                isSupabaseConfigured ? 'bg-emerald-400' : 'bg-amber-400'
              }`}
            />
            <span
              className={`relative inline-flex rounded-full h-2 w-2 ${
                isSupabaseConfigured ? 'bg-emerald-500' : 'bg-amber-500'
              }`}
            />
          </span>
        </div>
        <p className="text-[11px] text-slate-400 leading-tight">
          {isSupabaseConfigured
            ? 'Conectado à nuvem Supabase em tempo real'
            : 'Ambiente Mock Ativo (Pronto para sincronizar Supabase)'}
        </p>
      </div>

      {/* User Footer */}
      <div className="p-4 border-t border-navy-700/60 bg-navy-850/80 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-full bg-[#2A4468] border border-navy-600 flex items-center justify-center font-bold text-xs text-white">
            MA
          </div>
          <div className="flex flex-col">
            <span className="text-xs font-semibold text-white">Mariana Alves</span>
            <span className="text-[10px] text-slate-400">Gestora de entregas</span>
          </div>
        </div>
        <div className="p-1 rounded-lg bg-emerald-500/10 text-emerald-400" title="Sistema Online">
          <ShieldCheck className="w-4 h-4" />
        </div>
      </div>
    </aside>
  );
};
