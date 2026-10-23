import React, { useEffect, useState } from 'react';
import { 
  LayoutDashboard, 
  Route, 
  PackageCheck, 
  Truck, 
  Building2, 
  History, 
  Settings, 
  ChevronRight, 
  Sparkles,
  Database as DatabaseIcon,
  UserCheck,
  LogOut
} from 'lucide-react';
import { supabase, isSupabaseConfigured } from '../../lib/supabase';
import { EntregaCondoLogo } from '../common/EntregaCondoLogo';
import { useCompanyIdentity } from '../../lib/companyIdentity';

interface UserProfile {
  nome: string;
  email: string;
  iniciais: string;
}

function extrairPerfil(user: any): UserProfile {
  if (!user) {
    return {
      nome: 'Gestor',
      email: '',
      iniciais: 'GL',
    };
  }

  const meta = user.user_metadata || {};
  const nomeCompleto =
    meta.name ||
    meta.full_name ||
    user.email?.split('@')[0] ||
    'Gestor';

  let iniciais = 'GL';
  const partes = nomeCompleto.trim().split(/\s+/);
  if (partes.length >= 2) {
    iniciais = `${partes[0][0]}${partes[partes.length - 1][0]}`.toUpperCase();
  } else if (nomeCompleto.length >= 2) {
    iniciais = nomeCompleto.substring(0, 2).toUpperCase();
  } else if (nomeCompleto.length === 1) {
    iniciais = nomeCompleto.toUpperCase();
  }

  return {
    nome: nomeCompleto,
    email: user.email || '',
    iniciais,
  };
}

export type ActiveTab = 'overview' | 'new_route' | 'deliveries' | 'drivers' | 'approvals' | 'condos' | 'history' | 'settings' | 'proofs';

interface SidebarProps {
  activeTab: ActiveTab;
  onTabChange: (tab: ActiveTab) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, onTabChange }) => {
  const company = useCompanyIdentity();
  const [perfil, setPerfil] = useState<UserProfile>({
    nome: 'Gestor',
    email: '',
    iniciais: 'GL',
  });

  useEffect(() => {
    let active = true;

    supabase.auth.getUser().then(({ data }) => {
      if (active && data?.user) {
        setPerfil(extrairPerfil(data.user));
      }
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      if (active) {
        setPerfil(extrairPerfil(session?.user ?? null));
      }
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);

  async function handleLogout() {
    localStorage.removeItem('ec_demo_auth');
    localStorage.removeItem('ec_active_company_id');
    await supabase.auth.signOut();
    if (typeof window !== 'undefined' && window.location.search.includes('demo=')) {
      const url = new URL(window.location.href);
      url.searchParams.delete('demo');
      window.location.href = url.pathname + url.search;
    } else {
      window.location.reload();
    }
  }

  const menuItems = [
    {
      id: 'overview' as ActiveTab,
      label: 'Visão geral',
      icon: LayoutDashboard,
      badge: null,
    },
    {
      id: 'new_route' as ActiveTab,
      label: 'Nova Rota',
      icon: Route,
      badge: null,
      highlight: true,
    },
    {
      id: 'deliveries' as ActiveTab,
      label: 'Gestão de entregas',
      icon: PackageCheck,
      badge: null,
    },
    {
      id: 'approvals' as ActiveTab,
      label: 'Aprovações de Acesso',
      icon: UserCheck,
      badge: null,
      highlight: true,
    },
    {
      id: 'drivers' as ActiveTab,
      label: 'Motoristas',
      icon: Truck,
      badge: null,
    },
    {
      id: 'condos' as ActiveTab,
      label: 'Endereços salvos',
      icon: Building2,
      badge: null,
    },
    {id:'proofs' as ActiveTab, label:'Comprovantes', icon:PackageCheck, badge:null},
    {
      id: 'history' as ActiveTab,
      label: 'Relatórios & Histórico',
      icon: History,
      badge: null,
    },
  ];

  return (
    <aside className="w-[248px] bg-[#0F1B2D] text-slate-200 flex flex-col flex-shrink-0 border-r border-navy-700/70 select-none h-screen sticky top-0 z-30 transition-all">
      {/* Brand Header */}
      <div className="min-h-20 flex flex-col justify-center px-6 py-4 border-b border-navy-700/60 bg-navy-850/60 backdrop-blur">
        <p className="text-xs text-slate-400">Painel da empresa</p>
        <h1 data-company-identity className="mt-1 break-words text-lg font-bold text-white">{company.name || 'Sua empresa'}</h1>
      </div>

      {/* Main Navigation */}
      <div className="flex-1 py-6 px-3 space-y-1.5 overflow-y-auto">
        <div className="px-3 pb-2 text-[11px] font-bold uppercase tracking-wider text-slate-500">
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
                  ? 'bg-slate-800/50 text-white font-semibold'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/30'
              }`}
            >
              <div className="flex items-center gap-3">
                <Icon
                  className={`w-5 h-5 transition-colors ${
                    isActive ? 'text-white' : 'text-slate-500 group-hover:text-slate-300'
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

        <div className="pt-6 px-3 pb-2 text-[11px] font-bold uppercase tracking-wider text-slate-500">
          Sistema & Conexões
        </div>

        <button
          onClick={() => onTabChange('settings')}
          className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all group ${
            activeTab === 'settings'
              ? 'bg-slate-800/50 text-white font-semibold'
              : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/30'
          }`}
        >
          <div className="flex items-center gap-3">
            <Settings
              className={`w-5 h-5 transition-colors ${
                activeTab === 'settings' ? 'text-white' : 'text-slate-500 group-hover:text-slate-300'
              }`}
            />
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
            ? 'Conexão Supabase configurada'
            : 'Conexão não configurada'}
        </p>
      </div>

      <div className="px-6 pb-3"><EntregaCondoLogo height={24} subtitle="Tecnologia para sua operação" /></div>

      {/* User Footer Dinâmico com Perfil Real e Logout */}
      <div className="p-3.5 border-t border-navy-700/60 bg-navy-850/90 flex items-center justify-between gap-2">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          <div className="w-9 h-9 rounded-full bg-gradient-to-br from-terracotta-600 to-terracotta-500 border border-terracotta-400/40 flex items-center justify-center font-bold text-xs text-white shadow-sm shrink-0">
            {perfil.iniciais}
          </div>
          <div className="flex flex-col min-w-0">
            <span className="text-xs font-semibold text-slate-200 truncate" title={perfil.nome}>
              {perfil.nome}
            </span>
            <span className="text-[10px] text-slate-400 font-medium">Gestor de Logística</span>
          </div>
        </div>

        <button
          onClick={handleLogout}
          className="p-2 rounded-lg text-slate-400 hover:text-red-400 hover:bg-red-500/10 transition-colors shrink-0"
          title="Sair da conta"
          type="button"
        >
          <LogOut className="w-4 h-4" />
        </button>
      </div>
    </aside>
  );
};
