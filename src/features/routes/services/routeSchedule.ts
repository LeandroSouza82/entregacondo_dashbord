export interface RouteRule {
  id: string;
  after?: string | null;
  dependencyDone?: boolean;
  start?: number | null;
  end?: number | null;
  serviceSeconds?: number;
}
export interface ScheduleVisit { id: string; arrival: number; start: number; finish: number }
export interface SchedulePlan { order: number[]; finish: number; roadSeconds: number; waitingSeconds: number; visits: ScheduleVisit[] }
export interface ScheduleOptions { pinFirst?: number; returnIndex?: number }

function validateInput(rules: RouteRule[], costs: number[][], departure: number) {
  if (!Number.isFinite(departure) || costs.length < rules.length + 1 || costs.some(r => r.length !== costs.length || r.some(v => Number.isNaN(v) || v < 0))) throw new Error('Tempos viários inválidos. Recalcule a rota.');
  const ids = new Set(rules.map(r => r.id));
  if (ids.size !== rules.length) throw new Error('Há pedidos duplicados. Atualize a rota.');
  for (const rule of rules) {
    if (!rule.id || rule.after === rule.id || (rule.after && !ids.has(rule.after) && !rule.dependencyDone)) throw new Error('Aceite e conclua a coleta vinculada antes de organizar esta entrega.');
    if ((rule.start == null) !== (rule.end == null) || (rule.start != null && (!Number.isFinite(rule.start) || !Number.isFinite(rule.end) || rule.end! <= rule.start))) throw new Error('Confira a data e a faixa de horário do pedido.');
    if (!Number.isFinite(rule.serviceSeconds ?? 0) || (rule.serviceSeconds ?? 0) < 0) throw new Error('Tempo de atendimento inválido.');
  }
}

export function evaluateSchedule(rules: RouteRule[], costs: number[][], departure: number, order: number[], options: ScheduleOptions = {}): SchedulePlan {
  validateInput(rules, costs, departure);
  if (order.length !== rules.length || new Set(order).size !== rules.length || order.some(i => !Number.isInteger(i) || i < 1 || i > rules.length)) throw new Error('Informe todos os pedidos uma única vez.');
  if (options.pinFirst != null && order[0] !== options.pinFirst) throw new Error('Mantenha o atendimento em andamento na primeira posição.');
  const seen = new Set<string>(), ids = new Set(rules.map(r => r.id));
  let clock = departure, last = 0, roadSeconds = 0, waitingSeconds = 0;
  const visits: ScheduleVisit[] = [];
  for (const index of order) {
    const rule = rules[index - 1];
    if (rule.after && ids.has(rule.after) && !seen.has(rule.after)) throw new Error('A entrega deve ficar depois da coleta vinculada.');
    const road = costs[last][index];
    if (!Number.isFinite(road)) throw new Error('Trajeto viário indisponível entre paradas.');
    const arrival = clock + road * 1000;
    const start = Math.max(arrival, rule.start ?? arrival);
    const finish = start + (rule.serviceSeconds ?? 0) * 1000;
    if (rule.end != null && finish > rule.end) throw new Error('A sequência não cabe nos horários informados. Reveja os horários ou a ordem.');
    visits.push({id: rule.id, arrival, start, finish});
    waitingSeconds += (start - arrival) / 1000; roadSeconds += road;
    clock = finish; last = index; seen.add(rule.id);
  }
  if (options.returnIndex != null && order.length) {
    if (!Number.isInteger(options.returnIndex) || options.returnIndex < 0 || options.returnIndex >= costs.length) throw new Error('Ponto de retorno inválido.');
    const road = costs[last][options.returnIndex];
    if (!Number.isFinite(road)) throw new Error('Trajeto de retorno indisponível.');
    roadSeconds += road; clock += road * 1000;
  }
  return {order: [...order], finish: clock, roadSeconds, waitingSeconds, visits};
}

/** Bounded beam search. Only feasible candidates survive; no optimality guarantee. */
export function optimizeSchedule(rules: RouteRule[], costs: number[][], departure: number, options: ScheduleOptions = {}): SchedulePlan {
  validateInput(rules, costs, departure);
  if (rules.length > 100) throw new Error('Organize grupos de até 100 paradas.');
  const indices = new Map(rules.map((r,i) => [r.id, i + 1]));
  const bits = rules.map((_,i) => 1n << BigInt(i));
  type State = { mask: bigint; order: number[]; time: number; road: number; last: number };
  let beam: State[] = [{mask: 0n, order: [], time: departure, road: 0, last: 0}];
  const width = rules.length > 40 ? 24 : 96;
  for (let depth = 0; depth < rules.length; depth++) {
    const next = new Map<string,State>();
    for (const state of beam) for (let i = 1; i <= rules.length; i++) {
      if ((state.mask & bits[i-1]) !== 0n || (depth === 0 && options.pinFirst != null && i !== options.pinFirst)) continue;
      const rule = rules[i-1], parent = rule.after ? indices.get(rule.after) : undefined;
      if (parent != null && (state.mask & bits[parent-1]) === 0n) continue;
      const road = costs[state.last][i];
      if (!Number.isFinite(road)) continue;
      const time = Math.max(state.time + road * 1000, rule.start ?? -Infinity) + (rule.serviceSeconds ?? 0) * 1000;
      if (rule.end != null && time > rule.end) continue;
      const mask = state.mask | bits[i-1], key = `${mask}:${i}`;
      const candidate = {mask, order:[...state.order,i], time, road:state.road+road, last:i};
      const old = next.get(key);
      if (!old || candidate.time < old.time || (candidate.time === old.time && candidate.road < old.road)) next.set(key,candidate);
    }
    beam = [...next.values()].sort((a,b) => a.time-b.time || a.road-b.road).slice(0,width);
    if (!beam.length) break; // Still consider the original sequence if pruning lost a feasible branch.
  }
  const candidates: SchedulePlan[] = [];
  for (const state of beam) { try { candidates.push(evaluateSchedule(rules,costs,departure,state.order,options)); } catch { /* unreachable return */ } }
  try { candidates.push(evaluateSchedule(rules,costs,departure,rules.map((_,i)=>i+1),options)); } catch { /* infeasible original */ }
  candidates.sort((a,b) => a.finish-b.finish || a.roadSeconds-b.roadSeconds);
  if (!candidates.length) throw new Error('Não foi possível organizar estes horários. A ordem anterior foi preservada.');
  return candidates[0];
}
