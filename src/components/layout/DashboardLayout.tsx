import React from "react";
import { Sidebar, type ActiveTab } from "./Sidebar";
import { CompanySubscriptionNotice } from '../CompanySubscriptionNotice';
import { Header } from "./Header";

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
      <div className="flex-1 flex flex-col min-w-0 bg-[#E4E5E9]">
        {activeTab !== "overview" && activeTab !== "new_route" && (
          <Header
            onOpenNewDelivery={onOpenNewDelivery}
            onOpenOptimizer={() => onTabChange("new_route")}
          />
        )}

        <CompanySubscriptionNotice />
        <main className="flex-1 p-4 md:p-8 overflow-y-auto bg-[#E4E5E9] bg-dot-grid">{children}</main>
      </div>
    </div>
  );
};
