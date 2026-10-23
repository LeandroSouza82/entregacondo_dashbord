import { ReceiptsView } from './components/dashboard/ReceiptsView';
import { lazy, Suspense, useState, useEffect } from 'react';
import { DashboardLayout } from './components/layout/DashboardLayout';
import type { ActiveTab } from './components/layout/Sidebar';
import { OverviewView } from './components/dashboard/OverviewView';
import { NewRouteView } from './components/routing/NewRouteView';
import { DriverApprovalsView } from './components/drivers/DriverApprovalsView';
import { AuthGate } from './components/AuthGate';
import { CompanySettings } from './components/CompanySettings';
import { CustomerTrackingView } from './components/public/CustomerTrackingView';
import { CompanyRecords } from './components/CompanyRecords';
import { PublicReceiptView } from './components/public/PublicReceiptView';

const EntregaCondoPresentation = lazy(() => import('./components/public/EntregaCondoPresentation'));

export function App() {
  const [activeTab, setActiveTab] = useState<ActiveTab>('overview');
  const [currentPath, setCurrentPath] = useState(() => ({
    pathname: typeof window !== 'undefined' ? window.location.pathname : '',
    hash: typeof window !== 'undefined' ? window.location.hash : '',
  }));

  useEffect(() => {
    const handleLocationChange = () => {
      setCurrentPath({
        pathname: window.location.pathname,
        hash: window.location.hash,
      });
    };
    window.addEventListener('popstate', handleLocationChange);
    window.addEventListener('hashchange', handleLocationChange);
    return () => {
      window.removeEventListener('popstate', handleLocationChange);
      window.removeEventListener('hashchange', handleLocationChange);
    };
  }, []);

  if (/^#\/?conheca\/?$/.test(currentPath.hash)) {
    return <Suspense fallback={<main role="status" className="p-6">Carregando apresentação…</main>}><EntregaCondoPresentation /></Suspense>;
  }

  const trackingMatch = currentPath.hash.match(/^#\/?acompanhar\/(.*)$/);
  if (trackingMatch) return <CustomerTrackingView token={trackingMatch[1]} />;

  const receiptToken = currentPath.hash.match(/^#\/?comprovante\/([^/?#]+)$/)?.[1]
    || currentPath.pathname.match(/^\/comprovante\/([^/?#]+)\/?$/)?.[1];
  if (receiptToken) return <PublicReceiptView token={receiptToken}/>;

  return (
    <AuthGate key={/^#\/?cadastro\/?$/.test(currentPath.hash) ? 'cadastro' : 'login'} initialMode={/^#\/?cadastro\/?$/.test(currentPath.hash) ? 'cadastro' : 'login'}><DashboardLayout
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

      {activeTab === 'approvals' && (
        <DriverApprovalsView />
      )}

      {activeTab === 'deliveries' && <CompanyRecords table="entregas" title="Entregas" />}

      {activeTab === 'drivers' && <CompanyRecords table="motoristas" title="Motoristas" />}

      {activeTab === 'condos' && <CompanyRecords table="clientes_enderecos" title="Clientes e endereços" />}

      {activeTab === 'proofs' && <ReceiptsView />}
      {activeTab === 'history' && <ReceiptsView title="Histórico de atendimentos" />}

      {activeTab === 'settings' && <CompanySettings />}

      {/* Modal de Nova Entrega */}

    </DashboardLayout></AuthGate>
  );
}

export default App;
