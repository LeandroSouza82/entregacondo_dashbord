import test from 'node:test';
import assert from 'node:assert/strict';
import {fcmMessage,sendFcm,parseAccount} from '../supabase/functions/push-servicos/fcm.ts';
import {createPushHandler} from '../supabase/functions/push-servicos/handler.ts';
const job={id:'event',claim_token:'lease',token:'device-secret',rota_id:'route',tipo:'nova_rota',quantidade:3,expires_at:new Date(Date.now()+3600000).toISOString()};
test('route and collection use matching Android voice channels, TTL and generic content',()=>{
 const route=fcmMessage(job).message,collection=fcmMessage({...job,tipo:'nova_coleta'}).message;
 assert.equal(route.android.notification.channel_id,'entregacondo_rotas_voz_v2');assert.equal(collection.android.notification.sound,'nova_coleta');
 assert.equal(route.android.priority,'high');assert.ok(parseInt(route.android.ttl)<=3600);assert.equal(route.data.route_id,'route');
 assert.throws(()=>fcmMessage({...job,expires_at:new Date(0).toISOString()}),/EXPIRED/);
});
test('invalid registration is disabled; malformed payload is not confused with a dead token',async()=>{
 const reply=(status,code)=>async()=>Response.json({error:{details:[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:code}]}},{status});
 assert.equal((await sendFcm(job,'access',reply(404,'UNREGISTERED'))).result,'invalido');
 assert.equal((await sendFcm(job,'access',reply(400,'INVALID_ARGUMENT'))).result,'falhou');
 assert.equal((await sendFcm(job,'access',reply(503,'UNAVAILABLE'))).result,'repetir');
 assert.equal((await sendFcm(job,'access',async()=>Response.json({name:'accepted'}))).result,'aceito');
});
test('worker rejects unauthenticated access without reading tokens or claiming work',async()=>{
 let claimed=0;const handler=createPushHandler({secret:'s'.repeat(40),accessToken:async()=>{throw Error('must not access')},claim:async()=>{claimed++;return []},finish:async()=>true});
 assert.equal((await handler(new Request('https://local',{method:'POST'}))).status,401);assert.equal(claimed,0);
 assert.equal((await handler(new Request('https://local'))).status,405);
});
test('Firebase failure does not consume a delivery lease or leak credentials',async()=>{
 let claimed=false;const handler=createPushHandler({secret:'s'.repeat(40),accessToken:async()=>{throw Error('private credential')},claim:async()=>{claimed=true;return []},finish:async()=>true});
 const result=await handler(new Request('https://local',{method:'POST',headers:{'x-push-worker-secret':'s'.repeat(40)}}));
 assert.equal(result.status,503);assert.equal(claimed,false);assert.equal((await result.text()).includes('private credential'),false);
});
test('accepted and transient jobs are acknowledged separately and send count is honest',async()=>{
 const finished=[];const handler=createPushHandler({secret:'s'.repeat(40),accessToken:async()=>'access',claim:async()=>[job,{...job,id:'retry'}],send:async(j)=>j.id==='event'?{result:'aceito'}:{result:'repetir',code:'HTTP_503'},finish:async(j,result)=>{finished.push([j.id,result.result]);return true}});
 const response=await handler(new Request('https://local',{method:'POST',headers:{'x-push-worker-secret':'s'.repeat(40)}}));
 assert.deepEqual(await response.json(),{processed:2,accepted:1,retry_or_failed:1});assert.equal(finished.length,2);
});
test('service credentials are restricted to the configured EntregaCondo Firebase project',()=>{
 assert.throws(()=>parseAccount(JSON.stringify({project_id:'another-project',client_email:'x',private_key:'BEGIN PRIVATE KEY'})),/INVALID/);
});
