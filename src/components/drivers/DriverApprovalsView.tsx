import React, { useState } from 'react';
import { 
  UserCheck, 
  Clock, 
  ShieldAlert, 
  CheckCircle2, 
  AlertCircle, 
  RotateCw 
} from 'lucide-react';

import { useAccessApprovals } from '../../features/access-approvals/hooks/useAccessApprovals';
import type { SolicitacaoAcessoItem } from '../../features/access-approvals/types/accessApproval';
import { IndicadorEstadoIntegracao } from '../../features/access-approvals/components/IndicadorEstadoIntegracao';
import { FiltrosSolicitacoes } from '../../features/access-approvals/components/FiltrosSolicitacoes';
import { ListaSolicitacoes } from '../../features/access-approvals/components/ListaSolicitacoes';
import { ModalAprovarMotorista } from '../../features/access-approvals/components/ModalAprovarMotorista';
import { ModalRejeitarAcesso } from '../../features/access-approvals/components/ModalRejeitarAcesso';
import { ModalSuspenderAcesso } from '../../features/access-approvals/components/ModalSuspenderAcesso';

import type { DocumentoVeiculoItem } from '../../features/vehicle-documents/types/vehicleDocument';
import { VisualizadorDocumento } from '../../features/vehicle-documents/components/VisualizadorDocumento';

export const DriverApprovalsView: React.FC = () => {
  const {
    solicitacoes,
    todasSolicitacoes,
    motoristasDisponiveis,
    carregando,
    erro,
    alertaSucesso,
    setAlertaSucesso,
    modoDemo,
    alternarModoDemo,
    filtroStatus,
    setFiltroStatus,
    buscaTexto,
    setBuscaTexto,
    totalPendentes,
    totalAprovados,
    totalSuspensos,
    carregarDados,
    aprovar,
    rejeitar,
    suspender,
    reativar,
  } = useAccessApprovals();

  // Estados dos Modais
  const [modalAprovarItem, setModalAprovarItem] = useState<SolicitacaoAcessoItem | null>(null);
  const [modalRejeitarItem, setModalRejeitarItem] = useState<SolicitacaoAcessoItem | null>(null);
  const [modalSuspenderItem, setModalSuspenderItem] = useState<SolicitacaoAcessoItem | null>(null);
  const [documentoVisualizar, setDocumentoVisualizar] = useState<DocumentoVeiculoItem | null>(null);
  const [processandoAcao, setProcessandoAcao] = useState(false);
  const [alertaErroLocal, setAlertaErroLocal] = useState<string | null>(null);

  const handleAprovar = async (dados: {
    solicitacaoId: string;
    criarNovoMotorista: boolean;
    motoristaId?: string | null;
    nomeMotorista?: string;
    telefoneMotorista?: string;
    revisaoEsperadaVeiculo?: number | null;
  }) => {
    setProcessandoAcao(true);
    setAlertaErroLocal(null);
    try {
      await aprovar(dados);
      setModalAprovarItem(null);
    } catch (err) {
      setAlertaErroLocal(err instanceof Error ? err.message : 'Falha na aprovação.');
    } finally {
      setProcessandoAcao(false);
    }
  };

  const handleRejeitar = async (solicitacaoId: string, motivo: string) => {
    setProcessandoAcao(true);
    setAlertaErroLocal(null);
    try {
      await rejeitar(solicitacaoId, motivo);
      setModalRejeitarItem(null);
    } catch (err) {
      setAlertaErroLocal(err instanceof Error ? err.message : 'Falha na rejeição.');
    } finally {
      setProcessandoAcao(false);
    }
  };

  const handleSuspender = async (membroId: string, motivo: string) => {
    setProcessandoAcao(true);
    setAlertaErroLocal(null);
    try {
      await suspender(membroId, motivo);
      setModalSuspenderItem(null);
    } catch (err) {
      setAlertaErroLocal(err instanceof Error ? err.message : 'Falha na suspensão.');
    } finally {
      setProcessandoAcao(false);
    }
  };

  const handleReativar = async (item: SolicitacaoAcessoItem) => {
    setProcessandoAcao(true);
    setAlertaErroLocal(null);
    try {
      await reativar(item.id);
    } catch (err) {
      setAlertaErroLocal(err instanceof Error ? err.message : 'Falha na reativação.');
    } finally {
      setProcessandoAcao(false);
    }
  };

  return (
    <div className="space-y-6 animate-fadeIn">
      {/* Cabeçalho da Página */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-xl font-extrabold text-[#0F1B2D] tracking-tight">
              Aprovação e Vínculo de Motoristas
            </h2>
            <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-blue-100 text-blue-800">
              Módulo Gestão
            </span>
          </div>
          <p className="text-xs text-[#516074] mt-1">
            Homologação de contas autenticadas no app Flutter, conferência de veículos e liberação operacional via RLS
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => carregarDados()}
            disabled={carregando}
            className="h-9 px-3 rounded-xl border border-slate-300 text-slate-700 hover:bg-slate-50 text-xs font-semibold flex items-center gap-1.5 transition-colors cursor-pointer"
          >
            <RotateCw className={`w-3.5 h-3.5 ${carregando ? 'animate-spin' : ''}`} />
            <span>Atualizar</span>
          </button>
        </div>
      </div>

      {/* Indicador de Estado da Integração e Alternador de Demonstração */}
      <IndicadorEstadoIntegracao modoDemo={modoDemo} onAlternarModoDemo={alternarModoDemo} />

      {/* Alerta de Modo Demonstração Ativo */}
      {modoDemo && (
        <div className="p-3 bg-amber-50 border border-amber-200 rounded-2xl flex items-center justify-between text-xs text-amber-900">
          <div className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-amber-500 animate-ping"></span>
            <strong>Modo Demonstração Ativo:</strong> Exibindo dados simulados claramente identificados como fictícios. Nenhuma mutação real será enviada ao banco de dados.
          </div>
          <button
            type="button"
            onClick={() => alternarModoDemo(false)}
            className="text-xs font-bold text-amber-900 underline hover:text-amber-950 cursor-pointer"
          >
            Voltar para o Modo Real
          </button>
        </div>
      )}

      {/* Alertas de Feedback */}
      {alertaSucesso && (
        <div className="p-3.5 bg-emerald-50 border border-emerald-200 rounded-2xl flex items-center justify-between text-xs text-emerald-900 animate-fadeIn">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-emerald-600 flex-shrink-0" />
            <span>{alertaSucesso}</span>
          </div>
          <button
            type="button"
            onClick={() => setAlertaSucesso(null)}
            className="text-emerald-700 hover:text-emerald-900 font-bold"
          >
            ✕
          </button>
        </div>
      )}

      {(erro || alertaErroLocal) && (
        <div className="p-3.5 bg-red-50 border border-red-200 rounded-2xl flex items-center justify-between text-xs text-red-900 animate-fadeIn">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-red-600 flex-shrink-0" />
            <span>{erro || alertaErroLocal}</span>
          </div>
          <button
            type="button"
            onClick={() => setAlertaErroLocal(null)}
            className="text-red-700 hover:text-red-900 font-bold"
          >
            ✕
          </button>
        </div>
      )}

      {/* Cartões de Indicadores (KPIs) */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex items-center justify-between">
          <div>
            <span className="text-xs font-bold uppercase tracking-wider text-amber-600">Aguardando Análise</span>
            <div className="text-3xl font-extrabold text-[#0F1B2D] mt-1">{totalPendentes}</div>
            <span className="text-[11px] text-[#516074] mt-0.5 block">Contas com vínculo e veículo pendentes</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-amber-50 text-amber-600 flex items-center justify-center">
            <Clock className="w-6 h-6" />
          </div>
        </div>

        <div className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex items-center justify-between">
          <div>
            <span className="text-xs font-bold uppercase tracking-wider text-emerald-700">Motoristas Aprovados</span>
            <div className="text-3xl font-extrabold text-[#0F1B2D] mt-1">{totalAprovados}</div>
            <span className="text-[11px] text-[#516074] mt-0.5 block">Acesso operacional liberado no app</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-[#DDF3E4] text-[#14532D] flex items-center justify-center">
            <UserCheck className="w-6 h-6" />
          </div>
        </div>

        <div className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex items-center justify-between">
          <div>
            <span className="text-xs font-bold uppercase tracking-wider text-slate-500">Suspensos / Rejeitados</span>
            <div className="text-3xl font-extrabold text-[#0F1B2D] mt-1">{totalSuspensos}</div>
            <span className="text-[11px] text-[#516074] mt-0.5 block">Sem acesso operacional revogado</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-slate-100 text-slate-600 flex items-center justify-center">
            <ShieldAlert className="w-6 h-6" />
          </div>
        </div>
      </div>

      {/* Barra de Filtros e Busca */}
      <FiltrosSolicitacoes
        filtroStatus={filtroStatus}
        onSelecionarFiltro={setFiltroStatus}
        buscaTexto={buscaTexto}
        onMudarBusca={setBuscaTexto}
        totalPendentes={totalPendentes}
        totalAprovados={totalAprovados}
        totalSuspensos={totalSuspensos}
        totalGeral={todasSolicitacoes.length}
      />

      {/* Lista / Tabela de Solicitações */}
      <ListaSolicitacoes
        solicitacoes={solicitacoes}
        filtroStatus={filtroStatus}
        onAbrirModalAprovar={setModalAprovarItem}
        onAbrirModalRejeitar={setModalRejeitarItem}
        onAbrirModalSuspender={setModalSuspenderItem}
        onReativar={handleReativar}
        onVerDocumentos={(item) => {
          if (item.documentos && item.documentos.length > 0) {
            setDocumentoVisualizar(item.documentos[0]);
          }
        }}
      />

      {/* ========================================================================= */}
      {/* MODAL 1: APROVAÇÃO (CRIAR NOVO OU VINCULAR EXISTENTE) */}
      {/* ========================================================================= */}
      {modalAprovarItem && (
        <ModalAprovarMotorista
          solicitacao={modalAprovarItem}
          motoristasDisponiveis={motoristasDisponiveis}
          carregando={processandoAcao}
          onConfirmar={handleAprovar}
          onFechar={() => setModalAprovarItem(null)}
          onVerDocumento={setDocumentoVisualizar}
        />
      )}

      {/* ========================================================================= */}
      {/* MODAL 2: REJEIÇÃO */}
      {/* ========================================================================= */}
      {modalRejeitarItem && (
        <ModalRejeitarAcesso
          solicitacao={modalRejeitarItem}
          carregando={processandoAcao}
          onConfirmar={handleRejeitar}
          onFechar={() => setModalRejeitarItem(null)}
        />
      )}

      {/* ========================================================================= */}
      {/* MODAL 3: SUSPENSÃO */}
      {/* ========================================================================= */}
      {modalSuspenderItem && (
        <ModalSuspenderAcesso
          solicitacao={modalSuspenderItem}
          carregando={processandoAcao}
          onConfirmar={handleSuspender}
          onFechar={() => setModalSuspenderItem(null)}
        />
      )}

      {/* ========================================================================= */}
      {/* MODAL 4: VISUALIZADOR SEGURO DE DOCUMENTO / FOTO */}
      {/* ========================================================================= */}
      {documentoVisualizar && (
        <VisualizadorDocumento
          documento={documentoVisualizar}
          onFechar={() => setDocumentoVisualizar(null)}
        />
      )}
    </div>
  );
};
