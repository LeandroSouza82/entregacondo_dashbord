import React from 'react';
import { Sidebar, type ActiveTab } from './Sidebar';
import { Header } from './Header';

interface DashboardLayoutProps {
  children: React.ReactNode;
  activeTab: ActiveTab;
  onTabChange: (tab: ActiveTab) => void;
  onOpenNewDelivery?: () => void;
}

export const DashboardLayout: React.FC<DashboardLayoutProps> = ({
  children,
  activeTab,
  onTabChange,
  onOpenNewDelivery,
}) => {
  return (
    <div className="min-h-screen flex bg-surface font-sans text-slate-800 antialiased">
      {/* Sidebar Fixo Navy */}
      <Sidebar activeTab={activeTab} onTabChange={onTabChange} />

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0">
        <Header 
          onOpenNewDelivery={onOpenNewDelivery}
          onOpenOptimizer={() => onTabChange('routing')}
          driversActiveCount={3}
          driversInRouteCount={2}
        />
        
        <main className="flex-1 p-8 overflow-y-auto">
          {children}
        </main>
      </div>
    </div>
  );
};
