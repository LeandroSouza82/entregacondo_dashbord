import test from 'node:test';
import assert from 'node:assert/strict';
import {optimizeSchedule, evaluateSchedule} from '../src/features/routes/services/routeSchedule.ts';
import {ruleDateTime, validateDraftRule, emptyDraftRule, hasRouteRules} from '../src/features/routes/services/routeRules.ts';
import {dispatchDriverOrders} from '../src/features/routes/services/dispatchDriverServices.ts';
const matrix=(n,cost=60)=>Array.from({length:n},(_,i)=>Array.from({length:n},(_,j)=>i===j?0:cost));
const departure=Date.parse('2026-10-22T12:00:00Z');
test('deadline takes precedence over nearest stop; waiting and service fit the complete window',()=>{
 const costs=[[0,60,300],[60,0,300],[300,300,0]];
 const rules=[{id:'near',serviceSeconds:600},{id:'deadline',start:departure+300000,end:departure+600000,serviceSeconds:300}];
 assert.deepEqual(optimizeSchedule(rules,costs,departure).order,[2,1]);
 assert.throws(()=>evaluateSchedule(rules,costs,departure,[1,2]),/horários/);
 const plan=evaluateSchedule([{id:'a',start:departure+600000,end:departure+900000,serviceSeconds:300}],matrix(2),departure,[1]);
 assert.equal(plan.waitingSeconds,540);assert.equal(plan.roadSeconds,60);assert.equal(plan.finish,departure+900000);
});
test('pickup precedes dependent delivery, independently of distances',()=>{
 const costs=[[0,600,1],[600,0,60],[1,60,0]],rules=[{id:'pickup'},{id:'delivery',after:'pickup'}];
 assert.deepEqual(optimizeSchedule(rules,costs,departure).order,[1,2]);
 assert.throws(()=>evaluateSchedule(rules,costs,departure,[2,1]),/depois da coleta/);
});
test('missing dependency blocks; confirmed external pickup permits organization',()=>{
 assert.throws(()=>optimizeSchedule([{id:'d',after:'p'}],matrix(2),departure),/coleta vinculada/);
 assert.deepEqual(optimizeSchedule([{id:'d',after:'p',dependencyDone:true}],matrix(2),departure).order,[1]);
});
test('impossible or cyclic rules leave inputs unchanged',()=>{
 const rules=[{id:'a',end:departure+1000,start:departure}],costs=matrix(2),before=JSON.stringify({rules,costs});
 assert.throws(()=>optimizeSchedule(rules,costs,departure));assert.equal(JSON.stringify({rules,costs}),before);
 assert.throws(()=>optimizeSchedule([{id:'a',after:'b'},{id:'b',after:'a'}],matrix(3),departure));
});
test('started service remains first; directed travel and circuit return are accounted',()=>{
 const costs=[[0,1,20,99],[99,0,10,100],[99,1,0,7],[99,99,99,0]], rules=[{id:'a'},{id:'b'}];
 const plan=optimizeSchedule(rules,costs,departure,{pinFirst:2,returnIndex:3});
 assert.deepEqual(plan.order,[2,1]);assert.equal(plan.roadSeconds,121);
 assert.throws(()=>evaluateSchedule(rules,costs,departure,[1,2],{pinFirst:2}),/andamento/);
 assert.throws(()=>evaluateSchedule(rules,costs,departure,[1,2],{returnIndex:99}),/retorno inválido/);
});
test('invalid matrix, duplicated stops, bad windows and unreachable edges fail safely',()=>{
 assert.throws(()=>optimizeSchedule([{id:'a'}],[[0]],departure));
 assert.throws(()=>optimizeSchedule([{id:'a'},{id:'a'}],matrix(3),departure),/duplicados/);
 assert.throws(()=>optimizeSchedule([{id:'a',start:departure}],matrix(2),departure),/faixa/);
 assert.throws(()=>optimizeSchedule([{id:'a'}],[[0,Infinity],[Infinity,0]],departure));
});
test('visited mask supports more than 64 stops',()=>{
 const rules=Array.from({length:66},(_,i)=>({id:String(i),after:i?String(i-1):null}));
 assert.deepEqual(optimizeSchedule(rules,matrix(67,1),departure).order,Array.from({length:66},(_,i)=>i+1));
});
test('Brasília time is independent of workstation timezone; invalid calendar days rejected',()=>{
 assert.equal(ruleDateTime('2026-10-22','09:00'),departure);
 assert.throws(()=>ruleDateTime('2026-02-30','09:00'));
 assert.throws(()=>ruleDateTime('2026-10-22','25:00'));
});
test('rules remain optional; partially filled or invalid references are rejected',()=>{
 validateDraftRule(emptyDraftRule(),'entrega',[]);assert.equal(hasRouteRules([]),false);
 assert.throws(()=>validateDraftRule({...emptyDraftRule(),start:'09:00'},'entrega',[]),/três vazios/);
 assert.throws(()=>validateDraftRule({...emptyDraftRule(),date:'2026-10-22',start:'09:00',end:'09:05'},'entrega',[]),/não cabe/);
 assert.throws(()=>validateDraftRule({...emptyDraftRule(),collection:'missing'},'entrega',[]),/rascunho/);
 validateDraftRule({...emptyDraftRule(),collection:'p'},'entrega',[{id:'p',tipoTarefa:'coleta'}]);
});
test('old backend cannot silently discard rules; old dispatch remains unchanged',async()=>{
 const calls=[],client={rpc:async(name)=>{calls.push(name);return name==='obter_capacidades_rotas'?{error:{message:'missing'}}:{data:{sucesso:true}};}};
 const payload={empresa_id:'c',motorista_id:'d',idempotency_key:'one',paradas:[{tipo_tarefa:'entrega',coleta_origem_id:'p'}]};
 await assert.rejects(()=>dispatchDriverOrders(client,payload),/rascunho/);assert.deepEqual(calls,['obter_capacidades_rotas']);
 calls.length=0;await dispatchDriverOrders(client,{...payload,paradas:[{tipo_tarefa:'entrega'}]});assert.deepEqual(calls,['enviar_pedidos_motorista']);
 client.rpc=async(name,params)=>{calls.push({name,params});return {data:name==='obter_capacidades_rotas'?{regras_opcionais:1}:{sucesso:true}};};
 calls.length=0;await dispatchDriverOrders(client,payload);assert.equal(calls[1].params.p_dados,payload);
});
