import React, { useState, useEffect, useCallback } from 'react';
import { 
  UserCheck, 
  Clock, 
  ShieldAlert, 
  CheckCircle2, 
  AlertCircle, 
  RotateCw,
  Trash2,
  HardDrive,
  RefreshCw
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
import {
  processarFilaLimpezaStorage,
  consultarEstatisticasFilaLimpeza,
  retomarLimpezaFalha,
  type EstatisticasFilaLimpeza,
  type ResultadoProcessamentoFila
} from '../../features/vehicle-documents/services/processarFilaLimpezaStorage';

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

  // Estados da Fila de Limpeza do Storage
  const [statsFila, setStatsFila] = useState<EstatisticasFilaLimpeza | null>(null);
  const [resultadoLimpeza, setResultadoLimpeza] = useState<ResultadoProcessamentoFila | null>(null);
  const [processandoFila, setProcessandoFila] = useState(false);
  const [exibirPainelStorage, setExibirPainelStorage] = useState(false);

  const carregarStats = useCallback(async () => {
    if (modoDemo) return;
    try {
      const stats = await consultarEstatisticasFilaLimpeza();
      setStatsFila(stats);
    } catch {
      // Falha silenciosa no polling de estatísticas
    }
  }, [modoDemo]);

  useEffect(() => {
    carregarStats();
  }, [carregarStats]);

  const handleProcessarFila = async () => {
    setProcessandoFila(true);
    setAlertaErroLocal(null);
    try {
      const res = await processarFilaLimpezaStorage(15);
      setResultadoLimpeza(res);
      setAlertaSucesso(
        `Fila de limpeza processada: ${res.sucessosCompletos} item(ns) removido(s) com sucesso.` +
        (res.removidosFisicoPendenteConfirmacao > 0 ? ` (${res.removidosFisicoPendenteConfirmacao} pendentes de confirmação no banco).` : '')
      );
      await carregarStats();
    } catch (err) {
      setAlertaErroLocal(err instanceof Error ? err.message : 'Falha ao processar fila de limpeza.');
    } finally {
      setProcessandoFila(false);
    }
  };

  const handleRetomarItem = async (filaId: string) => {
    setProcessandoFila(true);
    setAlertaErroLocal(null);
    try {
      await retomarLimpezaFalha(filaId);
      setAlertaSucesso('Item retornado ao estado pendente para retentativa de limpeza.');
      await carregarStats();
    } catch (err) {
      setAlertaErroLocal(err instanceof Error ? err.message : 'Falha ao retomar limpeza.');
    } finally {
      setProcessandoFila(false);
    }
  };

  const handleAprovar = async (dados: {
    solicitacaoId: string;
    criarNovoMotorista: boolean;
    motoristaId?: string | null;
    nomeMotorista?: string;
    telefoneMotorista?: string;
    aprovarVeiculo?: boolean;
    revisaoEsperadaVeiculo?: number | null;
  }) => {
    setProcessandoAcao(true);
    setAlertaErroLocal(null);
    try {
      await aprovar(dados);
      setModalAprovarItem(null);
      await carregarStats();
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
            onClick={() => setExibirPainelStorage(!exibirPainelStorage)}
            className="h-9 px-3 rounded-xl border border-slate-300 text-slate-700 hover:bg-slate-50 text-xs font-semibold flex items-center gap-1.5 transition-colors cursor-pointer"
            title="Monitorar e executar limpeza de arquivos descartados do Storage"
          >
            <HardDrive className="w-3.5 h-3.5 text-slate-600" />
            <span>Fila Storage</span>
            {statsFila && (statsFila.pendentes > 0 || statsFila.falhas > 0) && (
              <span className="px-1.5 py-0.2 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800">
                {statsFila.pendentes + statsFila.falhas}
              </span>
            )}
          </button>

          <button
            type="button"
            onClick={() => {
              carregarDados();
              carregarStats();
            }}
            disabled={carregando}
            className="h-9 px-3 rounded-xl border border-slate-300 text-slate-700 hover:bg-slate-50 text-xs font-semibold flex items-center gap-1.5 transition-colors cursor-pointer"
          >
            <RotateCw className={`w-3.5 h-3.5 ${carregando ? 'animate-spin' : ''}`} />
            <span>Atualizar</span>
          </button>
        </div>
      </div>

      {/* Painel Expansível de Gerenciamento da Fila de Limpeza do Storage */}
      {exibirPainelStorage && (
        <div className="p-4 bg-slate-50 border border-slate-200 rounded-2xl space-y-3 animate-fadeIn">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Trash2 className="w-4 h-4 text-slate-700" />
              <h3 className="text-xs font-bold text-[#0F1B2D] uppercase tracking-wider">
                Recuperação e Limpeza Física do Storage (Bucket veiculos-documentos)
              </h3>
            </div>
            <button
              type="button"
              onClick={handleProcessarFila}
              disabled={processandoFila}
              className="px-3 py-1.5 bg-[#0F1B2D] hover:bg-[#1A2C42] text-white text-xs font-semibold rounded-lg flex items-center gap-1.5 transition-colors disabled:opacity-50 cursor-pointer"
            >
              <RefreshCw className={`w-3 h-3 ${processandoFila ? 'animate-spin' : ''}`} />
              <span>{processandoFila ? 'Processando Fila...' : 'Processar Fila Agora'}</span>
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
            <div className="bg-white p-2.5 rounded-xl border border-slate-200">
              <span className="text-[11px] text-slate-500 font-medium">Pendentes na Fila:</span>
              <div className="text-lg font-bold text-amber-600">{statsFila?.pendentes ?? 0}</div>
            </div>
            <div className="bg-white p-2.5 rounded-xl border border-slate-200">
              <span className="text-[11px] text-slate-500 font-medium">Em Processamento:</span>
              <div className="text-lg font-bold text-blue-600">{statsFila?.emProcessamento ?? 0}</div>
            </div>
            <div className="bg-white p-2.5 rounded-xl border border-slate-200">
              <span className="text-[11px] text-slate-500 font-medium">Limpezas Falhas:</span>
              <div className="text-lg font-bold text-red-600">{statsFila?.falhas ?? 0}</div>
            </div>
            <div className="bg-white p-2.5 rounded-xl border border-slate-200">
              <span className="text-[11px] text-slate-500 font-medium">Concluídos com Sucesso:</span>
              <div className="text-lg font-bold text-emerald-600">{statsFila?.concluidos ?? 0}</div>
            </div>
          </div>

          {resultadoLimpeza && (
            <div className="p-3 bg-white rounded-xl border border-slate-200 text-xs space-y-1.5">
              <div className="font-semibold text-[#0F1B2D]">Último Resultado de Processamento:</div>
              <div className="text-[11px] text-slate-600 flex flex-wrap gap-3">
                <span>Reivindicados: <b>{resultadoLimpeza.totalReivindicados}</b></span>
                <span className="text-emerald-700">Sucessos Completos: <b>{resultadoLimpeza.sucessosCompletos}</b></span>
                {resultadoLimpeza.removidosFisicoPendenteConfirmacao > 0 && (
                  <span className="text-amber-700">Físico OK / Confirmação Pendente: <b>{resultadoLimpeza.removidosFisicoPendenteConfirmacao}</b></span>
                )}
                {resultadoLimpeza.falhasFisicas > 0 && (
                  <span className="text-red-700">Falhas Físicas: <b>{resultadoLimpeza.falhasFisicas}</b></span>
                )}
              </div>

              {resultadoLimpeza.itens.length > 0 && (
                <div className="mt-2 space-y-1 max-h-36 overflow-y-auto">
                  {resultadoLimpeza.itens.map((it) => (
                    <div key={it.filaId} className="flex items-center justify-between text-[11px] p-1.5 bg-slate-50 rounded border border-slate-100">
                      <span className="font-mono truncate max-w-xs">{it.storagePath}</span>
                      <div className="flex items-center gap-2">
                        <span className={`px-1.5 py-0.5 rounded text-[10px] font-semibold ${
                          it.remocaoFisicaSucesso && it.confirmacaoBancoSucesso
                            ? 'bg-emerald-100 text-emerald-800'
                            : 'bg-amber-100 text-amber-800'
                        }`}>
                          {it.statusFinal}
                        </span>
                        {it.statusFinal === 'falhou' && (
                          <button
                            type="button"
                            onClick={() => handleRetomarItem(it.filaId)}
                            className="text-xs text-blue-600 hover:underline font-semibold cursor-pointer"
                          >
                            Retomar
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}

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

      {/* MODAIS DE AÇÃO */}
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

      {modalRejeitarItem && (
        <ModalRejeitarAcesso
          solicitacao={modalRejeitarItem}
          carregando={processandoAcao}
          onConfirmar={handleRejeitar}
          onFechar={() => setModalRejeitarItem(null)}
        />
      )}

      {modalSuspenderItem && (
        <ModalSuspenderAcesso
          solicitacao={modalSuspenderItem}
          carregando={processandoAcao}
          onConfirmar={handleSuspender}
          onFechar={() => setModalSuspenderItem(null)}
        />
      )}

      {documentoVisualizar && (
        <VisualizadorDocumento
          documento={documentoVisualizar}
          onFechar={() => setDocumentoVisualizar(null)}
        />
      )}
    </div>
  );
};
