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
  X,
  MapPin,
  Sparkles,
  BookmarkCheck,
  Trash2
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
import {
  obterPontoPartidaPadrao,
  salvarPontoPartidaPadrao,
  geocodificarEndereco,
  otimizarSequenciaERota,
  formatarTempoMinutos,
  type PontoPartidaItem,
  type MetricasRota,
} from '../../features/routes/services/routeOptimization';

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

const STORAGE_KEY_ROTA_RASCUNHO = 'ec_draft_current_route';

export interface RotaRascunho {
  motoristaAtivo: string;
  entregasDaRota: PontoParada[];
  observacaoTexto: string;
  otimizarAutomatico: boolean;
  pontoPartida?: PontoPartidaItem;
  pontoPartidaTexto?: string;
  timestamp: number;
}

export function obterRascunhoRota(): RotaRascunho | null {
  if (typeof window === 'undefined' || !window.localStorage) return null;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY_ROTA_RASCUNHO);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (parsed && Array.isArray(parsed.entregasDaRota)) {
      return parsed;
    }
  } catch (e) {
    console.warn('[NewRouteView] Falha ao recuperar rascunho da rota:', e);
  }
  return null;
}

export function salvarRascunhoRota(rascunho: RotaRascunho): void {
  if (typeof window === 'undefined' || !window.localStorage) return;
  try {
    window.localStorage.setItem(STORAGE_KEY_ROTA_RASCUNHO, JSON.stringify(rascunho));
  } catch (e) {
    console.warn('[NewRouteView] Falha ao salvar rascunho da rota:', e);
  }
}

export function limparRascunhoRota(): void {
  if (typeof window === 'undefined' || !window.localStorage) return;
  try {
    window.localStorage.removeItem(STORAGE_KEY_ROTA_RASCUNHO);
  } catch (e) {
    console.warn('[NewRouteView] Falha ao limpar rascunho da rota:', e);
  }
}

export const NewRouteView: React.FC = () => {
  // Carrega rascunho persistido para evitar perda de dados ao alternar de aba
  const rascunhoInicial = useMemo(() => obterRascunhoRota(), []);

  const [motoristaAtivo, setMotoristaAtivo] = useState<string>(() => rascunhoInicial?.motoristaAtivo || '');
  const [otimizarAutomatico, setOtimizarAutomatico] = useState<boolean>(() => 
    typeof rascunhoInicial?.otimizarAutomatico === 'boolean' ? rascunhoInicial.otimizarAutomatico : true
  );
  const [dataRota, setDataRota] = useState<string>(() => new Date().toLocaleDateString('pt-BR'));
  const [empresaId, setEmpresaId] = useState<string>('');
  
  // Ponto de partida inicializado com a preferência persistida da empresa ou rascunho
  const [pontoPartida, setPontoPartida] = useState<PontoPartidaItem>(() => {
    if (rascunhoInicial?.pontoPartida?.coordenadas) {
      return rascunhoInicial.pontoPartida;
    }
    return obterPontoPartidaPadrao();
  });
  const [pontoPartidaTexto, setPontoPartidaTexto] = useState<string>(() => {
    if (rascunhoInicial?.pontoPartidaTexto) {
      return rascunhoInicial.pontoPartidaTexto;
    }
    const padrao = obterPontoPartidaPadrao();
    return padrao.endereco || padrao.nome;
  });
  const [isPadraoFixado, setIsPadraoFixado] = useState<boolean>(true);

  // Carregamento inicial inteligente: garante que o padrão fixado seja imediatamente recuperado
  useEffect(() => {
    if (!rascunhoInicial?.pontoPartida) {
      const salvo = obterPontoPartidaPadrao();
      if (salvo && salvo.coordenadas && salvo.endereco) {
        setPontoPartida(salvo);
        setPontoPartidaTexto(salvo.endereco || salvo.nome);
        setIsPadraoFixado(true);
      }
    }
  }, [rascunhoInicial]);
  
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
  const [observacaoTexto, setObservacaoTexto] = useState<string>(() => rascunhoInicial?.observacaoTexto || '');
  const [salvarParaProximas, setSalvarParaProximas] = useState<boolean>(true);
  const [isBalanceteOpen, setIsBalanceteOpen] = useState<boolean>(false);
  const [isDocumentosOpen, setIsDocumentosOpen] = useState<boolean>(false);
  const [chipsCustomizados, setChipsCustomizados] = useState<string[]>(() => obterChipsCustomizados());

  // Alertas de feedback
  const [mensagemSucesso, setMensagemSucesso] = useState<string | null>(null);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  // Lista de Entregas da Rota com restauração instantânea do rascunho
  const [entregasDaRota, setEntregasDaRota] = useState<PontoParada[]>(() => rascunhoInicial?.entregasDaRota || []);

  // Auto-Save do Rascunho da Rota em localStorage a cada alteração
  useEffect(() => {
    if (entregasDaRota.length > 0 || observacaoTexto.trim()) {
      salvarRascunhoRota({
        motoristaAtivo,
        entregasDaRota,
        observacaoTexto,
        otimizarAutomatico,
        pontoPartida,
        pontoPartidaTexto,
        timestamp: Date.now(),
      });
    }
  }, [entregasDaRota, motoristaAtivo, observacaoTexto, otimizarAutomatico, pontoPartida, pontoPartidaTexto]);

  const handleLimparRascunho = useCallback(() => {
    limparRascunhoRota();
    setEntregasDaRota([]);
    setObservacaoTexto('');
    setMensagemSucesso('Rascunho da rota limpo com sucesso.');
    setTimeout(() => setMensagemSucesso(null), 3000);
  }, []);

  const handleRemoverParada = useCallback((id: string) => {
    setEntregasDaRota(prev => {
      const novaLista = prev.filter(p => p.id !== id);
      if (novaLista.length === 0) {
        limparRascunhoRota();
      }
      return novaLista;
    });
  }, []);

  // Cálculo inteligente de trajeto e métricas (Ordem de cadastro vs Rota Otimizada)
  const metricasRota = useMemo<MetricasRota>(() => {
    return otimizarSequenciaERota(pontoPartida, entregasDaRota);
  }, [pontoPartida, entregasDaRota]);

  // Lista de paradas a renderizar no mapa: ordenada pela melhor sequência se otimização estiver ativa
  const paradasParaOMapa = useMemo(() => {
    if (otimizarAutomatico && metricasRota.paradasOtimizadas.length > 0) {
      return metricasRota.paradasOtimizadas;
    }
    return entregasDaRota;
  }, [otimizarAutomatico, metricasRota.paradasOtimizadas, entregasDaRota]);

  const handleFixarPontoPartidaPadrao = useCallback(async () => {
    const textoDigitado = pontoPartidaTexto.trim();
    if (!textoDigitado) {
      setMensagemErro('Digite um endereço para o ponto de partida.');
      setTimeout(() => setMensagemErro(null), 3000);
      return;
    }

    let coordsFinais = pontoPartida.coordenadas;
    let nomeFinal = pontoPartida.nome;
    let enderecoFinal = textoDigitado;

    // Se o texto digitado difere do endereço atualmente gravado no pontoPartida,
    // ou se as coordenadas atuais ainda são as do Centro de Florianópolis enquanto o texto é outro (ex: Palhoça):
    const precisaGeocodificar =
      textoDigitado !== pontoPartida.endereco.trim() ||
      !coordsFinais ||
      (coordsFinais.lat === -27.5954 && coordsFinais.lng === -48.5480 && !textoDigitado.toLowerCase().includes('centro'));

    if (precisaGeocodificar) {
      try {
        const geo = await geocodificarEndereco(textoDigitado);
        if (geo && geo.coordenadas) {
          coordsFinais = geo.coordenadas;
          nomeFinal = geo.nome || textoDigitado.split(',')[0].trim();
          enderecoFinal = geo.endereco || textoDigitado;
        }
      } catch (err) {
        console.warn('Falha na geocodificação ao fixar:', err);
      }
    }

    const pontoAtualizado: PontoPartidaItem = {
      nome: nomeFinal,
      endereco: enderecoFinal,
      lat: coordsFinais.lat,
      lng: coordsFinais.lng,
      coordenadas: coordsFinais,
    };

    // 1. Atualiza estado do componente e do input com os dados exatos resolvidos
    setPontoPartida(pontoAtualizado);
    setPontoPartidaTexto(enderecoFinal);
    setIsPadraoFixado(true);

    // 2. Gravação definitiva no localStorage garantindo persistência sem latência
    salvarPontoPartidaPadrao(pontoAtualizado);
    setMensagemSucesso(`Sede e ponto de partida "${pontoAtualizado.nome}" fixado com sucesso!`);
    setTimeout(() => setMensagemSucesso(null), 4000);

    // 3. Atualização em segundo plano na empresa se aplicável
    if (empresaId) {
      void supabase
        .from('empresas')
        .update({
          cidade: enderecoFinal.split(',').pop()?.trim() || 'Palhoça',
        })
        .eq('id', empresaId);
    }
  }, [pontoPartida, pontoPartidaTexto, empresaId]);

  const [MOTORISTAS, setMotoristas] = useState<MotoristaItem[]>([]);
  const [despachando, setDespachando] = useState(false);
  const despachoKey = useRef(crypto.randomUUID());
  useEffect(() => {
    let active = true;
    void requireCompanyId().then(async id => {
      const { data } = await supabase.from('motoristas').select('*').eq('empresa_id', id).eq('ativo', true);
      if (active) {
        setEmpresaId(id);
        const mapped = (data || []).map(m => ({
          id: m.id,
          nome: m.nome,
          iniciais: m.nome.split(' ').map((n: string) => n[0]).slice(0, 2).join(''),
          veiculo: m.veiculo_modelo || 'Moto Padrão',
          status: m.status || 'Disponível',
          corAvatar: '#0F1B2D',
          empresa_id: m.empresa_id
        }));

        setMotoristas(mapped);
        setMotoristaAtivo(prev => prev || mapped[0]?.id || '');
      }
    }).catch((e: Error) => {
      if (active) {
        console.warn('Erro ao carregar motoristas:', e);
        setMotoristas([]);
        setMotoristaAtivo('');
      }
    });
    return () => { active = false; };
  }, []);
  const motoristaSelecionado = MOTORISTAS.find(m => m.id === motoristaAtivo);

  // Callback inteligente: ao selecionar um cliente/condomínio da base salva (0 chamadas de API)
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
    setMensagemSucesso(`"${item.nome_identificador}" carregado do banco local (sem custo de API).`);
    setTimeout(() => setMensagemSucesso(null), 3500);
  }, []);

  // Callback inteligente: ao selecionar um local do Google Places pelo campo de condomínio -> Auto-persiste no banco
  const handleSelectGooglePlace = useCallback((dados: {
    nome: string;
    endereco: string;
    coordenadas: PontoCoordenada;
  }) => {
    setNomeCliente(dados.nome);
    setEnderecoTexto(dados.endereco);
    setCoordenadasSelecionadas(dados.coordenadas);
    setPontoPreview({
      nome: dados.nome,
      coordenadas: dados.coordenadas,
    });
    setErroValidacao(null);

    // GRAVAÇÃO IMEDIATA NO SUPABASE (Criação de base própria e cache definitivo)
    if (empresaId && dados.coordenadas && dados.endereco) {
      void salvarClienteEndereco({
        empresa_id: empresaId,
        nome_identificador: dados.nome,
        destinatario_padrao: blocoApto.trim() || undefined,
        endereco_completo: dados.endereco,
        coordenadas: dados.coordenadas,
      }).then(() => {
        setMensagemSucesso(`"${dados.nome}" geocodificado pelo Google Places e gravado na base de dados da empresa.`);
        setTimeout(() => setMensagemSucesso(null), 4000);
      }).catch((e) => {
        console.warn('Persistência automática em background:', e);
      });
    }
  }, [blocoApto, empresaId]);

  // Callback memoizado para seleção de endereço via Google Places ou base salva -> Auto-persiste no banco
  const handleAddressSelect = useCallback((dados: {
    enderecoCompleto: string;
    nomeLocal?: string;
    coordenadas: PontoCoordenada;
  }) => {
    setEnderecoTexto(dados.enderecoCompleto);
    const nomeFinal = nomeCliente.trim() || dados.nomeLocal || dados.enderecoCompleto.split(',')[0].trim();
    if (!nomeCliente.trim() && dados.nomeLocal) {
      setNomeCliente(dados.nomeLocal);
    }
    if (dados.nomeLocal && (!blocoApto || blocoApto.includes('Bloco B'))) {
      setBlocoApto(dados.nomeLocal);
    }
    setCoordenadasSelecionadas(dados.coordenadas);
    setPontoPreview({
      nome: nomeFinal,
      coordenadas: dados.coordenadas,
    });
    setErroValidacao(null);

    // GRAVAÇÃO IMEDIATA NO SUPABASE (Garante que todo endereço buscado fique na base própria)
    if (empresaId && dados.coordenadas && dados.enderecoCompleto) {
      void salvarClienteEndereco({
        empresa_id: empresaId,
        nome_identificador: nomeFinal,
        destinatario_padrao: blocoApto.trim() || undefined,
        endereco_completo: dados.enderecoCompleto,
        coordenadas: dados.coordenadas,
        observacoes_acesso: observacaoTexto.trim() || undefined,
      }).then(() => {
        setMensagemSucesso(`Local "${nomeFinal}" gravado na base da empresa para futuras entregas.`);
        setTimeout(() => setMensagemSucesso(null), 4000);
      }).catch((e) => {
        console.warn('Persistência automática de endereço em background:', e);
      });
    }
  }, [blocoApto, empresaId, nomeCliente, observacaoTexto]);

  const handleAdicionarEntrega = async () => {
    const nomeFinal = nomeCliente.trim() || blocoApto.trim() || enderecoTexto.trim().split(',')[0].trim();
    if (!nomeFinal) {
      setErroValidacao('Nome do cliente ou condomínio é obrigatório.');
      return;
    }

    if (!enderecoTexto.trim()) {
      setErroValidacao('Endereço é obrigatório.');
      return;
    }

    // Validação estrita se "Outros" foi selecionado
    if (tipoTarefa === 'outros' && !especificacaoOutro.trim()) {
      setErroValidacao('Por favor, especifique o tipo de serviço para a opção "Outros" (ex: Registro de Ata).');
      return;
    }

    // Validação de coordenadas com fallback suave para Florianópolis se necessário
    let coords = coordenadasSelecionadas;
    if (!coords || (coords.lat === 0 && coords.lng === 0)) {
      coords = {
        lat: -27.5954 + (Math.random() - 0.5) * 0.03,
        lng: -48.5480 + (Math.random() - 0.5) * 0.03,
      };
      setCoordenadasSelecionadas(coords);
    }

    const novoIdEntrega = crypto.randomUUID();
    const novoIdClienteEndereco = crypto.randomUUID();

    const nova: PontoParada = {
      id: novoIdEntrega,
      sequencia: entregasDaRota.length + 1,
      clienteEnderecoId: novoIdClienteEndereco,
      nomeLocal: blocoApto || 'Edifício',
      destinatario: nomeFinal,
      enderecoFormatado: enderecoTexto.trim(),
      coordenadas: coords,
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
    if (salvarParaProximas && coords) {
      try {
        const saved = await salvarClienteEndereco({
          empresa_id: empresaId,
          nome_identificador: nomeFinal,
          destinatario_padrao: blocoApto.trim() || undefined,
          endereco_completo: enderecoTexto.trim(),
          coordenadas: coords,
          observacoes_acesso: observacaoTexto.trim() || undefined,
        });
        if (saved?.id) {
          nova.clienteEnderecoId = saved.id;
        }
      } catch (e) {
        console.warn('Persistência opcional no Supabase falhou (mantendo parada na rota):', e);
      }
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
          distancia_original_km: metricasRota.distanciaOriginalKm,
          tempo_original_minutos: metricasRota.tempoOriginalMinutos,
          distancia_otimizada_km: metricasRota.distanciaOtimizadaKm,
          tempo_otimizado_minutos: metricasRota.tempoOtimizadoMinutos,
          percentual_economia_km: metricasRota.percentualEconomiaKm,
          percentual_economia_tempo: metricasRota.percentualEconomiaTempo,
          ordem_paradas_json: paradasParaOMapa.map((p, idx) => ({
            sequencia: idx + 1,
            id: p.id,
            cliente_endereco_id: p.clienteEnderecoId,
            destinatario: p.destinatario,
            nome_local: p.nomeLocal,
            endereco_formatado: p.enderecoFormatado,
            coordenadas: p.coordenadas,
            tipo_tarefa: p.tipoTarefa,
          })),
          paradas: paradasParaOMapa.map((parada, idx) => ({
            cliente_endereco_id: /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(parada.clienteEnderecoId) ? parada.clienteEnderecoId : null,
            ordem_na_rota: idx + 1,
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
        limparRascunhoRota();
        setEntregasDaRota([]);
        despachoKey.current = crypto.randomUUID();

        // Salva cache de última rota despachada para sincronizar instantaneamente com a Visão Geral
        if (typeof window !== 'undefined' && window.localStorage) {
          window.localStorage.setItem('ec_last_dispatched_route', JSON.stringify({
            pontoPartida,
            paradas: paradasParaOMapa,
            distanciaOtimizadaKm: metricasRota.distanciaOtimizadaKm,
            tempoOtimizadoMinutos: metricasRota.tempoOtimizadoMinutos,
            motoristaNome: motoristaSelecionado.nome,
            timestamp: Date.now(),
          }));
        }
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
              name="data_rota_ec"
              autoComplete="off"
              spellCheck={false}
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
                  name="especificacao_outro_ec"
                  autoComplete="off"
                  spellCheck={false}
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
                  onSelectGooglePlace={handleSelectGooglePlace}
                  placeholder="Ex: Condomínio Jardim América ou Maria Fernanda"
                  empresaId={empresaId}
                />
              </div>

              <label className="flex flex-col gap-1.5 text-[13px] font-semibold text-[#2B3A4F]">
                Bloco / apartamento
                <input
                  type="text"
                  name="bloco_apartamento_ec"
                  autoComplete="off"
                  spellCheck={false}
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
                  empresaId={empresaId}
                  onAddressSelect={handleAddressSelect}
                />
              </div>

              {/* Observação para o motorista */}
              <div className="sm:col-span-2 flex flex-col gap-2">
                <label className="flex flex-col gap-1.5 text-[13px] font-semibold text-[#2B3A4F]">
                  Observação para o motorista
                  <textarea
                    rows={2}
                    name="observacao_motorista_ec"
                    autoComplete="off"
                    spellCheck={false}
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
                  Entregas da rota · {paradasParaOMapa.length}
                </h2>
              </div>
              <div className="flex items-center gap-2">
                {entregasDaRota.length > 0 && (
                  <>
                    <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-emerald-700 bg-emerald-50 px-2.5 py-0.5 rounded-full border border-emerald-200">
                      <Check className="w-3 h-3 text-emerald-600" />
                      Rascunho salvo
                    </span>
                    <button
                      type="button"
                      data-testid="btn-limpar-rascunho"
                      onClick={handleLimparRascunho}
                      className="inline-flex items-center gap-1 text-[11px] font-semibold text-slate-500 hover:text-red-600 px-2 py-0.5 rounded hover:bg-red-50 transition-colors cursor-pointer"
                      title="Limpar rascunho de paradas"
                    >
                      <Trash2 className="w-3 h-3" />
                      Limpar rascunho
                    </button>
                  </>
                )}
                <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold ${
                  otimizarAutomatico && metricasRota.paradasOtimizadas.length > 0
                    ? 'bg-blue-50 text-blue-700 border border-blue-200'
                    : 'bg-[#DDF3E4] text-[#14532D]'
                }`}>
                  {otimizarAutomatico && metricasRota.paradasOtimizadas.length > 0 ? (
                    <>
                      <Sparkles className="w-3.5 h-3.5 text-blue-600" />
                      Sequência Otimizada (Rota Inteligente)
                    </>
                  ) : (
                    <>
                      <Check className="w-3.5 h-3.5" />
                      Ordem de cadastro
                    </>
                  )}
                </span>
              </div>
            </div>

            {paradasParaOMapa.length === 0 ? (
              <div className="py-8 text-center text-xs text-slate-400 font-medium">
                Nenhuma parada adicionada ainda. Busque um condomínio acima para adicionar.
              </div>
            ) : (
              <div className="divide-y divide-[#EAEFF4]">
                {paradasParaOMapa.map((parada, idx) => {
                  const tagAlerta = null;

                  return (
                    <div key={parada.id} className="flex items-center gap-3.5 py-3 flex-wrap">
                      <div className={`w-[30px] h-[30px] rounded-full ${
                        otimizarAutomatico ? 'bg-[#1D4ED8]' : 'bg-[#0F1B2D]'
                      } text-white flex items-center justify-center font-bold text-[13px] flex-none shadow-sm`}>
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

                      <div className="flex items-center gap-2.5 min-w-[85px] justify-end text-[13px] font-bold text-[#334155]">
                        <span>⏱ {parada.tempoMedioAtendimentoMinutos || 11} min</span>
                        <button
                          type="button"
                          onClick={() => handleRemoverParada(parada.id)}
                          className="p-1 rounded text-slate-400 hover:text-red-600 hover:bg-red-50 transition-colors cursor-pointer"
                          title="Remover esta parada da rota"
                        >
                          <X className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

            <div className="border-t border-[#EAEFF4] pt-3 text-[13px] font-bold text-[#1D4ED8]">
              {paradasParaOMapa.length > 0 ? `Total: ${paradasParaOMapa.length} parada(s)` : 'Aguardando cadastro de paradas'}
            </div>
          </section>

        </div>

        {/* Coluna Direita: Seções 4 e 5 (Rota Inteligente, Mapa e Despacho) */}
        <div className="w-full lg:w-[38%] space-y-6 sticky top-24">
          
          {/* SEÇÃO 4: ROTA INTELIGENTE & MAPA */}
          <section className="bg-white border border-[#E1E6ED] rounded-2xl p-5 shadow-card flex flex-col gap-4">
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="flex items-center gap-2">
                  <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">Rota inteligente</h2>
                  <span className={`text-[11px] font-extrabold px-2 py-0.5 rounded-md ${
                    otimizarAutomatico ? 'bg-emerald-100 text-emerald-800' : 'bg-slate-100 text-slate-600'
                  }`}>
                    {otimizarAutomatico ? 'Ativada' : 'Ordem Manual'}
                  </span>
                </div>
                <p className="text-[#516074] text-[13px] mt-1 leading-snug">
                  {otimizarAutomatico
                    ? 'Sequenciamento inteligente de paradas para menor distância e tempo.'
                    : 'Seguindo a sequência de cadastro sem otimização de trajeto.'}
                </p>
              </div>

              {/* Switch Liga/Desliga Rota Inteligente */}
              <button
                type="button"
                onClick={() => setOtimizarAutomatico(prev => !prev)}
                role="switch"
                aria-checked={otimizarAutomatico}
                title={otimizarAutomatico ? 'Clique para desativar a otimização de rota' : 'Clique para ativar a rota inteligente'}
                className={`flex-none w-[48px] h-[28px] rounded-full p-[3px] transition-colors flex items-center cursor-pointer shadow-inner ${
                  otimizarAutomatico ? 'bg-[#15803D] justify-end' : 'bg-slate-300 justify-start'
                }`}
              >
                <div className="w-5 h-5 rounded-full bg-white shadow-md flex items-center justify-center">
                  {otimizarAutomatico && <Sparkles className="w-3 h-3 text-[#15803D]" />}
                </div>
              </button>
            </div>

            {/* PONTO DE PARTIDA COM AUTOCOMPLETE E FIXAÇÃO COMO PADRÃO */}
            <div className="flex flex-col gap-2">
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-1.5 text-[13px] font-semibold text-[#2B3A4F]">
                  <MapPin className="w-4 h-4 text-navy-900" />
                  <span>Ponto de partida da frota</span>
                </span>
                <button
                  type="button"
                  onClick={handleFixarPontoPartidaPadrao}
                  className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-bold transition-all cursor-pointer ${
                    isPadraoFixado
                      ? 'bg-emerald-50 text-emerald-700 border border-emerald-200 shadow-2xs'
                      : 'bg-slate-50 text-slate-600 hover:bg-slate-100 border border-slate-200'
                  }`}
                  title="Fixar este endereço nas preferências da empresa para que toda nova rota já inicie com a sede preenchida"
                >
                  <BookmarkCheck className={`w-3.5 h-3.5 ${isPadraoFixado ? 'text-emerald-600' : 'text-slate-400'}`} />
                  <span>{isPadraoFixado ? 'Sede Fixada como Padrão' : 'Fixar como Padrão'}</span>
                </button>
              </div>

              <PlacesAutocompleteInput
                name="ponto_partida_autocomplete_ec"
                placeholder="Buscar sede da empresa ou ponto de partida..."
                value={pontoPartidaTexto}
                onChange={(val) => {
                  setPontoPartidaTexto(val);
                  setIsPadraoFixado(false);
                }}
                onAddressSelect={(dados) => {
                  const coords = dados.coordenadas;
                  const nome = dados.nomeLocal || dados.enderecoCompleto.split(',')[0].trim() || 'Ponto de Partida';
                  const novoPonto: PontoPartidaItem = {
                    nome,
                    endereco: dados.enderecoCompleto,
                    lat: coords.lat,
                    lng: coords.lng,
                    coordenadas: coords,
                  };
                  setPontoPartida(novoPonto);
                  setPontoPartidaTexto(dados.enderecoCompleto);
                  setIsPadraoFixado(false);
                  setMensagemSucesso(`Ponto de partida definido: ${novoPonto.nome}. Marcador "Início" atualizado no mapa.`);
                  setTimeout(() => setMensagemSucesso(null), 3500);
                }}
                empresaId={empresaId}
              />
              <span className="text-[11px] text-slate-400">
                Marcador "Início" posicionado no mapa. As distâncias da rota partem deste local.
              </span>
            </div>

            {/* MAPA INTERATIVO MAPBOX */}
            <RouteMap
              pontoPartida={pontoPartida}
              paradas={paradasParaOMapa}
              pontoPreview={pontoPreview}
              otimizado={otimizarAutomatico}
            />

            {/* COMPARATIVO DE BARRAS: ORDEM CADASTRO VS ROTA OTIMIZADA */}
            <div className="flex flex-col gap-3.5 pt-1">
              <div className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold text-[#2B3A4F]">Ordem de cadastro</span>
                  <span className="font-bold text-[#0F1B2D]">
                    {entregasDaRota.length > 0
                      ? `${metricasRota.distanciaOriginalKm} km · ${formatarTempoMinutos(metricasRota.tempoOriginalMinutos)}`
                      : '0 km · 0 min'}
                  </span>
                </div>
                <div className="h-2.5 rounded-full bg-[#E4E9F0] overflow-hidden">
                  <div className="w-full h-full bg-[#94A3B8]" />
                </div>
              </div>

              <div className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold text-[#2B3A4F]">Rota otimizada</span>
                  <span className="font-bold text-[#15803D]">
                    {entregasDaRota.length > 0
                      ? `${metricasRota.distanciaOtimizadaKm} km · ${formatarTempoMinutos(metricasRota.tempoOtimizadoMinutos)}`
                      : '0 km · 0 min'}
                  </span>
                </div>
                <div className="h-2.5 rounded-full bg-[#E4E9F0] overflow-hidden">
                  <div
                    style={{
                      width:
                        metricasRota.distanciaOriginalKm > 0
                          ? `${Math.min(100, Math.max(10, Math.round((metricasRota.distanciaOtimizadaKm / metricasRota.distanciaOriginalKm) * 100)))}%`
                          : '0%',
                    }}
                    className="h-full bg-[#15803D] rounded-full transition-all duration-500"
                  />
                </div>
              </div>

              {/* Card Destaque Verde de Economia */}
              <div className="flex items-center gap-3 p-3.5 rounded-xl bg-[#DDF3E4] text-[#14532D]">
                <div className="text-2xl font-extrabold leading-none">
                  {entregasDaRota.length === 0
                    ? '—'
                    : metricasRota.economiaKm > 0
                    ? `-${metricasRota.economiaKm} km`
                    : '100%'}
                </div>
                <div className="text-[13px] font-semibold leading-tight">
                  {entregasDaRota.length === 0
                    ? 'Adicione paradas para traçar a rota e calcular a economia.'
                    : metricasRota.economiaKm > 0
                    ? `Economia de ${metricasRota.percentualEconomiaKm}% na distância e ${metricasRota.economiaTempoMinutos} min previstos a menos com a Rota Inteligente!`
                    : `Trajeto ideal traçado · ${metricasRota.distanciaOtimizadaKm} km no trajeto mais eficiente.`}
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
              onClick={() => {
                salvarRascunhoRota({
                  motoristaAtivo,
                  entregasDaRota,
                  observacaoTexto,
                  otimizarAutomatico,
                  pontoPartida,
                  pontoPartidaTexto,
                  timestamp: Date.now(),
                });
                setMensagemSucesso(`Rascunho com ${entregasDaRota.length} paradas salvo com sucesso! Você pode alternar de tela livremente.`);
                setTimeout(() => setMensagemSucesso(null), 4000);
              }}
              className="h-11 rounded-[10px] border border-[#CBD5E1] bg-white hover:bg-slate-50 text-[#0F1B2D] font-bold text-sm transition-colors cursor-pointer flex items-center justify-center gap-2"
            >
              <BookmarkCheck className="w-4 h-4 text-emerald-600" />
              <span>Salvar como rascunho</span>
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
