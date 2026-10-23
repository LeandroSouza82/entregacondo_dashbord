import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchRoadPlan } from '../src/features/routes/services/roadGeometry.ts';

const route = { code: 'Ok', routes: [{ distance: 12500, duration: 600, geometry: { coordinates: [[-48,-27],[-48.1,-27.1]] } }] };
test('road totals use provider meters and seconds across overlapping chunks', async () => {
  const calls = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url) => { calls.push(url); return Response.json(route); };
  try {
    const points = Array.from({length:27}, (_,i) => [-48-i/100,-27-i/100]);
    const plan = await fetchRoadPlan(points,'test');
    assert.equal(calls.length,2);
    assert.equal(plan.kilometers,25);
    assert.equal(plan.minutes,20);
    assert.equal(plan.lines.length,2);
    assert.ok(calls[1].includes(points[24].join(',')));
  } finally { globalThis.fetch = original; }
});
test('missing duration never becomes a fabricated estimate', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => Response.json({...route,routes:[{...route.routes[0],duration:undefined}]});
  try { await assert.rejects(fetchRoadPlan([[-48,-27],[-48.1,-27.1]],'test'),/estimativa/); }
  finally { globalThis.fetch = original; }
});
test('provider failure and cancellation propagate without a straight line fallback', async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = async () => new Response('',{status:503});
    await assert.rejects(fetchRoadPlan([[-48,-27],[-48.1,-27.1]],'test'),/calcular/);
    globalThis.fetch = async (_url,{signal}) => { signal.throwIfAborted(); };
    const controller = new AbortController(); controller.abort();
    await assert.rejects(fetchRoadPlan([[-48,-27],[-48.1,-27.1]],'test',controller.signal),{name:'AbortError'});
  } finally { globalThis.fetch = original; }
});
test('missing token or fewer than two points is unavailable',async () => {
  await assert.rejects(fetchRoadPlan([[-48,-27]],'test'));
  await assert.rejects(fetchRoadPlan([[-48,-27],[-48.1,-27.1]],''));
});
