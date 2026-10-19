import { useState } from 'react';
import { DashboardLayout } from './components/layout/DashboardLayout';
import type { ActiveTab } from './components/layout/Sidebar';
import { OverviewView } from './components/dashboard/OverviewView';
import { RouteOptimizerView } from './components/routing/RouteOptimizerView';
import { NewRouteView } from './components/routing/NewRouteView';
import { DriverApprovalsView } from './components/drivers/DriverApprovalsView';
import { AuthGate } from './components/AuthGate';
import { History as HistoryIcon, Settings as SettingsIcon } from 'lucide-react';
import { CompanyRecords } from './components/CompanyRecords';

export function App() {
  const [activeTab, setActiveTab] = useState<ActiveTab>('overview');
  



  return (
    <AuthGate><DashboardLayout
      activeTab={activeTab}
      onTabChange={setActiveTab}
      onOpenNewDelivery={() => setActiveTab('new_route')}
    >
      {activeTab === 'new_route' && (
        <NewRouteView />
      )}

      {activeTab === 'overview' && (
        <OverviewView 
          onGoToOptimizer={() => setActiveTab('new_route')}
          onOpenNewDelivery={() => setActiveTab('new_route')}
        />
      )}

      {activeTab === 'routing' && (
        <RouteOptimizerView />
      )}

      {activeTab === 'approvals' && (
        <DriverApprovalsView />
      )}

      {activeTab === 'deliveries' && <CompanyRecords table="entregas" title="Entregas" />}

      {activeTab === 'drivers' && <CompanyRecords table="motoristas" title="Motoristas" />}

      {activeTab === 'condos' && <CompanyRecords table="clientes_enderecos" title="Clientes e endereços" />}

      {activeTab === 'history' && (
        <div className="bg-white rounded-2xl p-8 border border-slate-200/90 shadow-card">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-xl bg-slate-800 text-white flex items-center justify-center">
              <HistoryIcon className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-xl font-extrabold text-navy-900">Auditoria & Histórico Logístico</h2>
              <p className="text-xs text-slate-500">Métricas acumuladas de economia e relatórios de tempo</p>
            </div>
          </div>
          <p className="text-sm text-slate-600">
            Registros completos das rotas calculadas e atendimentos concluídos no Supabase.
          </p>
        </div>
      )}

      {activeTab === 'settings' && (
        <div className="bg-white rounded-2xl p-8 border border-slate-200/90 shadow-card max-w-3xl">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-xl bg-slate-800 text-white flex items-center justify-center">
              <SettingsIcon className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-xl font-extrabold text-navy-900">Configurações do Sistema</h2>
              <p className="text-xs text-slate-500">Domínio: entregacondo.com.br • Banco de Dados: Supabase</p>
            </div>
          </div>

          <div className="space-y-4 text-xs text-slate-600">
            <div className="p-4 rounded-xl bg-slate-50 border border-slate-200">
              <h4 className="font-bold text-navy-900 text-sm mb-1">Conexão com o Supabase</h4>
              <p className="text-slate-500 mb-3">
                Configure as chaves do seu novo projeto Supabase no arquivo <code className="font-mono bg-white px-1.5 py-0.5 rounded border">.env</code>:
              </p>
              <pre className="p-3 bg-navy-900 text-slate-200 rounded-lg font-mono text-[11px] overflow-x-auto">
                VITE_SUPABASE_URL=https://seu-projeto.supabase.co&#10;VITE_SUPABASE_ANON_KEY=sua-chave-anonima
              </pre>
            </div>

            <div className="p-4 rounded-xl bg-slate-50 border border-slate-200">
              <h4 className="font-bold text-navy-900 text-sm mb-1">Script SQL de Inicialização</h4>
              <p className="text-slate-500">
                O arquivo <code className="font-mono bg-white px-1.5 py-0.5 rounded border">supabase/schema.sql</code> já contém todas as tabelas, triggers de tempo médio de condomínio e políticas RLS para serem executados no SQL Editor do Supabase.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Modal de Nova Entrega */}

    </DashboardLayout></AuthGate>
  );
}

export default App;
