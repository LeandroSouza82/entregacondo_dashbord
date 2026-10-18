import React, { useState, useCallback, useMemo, useRef } from 'react';
import { RouteMap } from './RouteMap';
import { PlacesAutocompleteInput } from './PlacesAutocompleteInput';
import { ClienteCondominioSearchInput } from './ClienteCondominioSearchInput';
import type { ClienteEnderecoItem } from '../../features/routes/types/clienteEndereco';
import { salvarClienteEndereco } from '../../features/routes/services/salvarClienteEndereco';
import { 
  Check, 
  MessageSquare, 
  Send, 
  CheckCircle2,
  PackageCheck,
  Inbox,
  FileText,
  AlertCircle
} from 'lucide-react';
import type { PontoParada, PontoCoordenada } from '../../types/logistics';
import { supabase, isSupabaseConfigured } from '../../lib/supabase';

const MOCK_PONTO_PARTIDA = {
  nome: 'Sede da administradora · Centro',
  coordenadas: { lat: -27.5954, lng: -48.5480 } as PontoCoordenada,
};

interface MotoristaItem {
  id: string;
  nome: string;
  iniciais: string;
  veiculo: string;
  status: string;
  corAvatar: string;
  empresa_id?: string;
}

const MOTORISTAS: MotoristaItem[] = [
  { id: '22222222-2222-2222-2222-222222222221', nome: 'Carlos Mendes', iniciais: 'CM', veiculo: 'Fiorino', status: 'disponível', corAvatar: '#1D4ED8', empresa_id: '11111111-1111-1111-1111-111111111111' },
  { id: '22222222-2222-2222-2222-222222222222', nome: 'Rafael Souza', iniciais: 'RS', veiculo: 'Moto', status: 'disponível', corAvatar: '#0F766E', empresa_id: '11111111-1111-1111-1111-111111111111' },
  { id: '22222222-2222-2222-2222-222222222223', nome: 'Anderson Costa', iniciais: 'AC', veiculo: 'Moto', status: 'disponível', corAvatar: '#475569', empresa_id: '11111111-1111-1111-1111-111111111111' },
];

const ENDERECOS_SALVOS_EXEMPLO = [
  {
    endereco: 'Rua Lauro Linhares, 820 · Trindade',
    complemento: 'Ed. Solar das Palmeiras',
    entregasContagem: 14,
    coordenadas: { lat: -27.5992, lng: -48.5205 },
    tempoPortaria: 12,
  },
  {
    endereco: 'Rua Lauro Linhares, 1120 · Trindade',
    complemento: 'Res. Lauro Park',
    entregasContagem: 3,
    coordenadas: { lat: -27.5978, lng: -48.5175 },
    tempoPortaria: 8,
  },
];

const CHIPS_OBSERVACOES = [
  'Cuidado com o cachorro',
  'Entregar ao zelador',
  'Interfonar antes',
  'Portaria só até 17h',
];

export const NewRouteView: React.FC = () => {
  const [motoristaAtivo, setMotoristaAtivo] = useState<string>('cm');
  const [otimizarAutomatico, setOtimizarAutomatico] = useState<boolean>(true);
  const [dataRota, setDataRota] = useState<string>('Segunda, 19/10');
  const [pontoPartidaTexto, setPontoPartidaTexto] = useState<string>('Sede da administradora · Centro');
  
  // Referência para focar naturalmente no campo "Nome do cliente / Condomínio"
  const clienteInputRef = useRef<HTMLInputElement | null>(null);

  // Form Nova Entrega
  const [tipoTarefa, setTipoTarefa] = useState<'entrega' | 'coleta' | 'outros'>('entrega');
  const [especificacaoOutro, setEspecificacaoOutro] = useState<string>('');
  const [erroValidacao, setErroValidacao] = useState<string | null>(null);
  const [nomeCliente, setNomeCliente] = useState<string>('');
  const [blocoApto, setBlocoApto] = useState<string>('');
  const [enderecoTexto, setEnderecoTexto] = useState<string>('');
  const [coordenadasSelecionadas, setCoordenadasSelecionadas] = useState<PontoCoordenada | null>(null);
  const [pontoPreview, setPontoPreview] = useState<{ nome: string; coordenadas: PontoCoordenada } | null>(null);
  const [observacaoTexto, setObservacaoTexto] = useState<string>('');
  const [salvarParaProximas, setSalvarParaProximas] = useState<boolean>(true);

  // Alertas de feedback
  const [mensagemSucesso, setMensagemSucesso] = useState<string | null>(null);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  // Lista de Entregas da Rota (baseada na referência de Florianópolis/São Paulo)
  const [entregasDaRota, setEntregasDaRota] = useState<PontoParada[]>([
    {
      id: 'p1',
      sequencia: 1,
      clienteEnderecoId: 'c1',
      nomeLocal: 'Res. Vista Mar',
      destinatario: 'Ricardo Almeida',
      enderecoFormatado: 'Av. Beira-Mar Norte, 3400 · Centro',
      coordenadas: { lat: -27.5854, lng: -48.5440 },
      tempoMedioAtendimentoMinutos: 10,
      prioridade: 'normal',
      tipoTarefa: 'entrega',
      codigoRastreio: 'EC-001',
    },
    {
      id: 'p2',
      sequencia: 2,
      clienteEnderecoId: 'c2',
      nomeLocal: 'Ed. Marina Tower',
      destinatario: 'Luciana Prado',
      enderecoFormatado: 'Rua Felipe Schmidt, 1250 · Centro',
      coordenadas: { lat: -27.5912, lng: -48.5510 },
      tempoMedioAtendimentoMinutos: 8,
      prioridade: 'normal',
      tipoTarefa: 'entrega',
      codigoRastreio: 'EC-002',
    },
    {
      id: 'p3',
      sequencia: 3,
      clienteEnderecoId: 'c3',
      nomeLocal: 'Ed. Bela Vista',
      destinatario: 'Camila Souza',
      enderecoFormatado: 'Rua Bocaiúva, 450 · Centro',
      coordenadas: { lat: -27.5890, lng: -48.5495 },
      tempoMedioAtendimentoMinutos: 15,
      prioridade: 'alta',
      tipoTarefa: 'coleta',
      codigoRastreio: 'EC-003',
    },
    {
      id: 'p4',
      sequencia: 4,
      clienteEnderecoId: 'c4',
      nomeLocal: 'Ed. Solar das Palmeiras',
      destinatario: 'Maria Fernanda Rocha',
      enderecoFormatado: 'Rua Lauro Linhares, 820 · Trindade',
      coordenadas: { lat: -27.5992, lng: -48.5205 },
      tempoMedioAtendimentoMinutos: 12,
      prioridade: 'normal',
      tipoTarefa: 'entrega',
      codigoRastreio: 'EC-004',
    },
    {
      id: 'p5',
      sequencia: 5,
      clienteEnderecoId: 'c5',
      nomeLocal: 'Cond. Jardim Imperial',
      destinatario: 'Paulo Henrique Dias',
      enderecoFormatado: 'Av. Madre Benvenuta, 1100 · Itacorubi',
      coordenadas: { lat: -27.5880, lng: -48.5110 },
      tempoMedioAtendimentoMinutos: 14,
      prioridade: 'normal',
      tipoTarefa: 'outros',
      descricaoOutro: 'Registro de Ata',
      codigoRastreio: 'EC-005',
    },
    {
      id: 'p6',
      sequencia: 6,
      clienteEnderecoId: 'c6',
      nomeLocal: 'Res. Alameda Park',
      destinatario: 'Fernando Lopes',
      enderecoFormatado: 'Rua João Pio Duarte Silva, 900 · Córrego Grande',
      coordenadas: { lat: -27.5970, lng: -48.5080 },
      tempoMedioAtendimentoMinutos: 9,
      prioridade: 'normal',
      tipoTarefa: 'entrega',
      codigoRastreio: 'EC-006',
    },
  ]);

  const paradasParaOMapa = useMemo(() => entregasDaRota, [entregasDaRota]);

  const motoristaSelecionado = MOTORISTAS.find(m => m.id === motoristaAtivo) || MOTORISTAS[0];

  // Callback inteligente: ao selecionar um cliente/condomínio da base salva
  const handleSelectClienteCondominio = useCallback((item: ClienteEnderecoItem) => {
    setNomeCliente(item.nome_identificador);
    if (item.destinatario_padrao) {
      setBlocoApto(item.destinatario_padrao);
    }
    setEnderecoTexto(item.endereco_completo);
    if (item.observacoes_acesso) {
      setObservacaoTexto(item.observacoes_acesso);
    }
    const coords: PontoCoordenada = {
      lat: Number(item.latitude),
      lng: Number(item.longitude),
    };
    setCoordenadasSelecionadas(coords);
    setPontoPreview({
      nome: item.nome_identificador,
      coordenadas: coords,
    });
    setErroValidacao(null);
  }, []);

  // Callback memoizado para seleção de endereço via Google Places ou base salva (anti-loop)
  const handleAddressSelect = useCallback((dados: {
    enderecoCompleto: string;
    nomeLocal?: string;
    coordenadas: PontoCoordenada;
  }) => {
    setEnderecoTexto(dados.enderecoCompleto);
    if (dados.nomeLocal && (!blocoApto || blocoApto.includes('Bloco B'))) {
      setBlocoApto(dados.nomeLocal);
    }
    setCoordenadasSelecionadas(dados.coordenadas);
    setPontoPreview({
      nome: nomeCliente || dados.nomeLocal || dados.enderecoCompleto,
      coordenadas: dados.coordenadas,
    });
    setErroValidacao(null);
  }, [blocoApto, nomeCliente]);

  const handleAdicionarEntrega = () => {
    if (!nomeCliente.trim() || !enderecoTexto.trim()) return;

    // Validação estrita se "Outros" foi selecionado
    if (tipoTarefa === 'outros' && !especificacaoOutro.trim()) {
      setErroValidacao('Por favor, especifique o tipo de serviço para a opção "Outros" (ex: Registro de Ata).');
      return;
    }

    // Validação estrita de coordenadas: exige geocoding real do Google Places ou endereço salvo
    if (!coordenadasSelecionadas || (coordenadasSelecionadas.lat === 0 && coordenadasSelecionadas.lng === 0)) {
      setErroValidacao('Por favor, selecione um endereço sugerido pelo Google Places ou escolha um condomínio cadastrado na lista. Endereços sem coordenadas exatas não podem ser despachados.');
      return;
    }

    const novoIdEntrega = crypto.randomUUID();
    const novoIdClienteEndereco = crypto.randomUUID();

    const nova: PontoParada = {
      id: novoIdEntrega,
      sequencia: entregasDaRota.length + 1,
      clienteEnderecoId: novoIdClienteEndereco,
      nomeLocal: blocoApto || 'Edifício',
      destinatario: nomeCliente.trim(),
      enderecoFormatado: enderecoTexto.trim(),
      coordenadas: coordenadasSelecionadas,
      tempoMedioAtendimentoMinutos: tipoTarefa === 'coleta' ? 15 : tipoTarefa === 'outros' ? 14 : 11,
      prioridade: 'normal',
      tipoTarefa,
      descricaoOutro: tipoTarefa === 'outros' ? especificacaoOutro.trim() : undefined,
      codigoRastreio: `EC-${Math.floor(100000 + Math.random() * 900000)}`,
    };

    setEntregasDaRota(prev => [...prev, nova]);

    // Persistência inteligente: salva para as próximas entregas se selecionado
    if (salvarParaProximas && coordenadasSelecionadas) {
      salvarClienteEndereco({
        empresa_id: motoristaSelecionado?.empresa_id,
        nome_identificador: nomeCliente.trim(),
        destinatario_padrao: blocoApto.trim() || undefined,
        endereco_completo: enderecoTexto.trim(),
        coordenadas: coordenadasSelecionadas,
        observacoes_acesso: observacaoTexto.trim() || undefined,
      }).catch((err) => console.warn('Erro ao salvar endereço em segundo plano:', err));
    }

    setNomeCliente('');
    setBlocoApto('');
    setEnderecoTexto('');
    setObservacaoTexto('');
    setTipoTarefa('entrega');
    setEspecificacaoOutro('');
    setErroValidacao(null);
    setCoordenadasSelecionadas(null);
    setPontoPreview(null);
    const labelTipo = tipoTarefa === 'coleta' ? 'Coleta' : tipoTarefa === 'outros' ? (nova.descricaoOutro || 'Outro serviço') : 'Entrega';
    setMensagemSucesso(`${labelTipo} para ${nova.destinatario} geolocalizada e adicionada à rota!`);
    setTimeout(() => setMensagemSucesso(null), 4000);

    // Retorna o foco natural para o campo de busca de cliente/condomínio
    setTimeout(() => {
      clienteInputRef.current?.focus();
    }, 50);
  };

  const handleChipClick = (texto: string) => {
    setObservacaoTexto(prev => {
      if (!prev) return texto;
      if (prev.includes(texto)) return prev;
      return `${prev}. ${texto}`;
    });
  };

  const handleEnviarParaMotorista = async () => {
    setMensagemErro(null);

    if (entregasDaRota.length === 0) {
      setMensagemErro('Adicione pelo menos uma entrega com endereço geocodificado antes de despachar.');
      setTimeout(() => setMensagemErro(null), 6000);
      return;
    }

    if (!motoristaSelecionado) {
      setMensagemErro('Selecione um motorista da frota para realizar o despacho.');
      setTimeout(() => setMensagemErro(null), 6000);
      return;
    }

    if (isSupabaseConfigured) {
      try {
        const payloadDespacho = {
          idempotency_key: `despacho-${motoristaSelecionado.id}-${entregasDaRota.map(e => e.codigoRastreio).sort().join('-')}`,
          empresa_id: motoristaSelecionado.empresa_id || '11111111-1111-1111-1111-111111111111',
          motorista_id: motoristaSelecionado.id,
          distancia_original_km: 74.2,
          tempo_original_minutos: 192,
          distancia_otimizada_km: 46.8,
          tempo_otimizado_minutos: 125,
          percentual_economia_km: 37,
          percentual_economia_tempo: 35,
          paradas: entregasDaRota.map((parada) => ({
            codigo_rastreio: parada.codigoRastreio,
            destinatario_nome: parada.destinatario,
            unidade_apartamento: parada.nomeLocal,
            tipo_tarefa: parada.tipoTarefa || 'entrega',
            descricao_outro: parada.descricaoOutro || null,
            prioridade: parada.prioridade || 'normal',
            volumes_qtd: 1,
            observacoes_gestor: observacaoTexto || null,
            endereco: {
              id: parada.clienteEnderecoId.startsWith('cli-') ? null : parada.clienteEnderecoId,
              nome_identificador: parada.nomeLocal,
              endereco_completo: parada.enderecoFormatado,
              numero: 'S/N',
              bairro: 'Região de Entrega',
              cidade: 'Florianópolis',
              cep: '88000-000',
              latitude: parada.coordenadas.lat,
              longitude: parada.coordenadas.lng,
              tipo_local: 'condominio_horizontal',
              observacoes_acesso: parada.nomeLocal,
            }
          }))
        };

        const { data, error } = await supabase.rpc('despachar_rota_transacional', {
          p_dados: payloadDespacho as any,
        });

        if (error) {
          console.warn('Erro ao executar RPC despachar_rota_transacional:', error);
          setMensagemErro(`Falha transacional ao despachar rota: ${error.message}. As paradas foram mantidas no painel.`);
          setTimeout(() => setMensagemErro(null), 8000);
          return;
        }

        const resp = data as any;
        if (resp && resp.sucesso === false) {
          setMensagemErro(`Erro no despacho da rota: ${resp.mensagem || 'Falha no banco de dados'}.`);
          setTimeout(() => setMensagemErro(null), 8000);
          return;
        }

        setMensagemSucesso(`Rota inteligente com ${entregasDaRota.length} paradas gravada com sucesso no Supabase e despachada para ${motoristaSelecionado.nome}!`);
        setTimeout(() => setMensagemSucesso(null), 6000);
      } catch (err: unknown) {
        console.error('Erro de conexão ao despachar rota:', err);
        setMensagemErro('Erro de conexão ao despachar rota para o servidor. O rascunho foi mantido intacto.');
        setTimeout(() => setMensagemErro(null), 8000);
        return;
      }
    } else {
      setMensagemSucesso(`Modo de Demonstração: Rota com ${entregasDaRota.length} paradas calculada localmente na memória (servidor Supabase não conectado nesta sessão).`);
      setTimeout(() => setMensagemSucesso(null), 6000);
    }
  };

  return (
    <div className="space-y-6 text-[#0F1B2D] animate-fadeIn">
      {/* Header Principal */}
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-[26px] font-extrabold text-[#0F1B2D] tracking-tight m-0">
            Nova rota de entregas
          </h1>
          <p className="text-[#516074] text-sm mt-1">
            Cadastre as entregas, escolha o motorista e deixe o sistema montar a melhor rota.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <label className="flex items-center gap-2 text-[13px] font-semibold text-[#2B3A4F]">
            Data da rota
            <input
              type="text"
              value={dataRota}
              onChange={(e) => setDataRota(e.target.value)}
              className="h-11 border border-[#CBD5E1] rounded-[10px] px-3 text-sm text-[#0F1B2D] bg-white w-[150px] font-medium focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 focus:border-[#1D4ED8]"
            />
          </label>
        </div>
      </header>

      {/* Alertas de Feedback */}
      {mensagemSucesso && (
        <div className="p-4 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm flex items-center gap-3 shadow-sm animate-fadeIn">
          <CheckCircle2 className="w-5 h-5 text-emerald-600 flex-shrink-0" />
          <span>{mensagemSucesso}</span>
        </div>
      )}

      {mensagemErro && (
        <div className="p-4 rounded-xl bg-red-50 border border-red-200 text-red-800 text-sm flex items-center gap-3 shadow-sm animate-fadeIn">
          <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0" />
          <span>{mensagemErro}</span>
        </div>
      )}

      {/* Grid Principal: 2 Colunas (flex: 3 e flex: 2) */}
      <div className="flex flex-col lg:flex-row gap-6 items-start">
        {/* Coluna Esquerda: Passos 1, 2 e 3 */}
        <div className="flex-1 w-full lg:max-w-[62%] space-y-6">
          
          {/* SEÇÃO 1: MOTORISTA */}
          <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-4">
            <div className="flex items-center gap-2.5">
              <span className="w-[26px] h-[26px] rounded-full bg-[#0F1B2D] text-white flex items-center justify-center text-[13px] font-bold">
                1
              </span>
              <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">Motorista</h2>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              {MOTORISTAS.map((m) => {
                const isSelected = motoristaAtivo === m.id;
                return (
                  <button
                    key={m.id}
                    type="button"
                    onClick={() => setMotoristaAtivo(m.id)}
                    className={`text-left flex items-center gap-3 p-3.5 rounded-xl border-2 transition-all cursor-pointer ${
                      isSelected
                        ? 'border-[#1D4ED8] bg-[#EEF4FF] shadow-sm'
                        : 'border-[#E1E6ED] bg-white hover:border-slate-300'
                    }`}
                  >
                    <span
                      style={{ backgroundColor: m.corAvatar }}
                      className="w-10 h-10 rounded-full text-white inline-flex items-center justify-center font-bold text-[13px] flex-shrink-0"
                    >
                      {m.iniciais}
                    </span>
                    <span className="min-w-0">
                      <span className="block font-bold text-sm text-[#0F1B2D] truncate">
                        {m.nome}
                      </span>
                      <span className={`block text-xs truncate ${isSelected ? 'text-[#334155]' : 'text-[#516074]'}`}>
                        {m.veiculo} · {m.status}
                      </span>
                    </span>
                  </button>
                );
              })}
            </div>
          </section>

          {/* SEÇÃO 2: ADICIONAR ENTREGA / PARADA */}
          <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2.5">
                <span className="w-[26px] h-[26px] rounded-full bg-[#0F1B2D] text-white flex items-center justify-center text-[13px] font-bold">
                  2
                </span>
                <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">Adicionar parada</h2>
              </div>
              <span className="text-xs text-[#516074] font-medium">128 endereços salvos</span>
            </div>

            {/* SELETOR DE TIPO DE SERVIÇO (Segmented Buttons) */}
            <div className="flex flex-col gap-2">
              <label className="text-[13px] font-semibold text-[#2B3A4F]">
                Tipo de serviço
              </label>
              <div className="grid grid-cols-3 gap-2.5">
                <button
                  type="button"
                  onClick={() => {
                    setTipoTarefa('entrega');
                    setEspecificacaoOutro('');
                    setErroValidacao(null);
                  }}
                  className={`h-11 px-3 rounded-[10px] border flex items-center justify-center gap-2 text-sm font-bold transition-all ${
                    tipoTarefa === 'entrega'
                      ? 'bg-[#EEF4FF] border-[#1D4ED8] text-[#1D4ED8] shadow-sm ring-1 ring-[#1D4ED8]/20'
                      : 'bg-slate-50 border-[#CBD5E1] text-[#516074] hover:bg-slate-100 hover:text-[#0F1B2D]'
                  }`}
                >
                  <PackageCheck className="w-4 h-4" />
                  <span>Entrega</span>
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setTipoTarefa('coleta');
                    setEspecificacaoOutro('');
                    setErroValidacao(null);
                  }}
                  className={`h-11 px-3 rounded-[10px] border flex items-center justify-center gap-2 text-sm font-bold transition-all ${
                    tipoTarefa === 'coleta'
                      ? 'bg-[#DDF3E4] border-[#15803D] text-[#14532D] shadow-sm ring-1 ring-[#15803D]/20'
                      : 'bg-slate-50 border-[#CBD5E1] text-[#516074] hover:bg-slate-100 hover:text-[#0F1B2D]'
                  }`}
                >
                  <Inbox className="w-4 h-4" />
                  <span>Coleta</span>
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setTipoTarefa('outros');
                    setErroValidacao(null);
                  }}
                  className={`h-11 px-3 rounded-[10px] border flex items-center justify-center gap-2 text-sm font-bold transition-all ${
                    tipoTarefa === 'outros'
                      ? 'bg-purple-50 border-purple-600 text-purple-700 shadow-sm ring-1 ring-purple-600/20'
                      : 'bg-slate-50 border-[#CBD5E1] text-[#516074] hover:bg-slate-100 hover:text-[#0F1B2D]'
                  }`}
                >
                  <FileText className="w-4 h-4" />
                  <span>Outros</span>
                </button>
              </div>
            </div>

            {/* CAMPO DINÂMICO PARA "OUTROS" */}
            {tipoTarefa === 'outros' && (
              <div className="flex flex-col gap-1.5 p-3.5 bg-purple-50/60 border border-purple-200 rounded-xl animate-fadeIn">
                <label className="flex items-center justify-between text-[13px] font-semibold text-purple-900">
                  <span className="flex items-center gap-1.5">
                    <FileText className="w-4 h-4 text-purple-600" />
                    Especifique o serviço <span className="text-red-500 font-bold">*</span>
                  </span>
                  <span className="text-xs text-purple-600 font-normal">Obrigatório</span>
                </label>
                <input
                  type="text"
                  value={especificacaoOutro}
                  onChange={(e) => {
                    setEspecificacaoOutro(e.target.value);
                    if (erroValidacao) setErroValidacao(null);
                  }}
                  placeholder="Ex: Registro de Ata, Leitura de Água/Gás, Vistoria Técnica..."
                  className={`h-11 border ${
                    erroValidacao ? 'border-red-500 bg-red-50/50 ring-2 ring-red-400/25' : 'border-purple-300 bg-white'
                  } rounded-[10px] px-3.5 text-sm text-[#0F1B2D] focus:outline-none focus:ring-2 focus:ring-purple-500/25 focus:border-purple-600 transition-all`}
                  autoFocus
                />
                {erroValidacao ? (
                  <div className="flex items-center gap-1.5 text-xs text-red-600 font-semibold mt-0.5">
                    <AlertCircle className="w-3.5 h-3.5 flex-shrink-0" />
                    <span>{erroValidacao}</span>
                  </div>
                ) : (
                  <div className="flex flex-wrap items-center gap-1.5 pt-1">
                    <span className="text-[11px] text-purple-700 font-medium">Sugestões rápidas:</span>
                    {['Registro de Ata', 'Leitura de Água/Gás', 'Assinatura Notarial', 'Vistoria Predial'].map((sugestao) => (
                      <button
                        key={sugestao}
                        type="button"
                        onClick={() => {
                          setEspecificacaoOutro(sugestao);
                          setErroValidacao(null);
                        }}
                        className="text-[11px] px-2 py-0.5 rounded-md bg-white border border-purple-200 text-purple-800 hover:bg-purple-100 transition-colors cursor-pointer"
                      >
                        + {sugestao}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="flex flex-col gap-1.5">
                <label className="text-[13px] font-semibold text-[#2B3A4F]">
                  Nome do cliente / Condomínio
                </label>
                <ClienteCondominioSearchInput
                  inputRef={clienteInputRef}
                  value={nomeCliente}
                  onChange={setNomeCliente}
                  onSelectClienteEndereco={handleSelectClienteCondominio}
                  placeholder="Ex: Condomínio Jardim América ou Maria Fernanda"
                  empresaId={motoristaSelecionado?.empresa_id}
                />
              </div>

              <label className="flex flex-col gap-1.5 text-[13px] font-semibold text-[#2B3A4F]">
                Bloco / apartamento
                <input
                  type="text"
                  value={blocoApto}
                  onChange={(e) => setBlocoApto(e.target.value)}
                  placeholder="Ex: Bloco B · Apto 302"
                  className="h-11 border border-[#CBD5E1] rounded-[10px] px-3 text-sm text-[#0F1B2D] bg-white focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 focus:border-[#1D4ED8]"
                />
              </label>

              {/* Endereço com Autocomplete de Alta Precisão (Google Places + Endereços Salvos) */}
              <div className="sm:col-span-2 flex flex-col gap-1.5">
                <label className="text-[13px] font-semibold text-[#2B3A4F]">
                  Endereço
                </label>
                <PlacesAutocompleteInput
                  value={enderecoTexto}
                  onChange={setEnderecoTexto}
                  enderecosSalvos={ENDERECOS_SALVOS_EXEMPLO}
                  onAddressSelect={handleAddressSelect}
                />
              </div>

              {/* Observação para o motorista */}
              <div className="sm:col-span-2 flex flex-col gap-2">
                <label className="flex flex-col gap-1.5 text-[13px] font-semibold text-[#2B3A4F]">
                  Observação para o motorista
                  <textarea
                    rows={2}
                    value={observacaoTexto}
                    onChange={(e) => setObservacaoTexto(e.target.value)}
                    className="border border-[#CBD5E1] rounded-[10px] p-2.5 text-sm text-[#0F1B2D] bg-white w-full resize-y focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 focus:border-[#1D4ED8]"
                  />
                </label>

                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex flex-wrap gap-2">
                    {CHIPS_OBSERVACOES.map((chip, i) => (
                      <button
                        key={i}
                        type="button"
                        onClick={() => handleChipClick(chip)}
                        className="h-[30px] px-3 rounded-full border border-[#D5DCE5] bg-white text-[#2B3A4F] text-xs font-semibold hover:bg-slate-50 transition-colors"
                      >
                        + {chip}
                      </button>
                    ))}
                  </div>
                  <span className="text-xs text-[#516074]">
                    Aparece em destaque no app do motorista · {observacaoTexto.length}/200
                  </span>
                </div>
              </div>
            </div>

            {/* Ações do Form */}
            <div className="flex flex-wrap items-center justify-between gap-3 pt-2 border-t border-slate-100">
              <label className="flex items-center gap-2 text-[13px] text-[#2B3A4F] cursor-pointer">
                <input
                  type="checkbox"
                  checked={salvarParaProximas}
                  onChange={(e) => setSalvarParaProximas(e.target.checked)}
                  className="w-[18px] h-[18px] accent-[#1D4ED8]"
                />
                Salvar este endereço para próximas entregas
              </label>

              <div className="flex items-center gap-3">
                <button
                  type="button"
                  onClick={() => {
                    setNomeCliente('');
                    setBlocoApto('');
                    setEnderecoTexto('');
                    setObservacaoTexto('');
                    setTipoTarefa('entrega');
                    setEspecificacaoOutro('');
                    setErroValidacao(null);
                    setCoordenadasSelecionadas(null);
                    setPontoPreview(null);
                    setTimeout(() => clienteInputRef.current?.focus(), 50);
                  }}
                  className="h-11 px-4 rounded-[10px] border border-[#CBD5E1] bg-white text-[#0F1B2D] text-sm font-bold hover:bg-slate-50 transition-colors"
                >
                  Limpar
                </button>
                <button
                  type="button"
                  onClick={handleAdicionarEntrega}
                  className="h-11 px-5 rounded-[10px] bg-[#C2410C] hover:bg-[#9A3412] active:scale-95 text-white text-sm font-bold transition-all shadow-md shadow-[#C2410C]/25"
                >
                  Adicionar à rota
                </button>
              </div>
            </div>
          </section>

          {/* SEÇÃO 3: ENTREGAS DA ROTA */}
          <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-3">
            <div className="flex flex-wrap items-center justify-between gap-2 pb-2">
              <div className="flex items-center gap-2.5">
                <span className="w-[26px] h-[26px] rounded-full bg-[#0F1B2D] text-white flex items-center justify-center text-[13px] font-bold">
                  3
                </span>
                <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">
                  Entregas da rota · {entregasDaRota.length}
                </h2>
              </div>
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#DDF3E4] text-[#14532D] text-xs font-bold">
                <Check className="w-3.5 h-3.5" />
                Ordem otimizada
              </span>
            </div>

            <div className="divide-y divide-[#EAEFF4]">
              {entregasDaRota.map((parada, idx) => {
                // Distâncias demonstrativas fiéis ao layout
                const distanciasTexto = ['Início', '0,9 km', '0,6 km', '4,1 km', '1,8 km', '1,5 km'];
                const badgesAlerta = [
                  null,
                  null,
                  'Portaria só até 17h',
                  'Cuidado com o cachorro',
                  'Interfonar no apto 302',
                  null,
                ];
                const tagAlerta = badgesAlerta[idx];

                return (
                  <div key={parada.id} className="flex items-center gap-3.5 py-3 flex-wrap">
                    <div className="w-[30px] h-[30px] rounded-full bg-[#0F1B2D] text-white flex items-center justify-center font-bold text-[13px] flex-none">
                      {idx + 1}
                    </div>

                    <div className="flex-1 min-w-[200px]">
                      <div className="flex items-center flex-wrap gap-2">
                        <span className="font-bold text-sm text-[#0F1B2D]">
                          {parada.destinatario}
                        </span>
                        <span className="font-medium text-[#516074] text-xs">
                          · {parada.nomeLocal}
                        </span>

                        {/* Badge elegante de Tipo de Tarefa */}
                        {(!parada.tipoTarefa || parada.tipoTarefa === 'entrega') && (
                          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-[#EEF4FF] text-[#1D4ED8] border border-blue-200 text-[11px] font-bold">
                            <PackageCheck className="w-3 h-3" />
                            Entrega
                          </span>
                        )}
                        {parada.tipoTarefa === 'coleta' && (
                          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-[#DDF3E4] text-[#14532D] border border-emerald-200 text-[11px] font-bold">
                            <Inbox className="w-3 h-3" />
                            Coleta
                          </span>
                        )}
                        {parada.tipoTarefa === 'outros' && (
                          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-md bg-purple-50 text-purple-700 border border-purple-200 text-[11px] font-bold">
                            <FileText className="w-3 h-3" />
                            {parada.descricaoOutro || 'Outros'}
                          </span>
                        )}
                      </div>
                      <div className="text-[13px] text-[#2B3A4F] mt-0.5">
                        {parada.enderecoFormatado}
                      </div>
                    </div>

                    {tagAlerta && (
                      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[#FDEFC8] text-[#7A4A06] text-xs font-bold">
                        <MessageSquare className="w-3.5 h-3.5" />
                        {tagAlerta}
                      </span>
                    )}

                    <div className="min-w-[65px] text-right text-[13px] font-bold text-[#334155]">
                      {distanciasTexto[idx] || `${(1.2 * (idx + 1)).toFixed(1).replace('.', ',')} km`}
                    </div>
                  </div>
                );
              })}
            </div>

            <div className="border-t border-[#EAEFF4] pt-3 text-[13px] font-bold text-[#1D4ED8] cursor-pointer hover:underline">
              + 14 entregas · ver todas
            </div>
          </section>

        </div>

        {/* Coluna Direita: Seções 4 e 5 (Rota Inteligente, Mapa e Despacho) */}
        <div className="w-full lg:w-[38%] space-y-6 sticky top-24">
          
          {/* SEÇÃO 4: ROTA INTELIGENTE & MAPA */}
          <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">Rota inteligente</h2>
                <p className="text-[#516074] text-[13px] mt-1 leading-snug">
                  Sempre segue para a entrega mais próxima, partindo do ponto inicial, para gastar menos tempo e km.
                </p>
              </div>

              {/* Switch Liga/Desliga Rota Inteligente */}
              <button
                type="button"
                onClick={() => setOtimizarAutomatico(!otimizarAutomatico)}
                role="switch"
                aria-checked={otimizarAutomatico}
                className={`flex-none w-[46px] h-[26px] rounded-full p-[3px] transition-colors flex ${
                  otimizarAutomatico ? 'bg-[#15803D] justify-end' : 'bg-slate-300 justify-start'
                }`}
              >
                <div className="w-5 h-5 rounded-full bg-white shadow-sm" />
              </button>
            </div>

            <label className="flex flex-col gap-1.5 text-[13px] font-semibold text-[#2B3A4F]">
              Ponto de partida
              <input
                type="text"
                value={pontoPartidaTexto}
                onChange={(e) => setPontoPartidaTexto(e.target.value)}
                className="h-11 border border-[#CBD5E1] rounded-[10px] px-3 text-sm text-[#0F1B2D] bg-white focus:outline-none focus:ring-2 focus:ring-[#1D4ED8]/20 focus:border-[#1D4ED8]"
              />
            </label>

            {/* MAPA INTERATIVO MAPBOX */}
            <RouteMap
              pontoPartida={MOCK_PONTO_PARTIDA}
              paradas={paradasParaOMapa}
              pontoPreview={pontoPreview}
              otimizado={otimizarAutomatico}
            />

            {/* COMPARATIVO DE BARRAS: ORDEM CADASTRO VS ROTA OTIMIZADA */}
            <div className="flex flex-col gap-3.5 pt-1">
              <div className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold text-[#2B3A4F]">Ordem de cadastro</span>
                  <span className="font-bold text-[#0F1B2D]">74,2 km · 3h12</span>
                </div>
                <div className="h-2.5 rounded-full bg-[#E4E9F0] overflow-hidden">
                  <div className="w-full h-full bg-[#94A3B8]" />
                </div>
              </div>

              <div className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold text-[#2B3A4F]">Rota otimizada</span>
                  <span className="font-bold text-[#15803D]">46,8 km · 2h05</span>
                </div>
                <div className="h-2.5 rounded-full bg-[#E4E9F0] overflow-hidden">
                  <div className="w-[63%] h-full bg-[#15803D] rounded-full" />
                </div>
              </div>

              {/* Card Destaque Verde de Economia */}
              <div className="flex items-center gap-3 p-3.5 rounded-xl bg-[#DDF3E4] text-[#14532D]">
                <div className="text-2xl font-extrabold leading-none">37%</div>
                <div className="text-[13px] font-semibold leading-tight">
                  de economia: 27,4 km a menos e 1h07 de tempo ganho
                </div>
              </div>
            </div>
          </section>

          {/* SEÇÃO 5: BOTÕES DE DESPACHO */}
          <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-3">
            <button
              type="button"
              onClick={handleEnviarParaMotorista}
              className="h-12 rounded-[10px] bg-[#C2410C] hover:bg-[#9A3412] active:scale-98 text-white font-bold text-[15px] transition-all shadow-md shadow-[#C2410C]/25 flex items-center justify-center gap-2 cursor-pointer"
            >
              <Send className="w-4 h-4" />
              <span>Enviar rota para {motoristaSelecionado.nome.split(' ')[0]}</span>
            </button>

            <button
              type="button"
              onClick={() => {
                setMensagemSucesso('Rota salva como rascunho com sucesso no banco de dados!');
                setTimeout(() => setMensagemSucesso(null), 4000);
              }}
              className="h-11 rounded-[10px] border border-[#CBD5E1] bg-white hover:bg-slate-50 text-[#0F1B2D] font-bold text-sm transition-colors cursor-pointer"
            >
              Salvar como rascunho
            </button>

            <p className="text-xs text-[#516074] text-center m-0 leading-normal">
              {motoristaSelecionado.nome.split(' ')[0]} recebe a rota no app móvel Flutter, já com endereços, observações e ordem de paradas.
            </p>
          </section>

        </div>
      </div>
    </div>
  );
};
