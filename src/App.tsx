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

const EmailActionView = lazy(() => import('./components/EmailActionView'));
const EntregaCondoPresentation = lazy(() => import('./components/public/EntregaCondoPresentation'));

export function App() {
  const [emailActionKey, setEmailActionKey] = useState(() => window.location.hash);
  const [activeTab, setActiveTab] = useState<ActiveTab>(() => /^#\/?assinatura\/?$/.test(window.location.hash) ? 'settings' : 'overview');
  const [currentPath, setCurrentPath] = useState(() => ({
    pathname: typeof window !== 'undefined' ? window.location.pathname : '',
    hash: typeof window !== 'undefined' ? window.location.hash : '',
  }));

  useEffect(() => {
    const handleLocationChange = () => {
      if (new URLSearchParams(window.location.hash.split('?')[1] || '').has('token_hash')) setEmailActionKey(window.location.hash);
      if (/^#\/?assinatura\/?$/.test(window.location.hash)) setActiveTab('settings');
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

  const emailAction = new URLSearchParams(window.location.search).get('auth_action');
  if (emailAction === 'signup' || emailAction === 'recovery') {
    return <Suspense fallback={<main role="status" className="p-6">Conferindo seu acesso…</main>}><EmailActionView legacy recovery={emailAction === 'recovery'} /></Suspense>;
  }
  if (/^#\/?(ativar|definir-senha)(?:[?]|$)/.test(currentPath.hash)) {
    // Clearing a consumed token from history must not remount the recovery form.
    return <Suspense fallback={<main role="status" className="p-6">Conferindo seu acesso…</main>}><EmailActionView key={emailActionKey} recovery={currentPath.hash.includes('definir-senha')} /></Suspense>;
  }

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
