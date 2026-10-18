import { useState } from 'react';
import { DashboardLayout } from './components/layout/DashboardLayout';
import type { ActiveTab } from './components/layout/Sidebar';
import { OverviewView } from './components/dashboard/OverviewView';
import { RouteOptimizerView } from './components/routing/RouteOptimizerView';
import { NewRouteView } from './components/routing/NewRouteView';
import { NewDeliveryModal } from './components/deliveries/NewDeliveryModal';
import { DriverApprovalsView } from './components/drivers/DriverApprovalsView';
import { MOCK_PARADAS_INICIAIS } from './services/mockData';
import type { PontoParada } from './types/logistics';
import { Building2, Truck, History as HistoryIcon, Settings as SettingsIcon, UserCheck } from 'lucide-react';

export function App() {
  const [activeTab, setActiveTab] = useState<ActiveTab>('overview');
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [paradas, setParadas] = useState<PontoParada[]>(MOCK_PARADAS_INICIAIS);

  const handleAddDelivery = (novaParada: PontoParada) => {
    setParadas((prev) => [novaParada, ...prev]);
    setActiveTab('new_route');
  };

  return (
    <DashboardLayout
      activeTab={activeTab}
      onTabChange={setActiveTab}
      onOpenNewDelivery={() => setIsModalOpen(true)}
    >
      {activeTab === 'new_route' && (
        <NewRouteView />
      )}

      {activeTab === 'overview' && (
        <OverviewView 
          onGoToOptimizer={() => setActiveTab('new_route')}
          onOpenNewDelivery={() => setIsModalOpen(true)}
        />
      )}

      {activeTab === 'routing' && (
        <RouteOptimizerView />
      )}

      {activeTab === 'approvals' && (
        <DriverApprovalsView />
      )}

      {activeTab === 'deliveries' && (
        <div className="bg-white rounded-2xl p-8 border border-slate-200/90 shadow-card">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h2 className="text-xl font-extrabold text-navy-900">Gestão de Entregas & Pedidos</h2>
              <p className="text-xs text-slate-500">Listagem de todas as encomendas ativas no EntregaCondo</p>
            </div>
            <button
              onClick={() => setIsModalOpen(true)}
              className="px-4 py-2 bg-terracotta-600 hover:bg-terracotta-700 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-terracotta-600/20 cursor-pointer"
            >
              + Adicionar Encomenda
            </button>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead>
                <tr className="border-b border-slate-200 text-slate-400 uppercase font-semibold">
                  <th className="pb-3">Código</th>
                  <th className="pb-3">Destinatário</th>
                  <th className="pb-3">Condomínio / Endereço</th>
                  <th className="pb-3 text-center">Tempo Est. Portaria</th>
                  <th className="pb-3 text-right">Prioridade</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 text-slate-700">
                {paradas.map((p) => (
                  <tr key={p.id} className="hover:bg-slate-50 transition-colors">
                    <td className="py-3 font-semibold text-navy-900">{p.codigoRastreio}</td>
                    <td className="py-3 font-medium">{p.destinatario}</td>
                    <td className="py-3 text-slate-500">{p.nomeLocal}</td>
                    <td className="py-3 text-center">
                      <span className="font-bold text-slate-800 bg-slate-100 px-2 py-0.5 rounded-full">
                        {p.tempoMedioAtendimentoMinutos} min
                      </span>
                    </td>
                    <td className="py-3 text-right">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-[10px] font-bold uppercase ${
                        p.prioridade === 'urgente' ? 'bg-red-100 text-red-700' : 'bg-slate-100 text-slate-600'
                      }`}>
                        {p.prioridade}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'drivers' && (
        <div className="bg-white rounded-2xl p-8 border border-slate-200/90 shadow-card">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-navy-800 text-white flex items-center justify-center">
                <Truck className="w-5 h-5" />
              </div>
              <div>
                <h2 className="text-xl font-extrabold text-navy-900">Motoristas e Frotas</h2>
                <p className="text-xs text-slate-500">Gestão dos motoristas cadastrados e integração com o app móvel Flutter</p>
              </div>
            </div>
            <button
              onClick={() => setActiveTab('approvals')}
              className="flex items-center gap-2 px-4 py-2 bg-navy-900 hover:bg-navy-800 text-white rounded-xl text-xs font-bold transition-all shadow-md cursor-pointer"
            >
              <UserCheck className="w-4 h-4 text-emerald-400" />
              Gerenciar Aprovações de Acesso
            </button>
          </div>
          <p className="text-sm text-slate-600 leading-relaxed">
            Os motoristas autenticam-se pelo aplicativo móvel Flutter (via Supabase Auth Google/E-mail) e solicitam acesso usando o código da empresa. 
            Após aprovação pela gestão na aba <strong className="text-navy-900">Aprovações de Acesso</strong>, a conta do Supabase é vinculada ao cadastro do motorista da frota, liberando em tempo real o acesso às rotas e entregas atribuídas via Row Level Security (RLS).
          </p>
        </div>
      )}

      {activeTab === 'condos' && (
        <div className="bg-white rounded-2xl p-8 border border-slate-200/90 shadow-card">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-xl bg-terracotta-600 text-white flex items-center justify-center">
              <Building2 className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-xl font-extrabold text-navy-900">Condomínios & Portarias Inteligentes</h2>
              <p className="text-xs text-slate-500">Parâmetros de acesso, tempos médios e regras de segurança predial</p>
            </div>
          </div>
          <p className="text-sm text-slate-600">
            O sistema armazena a média histórica de espera na portaria e tempo de descarga para cada condomínio cadastrado na tabela <code className="bg-slate-100 px-1 py-0.5 rounded text-navy-800 font-mono text-xs">clientes_enderecos</code>.
          </p>
        </div>
      )}

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
      <NewDeliveryModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        onAddDelivery={handleAddDelivery}
      />
    </DashboardLayout>
  );
}

export default App;
