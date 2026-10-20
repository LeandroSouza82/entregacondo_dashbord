import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, Json } from "../../../types/database";
import { fetchRoadPlan, type RoadCoordinate } from "./roadGeometry.ts";
import { collectionRoadCosts } from "./collectionRoadCosts.ts";
import { insertCollections } from "./collectionInsertion.ts";
export interface DispatchTask {
  cliente_endereco_id: string | null;
  tipo_tarefa: string;
  [key: string]: unknown;
}
export interface DispatchPayload {
  empresa_id: string;
  motorista_id: string;
  paradas: DispatchTask[];
  idempotency_key: string;
  [key: string]: unknown;
}
export interface DispatchResult {
  sucesso: boolean;
  codigo?: string;
  mensagem: string;
  coletas_adicionadas?: number;
  nova_rota_id?: string | null;
  rota_ativa_id?: string | null;
  idempotente?: boolean;
}
export async function dispatchDriverServices(
  client: SupabaseClient<Database>,
  payload: DispatchPayload,
  origin: RoadCoordinate,
  token: string,
): Promise<DispatchResult> {
  async function send(plan: Record<string, unknown> | null) {
    const response = await client.rpc("enviar_servicos_motorista", {
      p_dados: payload as unknown as Json,
      p_plano_coletas: plan as Json,
    });
    if (response.error)
      throw new Error(
        `Não foi possível confirmar o envio: ${response.error.message}`,
      );
    return response.data as unknown as DispatchResult;
  }
  const initial = await send(null);
  if (initial.sucesso || initial.codigo !== "PLANO_COLETAS_NECESSARIO")
    return initial;
  // Refresh the snapshot once if the driver changes a stop during the road calculation.
  for (let attempt = 0; attempt < 2; attempt++) {
    const routeResult = await client
      .from("rotas_planejadas")
      .select("*")
      .eq("empresa_id", payload.empresa_id)
      .eq("motorista_id", payload.motorista_id)
      .eq("status", "em_execucao");
    if (routeResult.error) throw routeResult.error;
    if (routeResult.data.length !== 1)
      throw new Error(
        "A rota ativa mudou ou há mais de uma. Atualize o painel antes de enviar.",
      );
    const route = routeResult.data[0];
    const [driverResult, taskResult] = await Promise.all([
      client
        .from("motoristas")
        .select("latitude_atual,longitude_atual,localizacao_atualizada_em")
        .eq("id", payload.motorista_id)
        .eq("empresa_id", payload.empresa_id)
        .single(),
      client
        .from("entregas")
        .select(
          "id,status,ordem_na_rota,chegada_em,clientes_enderecos(latitude,longitude)",
        )
        .eq("empresa_id", payload.empresa_id)
        .eq("rota_id", route.id)
        .order("ordem_na_rota", { ascending: true })
        .order("id"),
    ]);
    if (driverResult.error) throw driverResult.error;
    if (taskResult.error) throw taskResult.error;
    const driver = driverResult.data;
    if (
      driver.latitude_atual == null ||
      driver.longitude_atual == null ||
      !driver.localizacao_atualizada_em ||
      !Number.isFinite(Date.parse(driver.localizacao_atualizada_em)) ||
      Date.now() - Date.parse(driver.localizacao_atualizada_em) > 300000
    )
      throw new Error(
        "Sem GPS recente do motorista. Peça para ativar a localização no perfil e manter a rota aberta. Os serviços continuam no rascunho.",
      );
    const gps: RoadCoordinate = [
      Number(driver.longitude_atual),
      Number(driver.latitude_atual),
    ];
    const tasks = taskResult.data;
    const unfinished = tasks.filter(
      (t) => !["entregue", "tentativa_falha", "cancelada"].includes(t.status),
    );
    const pinned = unfinished.filter((t) => t.chegada_em !== null);
    if (pinned.length > 1)
      throw new Error(
        "Há mais de um atendimento aberto. Finalize o atendimento pendente antes de inserir coletas.",
      );
    const ordered = [
      ...pinned,
      ...unfinished.filter((t) => t.chegada_em === null),
    ];
    const collections = payload.paradas
      .map((task, index) => ({ task, index }))
      .filter((t) => t.task.tipo_tarefa === "coleta");
    const addresses = await client
      .from("clientes_enderecos")
      .select("id,latitude,longitude")
      .eq("empresa_id", payload.empresa_id)
      .in(
        "id",
        collections.map((c) => c.task.cliente_endereco_id!),
      );
    if (addresses.error) throw addresses.error;
    const coordinate = (
      value: { latitude: number; longitude: number } | null | undefined,
    ): RoadCoordinate => {
      if (
        !value ||
        value.latitude == null ||
        value.longitude == null ||
        !Number.isFinite(Number(value.latitude)) ||
        !Number.isFinite(Number(value.longitude)) ||
        Math.abs(Number(value.latitude)) > 90 ||
        Math.abs(Number(value.longitude)) > 180
      )
        throw new Error(
          "Há uma parada sem coordenadas válidas. Complete o endereço antes de enviar.",
        );
      return [Number(value.longitude), Number(value.latitude)];
    };
    const points: RoadCoordinate[] = [
      gps,
      ...ordered.map((t) => coordinate(t.clientes_enderecos)),
      ...collections.map((c) =>
        coordinate(
          addresses.data.find((a) => a.id === c.task.cliente_endereco_id),
        ),
      ),
    ];
    const keys = [
      ...ordered.map((t) => t.id),
      ...collections.map((c) => `nova:${c.index}`),
    ];
    const old = ordered.map((_, i) => i + 1),
      added = collections.map((_, i) => ordered.length + i + 1);
    const config = route.configuracao_navegacao as {
      latitude?: number;
      longitude?: number;
      retornar_ao_inicio?: boolean;
    } | null;
    let end: number | undefined;
    if (
      config?.retornar_ao_inicio === true &&
      typeof config.latitude === "number" &&
      typeof config.longitude === "number"
    ) {
      end = points.length;
      points.push([config.longitude, config.latitude]);
    }
    const costs = await collectionRoadCosts(points, old, added, end, token);
    const order = insertCollections(
      old,
      added,
      costs,
      pinned.length === 1,
      end,
    );
    const road = await fetchRoadPlan(
      [
        gps,
        ...order.map((i) => points[i]),
        ...(end === undefined ? [] : [points[end]]),
      ],
      token,
    );
    let normalMetrics: Record<string, unknown> | undefined;
    const regular = payload.paradas
      .map((task, index) => ({ task, index }))
      .filter((t) => t.task.tipo_tarefa !== "coleta");
    if (regular.length) {
      const snapshot = payload.ordem_paradas_json as {
        coordenadas: { lat: number; lng: number };
        tipo_tarefa: string;
      }[];
      const normalRoad = await fetchRoadPlan(
        [
          origin,
          ...regular.map(
            (r) =>
              [
                snapshot[r.index].coordenadas.lng,
                snapshot[r.index].coordenadas.lat,
              ] as RoadCoordinate,
          ),
        ],
        token,
      );
      normalMetrics = {
        metricas_fonte: "mapbox_directions_planejamento",
        distancia_original_km: normalRoad.kilometers,
        distancia_otimizada_km: normalRoad.kilometers,
        tempo_original_minutos: normalRoad.minutes,
        tempo_otimizado_minutos: normalRoad.minutes,
      };
    }
    const result = await send({
      rota_id: route.id,
      origem: { lat: gps[1], lng: gps[0] },
      snapshot: tasks.map(({ id, status, ordem_na_rota, chegada_em }) => ({
        id,
        status,
        ordem_na_rota,
        chegada_em,
      })),
      ordem: order.map((i) => keys[i - 1]),
      metricas: {
        fonte: "mapbox_directions_restante",
        distancia_km: road.kilometers,
        tempo_minutos: road.minutes,
      },
      ...(normalMetrics ? { metricas_nova_rota: normalMetrics } : {}),
    });
    if (result.codigo !== "PLANO_DESATUALIZADO") return result;
  }
  return {
    sucesso: false,
    mensagem:
      "O motorista está atualizando a rota. Tente enviar novamente; seu rascunho foi preservado.",
  };
}
