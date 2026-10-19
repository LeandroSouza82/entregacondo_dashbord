import { useEffect, useState } from 'react';
import { 
  Package, 
  CheckCircle2, 
  Truck, 
  Users, 
  RotateCw, 
  Plus, 
  Route, 
  Building2, 
  Inbox, 
  ArrowRight,
  ShieldCheck,
  MapPin
} from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { requireCompanyId } from '../../lib/company';
import type { Database } from '../../types/database';
import { RouteMap } from '../routing/RouteMap';
import type { PontoParada } from '../../types/logistics';
import { 
  obterPontoPartidaPadrao, 
  type PontoPartidaItem 
} from '../../features/routes/services/routeOptimization';
import { 
  normalizarTipoVeiculo, 
  type MotoristaVeiculoMapa 
} from '../../features/routes/utils/vehicleMovement';

type Delivery = Database['public']['Tables']['entregas']['Row'] & {
  clientes_enderecos?: Database['public']['Tables']['clientes_enderecos']['Row'] | null;
};

type RotaPlanejada = Database['public']['Tables']['rotas_planejadas']['Row'] & { configuracao_navegacao?: { latitude?: number; longitude?: number; retornar_ao_inicio?: boolean } };

interface OverviewViewProps {
  onGoToOptimizer?: () => void;
  onOpenNewDelivery?: () => void;
}

export function OverviewView({ onGoToOptimizer, onOpenNewDelivery }: OverviewViewProps) {
  const [deliveries, setDeliveries] = useState<Delivery[]>([]);
  const [rotasPlanejadas, setRotasPlanejadas] = useState<RotaPlanejada[]>([]);
  const [paradasMapa, setParadasMapa] = useState<PontoParada[]>([]);
  const [pontoPartida, setPontoPartida] = useState<PontoPartidaItem>(() => obterPontoPartidaPadrao());
  const [drivers, setDrivers] = useState<number>(0);
  const [veiculosAtivos, setVeiculosAtivos] = useState<MotoristaVeiculoMapa[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [refreshing, setRefreshing] = useState<boolean>(false);
  const [revision, setRevision] = useState<number>(0);

  useEffect(() => {
    let active = true;

    async function loadData() {
      if (revision === 0) {
        setLoading(true);
      } else {
        setRefreshing(true);
      }

      try {
        let companyId: string | null = null;
        try {
          companyId = await requireCompanyId();
        } catch (compErr) {
          console.warn('[OverviewView] Fallback na resolução da empresa:', compErr);
        }

        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const last24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

        // 1. Consulta entregas de hoje vinculadas à empresa com dados do endereço persistido
        let entregasCarregadas: Delivery[] = [];
        if (companyId) {
          try {
            const { data, error } = await supabase
              .from('entregas')
              .select('*, clientes_enderecos(*)')
              .eq('empresa_id', companyId)
              .gte('created_at', today.toISOString())
              .order('ordem_na_rota', { ascending: true });

            if (!error && Array.isArray(data) && data.length > 0) {
              entregasCarregadas = data as any;
            } else {
              // Se hoje não retornou entregas (ex: fuso horário UTC ou entregas recentes), busca as ativas das últimas 24h
              const { data: recents } = await supabase
                .from('entregas')
                .select('*, clientes_enderecos(*)')
                .eq('empresa_id', companyId)
                .gte('created_at', last24h)
                .order('ordem_na_rota', { ascending: true });
              if (Array.isArray(recents) && recents.length > 0) {
                entregasCarregadas = recents as any;
              }
            }
          } catch (e) {
            console.warn('[OverviewView] Consulta de entregas retornou vazio ou erro silenciado:', e);
          }
        }

        // 2. Consulta rotas ativas de hoje vinculadas à empresa em public.rotas_planejadas
        let rotasCarregadas: RotaPlanejada[] = [];
        if (companyId) {
          try {
            const { data: rotas, error: rotasErr } = await supabase
              .from('rotas_planejadas')
              .select('*')
              .eq('empresa_id', companyId)
              .gte('created_at', today.toISOString())
              .order('created_at', { ascending: false });

            if (!rotasErr && Array.isArray(rotas) && rotas.length > 0) {
              rotasCarregadas = rotas;
            } else {
              // Busca rotas das últimas 24h se hoje ainda não tiver novas rotas
              const { data: rotasRecentes } = await supabase
                .from('rotas_planejadas')
                .select('*')
                .eq('empresa_id', companyId)
                .gte('created_at', last24h)
                .order('created_at', { ascending: false });
              if (Array.isArray(rotasRecentes) && rotasRecentes.length > 0) {
                rotasCarregadas = rotasRecentes;
              }
            }
          } catch (e) {
            console.warn('[OverviewView] Consulta de rotas retornou vazio ou erro silenciado:', e);
          }
        }

        // 3. Montagem dos pontos para o Mapa Operacional
        let paradasDoMapa: PontoParada[] = [];

        if (entregasCarregadas.length > 0) {
          paradasDoMapa = entregasCarregadas
            .filter(e => e.status !== 'cancelada')
            .map((e, idx) => {
              const cli = e.clientes_enderecos;
              const record = e as unknown as Record<string, unknown>;
              const route = rotasCarregadas.find(r => r.id === e.rota_id);
              const snapshot = Array.isArray(route?.ordem_paradas_json) ? (route.ordem_paradas_json as any[]).find(p => p.cliente_endereco_id === e.cliente_endereco_id || p.id === e.id) : undefined;
              const rawLat = record.latitude ?? cli?.latitude ?? snapshot?.coordenadas?.lat;
              const rawLng = record.longitude ?? cli?.longitude ?? snapshot?.coordenadas?.lng;
              const lat = rawLat == null ? NaN : Number(rawLat);
              const lng = rawLng == null ? NaN : Number(rawLng);

              return {
                id: e.id,
                status: e.status,
                rotaId: e.rota_id || undefined,
                sequencia: e.ordem_na_rota || idx + 1,
                clienteEnderecoId: e.cliente_endereco_id,
                nomeLocal: cli?.nome_identificador || e.unidade_apartamento || 'Local',
                destinatario: e.destinatario_nome,
                enderecoFormatado: String(record.endereco || snapshot?.endereco_formatado || cli?.endereco_completo || ''),
                coordenadas: { lat, lng },
                tempoMedioAtendimentoMinutos: cli?.tempo_medio_minutos || 11,
                tipoTarefa: (e.tipo_tarefa as any) || 'entrega',
                prioridade: (e.prioridade as any) || 'normal',
                codigoRastreio: e.codigo_rastreio,
              };
            }).filter(p => Number.isFinite(p.coordenadas.lat) && Number.isFinite(p.coordenadas.lng) && Math.abs(p.coordenadas.lat) <= 90 && Math.abs(p.coordenadas.lng) <= 180);
        }

        // 4. Consulta motoristas e veículos ativos com localização em tempo real
        let totalMotoristas = 0;
        let veiculosLista: MotoristaVeiculoMapa[] = [];
        if (companyId) {
          try {
            const { data: motData, count, error } = await supabase
              .from('motoristas')
              .select('*', { count: 'exact' })
              .eq('empresa_id', companyId)
              .eq('ativo', true);

            if (!error && Array.isArray(motData)) {
              totalMotoristas = count ?? motData.length;
              veiculosLista = motData.map((m) => {
                const tipo = normalizarTipoVeiculo(m.veiculo_tipo, m.veiculo_modelo);
                const rotaDoMotorista = rotasCarregadas.find(r => r.motorista_id === m.id && r.status !== 'cancelada');

                let lat = m.latitude_atual ? Number(m.latitude_atual) : NaN;
                let lng = m.longitude_atual ? Number(m.longitude_atual) : NaN;

                // Se ainda não houver GPS ao vivo, utiliza a origem da rota ou a primeira parada
                if ((isNaN(lat) || isNaN(lng)) && rotaDoMotorista) {
                  const cfg = rotaDoMotorista.configuracao_navegacao;
                  if (cfg?.latitude && cfg?.longitude) {
                    lat = Number(cfg.latitude);
                    lng = Number(cfg.longitude);
                  } else {
                    const primeiraParada = paradasDoMapa.find(p => p.rotaId === rotaDoMotorista.id);
                    if (primeiraParada) {
                      lat = primeiraParada.coordenadas.lat;
                      lng = primeiraParada.coordenadas.lng;
                    }
                  }
                }

                return {
                  id: m.id,
                  nome: m.nome,
                  veiculo_tipo: tipo,
                  veiculo_modelo: m.veiculo_modelo || 'Veículo Padrão',
                  veiculo_placa: m.veiculo_placa || '',
                  status: (m.status as any) || (rotaDoMotorista ? 'em_rota' : 'disponivel'),
                  coordenadas: {
                    lat: !isNaN(lat) ? lat : -27.5954,
                    lng: !isNaN(lng) ? lng : -48.5480,
                  },
                  localizacao_atualizada_em: m.localizacao_atualizada_em || undefined,
                  rota_id: rotaDoMotorista?.id,
                };
              }).filter(v => Number.isFinite(v.coordenadas.lat) && Number.isFinite(v.coordenadas.lng));
            }
          } catch (e) {
            console.warn('[OverviewView] Consulta de motoristas retornou vazio ou erro silenciado:', e);
          }
        }

        if (active) {
          setDeliveries(entregasCarregadas);
          setRotasPlanejadas(rotasCarregadas);
          setParadasMapa(paradasDoMapa);
          setPontoPartida(obterPontoPartidaPadrao());
          setDrivers(totalMotoristas);
          setVeiculosAtivos(veiculosLista);
        }
      } catch (err) {
        console.warn('[OverviewView] Erro geral capturado de forma resiliente:', err);
        if (active) {
          setDeliveries([]);
          setRotasPlanejadas([]);
          setParadasMapa([]);
          setDrivers(0);
        }
      } finally {
        if (active) {
          setLoading(false);
          setRefreshing(false);
        }
      }
    }

    void loadData();

    // Sincronização em tempo real de posições de motoristas via canal do Supabase
    const canalMotoristas = supabase
      .channel('realtime_fleet_overview')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'motoristas' },
        () => {
          if (document.visibilityState === 'visible') void loadData();
        }
      )
      .subscribe();

    const refreshTimer = window.setInterval(() => { 
      if (document.visibilityState === "visible") void loadData(); 
    }, 8000);

    return () => {
      window.clearInterval(refreshTimer);
      void supabase.removeChannel(canalMotoristas);
      active = false;
    };
  }, [revision]);

  const entregasConcluidas = deliveries.filter(d => d.status === 'entregue').length;
  const entregasEmTransito = deliveries.filter(d => d.status === 'em_transito' || d.status === 'atribuida').length;
  const totalKmHoje = rotasPlanejadas.reduce(
    (acc, r) => acc + (r.metricas_fonte === 'mapbox_directions_planejamento' && r.metricas_atualizadas_em ? Number(r.distancia_otimizada_km || 0) : 0),
    0
  );

  const kpis = [
    {
      label: 'Entregas Hoje',
      valor: deliveries.length,
      descricao: 'Total programado para hoje',
      icone: Package,
      corIcone: 'text-blue-600',
      bgIcone: 'bg-blue-50 border-blue-100',
    },
    {
      label: 'Concluídas',
      valor: entregasConcluidas,
      descricao: `${deliveries.length > 0 ? Math.round((entregasConcluidas / deliveries.length) * 100) : 0}% de conclusão`,
      icone: CheckCircle2,
      corIcone: 'text-emerald-600',
      bgIcone: 'bg-emerald-50 border-emerald-100',
    },
    {
      label: 'Em Trânsito / Atribuídas',
      valor: entregasEmTransito,
      descricao: 'Em rota com os condutores',
      icone: Truck,
      corIcone: 'text-amber-600',
      bgIcone: 'bg-amber-50 border-amber-100',
    },
    {
      label: 'Motoristas Ativos',
      valor: drivers,
      descricao: 'Frota ativa na empresa',
      icone: Users,
      corIcone: 'text-purple-600',
      bgIcone: 'bg-purple-50 border-purple-100',
    },
  ];

  return (
    <div className="space-y-6 animate-fadeIn">
      {/* CABEÇALHO */}
      <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-navy-900">
            Visão Geral das Operações
          </h1>
          <p className="text-xs text-slate-500 mt-1">
            Painel de controle logístico em tempo real da administradora
          </p>
        </div>

        <div className="flex items-center gap-2.5">
          <button
            type="button"
            onClick={() => setRevision(r => r + 1)}
            disabled={refreshing}
            className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-200 rounded-xl hover:bg-slate-50 transition-colors shadow-sm disabled:opacity-50"
          >
            <RotateCw className={`w-3.5 h-3.5 ${refreshing ? 'animate-spin text-terracotta-600' : 'text-slate-400'}`} />
            <span>{refreshing ? 'Atualizando…' : 'Atualizar'}</span>
          </button>

          <button
            type="button"
            onClick={onGoToOptimizer || onOpenNewDelivery}
            className="inline-flex items-center gap-2 px-4 py-2 text-xs font-bold text-white bg-terracotta-600 hover:bg-terracotta-700 rounded-xl transition-all shadow-md shadow-terracotta-600/20"
          >
            <Plus className="w-4 h-4" />
            <span>Nova Rota de Entregas</span>
          </button>
        </div>
      </header>

      {/* CARDS DE KPI / MÉTRICAS ZERADAS E ELEGANTES */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {kpis.map((kpi) => {
          const Icon = kpi.icone;
          return (
            <div
              key={kpi.label}
              className="bg-white rounded-2xl p-5 border border-slate-200/90 shadow-card flex items-start justify-between gap-4 transition-all hover:border-slate-300"
            >
              <div>
                <span className="text-xs font-semibold text-slate-500 uppercase tracking-wider">
                  {kpi.label}
                </span>
                <div className="text-3xl font-black text-navy-900 tracking-tight mt-1.5">
                  {loading ? (
                    <span className="inline-block w-8 h-8 bg-slate-100 rounded-md animate-pulse" />
                  ) : (
                    kpi.valor
                  )}
                </div>
                <p className="text-[11px] text-slate-400 font-medium mt-1">
                  {kpi.descricao}
                </p>
              </div>

              <div className={`w-11 h-11 rounded-xl border flex items-center justify-center shrink-0 ${kpi.bgIcone}`}>
                <Icon className={`w-5 h-5 ${kpi.corIcone}`} />
              </div>
            </div>
          );
        })}
      </div>

      {/* SEÇÃO DO MAPA OPERACIONAL EM TEMPO REAL */}
      <section className="bg-white rounded-2xl border border-slate-200/90 shadow-card overflow-hidden">
        <div className="px-6 py-4.5 border-b border-slate-100 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-blue-50 text-blue-600 flex items-center justify-center font-bold">
              <MapPin className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-navy-900">
                Mapa Operacional em Tempo Real
              </h2>
              <p className="text-[11px] text-slate-400">
                Trajeto do dia, paradas georreferenciadas e ponto de partida da sede
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-blue-50 text-blue-700 text-xs font-bold border border-blue-100">
              <span className="w-2 h-2 rounded-full bg-blue-600 animate-pulse"></span>
              {paradasMapa.length} {paradasMapa.length === 1 ? 'parada ativa' : 'paradas ativas'}
            </span>
            {rotasPlanejadas.length > 0 && (
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-emerald-50 text-emerald-700 text-xs font-bold border border-emerald-100">
                <Route className="w-3.5 h-3.5" />
                {rotasPlanejadas.length} {rotasPlanejadas.length === 1 ? 'rota do dia' : 'rotas do dia'}
              </span>
            )}
          </div>
        </div>

        <div className="p-4 bg-slate-50/50">
          <RouteMap
            showStartPoint={false}
            routeOrigins={Object.fromEntries(rotasPlanejadas.map(r => [r.id, r.configuracao_navegacao || {}]))}
            pontoPartida={pontoPartida}
            paradas={paradasMapa}
            veiculosAtivos={veiculosAtivos}
            otimizado={true}
          />
        </div>

        {/* Barra de resumo da operação no rodapé do mapa */}
        <div className="px-6 py-3 bg-white border-t border-slate-100 flex flex-wrap items-center justify-between gap-3 text-xs text-slate-600">
          <div className="flex items-center gap-4">
            <span className="flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-[#0F1B2D]"></span>
              <span className="font-medium text-slate-500">Ponto de partida:</span>
              <strong className="text-navy-900">{pontoPartida.nome}</strong>
            </span>
            {totalKmHoje > 0 && (
              <span className="hidden sm:inline-flex items-center gap-1 text-slate-500">
                · <strong>{totalKmHoje.toFixed(1)} km</strong> programados
              </span>
            )}
          </div>

          {paradasMapa.length === 0 ? (
            <span className="text-slate-400 font-medium">
              Aguardando nova rota despachada hoje
            </span>
          ) : (
            <span className="font-semibold text-emerald-700 flex items-center gap-1">
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
              Rotas ativas sincronizadas com o Supabase
            </span>
          )}
        </div>
      </section>

      {/* SEÇÃO PRINCIPAL: ENTREGAS DE HOJE */}
      <div className="bg-white rounded-2xl border border-slate-200/90 shadow-card overflow-hidden">
        <div className="px-6 py-4.5 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-bold text-navy-900">
              Entregas Programadas para Hoje
            </h2>
            <span className="text-xs font-bold px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
              {deliveries.length}
            </span>
          </div>

          <span className="text-xs text-slate-400 font-medium hidden sm:inline">
            Florianópolis e Região
          </span>
        </div>

        {loading ? (
          <div className="py-16 text-center space-y-3">
            <div className="w-8 h-8 border-2 border-terracotta-500 border-t-transparent rounded-full animate-spin mx-auto" />
            <p className="text-xs font-medium text-slate-500">
              Carregando dados da empresa…
            </p>
          </div>
        ) : deliveries.length === 0 ? (
          /* EMPTY STATE ELEGANTE */
          <div className="py-16 px-6 text-center max-w-md mx-auto space-y-4">
            <div className="w-16 h-16 rounded-2xl bg-slate-50 border border-slate-200 flex items-center justify-center mx-auto text-slate-400 shadow-inner">
              <Inbox className="w-8 h-8 text-slate-400" />
            </div>

            <div>
              <h3 className="text-base font-bold text-navy-900">
                Nenhuma entrega cadastrada para hoje
              </h3>
              <p className="text-xs text-slate-500 mt-1.5 leading-relaxed">
                Sua operação está pronta. Crie uma nova rota otimizada para seus condomínios ou adicione paradas aos motoristas.
              </p>
            </div>

            <div className="pt-2">
              <button
                type="button"
                onClick={onGoToOptimizer || onOpenNewDelivery}
                className="inline-flex items-center gap-2 px-4 py-2.5 bg-navy-800 hover:bg-navy-900 text-white text-xs font-bold rounded-xl transition-all shadow-md shadow-navy-900/15"
              >
                <Route className="w-4 h-4 text-terracotta-400" />
                <span>Criar Primeira Rota</span>
                <ArrowRight className="w-3.5 h-3.5 text-slate-400" />
              </button>
            </div>
          </div>
        ) : (
          /* LISTA DE ENTREGAS */
          <div className="divide-y divide-slate-100 overflow-x-auto">
            {deliveries.map((delivery) => (
              <div
                key={delivery.id}
                className="px-6 py-3.5 flex items-center justify-between gap-4 hover:bg-slate-50/80 transition-colors text-xs"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-8 h-8 rounded-lg bg-blue-50 text-blue-600 flex items-center justify-center shrink-0 font-bold text-[10px]">
                    <Package className="w-4 h-4" />
                  </div>
                  <div className="min-w-0">
                    <span className="font-bold text-slate-900 block truncate">
                      {delivery.destinatario_nome}
                    </span>
                    <span className="text-[11px] text-slate-400 block truncate">
                      {delivery.codigo_rastreio} {delivery.unidade_apartamento ? `· ${delivery.unidade_apartamento}` : ''}
                    </span>
                  </div>
                </div>

                <div className="flex items-center gap-3 shrink-0">
                  <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider ${
                    delivery.status === 'entregue'
                      ? 'bg-emerald-100 text-emerald-800'
                      : delivery.status === 'em_transito'
                      ? 'bg-amber-100 text-amber-800'
                      : 'bg-slate-100 text-slate-700'
                  }`}>
                    {delivery.status.replace('_', ' ')}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* GUIA DE INÍCIO RÁPIDO PARA GESTOR QUANDO BANCO ESTÁ VAZIO */}
      {deliveries.length === 0 && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div
            onClick={onGoToOptimizer || onOpenNewDelivery}
            className="p-5 bg-white rounded-2xl border border-slate-200/90 shadow-card hover:border-terracotta-500/50 hover:shadow-md transition-all cursor-pointer group"
          >
            <div className="w-10 h-10 rounded-xl bg-orange-50 text-orange-600 flex items-center justify-center mb-3 group-hover:scale-105 transition-transform">
              <Route className="w-5 h-5" />
            </div>
            <h4 className="text-sm font-bold text-navy-900 group-hover:text-terracotta-600 transition-colors">
              1. Nova Rota Otimizada
            </h4>
            <p className="text-xs text-slate-500 mt-1 leading-relaxed">
              Agrupe paradas em condomínios da Grande Florianópolis com cálculo de tempo inteligente.
            </p>
          </div>

          <div
            onClick={onOpenNewDelivery}
            className="p-5 bg-white rounded-2xl border border-slate-200/90 shadow-card hover:border-blue-500/50 hover:shadow-md transition-all cursor-pointer group"
          >
            <div className="w-10 h-10 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center mb-3 group-hover:scale-105 transition-transform">
              <Building2 className="w-5 h-5" />
            </div>
            <h4 className="text-sm font-bold text-navy-900 group-hover:text-blue-600 transition-colors">
              2. Endereços Salvos
            </h4>
            <p className="text-xs text-slate-500 mt-1 leading-relaxed">
              Consulte e salve pontos de entrega frequentes com memória de portaria e balancetes.
            </p>
          </div>

          <div className="p-5 bg-white rounded-2xl border border-slate-200/90 shadow-card flex items-start gap-3">
            <div className="w-10 h-10 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center shrink-0">
              <ShieldCheck className="w-5 h-5" />
            </div>
            <div>
              <h4 className="text-sm font-bold text-navy-900">
                3. Gestão Integrada
              </h4>
              <p className="text-xs text-slate-500 mt-1 leading-relaxed">
                Aprovações atômicas de condutores, segurança multi-empresa e auditoria ativas.
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
