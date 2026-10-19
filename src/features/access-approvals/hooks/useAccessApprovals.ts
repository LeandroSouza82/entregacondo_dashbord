import { useState, useEffect, useCallback } from 'react';
import type { SolicitacaoAcessoItem, MotoristaFrotaItem, FiltroStatusAcesso } from '../types/accessApproval';
import { obterSolicitacoesAcesso } from '../services/obterSolicitacoesAcesso';
import { aprovarSolicitacaoMotorista, type ParametrosAprovacao } from '../services/aprovarSolicitacaoMotorista';
import { rejeitarSolicitacaoAcesso } from '../services/rejeitarSolicitacaoAcesso';
import { suspenderAcessoMembro } from '../services/suspenderAcessoMembro';
import { reativarAcessoMembro } from '../services/reativarAcessoMembro';

export function useAccessApprovals() {
  const [solicitacoes, setSolicitacoes] = useState<SolicitacaoAcessoItem[]>([]);
  const [motoristasDisponiveis, setMotoristasDisponiveis] = useState<MotoristaFrotaItem[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [alertaSucesso, setAlertaSucesso] = useState<string | null>(null);

  const modoDemo = false;
  const alternarModoDemo = (_ativar: boolean) => {};

  // Filtros
  const [filtroStatus, setFiltroStatus] = useState<FiltroStatusAcesso>('pendente');
  const [buscaTexto, setBuscaTexto] = useState('');

  const carregarDados = useCallback(async () => {
    setCarregando(true);
    setErro(null);


    try {
      const res = await obterSolicitacoesAcesso();
      setSolicitacoes(res.solicitacoes);
      setMotoristasDisponiveis(res.motoristas);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Falha ao carregar dados do servidor.';
      setErro(msg);
      setSolicitacoes([]);
      setMotoristasDisponiveis([]);
    } finally {
      setCarregando(false);
    }
  }, []);

  useEffect(() => {
    carregarDados();
  }, [carregarDados]);


  // Ação de Aprovação
  const aprovar = async (params: ParametrosAprovacao) => {

    const res = await aprovarSolicitacaoMotorista(params);
    setAlertaSucesso(res.mensagem || 'Condutor aprovado com sucesso.');
    await carregarDados();
  };

  // Ação de Rejeição
  const rejeitar = async (solicitacaoId: string, motivo: string) => {

    const res = await rejeitarSolicitacaoAcesso(solicitacaoId, motivo);
    setAlertaSucesso(res.mensagem || 'Solicitação rejeitada com sucesso.');
    await carregarDados();
  };

  // Ação de Suspensão
  const suspender = async (membroId: string, motivo: string) => {

    const res = await suspenderAcessoMembro(membroId, motivo);
    setAlertaSucesso(res.mensagem || 'Acesso suspenso preventivamente.');
    await carregarDados();
  };

  // Ação de Reativação
  const reativar = async (membroId: string) => {

    const res = await reativarAcessoMembro(membroId);
    setAlertaSucesso(res.mensagem || 'Acesso reativado com sucesso.');
    await carregarDados();
  };

  // Filtra lista de acordo com os filtros de status e busca
  const listaFiltrada = solicitacoes.filter((item) => {
    const atendeStatus = filtroStatus === 'todos' || item.status === filtroStatus;
    const busca = buscaTexto.toLowerCase().trim();
    const atendeBusca =
      !busca ||
      item.usuario_nome.toLowerCase().includes(busca) ||
      item.usuario_email.toLowerCase().includes(busca) ||
      (item.motorista_placa && item.motorista_placa.toLowerCase().includes(busca)) ||
      (item.veiculo_declarado?.placa && item.veiculo_declarado.placa.toLowerCase().includes(busca));

    return atendeStatus && atendeBusca;
  });

  const totalPendentes = solicitacoes.filter((s) => s.status === 'pendente').length;
  const totalAprovados = solicitacoes.filter((s) => s.status === 'aprovado').length;
  const totalSuspensos = solicitacoes.filter((s) => s.status === 'suspenso' || s.status === 'rejeitado').length;

  return {
    solicitacoes: listaFiltrada,
    todasSolicitacoes: solicitacoes,
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
  };
}
