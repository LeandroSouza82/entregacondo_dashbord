import test from 'node:test';
import assert from 'node:assert/strict';
import { createCheckoutHandler } from '../supabase/functions/_shared/subscriptionBilling.ts';
const company = '11111111-1111-1111-1111-111111111111';
const checkout = 'ab000000-0000-0000-0000-000000000001';
const request = () => new Request('https://server.test/checkout', {method:'POST',headers:{authorization:'Bearer user-jwt',origin:'https://entregacondo.com.br','content-type':'application/json'},body:JSON.stringify({empresa_id:company})});
async function run(fetch, report, extra = {}) {
  let linked = false;
  const handler = createCheckoutHandler({accessToken:'TEST-sensitive',webhookSecret:'private-sensitive',publicUrl:'https://entregacondo.com.br',live:false,
    reserve:async()=>({id:checkout,email:'private-client@example.test',valor:149.90,ambiente:'test'}),
    fetch, reportProviderFailure: report, link:async()=>{linked=true;return true;},context:async()=>null,record:async()=>true,...extra});
  return { response:await handler(request()), linked };
}
for (const [status,message,reason] of [
  [400,'Both payer and collector must be real or test users','test_account_mismatch'],
  [401,'private-client@example.test TEST-sensitive','invalid_credentials'],
  [403,'Access denied','invalid_credentials'],
  [400,'Invalid back_url: https://secret.example.test','invalid_return_url'],
  [400,'Invalid payer_email private-client@example.test','invalid_payer'],
  [400,'Unrecognized error private-client@example.test TEST-sensitive','provider_rejected'],
  [503,'upstream failure','provider_unavailable'],
]) test(reason + ' HTTP ' + status, async()=>{
  const logs=[];
  const result=await run(async()=>new Response(JSON.stringify({message,access_token:'TEST-sensitive'}),{status}),d=>logs.push(d));
  assert.equal(result.response.status,400); assert.equal(result.linked,false);
  assert.deepEqual(logs,[{status,reason}]);
  const publicBody=await result.response.text();
  for(const privateValue of ['private-client@example.test','TEST-sensitive','private-sensitive','user-jwt',message]) assert.ok(!publicBody.includes(privateValue));
  assert.ok(!JSON.stringify(logs).includes('@'));
});
test('malformed and oversized errors remain generic',async()=>{
  for(const body of ['not-json','x'.repeat(40000)]){
    const logs=[];const result=await run(async()=>new Response(body,{status:400}),d=>logs.push(d));
    assert.equal(result.response.status,400);assert.deepEqual(logs,[{status:400,reason:'provider_rejected'}]);
  }
});
test('network error does not leak error text',async()=>{
  const logs=[];const result=await run(async()=>{throw Error('TEST-sensitive private-client@example.test');},d=>logs.push(d));
  assert.equal(result.response.status,400);assert.equal(result.linked,false);
  assert.deepEqual(logs,[{status:0,reason:'network_unavailable'}]);
});
test('diagnostic logger failure does not change error response',async()=>{
  const result=await run(async()=>new Response('{}',{status:500}),()=>{throw Error('logger failed');});
  assert.equal(result.response.status,400);assert.equal(result.linked,false);
});
test('successful checkout does not log provider failure',async()=>{
  const logs=[];const result=await run(async()=>new Response(JSON.stringify({id:'sub-test',init_point:'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=sub-test'})),d=>logs.push(d));
  assert.equal(result.response.status,200);assert.equal(result.linked,true);assert.deepEqual(logs,[]);
});

test('checkout diagnostics isolate schedule mismatch without leaking private data',async()=>{
  for(const [providerDate,delta] of [['2026-11-28T14:51:45.000Z',-334],[null,null]]){
    const logs=[];
    const result=await run(async()=>Response.json({id:'sub-test',init_point:'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=sub-test',auto_recurring:{start_date:providerDate}}),()=>{}, {
      reserve:async()=>({id:checkout,email:'private-client@example.test',valor:149.90,ambiente:'test',inicio_cobranca:'2026-11-28T14:51:45.334Z',servidor_em:'2026-10-29T14:51:45.334Z'}),
      reportCheckoutFailure:diagnostic=>logs.push(diagnostic),
    });
    assert.equal(result.response.status,400);assert.equal(result.linked,false);
    assert.deepEqual(logs,[{stage:'schedule',providerStartDeltaMs:delta}]);
    for(const value of ['private-client@example.test','TEST-sensitive','private-sensitive','user-jwt','2026-11-28'])assert.ok(!JSON.stringify(logs).includes(value));
  }
});

test('reservation failures remain generic and diagnostic failure is harmless',async()=>{
  for(const failLogger of [false,true]){
    const logs=[];
    const result=await run(async()=>{throw Error('Provider must not be called');},()=>{}, {
      reserve:async()=>{throw Error('private-client@example.test user-jwt');},
      reportCheckoutFailure:diagnostic=>{logs.push(diagnostic);if(failLogger)throw Error('private-sensitive');},
    });
    assert.equal(result.response.status,400);assert.equal(result.linked,false);
    assert.deepEqual(logs,[{stage:'reserve'}]);
    assert.ok(!(await result.response.text()).includes('private-client@example.test'));
  }
});
