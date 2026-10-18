import { requireCompanyId } from '../../lib/company';
import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
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
  AlertCircle,
  ChevronDown,
  X
} from 'lucide-react';
import { BalanceteSelectorPopover } from './BalanceteSelectorPopover';
import { DocumentosSelectorPopover } from './DocumentosSelectorPopover';
import { 
  obterChipsCustomizados, 
  salvarChipCustomizado, 
  removerChipCustomizado 
} from '../../features/routes/services/chipsCustomizadosStorage';
import type { PontoParada, PontoCoordenada } from '../../types/logistics';
import { supabase, isSupabaseConfigured } from '../../lib/supabase';

const MAP_CENTER = { nome: 'Centro do mapa', coordenadas: { lat: -27.5954, lng: -48.5480 } as PontoCoordenada };

interface MotoristaItem {
  id: string;
  nome: string;
  iniciais: string;
  veiculo: string;
  status: string;
  corAvatar: string;
  empresa_id?: string;
}





const CHIPS_OBSERVACOES = [
  'Documentos',
  'Balancete',
  'Interfonar antes',
  'Portaria só até às 17h',
];

export const NewRouteView: React.FC = () => {
  const [motoristaAtivo, setMotoristaAtivo] = useState<string>('');
  const [otimizarAutomatico] = useState<boolean>(false);
  const [dataRota, setDataRota] = useState<string>(() => new Date().toLocaleDateString('pt-BR'));
  const [pontoPartidaTexto, setPontoPartidaTexto] = useState<string>('');
  
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
  const [isBalanceteOpen, setIsBalanceteOpen] = useState<boolean>(false);
  const [isDocumentosOpen, setIsDocumentosOpen] = useState<boolean>(false);
  const [chipsCustomizados, setChipsCustomizados] = useState<string[]>(() => obterChipsCustomizados());

  // Alertas de feedback
  const [mensagemSucesso, setMensagemSucesso] = useState<string | null>(null);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  // Lista de Entregas da Rota (baseada na referência de Florianópolis/São Paulo)
  const [entregasDaRota, setEntregasDaRota] = useState<PontoParada[]>([]);

  const paradasParaOMapa = useMemo(() => entregasDaRota, [entregasDaRota]);

  const [MOTORISTAS, setMotoristas] = useState<MotoristaItem[]>([]);
  const [empresaId, setEmpresaId] = useState('');
  const [despachando, setDespachando] = useState(false);
  const despachoKey = useRef(crypto.randomUUID());
  useEffect(() => {
    let active = true;
    void requireCompanyId().then(async id => {
      const { data, error } = await supabase.from('motoristas').select('*').eq('empresa_id', id).eq('ativo', true);
      if (error) throw error;
      if (active) { setEmpresaId(id); setMotoristas((data || []).map(m => ({ id: m.id, nome: m.nome, iniciais: m.nome.split(' ').map(n => n[0]).slice(0, 2).join(''), veiculo: m.veiculo_modelo, status: m.status, corAvatar: '#0F1B2D', empresa_id: m.empresa_id }))); }
    }).catch((e: Error) => { if (active) setMensagemErro(e.message); });
    return () => { active = false; };
  }, []);
  const motoristaSelecionado = MOTORISTAS.find(m => m.id === motoristaAtivo);

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

  const handleAdicionarEntrega = async () => {
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



    // Memória inteligente: se "outros" foi especificado, salva o termo como chip permanente
    if (tipoTarefa === 'outros' && especificacaoOutro.trim()) {
      setChipsCustomizados(salvarChipCustomizado(especificacaoOutro.trim()));
    }

    // Persistência inteligente: salva para as próximas entregas se selecionado
    if (salvarParaProximas && coordenadasSelecionadas) {
      try {
      const saved = await salvarClienteEndereco({
        empresa_id: empresaId,
        nome_identificador: nomeCliente.trim(),
        destinatario_padrao: blocoApto.trim() || undefined,
        endereco_completo: enderecoTexto.trim(),
        coordenadas: coordenadasSelecionadas,
        observacoes_acesso: observacaoTexto.trim() || undefined,
      });
      nova.clienteEnderecoId = saved.id;
      } catch (e) { setMensagemErro(e instanceof Error ? e.message : 'Não foi possível salvar o endereço.'); return; }
    }

    setEntregasDaRota(prev => [...prev, nova]);
    despachoKey.current = crypto.randomUUID();
    setNomeCliente('');
    setBlocoApto('');
    setEnderecoTexto('');
    setObservacaoTexto('');
    setTipoTarefa('entrega');
    setEspecificacaoOutro('');
    setErroValidacao(null);
    setCoordenadasSelecionadas(null);
    setPontoPreview(null);
    setIsBalanceteOpen(false);
    setIsDocumentosOpen(false);
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

  const handleSelectBalancete = (mesAno: string) => {
    const texto = `Balancete referente ao ${mesAno.toLowerCase()}`;
    setObservacaoTexto(prev => {
      if (!prev) return texto;
      if (prev.includes(texto)) return prev;
      return `${prev}. ${texto}`;
    });
  };

  const handleSelectDocumento = (nomeDocumento: string) => {
    const texto = nomeDocumento;
    setObservacaoTexto(prev => {
      if (!prev) return texto;
      if (prev.includes(texto)) return prev;
      return `${prev}. ${texto}`;
    });

    // Se for um item personalizado, grava automaticamente na memória de chips
    const ehPadrao = [
      'edital de convocação',
      'registro de ata',
      'prestação de contas',
      'convenção / regimento interno',
      'boletos',
      'documentos',
      'outros documentos',
    ].includes(nomeDocumento.toLowerCase());

    if (!ehPadrao) {
      setChipsCustomizados(salvarChipCustomizado(nomeDocumento));
    }
  };

  const handleEnviarParaMotorista = async () => {
    if (despachando) return;
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

    if (entregasDaRota.some(p => !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(p.clienteEnderecoId))) {
      setMensagemErro('Salve os endereços no banco antes de despachar. Ative a opção de salvar para próximas entregas.'); return;
    }
    if (isSupabaseConfigured) {
      setDespachando(true);
      try {
        const payloadDespacho = {
          idempotency_key: despachoKey.current,
          empresa_id: empresaId,
          motorista_id: motoristaSelecionado.id,
          distancia_original_km: 0,
          tempo_original_minutos: 0,
          distancia_otimizada_km: 0,
          tempo_otimizado_minutos: 0,
          percentual_economia_km: 0,
          percentual_economia_tempo: 0,
          paradas: entregasDaRota.map((parada) => ({
            cliente_endereco_id: /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(parada.clienteEnderecoId) ? parada.clienteEnderecoId : null,
            ordem_na_rota: parada.sequencia,
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
        if (!resp || resp.sucesso !== true) {
          setMensagemErro(`Erro no despacho da rota: ${resp?.mensagem || 'Falha no banco de dados'}.`);
          setTimeout(() => setMensagemErro(null), 8000);
          return;
        }

        setMensagemSucesso(`Rota inteligente com ${entregasDaRota.length} paradas gravada com sucesso no Supabase e despachada para ${motoristaSelecionado.nome}!`);
        setEntregasDaRota([]); despachoKey.current = crypto.randomUUID();
        setTimeout(() => setMensagemSucesso(null), 6000);
      } catch (err: unknown) {
        console.error('Erro de conexão ao despachar rota:', err);
        setMensagemErro('Erro de conexão ao despachar rota para o servidor. O rascunho foi mantido intacto.');
        setTimeout(() => setMensagemErro(null), 8000);
        return;
      } finally { setDespachando(false); }
    } else {
      setMensagemErro('Conexão não configurada. A rota não foi enviada.');
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
              <span className="text-xs text-[#516074] font-medium">Endereços da empresa</span>
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
                  empresaId={empresaId}
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
                  enderecosSalvos={[]}
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
                  <div className="flex flex-wrap items-center gap-2">
                    {CHIPS_OBSERVACOES.map((chip, i) => {
                      if (chip === 'Documentos') {
                        return (
                          <div key={i} className="relative">
                            <button
                              type="button"
                              onClick={() => {
                                setIsDocumentosOpen(prev => !prev);
                                setIsBalanceteOpen(false);
                              }}
                              className={`h-[30px] px-3 rounded-full border text-xs font-semibold transition-all flex items-center gap-1.5 cursor-pointer ${
                                isDocumentosOpen
                                  ? 'bg-blue-50 border-[#1D4ED8] text-[#1D4ED8] ring-2 ring-[#1D4ED8]/20 shadow-xs'
                                  : 'border-[#D5DCE5] bg-white text-[#2B3A4F] hover:bg-slate-50'
                              }`}
                            >
                              <span>+ Documentos</span>
                              <ChevronDown
                                className={`w-3.5 h-3.5 text-slate-400 transition-transform duration-150 ${
                                  isDocumentosOpen ? 'rotate-180 text-[#1D4ED8]' : ''
                                }`}
                              />
                            </button>

                            {isDocumentosOpen && (
                              <DocumentosSelectorPopover
                                onClose={() => setIsDocumentosOpen(false)}
                                onSelect={(docNome) => {
                                  handleSelectDocumento(docNome);
                                  setIsDocumentosOpen(false);
                                }}
                              />
                            )}
                          </div>
                        );
                      }

                      if (chip === 'Balancete') {
                        return (
                          <div key={i} className="relative">
                            <button
                              type="button"
                              onClick={() => {
                                setIsBalanceteOpen(prev => !prev);
                                setIsDocumentosOpen(false);
                              }}
                              className={`h-[30px] px-3 rounded-full border text-xs font-semibold transition-all flex items-center gap-1.5 cursor-pointer ${
                                isBalanceteOpen
                                  ? 'bg-blue-50 border-[#1D4ED8] text-[#1D4ED8] ring-2 ring-[#1D4ED8]/20 shadow-xs'
                                  : 'border-[#D5DCE5] bg-white text-[#2B3A4F] hover:bg-slate-50'
                              }`}
                            >
                              <span>+ Balancete</span>
                              <ChevronDown
                                className={`w-3.5 h-3.5 text-slate-400 transition-transform duration-150 ${
                                  isBalanceteOpen ? 'rotate-180 text-[#1D4ED8]' : ''
                                }`}
                              />
                            </button>

                            {isBalanceteOpen && (
                              <BalanceteSelectorPopover
                                onClose={() => setIsBalanceteOpen(false)}
                                onSelect={(mesAno) => {
                                  handleSelectBalancete(mesAno);
                                  setIsBalanceteOpen(false);
                                }}
                              />
                            )}
                          </div>
                        );
                      }

                      return (
                        <button
                          key={i}
                          type="button"
                          onClick={() => handleChipClick(chip)}
                          className="h-[30px] px-3 rounded-full border border-[#D5DCE5] bg-white text-[#2B3A4F] text-xs font-semibold hover:bg-slate-50 transition-colors cursor-pointer"
                        >
                          + {chip}
                        </button>
                      );
                    })}

                    {/* Chips Personalizados Salvos na Memória Inteligente */}
                    {chipsCustomizados.map((customChip) => (
                      <div
                        key={customChip}
                        className="group inline-flex items-center h-[30px] rounded-full border border-purple-200 bg-purple-50 hover:bg-purple-100/90 text-purple-900 text-xs font-semibold transition-all shadow-2xs"
                      >
                        <button
                          type="button"
                          onClick={() => handleChipClick(customChip)}
                          className="pl-2.5 pr-1 py-1 flex items-center gap-1 cursor-pointer hover:text-purple-950"
                          title={`Inserir "${customChip}" na observação`}
                        >
                          <span className="text-purple-600 font-bold">+</span>
                          <span>{customChip}</span>
                        </button>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            setChipsCustomizados(removerChipCustomizado(customChip));
                          }}
                          className="pr-2 pl-0.5 py-1 text-purple-400 hover:text-red-600 transition-colors cursor-pointer rounded-r-full"
                          title={`Remover "${customChip}" dos atalhos salvos`}
                        >
                          <X className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    ))}
                  </div>

                  <div className="flex items-center gap-2">
                    {observacaoTexto.trim().length >= 3 && 
                     observacaoTexto.trim().length <= 35 &&
                     !CHIPS_OBSERVACOES.some(c => c.toLowerCase() === observacaoTexto.trim().toLowerCase()) &&
                     !chipsCustomizados.some(c => c.toLowerCase() === observacaoTexto.trim().toLowerCase()) && (
                      <button
                        type="button"
                        onClick={() => {
                          setChipsCustomizados(salvarChipCustomizado(observacaoTexto.trim()));
                        }}
                        className="text-xs text-purple-700 font-bold hover:text-purple-900 bg-purple-50 hover:bg-purple-100 border border-purple-200 px-2 py-0.5 rounded-md transition-colors cursor-pointer"
                        title="Salvar esta observação como atalho permanente"
                      >
                        + Salvar como atalho
                      </button>
                    )}
                    <span className="text-xs text-[#516074]">
                      Aparece em destaque no app do motorista · {observacaoTexto.length}/200
                    </span>
                  </div>
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
                    setIsBalanceteOpen(false);
                    setIsDocumentosOpen(false);
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
                Ordem de cadastro
              </span>
            </div>

            <div className="divide-y divide-[#EAEFF4]">
              {entregasDaRota.map((parada, idx) => {
                const tagAlerta = null;

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
                      {'—'}
                    </div>
                  </div>
                );
              })}
            </div>

            <div className="border-t border-[#EAEFF4] pt-3 text-[13px] font-bold text-[#1D4ED8] cursor-pointer hover:underline">
              Fim da lista
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
                  Prévia dos endereços. Distância e tempo de trajeto ainda não calculados.
                </p>
              </div>

              {/* Switch Liga/Desliga Rota Inteligente */}
              <button
                type="button"
                disabled aria-label="Otimização de trajeto ainda indisponível"
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
              pontoPartida={MAP_CENTER}
              paradas={paradasParaOMapa}
              pontoPreview={pontoPreview}
              otimizado={otimizarAutomatico}
            />

            {/* COMPARATIVO DE BARRAS: ORDEM CADASTRO VS ROTA OTIMIZADA */}
            <div className="flex flex-col gap-3.5 pt-1">
              <div className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold text-[#2B3A4F]">Ordem de cadastro</span>
                  <span className="font-bold text-[#0F1B2D]">Não calculado</span>
                </div>
                <div className="h-2.5 rounded-full bg-[#E4E9F0] overflow-hidden">
                  <div className="w-full h-full bg-[#94A3B8]" />
                </div>
              </div>

              <div className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold text-[#2B3A4F]">Rota otimizada</span>
                  <span className="font-bold text-[#15803D]">Não calculado</span>
                </div>
                <div className="h-2.5 rounded-full bg-[#E4E9F0] overflow-hidden">
                  <div className="w-0 h-full bg-[#15803D] rounded-full" />
                </div>
              </div>

              {/* Card Destaque Verde de Economia */}
              <div className="flex items-center gap-3 p-3.5 rounded-xl bg-[#DDF3E4] text-[#14532D]">
                <div className="text-2xl font-extrabold leading-none">—</div>
                <div className="text-[13px] font-semibold leading-tight">
                  Economia ainda não calculada
                </div>
              </div>
            </div>
          </section>

          {/* SEÇÃO 5: BOTÕES DE DESPACHO */}
          <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-3">
            <button
              type="button"
              disabled={despachando || !motoristaSelecionado} onClick={handleEnviarParaMotorista}
              className="h-12 rounded-[10px] bg-[#C2410C] hover:bg-[#9A3412] active:scale-98 text-white font-bold text-[15px] transition-all shadow-md shadow-[#C2410C]/25 flex items-center justify-center gap-2 cursor-pointer"
            >
              <Send className="w-4 h-4" />
              <span>Enviar rota para {motoristaSelecionado?.nome.split(' ')[0] || 'o motorista'}</span>
            </button>

            <button
              type="button"
              onClick={() => { setMensagemErro('O rascunho fica nesta tela até o envio. Ainda não há salvamento de rascunho de rota.'); }}
              className="h-11 rounded-[10px] border border-[#CBD5E1] bg-white hover:bg-slate-50 text-[#0F1B2D] font-bold text-sm transition-colors cursor-pointer"
            >
              Salvar como rascunho
            </button>

            <p className="text-xs text-[#516074] text-center m-0 leading-normal">
              {motoristaSelecionado?.nome.split(' ')[0] || 'o motorista'} recebe a rota no app móvel Flutter, já com endereços, observações e ordem de paradas.
            </p>
          </section>

        </div>
      </div>
    </div>
  );
};
