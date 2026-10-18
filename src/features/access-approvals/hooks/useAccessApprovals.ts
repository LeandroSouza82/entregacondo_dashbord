import { useState, useEffect, useCallback } from 'react';
import type { SolicitacaoAcessoItem, MotoristaFrotaItem, FiltroStatusAcesso } from '../types/accessApproval';
import { obterSolicitacoesAcesso } from '../services/obterSolicitacoesAcesso';
import { aprovarSolicitacaoMotorista, type ParametrosAprovacao } from '../services/aprovarSolicitacaoMotorista';
import { rejeitarSolicitacaoAcesso } from '../services/rejeitarSolicitacaoAcesso';
import { suspenderAcessoMembro } from '../services/suspenderAcessoMembro';
import { reativarAcessoMembro } from '../services/reativarAcessoMembro';

// DADOS FICTÍCIOS EXCLUSIVOS PARA O MODO DEMONSTRAÇÃO
// Identificados explicitamente como fictícios, sem imitar contas ou nomes de usuários reais.
const MOCK_DEMONSTRACAO: SolicitacaoAcessoItem[] = [
  {
    id: 'demo-sol-001',
    empresa_id: '11111111-1111-1111-1111-111111111111',
    empresa_nome: 'EntregaCondo Matriz (Demonstração)',
    user_id: 'demo-usr-moto-01',
    usuario_nome: 'Condutor Demonstração 01 (Moto Baú)',
    usuario_email: 'condutor01.demo@entregacondo.com.br',
    papel_solicitado: 'motorista',
    status: 'pendente',
    veiculo_declarado: {
      id: 'demo-veic-001',
      user_id: 'demo-usr-moto-01',
      empresa_id: '11111111-1111-1111-1111-111111111111',
      tipo_veiculo: 'moto',
      marca: 'Honda',
      modelo: 'CG 160 Cargo',
      placa: 'BRA3G44',
      compartimento: 'bau',
      volume_litros: 80,
      tamanho_compartimento: null,
      capacidade_kg: 20,
      status_analise: 'pendente',
      revisao: 1,
    },
    documentos: [
      {
        id: 'demo-doc-001',
        veiculo_id: 'demo-veic-001',
        user_id: 'demo-usr-moto-01',
        empresa_id: '11111111-1111-1111-1111-111111111111',
        tipo_documento: 'foto_veiculo',
        nome_arquivo: 'foto_moto_cargo.jpg',
        storage_path: 'demo/foto_moto_cargo.jpg',
        mime_type: 'image/jpeg',
        tamanho_bytes: 1024 * 850,
        status_analise: 'pendente',
        created_at: new Date().toISOString(),
      },
      {
        id: 'demo-doc-002',
        veiculo_id: 'demo-veic-001',
        user_id: 'demo-usr-moto-01',
        empresa_id: '11111111-1111-1111-1111-111111111111',
        tipo_documento: 'crlv',
        nome_arquivo: 'crlv_2026.pdf',
        storage_path: 'demo/crlv_2026.pdf',
        mime_type: 'application/pdf',
        tamanho_bytes: 1024 * 1200,
        status_analise: 'pendente',
        created_at: new Date().toISOString(),
      },
    ],
    created_at: new Date(Date.now() - 1000 * 60 * 25).toISOString(),
  },
  {
    id: 'demo-sol-002',
    empresa_id: '11111111-1111-1111-1111-111111111111',
    empresa_nome: 'EntregaCondo Matriz (Demonstração)',
    user_id: 'demo-usr-carro-02',
    usuario_nome: 'Condutor Demonstração 02 (Carro Fiorino)',
    usuario_email: 'condutor02.demo@entregacondo.com.br',
    papel_solicitado: 'motorista',
    status: 'aprovado',
    motorista_vinculado_id: '22222222-2222-2222-2222-222222222221',
    motorista_nome: 'Condutor Demonstração 02',
    motorista_veiculo: 'Fiat Fiorino',
    motorista_placa: 'BRA-2E19',
    veiculo_declarado: {
      id: 'demo-veic-002',
      user_id: 'demo-usr-carro-02',
      empresa_id: '11111111-1111-1111-1111-111111111111',
      tipo_veiculo: 'carro',
      marca: 'Fiat',
      modelo: 'Fiorino 1.4 EVO',
      placa: 'BRA2E19',
      compartimento: null,
      volume_litros: null,
      tamanho_compartimento: null,
      capacidade_kg: null,
      status_analise: 'aprovado',
      revisao: 1,
    },
    motivo_decisao: 'Aprovado pelo gestor',
    decidido_por_nome: 'Gestor Logística (Demonstração)',
    decidido_em: new Date(Date.now() - 1000 * 60 * 60 * 24).toISOString(),
    created_at: new Date(Date.now() - 1000 * 60 * 60 * 30).toISOString(),
  },
  {
    id: 'demo-sol-003',
    empresa_id: '11111111-1111-1111-1111-111111111111',
    empresa_nome: 'EntregaCondo Matriz (Demonstração)',
    user_id: 'demo-usr-moto-03',
    usuario_nome: 'Condutor Demonstração 03 (Moto Mochila M)',
    usuario_email: 'condutor03.demo@entregacondo.com.br',
    papel_solicitado: 'motorista',
    status: 'aprovado',
    motorista_vinculado_id: '22222222-2222-2222-2222-222222222222',
    motorista_nome: 'Condutor Demonstração 03',
    motorista_veiculo: 'Honda CG 160 Fan',
    motorista_placa: 'QHX-4091',
    veiculo_declarado: {
      id: 'demo-veic-003',
      user_id: 'demo-usr-moto-03',
      empresa_id: '11111111-1111-1111-1111-111111111111',
      tipo_veiculo: 'moto',
      marca: 'Honda',
      modelo: 'CG 160 Fan',
      placa: 'QHX4091',
      compartimento: 'mochila',
      volume_litros: null,
      tamanho_compartimento: 'medio',
      capacidade_kg: 10,
      status_analise: 'aprovado',
      revisao: 1,
    },
    motivo_decisao: 'Aprovado pelo gestor',
    decidido_por_nome: 'Gestor Logística (Demonstração)',
    decidido_em: new Date(Date.now() - 1000 * 60 * 60 * 48).toISOString(),
    created_at: new Date(Date.now() - 1000 * 60 * 60 * 50).toISOString(),
  },
  {
    id: 'demo-sol-004',
    empresa_id: '11111111-1111-1111-1111-111111111111',
    empresa_nome: 'EntregaCondo Matriz (Demonstração)',
    user_id: 'demo-usr-invalido-04',
    usuario_nome: 'Condutor Demonstração 04 (Rejeitado)',
    usuario_email: 'condutor04.desconhecido@exemplo.com',
    papel_solicitado: 'motorista',
    status: 'rejeitado',
    motivo_decisao: 'Documento do veículo ilegível e condutor sem vínculo contratual ativo.',
    decidido_por_nome: 'Gestor Logística (Demonstração)',
    decidido_em: new Date(Date.now() - 1000 * 60 * 60 * 72).toISOString(),
    created_at: new Date(Date.now() - 1000 * 60 * 60 * 80).toISOString(),
  },
];

const MOTORISTAS_FROTA_DEMO: MotoristaFrotaItem[] = [
  {
    id: '22222222-2222-2222-2222-222222222221',
    empresa_id: '11111111-1111-1111-1111-111111111111',
    user_id: 'demo-usr-carro-02',
    nome: 'Frota Demo 01',
    telefone: '(48) 99123-4567',
    email: 'frota01@entregacondo.com.br',
    veiculo_modelo: 'Fiat Fiorino',
    veiculo_placa: 'BRA-2E19',
    status: 'disponivel',
    ativo: true,
  },
  {
    id: '22222222-2222-2222-2222-222222222222',
    empresa_id: '11111111-1111-1111-1111-111111111111',
    user_id: 'demo-usr-moto-03',
    nome: 'Frota Demo 02',
    telefone: '(48) 98877-6655',
    email: 'frota02@entregacondo.com.br',
    veiculo_modelo: 'Honda CG 160 Fan',
    veiculo_placa: 'QHX-4091',
    status: 'disponivel',
    ativo: true,
  },
  {
    id: '22222222-2222-2222-2222-222222222223',
    empresa_id: '11111111-1111-1111-1111-111111111111',
    user_id: null, // Disponível para vínculo
    nome: 'Frota Disponível (Sem Vínculo)',
    telefone: '(48) 99811-2233',
    email: 'frota03@entregacondo.com.br',
    veiculo_modelo: 'Yamaha Fazer 250',
    veiculo_placa: 'RLK-8120',
    status: 'disponivel',
    ativo: true,
  },
];

export function useAccessApprovals() {
  const [solicitacoes, setSolicitacoes] = useState<SolicitacaoAcessoItem[]>([]);
  const [motoristasDisponiveis, setMotoristasDisponiveis] = useState<MotoristaFrotaItem[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [alertaSucesso, setAlertaSucesso] = useState<string | null>(null);

  // Modo Demonstração explícito (desativado por padrão no modo real)
  const [modoDemo, setModoDemo] = useState(false);

  // Filtros
  const [filtroStatus, setFiltroStatus] = useState<FiltroStatusAcesso>('pendente');
  const [buscaTexto, setBuscaTexto] = useState('');

  const carregarDados = useCallback(async (isDemo = modoDemo) => {
    setCarregando(true);
    setErro(null);

    if (isDemo) {
      setSolicitacoes(MOCK_DEMONSTRACAO);
      setMotoristasDisponiveis(MOTORISTAS_FROTA_DEMO);
      setCarregando(false);
      return;
    }

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
  }, [modoDemo]);

  useEffect(() => {
    carregarDados();
  }, [carregarDados]);

  const alternarModoDemo = (ativar: boolean) => {
    setModoDemo(ativar);
    carregarDados(ativar);
  };

  // Ação de Aprovação
  const aprovar = async (params: ParametrosAprovacao) => {
    if (modoDemo) {
      setSolicitacoes((prev) =>
        prev.map((s) => (s.id === params.solicitacaoId ? { ...s, status: 'aprovado' } : s))
      );
      setAlertaSucesso('Condutor aprovado no modo demonstração.');
      return;
    }

    const res = await aprovarSolicitacaoMotorista(params);
    setAlertaSucesso(res.mensagem || 'Condutor aprovado com sucesso.');
    await carregarDados(false);
  };

  // Ação de Rejeição
  const rejeitar = async (solicitacaoId: string, motivo: string) => {
    if (modoDemo) {
      setSolicitacoes((prev) =>
        prev.map((s) => (s.id === solicitacaoId ? { ...s, status: 'rejeitado', motivo_decisao: motivo } : s))
      );
      setAlertaSucesso('Solicitação rejeitada no modo demonstração.');
      return;
    }

    const res = await rejeitarSolicitacaoAcesso(solicitacaoId, motivo);
    setAlertaSucesso(res.mensagem || 'Solicitação rejeitada com sucesso.');
    await carregarDados(false);
  };

  // Ação de Suspensão
  const suspender = async (membroId: string, motivo: string) => {
    if (modoDemo) {
      setSolicitacoes((prev) =>
        prev.map((s) => (s.id === membroId ? { ...s, status: 'suspenso', motivo_decisao: motivo } : s))
      );
      setAlertaSucesso('Acesso suspenso no modo demonstração.');
      return;
    }

    const res = await suspenderAcessoMembro(membroId, motivo);
    setAlertaSucesso(res.mensagem || 'Acesso suspenso preventivamente.');
    await carregarDados(false);
  };

  // Ação de Reativação
  const reativar = async (membroId: string) => {
    if (modoDemo) {
      setSolicitacoes((prev) =>
        prev.map((s) => (s.id === membroId ? { ...s, status: 'aprovado' } : s))
      );
      setAlertaSucesso('Acesso reativado no modo demonstração.');
      return;
    }

    const res = await reativarAcessoMembro(membroId);
    setAlertaSucesso(res.mensagem || 'Acesso reativado com sucesso.');
    await carregarDados(false);
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
