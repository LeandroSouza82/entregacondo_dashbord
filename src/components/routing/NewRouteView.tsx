import {RouteRuleFields, RouteRuleEditor} from './RouteRuleFields';
import {emptyDraftRule, validateDraftRule, hasRouteRules, draftToRule, planningNow, ruleDateTime, type DraftRule} from '../../features/routes/services/routeRules';
import {optimizeSchedule, evaluateSchedule, type SchedulePlan} from '../../features/routes/services/routeSchedule';
import {collectionRoadCosts} from '../../features/routes/services/collectionRoadCosts';
import { coordenadasValidas, erroLocalizacaoEndereco } from '../../features/routes/services/addressCoordinates';
import { normalizeCustomerWhatsApp, legacyAddressNotes } from '../../features/routes/services/customerContact';
import { dispatchDriverOrders } from '../../features/routes/services/dispatchDriverServices';
import { estimateServiceTimes, type ServiceSample } from '../../features/routes/services/serviceTimeEstimates';
import { fetchRoadPlan, type RoadCoordinate } from '../../features/routes/services/roadGeometry';
import { requireCompanyId, hasActiveSupabaseSession, isDemoModeActive } from '../../lib/company';
import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { RouteMap } from './RouteMap';
import { PlacesAutocompleteInput } from './PlacesAutocompleteInput';
import { ClienteCondominioSearchInput } from './ClienteCondominioSearchInput';
import type { ClienteEnderecoItem } from '../../features/routes/types/clienteEndereco';
import { salvarClienteEndereco } from '../../features/routes/services/salvarClienteEndereco';
import { ObterIconeVeiculo } from '../../assets/icons/vehicles/VehicleIcons';
import { normalizarTipoVeiculo } from '../../features/routes/utils/vehicleMovement';
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
  Trash2,
  Copy
} from 'lucide-react';
import { sendRouteToWhatsApp, copyRouteToClipboard } from '../../utils/whatsappRouteFormatter';

function WhatsAppIcon({ className = 'w-4 h-4' }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L0 24l6.335-1.662c1.746.953 3.71 1.456 5.711 1.457h.004c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413Z"/>
    </svg>
  );
}
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
  veiculoTipo?: string | null;
  latitude_atual?: number | null;
  longitude_atual?: number | null;
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
  condicoesNovoPedido?: DraftRule;
  saidaPrevista?: string;
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
  const [whatsappCliente, setWhatsappCliente] = useState<string>('');
  const [enderecoTexto, setEnderecoTexto] = useState<string>('');
  const [coordenadasSelecionadas, setCoordenadasSelecionadas] = useState<PontoCoordenada | null>(null);
  const [pontoPreview, setPontoPreview] = useState<{ nome: string; coordenadas: PontoCoordenada } | null>(null);
  const [observacaoTexto, setObservacaoTexto] = useState<string>(() => rascunhoInicial?.observacaoTexto || '');
  const [draftRule,setDraftRule]=useState<DraftRule>(()=>rascunhoInicial?.condicoesNovoPedido ?? emptyDraftRule());
  const [saidaPrevista,setSaidaPrevista]=useState(()=>rascunhoInicial?.saidaPrevista ?? planningNow());
  const [editingRule,setEditingRule]=useState<string|null>(null);
  const [scheduleRevision,setScheduleRevision]=useState(0);
  const [salvarParaProximas, setSalvarParaProximas] = useState<boolean>(true);
  const [isBalanceteOpen, setIsBalanceteOpen] = useState<boolean>(false);
  const [isDocumentosOpen, setIsDocumentosOpen] = useState<boolean>(false);
  const [chipsCustomizados, setChipsCustomizados] = useState<string[]>(() => obterChipsCustomizados());

  // Alertas de feedback
  const [mensagemSucesso, setMensagemSucesso] = useState<string | null>(null);
  const [despachoEnviado, setDespachoEnviado] = useState<string | null>(null);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  // Lista de Entregas da Rota com restauração instantânea do rascunho
  const [entregasDaRota, setEntregasDaRota] = useState<PontoParada[]>(() => rascunhoInicial?.entregasDaRota || []);

  const [ultimaRotaDespachada, setUltimaRotaDespachada] = useState<{
    paradas: PontoParada[];
    motoristaNome?: string;
    timestamp?: number;
  } | null>(() => {
    if (typeof window === 'undefined' || !window.localStorage) return null;
    try {
      const salvo = window.localStorage.getItem('ec_last_dispatched_route');
      if (!salvo) return null;
      const parsed = JSON.parse(salvo);
      if (Array.isArray(parsed?.paradas) && parsed.paradas.length > 0) {
        return {
          paradas: parsed.paradas,
          motoristaNome: parsed.motoristaNome,
          timestamp: parsed.timestamp,
        };
      }
    } catch {
      return null;
    }
    return null;
  });

  const handleCopiarRota = useCallback(async (paradas: PontoParada[]) => {
    const copiado = await copyRouteToClipboard(paradas, (msg) => {
      setMensagemSucesso(msg);
      setTimeout(() => setMensagemSucesso(null), 3500);
    });
    if (!copiado) {
      setMensagemErro('Não foi possível copiar o texto automaticamente.');
      setTimeout(() => setMensagemErro(null), 3500);
    }
  }, []);

  const handleEnviarWhatsApp = useCallback((paradas: PontoParada[]) => {
    const enviado = sendRouteToWhatsApp(paradas);
    if (!enviado) {
      setMensagemErro('Nenhuma parada para enviar ao WhatsApp.');
      setTimeout(() => setMensagemErro(null), 3500);
    }
  }, []);

  // Auto-Save do Rascunho da Rota em localStorage a cada alteração
  useEffect(() => {
    if (entregasDaRota.length > 0 || observacaoTexto.trim()) {
      salvarRascunhoRota({
        motoristaAtivo,
        entregasDaRota,
        observacaoTexto,
        otimizarAutomatico,
        condicoesNovoPedido:draftRule, saidaPrevista,
        pontoPartida,
        pontoPartidaTexto,
        timestamp: Date.now(),
      });
    }
  }, [entregasDaRota, motoristaAtivo, observacaoTexto, otimizarAutomatico, pontoPartida, pontoPartidaTexto, draftRule, saidaPrevista]);

  const handleLimparRascunho = useCallback(() => {
    limparRascunhoRota();
    setEntregasDaRota([]);
    setObservacaoTexto('');
    setDraftRule(emptyDraftRule());
    setSaidaPrevista(planningNow());
    setMensagemSucesso('Rascunho da rota limpo com sucesso.');
    setTimeout(() => setMensagemSucesso(null), 3000);
  }, []);

  const handleRemoverParada = useCallback((id: string) => {
    if (entregasDaRota.some(p=>p.coletaOrigemId===id)) {
      setMensagemErro('Remova o vínculo das entregas em Editar condições antes de excluir esta coleta.');
      return;
    }
    setEntregasDaRota(prev => {
      const novaLista = prev.filter(p => p.id !== id);
      if (novaLista.length === 0) {
        limparRascunhoRota();
      }
      return novaLista;
    });
  }, [entregasDaRota]);

  // Cálculo inteligente de trajeto e métricas (Ordem de cadastro vs Rota Otimizada)
  const heuristicMetrics = useMemo<MetricasRota>(() => {
    return otimizarSequenciaERota(pontoPartida, entregasDaRota);
  }, [pontoPartida, entregasDaRota]);

  const constrained=hasRouteRules(entregasDaRota);
  const scheduleKey=JSON.stringify({stops:entregasDaRota,departure:saidaPrevista,optimize:otimizarAutomatico,point:pontoPartida.coordenadas,revision:scheduleRevision});
  const [scheduled,setScheduled]=useState<{key:string;plan?:SchedulePlan;error?:string}|null>(null);
  useEffect(()=>{
    const request=JSON.parse(scheduleKey) as {stops:PontoParada[];departure:string;optimize:boolean;point:PontoCoordenada};
    if (!hasRouteRules(request.stops)) return;
    const controller=new AbortController();
    let active=true;
    const timeout=setTimeout(()=>{
      if (active) setScheduled({key:scheduleKey,error:'O cálculo de horários demorou demais. Recalcule antes de enviar.'});
      controller.abort();
    },45000);
    const points:RoadCoordinate[]=[[request.point.lng,request.point.lat],...request.stops.map(p=>[p.coordenadas.lng,p.coordenadas.lat] as RoadCoordinate)];
    Promise.resolve().then(()=>{
      if (request.stops.length>100) throw new Error('Organize grupos de até 100 paradas com condições.');
      return collectionRoadCosts(points,[],request.stops.map((_,i)=>i+1),undefined,import.meta.env.VITE_MAPBOX_TOKEN || '',controller.signal);
    })
      .then(costs=>{
        const [date,time]=request.departure.split('T'); const departure=ruleDateTime(date,time);
        const rules=request.stops.map(draftToRule);
        const plan=request.optimize ? optimizeSchedule(rules,costs,departure) : evaluateSchedule(rules,costs,departure,request.stops.map((_,i)=>i+1));
        if (!controller.signal.aborted) setScheduled({key:scheduleKey,plan});
      }).catch(error=>{if (!controller.signal.aborted) setScheduled({key:scheduleKey,error:(error as Error).message});})
      .finally(()=>clearTimeout(timeout));
    return ()=>{active=false;clearTimeout(timeout);controller.abort();};
  },[scheduleKey]);
  const verifiedSchedule=scheduled?.key===scheduleKey ? scheduled : null;
  const schedulePlan=verifiedSchedule?.plan;

  // Lista de paradas a renderizar no mapa: ordenada pela melhor sequência se otimização estiver ativa
  const paradasParaOMapa = useMemo(() => {
    if (constrained) return schedulePlan ? schedulePlan.order.map(i=>({...entregasDaRota[i-1],sequencia:0})).map((p,i)=>({...p,sequencia:i+1})) : entregasDaRota;
    if (otimizarAutomatico && heuristicMetrics.paradasOtimizadas.length > 0) {
      return heuristicMetrics.paradasOtimizadas;
    }
    return entregasDaRota;
  }, [otimizarAutomatico, heuristicMetrics.paradasOtimizadas, entregasDaRota, constrained, schedulePlan]);

  const roadKey = JSON.stringify([
    [[pontoPartida.coordenadas.lng, pontoPartida.coordenadas.lat], ...entregasDaRota.map(p => [p.coordenadas.lng, p.coordenadas.lat])],
    [[pontoPartida.coordenadas.lng, pontoPartida.coordenadas.lat], ...paradasParaOMapa.map(p => [p.coordenadas.lng, p.coordenadas.lat])],
  ]);
  const [roadTotals, setRoadTotals] = useState<{key: string; original: {kilometers: number; minutes: number}; selected: {kilometers: number; minutes: number}} | null>(null);
  useEffect(() => {
    const controller = new AbortController();
    const [original, selected] = JSON.parse(roadKey) as RoadCoordinate[][];
    if (original.length < 2) return () => controller.abort();
    const token = import.meta.env.VITE_MAPBOX_TOKEN || '';
    Promise.all([fetchRoadPlan(original, token, controller.signal), fetchRoadPlan(selected, token, controller.signal)])
      .then(([a,b]) => { if (!controller.signal.aborted) setRoadTotals({key: roadKey, original:a, selected:b}); })
      .catch(() => { if (!controller.signal.aborted) setRoadTotals(null); });
    return () => controller.abort();
  }, [roadKey]);
  const verifiedTotals = roadTotals?.key === roadKey ? roadTotals : null;
  const originalKm = verifiedTotals?.original.kilometers || 0;
  const selectedKm = verifiedTotals?.selected.kilometers || 0;
  const originalMin = verifiedTotals?.original.minutes || 0;
  const selectedMin = verifiedTotals?.selected.minutes || 0;
  const metricasRota: MetricasRota = {...heuristicMetrics, paradasOtimizadas:paradasParaOMapa,
    distanciaOriginalKm:Number(originalKm.toFixed(2)), tempoOriginalMinutos:Math.ceil(originalMin),
    distanciaOtimizadaKm:Number(selectedKm.toFixed(2)), tempoOtimizadoMinutos:Math.ceil(selectedMin),
    economiaKm:Number(Math.max(0,originalKm-selectedKm).toFixed(2)),
    percentualEconomiaKm:originalKm>0 ? Math.round(Math.max(0,originalKm-selectedKm)/originalKm*100):0,
    economiaTempoMinutos:Math.max(0,Math.ceil(originalMin-selectedMin)),
    percentualEconomiaTempo:originalMin>0 ? Math.round(Math.max(0,originalMin-selectedMin)/originalMin*100):0,
  };

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
      void hasActiveSupabaseSession().then(has => { if (has) void supabase.from('empresas').update({ cidade: enderecoFinal.split(',').pop()?.trim() || 'Palhoça' }).eq('id', empresaId); });
      if (false) void supabase
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
      const hasSession = await hasActiveSupabaseSession();
      const { data } = hasSession
        ? await supabase.from('motoristas').select('*').eq('empresa_id', id).eq('ativo', true)
        : {
            data: isDemoModeActive()
              ? [
                  { id: '00000000-0000-4000-8000-000000000101', nome: 'Carlos Silva', veiculo_modelo: 'Honda CG 160 Cargo', veiculo_tipo: 'moto', latitude_atual: -27.5954, longitude_atual: -48.548, status: 'Disponível', empresa_id: id },
                  { id: '00000000-0000-4000-8000-000000000102', nome: 'Rodrigo Costa', veiculo_modelo: 'Fiorino Furgão', veiculo_tipo: 'utilitario', latitude_atual: -27.5969, longitude_atual: -48.5495, status: 'Disponível', empresa_id: id },
                  { id: '00000000-0000-4000-8000-000000000103', nome: 'Mariana Souza', veiculo_modelo: 'Yamaha Factor 150', veiculo_tipo: 'moto', latitude_atual: -27.5935, longitude_atual: -48.5512, status: 'Em Rota', empresa_id: id },
                ]
              : [],
          };
      if (active) {
        setEmpresaId(id);
        const mapped = (data || []).map(m => ({
          id: m.id,
          nome: m.nome,
          iniciais: m.nome.split(' ').map((n: string) => n[0]).slice(0, 2).join(''),
          veiculo: m.veiculo_modelo || 'Moto Padrão',
          veiculoTipo: m.veiculo_tipo,
          latitude_atual: m.latitude_atual,
          longitude_atual: m.longitude_atual,
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
  const serviceKey = JSON.stringify([empresaId,motoristaAtivo,paradasParaOMapa.map(p=>p.clienteEnderecoId)]);
  const [serviceHistory,setServiceHistory]=useState<{key:string;samples:ServiceSample[]}|null>(null);
  useEffect(()=>{
    let active=true;
    const [company,driver,addresses]=JSON.parse(serviceKey) as [string,string,string[]];
    if(!company||!driver||!addresses.length)return ()=>{active=false;};
    // Receipt timestamps identify explicit arrival/finish records; legacy guessed times are excluded.
    void hasActiveSupabaseSession().then(has => { if (!has) return; return supabase.from('entrega_comprovantes').select('duracao_segundos, entregas!inner(cliente_endereco_id,motorista_id)').eq('empresa_id',company).neq('recebedor_tipo','tentativa_falha').in('entregas.cliente_endereco_id',addresses).order('concluida_em',{ascending:false}).limit(1000)
      .then(({data,error})=>{if(!active)return;setServiceHistory(error?null:{key:serviceKey,samples:(data||[]).map(r=>({addressId:r.entregas.cliente_endereco_id,driverId:r.entregas.motorista_id||'',minutes:r.duracao_segundos/60}))});}); });
    return ()=>{active=false;};
  },[serviceKey]);
  const serviceEstimate=estimateServiceTimes(paradasParaOMapa.map(p=>p.clienteEnderecoId),motoristaAtivo,serviceHistory?.key===serviceKey?serviceHistory.samples:[]);


  // Callback inteligente: ao selecionar um cliente/condomínio da base salva (0 chamadas de API)
  const handleSelectClienteCondominio = useCallback((item: ClienteEnderecoItem) => {
    setNomeCliente(item.nome_identificador);
    setWhatsappCliente(item.whatsapp_cliente || '');
    setEnderecoTexto(item.endereco_completo);
    setObservacaoTexto(legacyAddressNotes(item.observacoes_acesso, item.destinatario_padrao));
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
    setWhatsappCliente('');
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
        endereco_completo: dados.endereco,
        coordenadas: dados.coordenadas,
      }).then(() => {
        setMensagemSucesso(`"${dados.nome}" geocodificado pelo Google Places e gravado na base de dados da empresa.`);
        setTimeout(() => setMensagemSucesso(null), 4000);
      }).catch((e) => {
        console.warn('Persistência automática em background:', e);
      });
    }
  }, [empresaId]);

  // Callback memoizado para seleção de endereço via Google Places ou base salva
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
    setCoordenadasSelecionadas(dados.coordenadas);
    setPontoPreview({
      nome: nomeFinal,
      coordenadas: dados.coordenadas,
    });
    setErroValidacao(null);
  }, [nomeCliente]);

  const handleAdicionarEntrega = async () => {
    const nomeFinal = nomeCliente.trim() || enderecoTexto.trim().split(',')[0].trim();
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

    const rule={...draftRule,collection:tipoTarefa==='entrega'?draftRule.collection:''};
    try { validateDraftRule(rule,tipoTarefa,entregasDaRota); }
    catch(error) { setErroValidacao((error as Error).message); return; }
    let normalizedPhone: string;
    try { normalizedPhone = normalizeCustomerWhatsApp(whatsappCliente); }
    catch (error) { setErroValidacao((error as Error).message); return; }

    // A typed address is usable only after a successful geocoding response.
    let coords = coordenadasSelecionadas;
    if (!coordenadasValidas(coords)) {
      const geo = await geocodificarEndereco(enderecoTexto.trim());
      coords = geo?.coordenadas ?? null;
      if (!coordenadasValidas(coords)) {
        setErroValidacao(erroLocalizacaoEndereco);
        return;
      }
      setCoordenadasSelecionadas(coords);
    }

    const novoIdEntrega = crypto.randomUUID();
    const novoIdClienteEndereco = `cli-${crypto.randomUUID()}`;

    const nova: PontoParada = {
      id: novoIdEntrega,
      sequencia: entregasDaRota.length + 1,
      clienteEnderecoId: novoIdClienteEndereco,
      nomeLocal: nomeFinal,
      unidade: '',
      whatsappCliente: normalizedPhone,
      destinatario: nomeFinal,
      enderecoFormatado: enderecoTexto.trim(),
      coordenadas: coords,
      tempoMedioAtendimentoMinutos: tipoTarefa === 'coleta' ? 15 : tipoTarefa === 'outros' ? 14 : 11,
      prioridade: 'normal',
      tipoTarefa,
      descricaoOutro: tipoTarefa === 'outros' ? especificacaoOutro.trim() : undefined,
      observacoesGestor: observacaoTexto.trim() || undefined,
      janelaData:rule.date || undefined, janelaInicio:rule.start || undefined, janelaFim:rule.end || undefined,
      coletaOrigemId:rule.collection || undefined,
      codigoRastreio: `EC-${Math.floor(100000 + Math.random() * 900000)}`,
    };

    if (rule.date) nova.tempoMedioAtendimentoMinutos=rule.minutes;

    // Memória inteligente: se "outros" foi especificado, salva o termo como chip permanente
    if (tipoTarefa === 'outros' && especificacaoOutro.trim()) {
      setChipsCustomizados(salvarChipCustomizado(especificacaoOutro.trim()));
    }

    // O despacho exige endereço gravado no banco: a parada é sempre persistida
    if (coords) {
      try {
        const saved = await salvarClienteEndereco({
          empresa_id: empresaId,
          nome_identificador: nomeFinal,
          whatsapp_cliente: normalizedPhone,
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
    setWhatsappCliente('');
    setEnderecoTexto('');
    setObservacaoTexto('');
    setTipoTarefa('entrega');
    setDraftRule(emptyDraftRule());
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
    try {
      for (const p of entregasDaRota) validateDraftRule({date:p.janelaData ?? '',start:p.janelaInicio ?? '',end:p.janelaFim ?? '',collection:p.coletaOrigemId ?? '',minutes:Math.round(p.tempoMedioAtendimentoMinutos || 0)},p.tipoTarefa ?? 'entrega',entregasDaRota);
      if (constrained && !schedulePlan) throw new Error(verifiedSchedule?.error || 'Aguarde o cálculo dos horários ou toque em Recalcular.');
      if (constrained && ruleDateTime(...saidaPrevista.split('T') as [string,string])<Date.now()-300000) throw new Error('Atualize a saída prevista para um horário atual ou futuro e recalcule.');
    } catch(error) {setMensagemErro((error as Error).message);return;}
    if (isSupabaseConfigured) {
      setDespachando(true);
      try {
        const payloadDespacho = {
          ...(schedulePlan ? {planejamento_saida_em:new Date(ruleDateTime(...saidaPrevista.split('T') as [string,string])).toISOString(),agenda:schedulePlan.visits.map(v=>({entrega_id:v.id,inicio_em:new Date(v.start).toISOString(),fim_em:new Date(v.finish).toISOString()}))} : {}),
          metricas_fonte: verifiedTotals && selectedKm>0 && selectedMin>0 ? 'mapbox_directions_planejamento' : null,
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
            janela_data:p.janelaData,janela_inicio:p.janelaInicio,janela_fim:p.janelaFim,coleta_origem_id:p.coletaOrigemId,
          })),
          paradas: paradasParaOMapa.map((parada, idx) => ({
            id:parada.id,janela_data:parada.janelaData || null,janela_inicio:parada.janelaInicio || null,janela_fim:parada.janelaFim || null,
            coleta_origem_id:parada.coletaOrigemId || null,tempo_atendimento_previsto_min:Math.round(parada.tempoMedioAtendimentoMinutos || 0),
            cliente_endereco_id: /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(parada.clienteEnderecoId) ? parada.clienteEnderecoId : null,
            ordem_na_rota: idx + 1,
            codigo_rastreio: parada.codigoRastreio,
            destinatario_nome: parada.destinatario,
            unidade_apartamento: (parada.unidade ?? parada.nomeLocal) || null,
            destinatario_telefone: parada.whatsappCliente || null,
            tipo_tarefa: parada.tipoTarefa || 'entrega',
            descricao_outro: parada.descricaoOutro || null,
            prioridade: parada.prioridade || 'normal',
            volumes_qtd: 1,
            observacoes_gestor: parada.observacoesGestor?.trim() || null,
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

        const resp = await dispatchDriverOrders(supabase, payloadDespacho);
        if (!resp || resp.sucesso !== true) {
          setMensagemErro(`Erro no despacho da rota: ${resp?.mensagem || 'Falha no banco de dados'}.`);
          setTimeout(() => setMensagemErro(null), 8000);
          return;
        }

        setMensagemSucesso(resp.mensagem);
        setDespachoEnviado(resp.mensagem);
        setTimeout(() => setDespachoEnviado(null), 6000);
        limparRascunhoRota();
        setEntregasDaRota([]);
        despachoKey.current = crypto.randomUUID();

        // Salva cache de última rota despachada para sincronizar instantaneamente com a Visão Geral e reenvio WhatsApp
        const dadosRotaDespachada = {
          pontoPartida,
          paradas: paradasParaOMapa,
          distanciaOtimizadaKm: metricasRota.distanciaOtimizadaKm,
          tempoOtimizadoMinutos: metricasRota.tempoOtimizadoMinutos,
          motoristaNome: motoristaSelecionado.nome,
          timestamp: Date.now(),
        };
        setUltimaRotaDespachada({
          paradas: paradasParaOMapa,
          motoristaNome: motoristaSelecionado.nome,
          timestamp: dadosRotaDespachada.timestamp,
        });
        if (typeof window !== 'undefined' && window.localStorage) {
          window.localStorage.setItem('ec_last_dispatched_route', JSON.stringify(dadosRotaDespachada));
        }
        setTimeout(() => setMensagemSucesso(null), 6000);
      } catch (err: unknown) {
        console.error('Erro de conexão ao despachar rota:', err);
        setMensagemErro(err instanceof Error ? err.message : 'Não foi possível confirmar o envio. O rascunho foi mantido intacto.');
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
      {editingRule && entregasDaRota.find(p=>p.id===editingRule) && <RouteRuleEditor key={editingRule}
        stop={entregasDaRota.find(p=>p.id===editingRule)!} stops={entregasDaRota} onClose={()=>setEditingRule(null)}
        onSave={value=>{setEntregasDaRota(prev=>prev.map(p=>p.id===editingRule?{...p,janelaData:value.date || undefined,janelaInicio:value.start || undefined,janelaFim:value.end || undefined,coletaOrigemId:value.collection || undefined,tempoMedioAtendimentoMinutos:value.minutes}:p));despachoKey.current=crypto.randomUUID();setEditingRule(null);}}/>}

      {/* Header Principal */}
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-[26px] font-extrabold text-[#0F1B2D] tracking-tight m-0">
            Nova rota de entregas
          </h1>
          <p className="text-[#516074] text-sm mt-1">
            Envie os pedidos para o motorista conferir e aceitar no aplicativo.
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

      {despachoEnviado && (
        <div role="status" className="fixed top-6 right-6 z-[100] max-w-sm p-4 rounded-xl bg-emerald-600 text-white text-sm font-semibold flex items-center gap-3 shadow-2xl animate-fadeIn">
          <CheckCircle2 className="w-5 h-5 flex-shrink-0" />
          <span>{despachoEnviado}</span>
          <button type="button" onClick={() => setDespachoEnviado(null)} aria-label="Fechar aviso" className="ml-1 opacity-80 hover:opacity-100">
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

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
          <section className="bg-white border border-gray-300 rounded-2xl p-5 shadow-card flex flex-col gap-4">
            <div className="flex items-center gap-2.5">
              <span className="w-[26px] h-[26px] rounded-full bg-[#0F1B2D] text-white flex items-center justify-center text-[13px] font-bold">
                1
              </span>
              <h2 className="text-[17px] font-extrabold text-[#0F1B2D] m-0">Motorista</h2>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
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
                      <span className={`flex items-center gap-1.5 text-xs truncate ${isSelected ? 'text-[#334155]' : 'text-[#516074]'}`}>
                        <ObterIconeVeiculo tipo={m.veiculoTipo || m.veiculo} size={15} />
                        <span>{m.veiculo} · {m.status}</span>
                      </span>
                    </span>
                  </button>
                );
              })}
            </div>
          </section>

          {/* SEÇÃO 2: ADICIONAR ENTREGA / PARADA */}
          <section className="bg-white border border-gray-300 rounded-2xl p-5 shadow-card flex flex-col gap-4">
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
                WhatsApp do cliente (com DDD)
                <input
                  type="text"
                  name="whatsapp_cliente_ec"
                  inputMode="tel"
                  maxLength={25}
                  autoComplete="off"
                  spellCheck={false}
                  value={whatsappCliente}
                  onChange={(e) => setWhatsappCliente(e.target.value)}
                  placeholder="Ex: (48) 99999-9999"
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
                  onChange={(value) => {
                    setEnderecoTexto(value);
                    setCoordenadasSelecionadas(null);
                    setPontoPreview(null);
                  }}
                  enderecosSalvos={[]}
                  empresaId={empresaId}
                  coordenadas={coordenadasSelecionadas}
                  nomeCondominio={nomeCliente}
                  blocoApto=""
                  showSaveButton={true}
                  onAddressSelect={handleAddressSelect}
                  onSalvoComSucesso={(labelSalvo) => {
                    setMensagemSucesso(`Endereço "${labelSalvo}" salvo no banco para futuras buscas.`);
                    setTimeout(() => setMensagemSucesso(null), 4000);
                  }}
                />
              </div>

              <details className="rounded-xl border border-slate-200 p-3">
                <summary className="cursor-pointer text-sm font-semibold">Horários e coleta vinculada (opcional)</summary>
                <div className="mt-3"><RouteRuleFields value={draftRule} onChange={setDraftRule} type={tipoTarefa} stops={entregasDaRota}/></div>
              </details>
              {/* Observação para o motorista (inclua o apartamento aqui) */}
              <div className="sm:col-span-2 flex flex-col gap-2">
                <label className="flex flex-col gap-1.5 text-[13px] font-semibold text-[#2B3A4F]">
                  Observação para o motorista (inclua o apartamento aqui)
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
                    setWhatsappCliente('');
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
          <section className="bg-white border border-gray-300 rounded-2xl p-5 shadow-card flex flex-col gap-3">
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
                      {constrained ? (schedulePlan ? 'Sequência conferida' : verifiedSchedule?.error ? 'Revisar condições' : 'Conferindo condições') : 'Sequência Otimizada (Rota Inteligente)'}
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

            {constrained && <section className="space-y-2 rounded-xl bg-blue-50 p-3 text-sm" aria-label="Planejamento com condições">
              <label className="block">Saída prevista (horário de Brasília)<input type="datetime-local" value={saidaPrevista} onChange={e=>setSaidaPrevista(e.target.value)} className="ml-2 rounded border p-2"/></label>
              <div className="flex flex-wrap gap-3"><button type="button" className="font-semibold underline" onClick={()=>setSaidaPrevista(planningNow())}>Usar horário de agora</button><button type="button" className="font-semibold underline" onClick={()=>setScheduleRevision(v=>v+1)}>Recalcular horários</button></div>
              <p role="status">{schedulePlan ? `Sequência conferida · ${Math.ceil((schedulePlan.finish-ruleDateTime(...saidaPrevista.split('T') as [string,string]))/60000)} min com atendimento e espera (${Math.ceil(schedulePlan.waitingSeconds/60)} min de espera). Previsão sujeita ao trânsito e ao atendimento real.` : verifiedSchedule?.error || 'Calculando horários e vínculos pelas ruas…'}</p>
            </section>}
            {paradasParaOMapa.length === 0 ? (
              <div className="py-6 space-y-3">
                <div className="text-center text-xs text-slate-400 font-medium">
                  Nenhuma parada adicionada ainda. Busque um condomínio acima para adicionar.
                </div>

                {ultimaRotaDespachada && ultimaRotaDespachada.paradas.length > 0 && (
                  <div className="p-3.5 rounded-xl bg-emerald-50/70 border border-emerald-200 flex flex-wrap items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5">
                      <span className="text-lg">📲</span>
                      <div>
                        <p className="text-xs font-bold text-emerald-900 m-0">
                          Última rota enviada ({ultimaRotaDespachada.paradas.length} parada{ultimaRotaDespachada.paradas.length > 1 ? 's' : ''}{ultimaRotaDespachada.motoristaNome ? ` · ${ultimaRotaDespachada.motoristaNome}` : ''})
                        </p>
                        <p className="text-[11px] text-emerald-700 m-0">
                          A rota foi despachada. Você pode reenviar a lista para a gestão interna no WhatsApp ou copiar o texto.
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => handleCopiarRota(ultimaRotaDespachada.paradas)}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 text-xs font-semibold transition-all cursor-pointer shadow-2xs"
                        title="Copiar texto da última rota enviada"
                      >
                        <Copy className="w-3.5 h-3.5 text-slate-500" />
                        <span>Copiar texto</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => handleEnviarWhatsApp(ultimaRotaDespachada.paradas)}
                        className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg border border-emerald-300 bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold transition-all cursor-pointer shadow-2xs"
                        title="Reenviar última rota para o WhatsApp"
                      >
                        <WhatsAppIcon className="w-3.5 h-3.5 text-white" />
                        <span>Reenviar última rota para o WhatsApp</span>
                      </button>
                    </div>
                  </div>
                )}
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
                        {(parada.janelaData || parada.coletaOrigemId) && <p className="mt-1 text-xs text-blue-800">
                          {parada.janelaData && `${parada.janelaData.split('-').reverse().join('/')} · ${parada.janelaInicio}–${parada.janelaFim}`}
                          {parada.coletaOrigemId && ` · Após coleta: ${entregasDaRota.find(p=>p.id===parada.coletaOrigemId)?.nomeLocal || 'ver vínculo'}`}
                        </p>}
                        <button type="button" className="mt-1 text-xs font-semibold text-slate-500 underline" onClick={()=>setEditingRule(parada.id)}>Editar condições</button>
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

            <div className="border-t border-[#EAEFF4] pt-3 flex flex-wrap items-center justify-between gap-3">
              <span className="text-[13px] font-bold text-[#1D4ED8]">
                {paradasParaOMapa.length > 0 ? `Total: ${paradasParaOMapa.length} parada(s)` : 'Aguardando cadastro de paradas'}
              </span>

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  disabled={paradasParaOMapa.length === 0}
                  onClick={() => handleCopiarRota(paradasParaOMapa)}
                  title="Copiar lista de entregas formatada para o WhatsApp"
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 text-xs font-semibold transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed shadow-2xs"
                >
                  <Copy className="w-3.5 h-3.5 text-slate-500" />
                  <span>Copiar texto</span>
                </button>

                <button
                  type="button"
                  disabled={paradasParaOMapa.length === 0}
                  onClick={() => handleEnviarWhatsApp(paradasParaOMapa)}
                  title="Enviar lista de entregas para o WhatsApp"
                  className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg border border-emerald-300 bg-emerald-50 hover:bg-emerald-100 text-emerald-800 text-xs font-bold transition-all cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed shadow-2xs"
                >
                  <WhatsAppIcon className="w-3.5 h-3.5 text-emerald-600" />
                  <span>Enviar p/ WhatsApp</span>
                </button>
              </div>
            </div>
          </section>

        </div>

        {/* Coluna Direita: Seções 4 e 5 (Rota Inteligente, Mapa e Despacho) */}
        <div className="w-full lg:w-[38%] space-y-6 sticky top-6">
          
          {/* SEÇÃO 4: ROTA INTELIGENTE & MAPA */}
          <section className="bg-white border border-gray-300 rounded-2xl p-5 shadow-card flex flex-col gap-4">
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
              veiculosAtivos={motoristaSelecionado ? [{
                id: motoristaSelecionado.id,
                nome: motoristaSelecionado.nome,
                veiculo_tipo: normalizarTipoVeiculo(motoristaSelecionado.veiculoTipo, motoristaSelecionado.veiculo),
                veiculo_modelo: motoristaSelecionado.veiculo,
                veiculo_placa: '',
                status: 'em_rota',
                coordenadas: {
                  lat: (motoristaSelecionado.latitude_atual && !isNaN(Number(motoristaSelecionado.latitude_atual)))
                    ? Number(motoristaSelecionado.latitude_atual)
                    : pontoPartida.coordenadas.lat,
                  lng: (motoristaSelecionado.longitude_atual && !isNaN(Number(motoristaSelecionado.longitude_atual)))
                    ? Number(motoristaSelecionado.longitude_atual)
                    : pontoPartida.coordenadas.lng,
                }
              }] : []}
              otimizado={otimizarAutomatico}
            />

            {/* COMPARATIVO DE BARRAS: ORDEM CADASTRO VS ROTA OTIMIZADA */}
            <div className="flex flex-col gap-3.5 pt-1">
              <div className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span className="font-semibold text-[#2B3A4F]">Ordem de cadastro</span>
                  <span className="font-bold text-[#0F1B2D]">
                    {entregasDaRota.length > 0
                      ? verifiedTotals ? `${metricasRota.distanciaOriginalKm} km · ${formatarTempoMinutos(metricasRota.tempoOriginalMinutos)}` : 'Estimativa viária indisponível'
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
                      ? verifiedTotals ? `${metricasRota.distanciaOtimizadaKm} km · ${formatarTempoMinutos(metricasRota.tempoOtimizadoMinutos)}` : 'Estimativa viária indisponível'
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

              <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-700">
                <p className="font-bold">Tempo de atendimento pelo histórico</p>
                <p>{serviceEstimate.covered>0 ? `${Math.ceil(serviceEstimate.minutes)} min em ${serviceEstimate.covered} de ${serviceEstimate.total} paradas com registros reais` : 'Sem histórico de atendimento para estas paradas.'}</p>
                {serviceEstimate.covered>0 && <p className="text-xs mt-1">{serviceEstimate.driverSpecific} parada(s) com histórico deste motorista; demais usam registros reais do local.</p>}
                <p className="font-semibold mt-2">{serviceEstimate.complete && verifiedTotals ? `Deslocamento + atendimento: ${formatarTempoMinutos(Math.ceil(selectedMin+serviceEstimate.minutes))}` : 'Jornada total ainda sem estimativa completa.'}</p>
                <p className="text-xs mt-1">Confira a jornada e as pausas do motorista. O histórico melhora as estimativas; não garante o horário de término.</p>
              </div>
              {/* Card Destaque Verde de Economia */}
              <div className="flex items-center gap-3 p-3.5 rounded-xl bg-[#DDF3E4] text-[#14532D]">
                <div className="text-2xl font-extrabold leading-none">
                  {entregasDaRota.length === 0
                    ? '—'
                    : metricasRota.economiaKm > 0
                    ? `-${metricasRota.economiaKm} km`
                    : '—'}
                </div>
                <div className="text-[13px] font-semibold leading-tight">
                  {entregasDaRota.length === 0
                    ? 'Adicione paradas para traçar a rota e calcular a economia.'
                    : !verifiedTotals ? 'Aguardando estimativa pelas ruas. Não inclui atendimento nas paradas.'
                    : metricasRota.economiaKm > 0
                    ? `Economia de ${metricasRota.percentualEconomiaKm}% na distância e ${metricasRota.economiaTempoMinutos} min previstos a menos com a Rota Inteligente!`
                    : `Deslocamento pelas ruas · ${metricasRota.distanciaOtimizadaKm} km. Atendimento nas paradas não incluído.`}
                </div>
              </div>
            </div>
          </section>

          {/* SEÇÃO 5: BOTÕES DE DESPACHO */}
          <section className="bg-white border border-gray-300 rounded-2xl p-5 shadow-card flex flex-col gap-3">
            <button
              type="button"
              disabled={despachando || !motoristaSelecionado} onClick={handleEnviarParaMotorista}
              className="h-12 rounded-[10px] bg-[#C2410C] hover:bg-[#9A3412] active:scale-98 text-white font-bold text-[15px] transition-all shadow-md shadow-[#C2410C]/25 flex items-center justify-center gap-2 cursor-pointer"
            >
              <Send className="w-4 h-4" />
              <span>Enviar serviços para {motoristaSelecionado?.nome.split(' ')[0] || 'o motorista'}</span>
            </button>

            {ultimaRotaDespachada && ultimaRotaDespachada.paradas.length > 0 && (
              <button
                type="button"
                onClick={() => handleEnviarWhatsApp(ultimaRotaDespachada.paradas)}
                className="h-10 rounded-[10px] border border-emerald-300 bg-emerald-50 hover:bg-emerald-100 text-emerald-900 font-bold text-xs transition-colors cursor-pointer flex items-center justify-center gap-2 shadow-2xs"
                title="Reenviar última rota despachada para o WhatsApp da equipe"
              >
                <WhatsAppIcon className="w-3.5 h-3.5 text-emerald-600" />
                <span>📲 Reenviar última rota para o WhatsApp</span>
              </button>
            )}

            <button
              type="button"
              onClick={() => {
                salvarRascunhoRota({
                  motoristaAtivo,
                  entregasDaRota,
                  observacaoTexto,
                  otimizarAutomatico,
                  condicoesNovoPedido: draftRule,
                  saidaPrevista,
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
