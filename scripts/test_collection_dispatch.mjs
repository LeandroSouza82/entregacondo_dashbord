import test from 'node:test';
import assert from 'node:assert/strict';
import {insertCollections} from '../src/features/routes/services/collectionInsertion.ts';
import {collectionRoadCosts} from '../src/features/routes/services/collectionRoadCosts.ts';
import {dispatchDriverServices} from '../src/features/routes/services/dispatchDriverServices.ts';
const costs = [[0,40,70,2],[20,0,20,80],[30,20,0,80],[30,2,20,0]];
test('road insertion puts nearby collection first without changing old order',()=>{
 const old=[1,2]; assert.deepEqual(insertCollections(old,[3],costs),[3,1,2]);assert.deepEqual(old,[1,2]);
});
test('arrival pins the current stop while the rest can accept collections',()=>{
 assert.equal(insertCollections([1,2],[3],costs,true)[0],1);
});
test('circuit uses original return point in the directed insertion cost',()=>{
 const matrix=[[0,2,1,99],[2,0,1,1],[2,1,0,30],[99,1,30,0]];
 assert.deepEqual(insertCollections([1],[2],matrix,false,3),[2,1]);
});
test('unreachable roads are rejected instead of using straight lines',()=>{
 assert.throws(()=>insertCollections([1],[2],[[0,1,Infinity],[1,0,Infinity],[Infinity,Infinity,0]]),/trajeto/);
});
test('Matrix batching respects 25 points and preserves asymmetric road costs',async()=>{
 const previous=globalThis.fetch;let calls=0;
 try {
 globalThis.fetch=async(url)=>{
   calls++;const parsed=new URL(url);const coords=parsed.pathname.split('/').at(-1).split(';');
   assert.ok(coords.length<=25);assert.equal(parsed.searchParams.has('fallback_speed'),false);
   const sources=parsed.searchParams.get('sources').split(';').map(Number),destinations=parsed.searchParams.get('destinations').split(';').map(Number);
   return new Response(JSON.stringify({code:'Ok',durations:sources.map(a=>destinations.map(b=>a===b?0:10+a+b))}));
 };
 const points=Array.from({length:29},(_,i)=>[-48+i/1000,-27]);
 const matrix=await collectionRoadCosts(points,Array.from({length:26},(_,i)=>i+1),[27,28],undefined,'test');
 assert.ok(calls>1);assert.ok(Number.isFinite(matrix[0][27]));assert.ok(Number.isFinite(matrix[27][26]));
 assert.deepEqual(new Set(insertCollections(Array.from({length:26},(_,i)=>i+1),[27,28],matrix)),new Set(Array.from({length:28},(_,i)=>i+1)));
 }finally{globalThis.fetch=previous;}
});
test('null Matrix costs stay unreachable and API failure is surfaced',async()=>{
 const previous=globalThis.fetch;
 try {
 globalThis.fetch=async()=>new Response(JSON.stringify({code:'Ok',durations:[[0,null],[null,0]]}));
 assert.equal((await collectionRoadCosts([[-48,-27],[-49,-27]],[],[1],undefined,'test'))[0][1],Infinity);
 globalThis.fetch=async()=>new Response('',{status:503});
 await assert.rejects(collectionRoadCosts([[-48,-27],[-49,-27]],[],[1],undefined,'test'),/comparar/);
 }finally{globalThis.fetch=previous;}
});
function clientFixture({stale=false,retry=false}={}){
 const sent=[];let attempts=0;
 const client={rpc:async(name,args)=>{assert.equal(name,'enviar_servicos_motorista');sent.push(args);return {data:args.p_plano_coletas===null?{sucesso:false,codigo:'PLANO_COLETAS_NECESSARIO'}:retry&&attempts++===0?{sucesso:false,codigo:'PLANO_DESATUALIZADO'}:{sucesso:true,mensagem:'ok'}};},from(table){
 let query={select(){return query},eq(){return query},in(){return query},order(){return query},single(){return query},then(resolve){
 const data=table==='rotas_planejadas'?[{id:'active',configuracao_navegacao:{latitude:-27,longitude:-48,retornar_ao_inicio:true}}]:table==='motoristas'?{latitude_atual:-27,longitude_atual:-48,localizacao_atualizada_em:new Date(Date.now()-(stale?600000:0)).toISOString()}:table==='entregas'?[{id:'completed',status:'entregue',ordem_na_rota:1,chegada_em:null,clientes_enderecos:{latitude:-27.001,longitude:-48.001}},{id:'pinned',status:'em_transito',ordem_na_rota:2,chegada_em:'2026-10-20T10:00:00Z',clientes_enderecos:{latitude:-27.002,longitude:-48.002}}]:[{id:'collection-address',latitude:-27.003,longitude:-48.003}];
 return Promise.resolve({data,error:null}).then(resolve);
 }};return query;
 }};return {client,sent};
}
const payload={empresa_id:'company',motorista_id:'driver',idempotency_key:'operation',paradas:[{tipo_tarefa:'coleta',cliente_endereco_id:'collection-address'},{tipo_tarefa:'entrega',cliente_endereco_id:'delivery-address'}],ordem_paradas_json:[{coordenadas:{lat:-27.003,lng:-48.003}},{coordenadas:{lat:-27.004,lng:-48.004}}]};
test('mixed dispatch plans active collection and separate delivery with pinned arrival',async()=>{
 const previous=globalThis.fetch;const {client,sent}=clientFixture({retry:true});
 try{
 globalThis.fetch=async(url)=>{const parsed=new URL(url);const coords=parsed.pathname.split('/').at(-1).split(';');return new Response(JSON.stringify(parsed.pathname.includes('directions-matrix')?{code:'Ok',durations:coords.map((_,a)=>coords.map((__,b)=>Math.abs(a-b)*30))}:{code:'Ok',routes:[{distance:2500,duration:420,geometry:{coordinates:[[-48,-27],[-48.01,-27.01]]}}]}));};
 assert.equal((await dispatchDriverServices(client,payload,[-48,-27],'test')).sucesso,true);
 assert.equal(sent.length,3);const plan=sent.at(-1).p_plano_coletas;
 assert.deepEqual(plan.ordem,['pinned','nova:0']);assert.equal(plan.snapshot.length,2);
 assert.equal(plan.metricas.fonte,'mapbox_directions_restante');assert.equal(plan.metricas_nova_rota.distancia_otimizada_km,2.5);
 assert.equal(sent.at(-1).p_dados.idempotency_key,'operation');
 }finally{globalThis.fetch=previous;}
});
test('stale GPS prevents sending any changes and retains draft',async()=>{
 const {client,sent}=clientFixture({stale:true});
 await assert.rejects(dispatchDriverServices(client,payload,[-48,-27],'test'),/GPS recente/);assert.equal(sent.length,1);
});
test('idempotent server response needs no new GPS or external calculation',async()=>{
 const client={rpc:async()=>({data:{sucesso:true,idempotente:true,mensagem:'ok'}}),from(){throw Error('should not query')}};
 assert.equal((await dispatchDriverServices(client,payload,[-48,-27],'')).idempotente,true);
});
