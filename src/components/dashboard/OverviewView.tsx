import { receiptLabel } from "./receiptLabels";
import { useEffect, useState } from "react";
import { Plus, RotateCw, Search } from "lucide-react";
import { DriversPanel } from "./DriversPanel";
import { TodayDeliveriesTable, deliveryStatus } from "./TodayDeliveriesTable";
import { supabase } from "../../lib/supabase";
import { requireCompanyId } from "../../lib/company";
import type { Database } from "../../types/database";
import { RouteMap } from "../routing/RouteMap";
import { MapStyleSelector } from "../routing/MapStyleSelector";
import { DEFAULT_MAP_STYLE } from "../routing/mapStyles";
import type { PontoParada } from "../../types/logistics";
import {
  obterPontoPartidaPadrao,
  type PontoPartidaItem,
} from "../../features/routes/services/routeOptimization";
import {
  normalizarTipoVeiculo,
  type MotoristaVeiculoMapa,
} from "../../features/routes/utils/vehicleMovement";

type Delivery = Database["public"]["Tables"]["entregas"]["Row"] & {
  clientes_enderecos?:
    | Database["public"]["Tables"]["clientes_enderecos"]["Row"]
    | null;
};

type RotaPlanejada = Database["public"]["Tables"]["rotas_planejadas"]["Row"] & {
  configuracao_navegacao?: {
    latitude?: number;
    longitude?: number;
    retornar_ao_inicio?: boolean;
  };
};

interface OverviewViewProps {
  onGoToOptimizer?: () => void;
  onOpenNewDelivery?: () => void;
}

export function OverviewView({
  onGoToOptimizer,
  onOpenNewDelivery,
}: OverviewViewProps) {
  const [deliveries, setDeliveries] = useState<Delivery[]>([]);
  const [rotasPlanejadas, setRotasPlanejadas] = useState<RotaPlanejada[]>([]);
  const [paradasMapa, setParadasMapa] = useState<PontoParada[]>([]);
  const [pontoPartida, setPontoPartida] = useState<PontoPartidaItem>(() =>
    obterPontoPartidaPadrao(),
  );
  const [drivers, setDrivers] = useState<
    Database["public"]["Tables"]["motoristas"]["Row"][]
  >([]);
  const [receivers, setReceivers] = useState<Record<string, string>>({});
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("Todas");
  const [driverFilter, setDriverFilter] = useState("");
  const [estiloMapa, setEstiloMapa] = useState<string>(DEFAULT_MAP_STYLE);
  const [loadError, setLoadError] = useState("");
  const [veiculosAtivos, setVeiculosAtivos] = useState<MotoristaVeiculoMapa[]>(
    [],
  );
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
        const companyId = await requireCompanyId();
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const [deliveryResult, routeResult, driverResult] = await Promise.all([
          supabase
            .from("entregas")
            .select("*,clientes_enderecos(*)")
            .eq("empresa_id", companyId)
            .gte("created_at", today.toISOString())
            .order("ordem_na_rota", { ascending: true }),
          supabase
            .from("rotas_planejadas")
            .select("*")
            .eq("empresa_id", companyId)
            .gte("created_at", today.toISOString())
            .order("created_at", { ascending: false }),
          supabase
            .from("motoristas")
            .select("*")
            .eq("empresa_id", companyId)
            .eq("ativo", true),
        ]);
        for (const result of [deliveryResult, routeResult, driverResult])
          if (result.error) throw result.error;
        const entregasCarregadas = deliveryResult.data as Delivery[];
        const rotasCarregadas = routeResult.data as RotaPlanejada[];

        // 3. Montagem dos pontos para o Mapa Operacional
        let paradasDoMapa: PontoParada[] = [];

        if (entregasCarregadas.length > 0) {
          paradasDoMapa = entregasCarregadas
            .filter((e) => e.status !== "cancelada")
            .map((e, idx) => {
              const cli = e.clientes_enderecos;
              const record = e as unknown as Record<string, unknown>;
              const route = rotasCarregadas.find((r) => r.id === e.rota_id);
              const snapshot = Array.isArray(route?.ordem_paradas_json)
                ? (route.ordem_paradas_json as any[]).find(
                    (p) =>
                      p.cliente_endereco_id === e.cliente_endereco_id ||
                      p.id === e.id,
                  )
                : undefined;
              const rawLat =
                record.latitude ?? cli?.latitude ?? snapshot?.coordenadas?.lat;
              const rawLng =
                record.longitude ??
                cli?.longitude ??
                snapshot?.coordenadas?.lng;
              const lat = rawLat == null ? NaN : Number(rawLat);
              const lng = rawLng == null ? NaN : Number(rawLng);

              return {
                id: e.id,
                status: e.status,
                rotaId: e.rota_id || undefined,
                sequencia: e.ordem_na_rota || idx + 1,
                clienteEnderecoId: e.cliente_endereco_id,
                nomeLocal:
                  cli?.nome_identificador || e.unidade_apartamento || "Local",
                destinatario: e.destinatario_nome,
                enderecoFormatado: String(
                  record.endereco ||
                    snapshot?.endereco_formatado ||
                    cli?.endereco_completo ||
                    "",
                ),
                coordenadas: { lat, lng },
                tempoMedioAtendimentoMinutos: cli?.tempo_medio_minutos || 0,
                tipoTarefa: (e.tipo_tarefa as any) || "entrega",
                prioridade: (e.prioridade as any) || "normal",
                codigoRastreio: e.codigo_rastreio,
              };
            })
            .filter(
              (p) =>
                Number.isFinite(p.coordenadas.lat) &&
                Number.isFinite(p.coordenadas.lng) &&
                Math.abs(p.coordenadas.lat) <= 90 &&
                Math.abs(p.coordenadas.lng) <= 180,
            );
        }

        // 4. Consulta motoristas e veículos ativos com localização em tempo real
        let driverRows: Database["public"]["Tables"]["motoristas"]["Row"][] =
          [];
        let veiculosLista: MotoristaVeiculoMapa[] = [];
        if (companyId) {
          try {
            const { data: motData, error } = driverResult;

            if (!error && Array.isArray(motData)) {
              driverRows = motData;
              veiculosLista = motData
                .map((m) => {
                  const tipo = normalizarTipoVeiculo(
                    m.veiculo_tipo,
                    m.veiculo_modelo,
                  );
                  const rotaDoMotorista = rotasCarregadas.find(
                    (r) => r.motorista_id === m.id && r.status !== "cancelada",
                  );

                  const lat =
                    m.latitude_atual == null ? NaN : Number(m.latitude_atual);
                  const lng =
                    m.longitude_atual == null ? NaN : Number(m.longitude_atual);

                  return {
                    id: m.id,
                    nome: m.nome,
                    veiculo_tipo: tipo,
                    veiculo_modelo: m.veiculo_modelo || "Veículo Padrão",
                    veiculo_placa: m.veiculo_placa || "",
                    status:
                      (m.status as any) ||
                      (rotaDoMotorista ? "em_rota" : "disponivel"),
                    coordenadas: {
                      lat,
                      lng,
                    },
                    localizacao_atualizada_em:
                      m.localizacao_atualizada_em || undefined,
                    rota_id: rotaDoMotorista?.id,
                  };
                })
                .filter(
                  (v) =>
                    Number.isFinite(v.coordenadas.lat) &&
                    Number.isFinite(v.coordenadas.lng) &&
                    v.localizacao_atualizada_em &&
                    Date.now() - Date.parse(v.localizacao_atualizada_em) <
                      300000,
                );
            }
          } catch (e) {
            throw e;
          }
        }

        const received: Record<string, string> = {};
        if (companyId && entregasCarregadas.length) {
          const receiptResult = await supabase
            .from("entrega_comprovantes")
            .select("entrega_id,recebedor_tipo,recebedor_nome")
            .eq("empresa_id", companyId)
            .in(
              "entrega_id",
              entregasCarregadas.map((d) => d.id),
            );
          if (receiptResult.error) throw receiptResult.error;
          for (const receipt of receiptResult.data || []) {
            if (receipt.recebedor_tipo !== "tentativa_falha")
              received[receipt.entrega_id] = [
                receiptLabel(receipt.recebedor_tipo),
                receipt.recebedor_nome,
              ]
                .filter(Boolean)
                .join(" · ");
          }
        }
        if (active) {
          setDeliveries(entregasCarregadas);
          setRotasPlanejadas(rotasCarregadas);
          setParadasMapa(paradasDoMapa);
          setPontoPartida(obterPontoPartidaPadrao());
          setDrivers(driverRows);
          setReceivers(received);
          setLoadError("");
          setVeiculosAtivos(veiculosLista);
        }
      } catch (err) {
        console.warn("[OverviewView] Falha ao consultar operação:", err);
        if (active)
          setLoadError("Não foi possível atualizar os dados. Tente novamente.");
        if (active) {
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
      .channel("realtime_fleet_overview")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "motoristas" },
        () => {
          if (document.visibilityState === "visible") void loadData();
        },
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

  const entregasConcluidas = deliveries.filter(
    (d) => d.status === "entregue",
  ).length;
  const entregasEmTransito = deliveries.filter(
    (d) => d.status === "em_transito" || d.status === "atribuida",
  ).length;
  const totalKmHoje = rotasPlanejadas.reduce(
    (acc, r) =>
      acc +
      (r.metricas_fonte === "mapbox_directions_planejamento" &&
      r.metricas_atualizadas_em
        ? Number(r.distancia_otimizada_km || 0)
        : 0),
    0,
  );

  const occurrences = deliveries.filter(
    (d) => deliveryStatus(d.status) === "Ocorrência",
  ).length;
  const savedKm = rotasPlanejadas.reduce(
    (sum, r) =>
      sum +
      (r.metricas_fonte === "mapbox_directions_planejamento" &&
      r.metricas_atualizadas_em
        ? Math.max(
            0,
            Number(r.distancia_original_km || 0) -
              Number(r.distancia_otimizada_km || 0),
          )
        : 0),
    0,
  );
  const progress = drivers.map((driver) => {
    const tasks = deliveries.filter((d) => d.motorista_id === driver.id);
    const next = tasks.find(
      (d) =>
        ![
          "entregue",
          "tentativa_falha",
          "falha",
          "falhou",
          "cancelada",
        ].includes(d.status),
    );
    return {
      driver,
      total: tasks.length,
      completed: tasks.filter((d) => d.status === "entregue").length,
      next: next?.clientes_enderecos?.endereco_completo || "",
      active: rotasPlanejadas.some(
        (r) => r.motorista_id === driver.id && r.status === "em_execucao",
      ),
    };
  });
  const filtered = deliveries.filter(
    (d) =>
      (!driverFilter || d.motorista_id === driverFilter) &&
      (statusFilter === "Todas" || deliveryStatus(d.status) === statusFilter) &&
      `${d.destinatario_nome} ${d.codigo_rastreio} ${d.clientes_enderecos?.endereco_completo || ""}`
        .toLocaleLowerCase("pt-BR")
        .includes(search.toLocaleLowerCase("pt-BR")),
  );
  const routeIds = new Set(
    rotasPlanejadas
      .filter((r) => !driverFilter || r.motorista_id === driverFilter)
      .map((r) => r.id),
  );
  const kpis = [
    ["Entregas hoje", deliveries.length, "Tarefas cadastradas hoje"],
    [
      "Concluídas",
      entregasConcluidas,
      `${deliveries.length ? Math.round((entregasConcluidas / deliveries.length) * 100) : 0}% do total do dia`,
    ],
    [
      "Em rota agora",
      entregasEmTransito,
      `${progress.filter((p) => p.active).length} motoristas em rota`,
    ],
    [
      "Km economizados",
      `${savedKm.toFixed(1).replace(".", ",")} km`,
      "pela rota inteligente",
    ],
    [
      "Ocorrências",
      occurrences,
      occurrences ? "exigem sua atenção" : "Nenhuma ocorrência registrada",
    ],
  ];
  return (
    <div className="space-y-6 text-[#0F1B2D]">
      <header className="flex flex-wrap justify-between items-center gap-4">
        <div>
          <h1 className="text-[26px] font-extrabold tracking-tight">
            Visão geral
          </h1>
          <p className="text-sm text-[#516074] mt-1 capitalize">
            {new Date().toLocaleDateString("pt-BR", {
              weekday: "long",
              day: "numeric",
              month: "long",
            })}{" "}
            · {refreshing ? "atualizando" : "atualização automática"}
          </p>
        </div>
        <div className="flex items-center gap-3 flex-wrap">
          <label className="flex items-center gap-2 border border-slate-300 rounded-xl bg-white px-3 py-3">
            <Search size={18} className="text-slate-500" />
            <input
              aria-label="Buscar entregas"
              placeholder="Buscar cliente, endereço ou pedido"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="outline-none text-sm w-56"
            />
          </label>
          <button
            type="button"
            onClick={() => setRevision((r) => r + 1)}
            aria-label="Atualizar operação"
            disabled={refreshing}
            className="p-3 rounded-xl border bg-white"
          >
            <RotateCw size={18} className={refreshing ? "animate-spin" : ""} />
          </button>
          <button
            onClick={onOpenNewDelivery || onGoToOptimizer}
            className="bg-[#C2410C] text-white rounded-xl px-5 py-3 flex items-center gap-2 font-bold text-sm"
          >
            <Plus size={18} />
            Nova entrega
          </button>
        </div>
      </header>
      {loadError && (
        <p role="alert" className="p-4 rounded-xl bg-red-50 text-red-800">
          {loadError}
        </p>
      )}
      <div className="grid grid-cols-2 xl:grid-cols-5 xl:divide-x divide-gray-200 bg-white border border-gray-300 rounded-2xl overflow-hidden max-xl:[&>*:nth-child(even)]:border-l max-xl:[&>*:nth-child(n+3)]:border-t max-xl:[&>*]:border-gray-200">
        {kpis.map(([label, value, caption], i) => (
          <section key={label} className="p-5">
            <h2 className="text-sm font-semibold text-[#516074]">{label}</h2>
            <strong
              className={`block text-3xl font-extrabold mt-2 ${i === 4 ? "text-red-800" : ""}`}
            >
              {loading ? "—" : value}
            </strong>
            {i === 1 && (
              <div className="h-1.5 bg-slate-200 rounded-full mt-2 overflow-hidden">
                <div
                  className="h-full bg-green-700"
                  style={{
                    width: `${deliveries.length ? (entregasConcluidas / deliveries.length) * 100 : 0}%`,
                  }}
                />
              </div>
            )}
            <p
              className={`text-xs mt-2 ${i === 4 && occurrences ? "text-red-700" : "text-slate-500"}`}
            >
              {caption}
            </p>
          </section>
        ))}
      </div>
      <div className="grid grid-cols-1 xl:grid-cols-[1.62fr_1fr] gap-6">
        <section className="bg-white border border-gray-300 rounded-2xl p-5">
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <h2 className="font-extrabold text-lg">
              Rotas em tempo real
            </h2>
            <MapStyleSelector
              value={estiloMapa}
              onChange={setEstiloMapa}
              className="mr-auto"
            />
            <button
              onClick={() => setDriverFilter("")}
              aria-pressed={!driverFilter}
              className={`px-3 py-2 text-xs rounded-full border font-bold ${!driverFilter ? "bg-[#0F1B2D] text-white" : ""}`}
            >
              Todos
            </button>
            {drivers.map((d) => (
              <button
                key={d.id}
                onClick={() => setDriverFilter(d.id)}
                aria-pressed={driverFilter === d.id}
                className={`text-xs rounded-full border px-3 py-2 font-bold ${driverFilter === d.id ? "bg-[#0F1B2D] text-white" : ""}`}
              >
                {d.nome.split(" ")[0]}
              </button>
            ))}
          </div>
          <RouteMap
            estiloMapa={estiloMapa}
            showStartPoint={false}
            routeOrigins={Object.fromEntries(
              rotasPlanejadas.map((r) => [
                r.id,
                r.configuracao_navegacao || {},
              ]),
            )}
            pontoPartida={pontoPartida}
            paradas={paradasMapa.filter(
              (p) => !driverFilter || (p.rotaId && routeIds.has(p.rotaId)),
            )}
            veiculosAtivos={veiculosAtivos.filter(
              (v) => !driverFilter || v.id === driverFilter,
            )}
            otimizado
          />
          <p className="text-xs text-slate-500 mt-4">
            ● Azul: pendente · ● Verde: concluída · ● Vermelho: falha
          </p>
          <p className="text-xs text-slate-500 mt-2">
            Veículos: GPS recebido nos últimos 5 minutos.{" "}
            {totalKmHoje > 0 ? `${totalKmHoje.toFixed(1)} km planejados.` : ""}
          </p>
        </section>
        <DriversPanel
          rows={progress.filter(
            (p) => !driverFilter || p.driver.id === driverFilter,
          )}
          onAssign={onOpenNewDelivery || onGoToOptimizer}
        />
      </div>
      <section className="bg-white border border-gray-300 rounded-2xl p-5">
        <div className="flex flex-wrap items-center gap-2 mb-4">
          <h2 className="text-lg font-extrabold mr-auto">Entregas de hoje</h2>
          {["Todas", "Em rota", "Entregue", "Ocorrência"].map((status) => (
            <button
              key={status}
              onClick={() => setStatusFilter(status)}
              aria-pressed={status === statusFilter}
              className={`px-3 py-2 rounded-full border font-bold text-xs ${status === statusFilter ? "bg-[#0F1B2D] text-white" : ""}`}
            >
              {status}{" "}
              {status === "Todas"
                ? deliveries.length
                : deliveries.filter((d) => deliveryStatus(d.status) === status)
                    .length}
            </button>
          ))}
        </div>
        {loading ? (
          <p className="p-12 text-center text-slate-500">
            Carregando dados da empresa…
          </p>
        ) : (
          <TodayDeliveriesTable
            rows={filtered}
            drivers={Object.fromEntries(drivers.map((d) => [d.id, d.nome]))}
            receivers={receivers}
          />
        )}
      </section>
    </div>
  );
}
