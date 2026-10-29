import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {createCheckoutHandler, createSubscriptionWebhook} from '../supabase/functions/_shared/subscriptionBilling.ts';
const company='11111111-1111-1111-1111-111111111111', id='ab000000-0000-0000-0000-000000000001';
const end='2026-11-26T14:00:00.000Z', now='2026-10-27T14:00:00.000Z';
let calls=[], synced=[], creates=0, reserves=0, status='authorized', collector=7, reference=id;
let reservation={id,email:'buyer@example.test',valor:149.90,ambiente:'test',inicio_cobranca:end,servidor_em:now};
const deps={accessToken:'TEST-only',webhookSecret:'test-secret',publicUrl:'https://entregacondo.com.br',live:false,
 reserve:async(jwt,c)=>{assert.equal(jwt,'valid');assert.equal(c,company);reserves++;return reservation;},
 lookup:async(jwt,c)=>{assert.equal(jwt,'valid');assert.equal(c,company);return {id,preapproval_id:'sub-1',ambiente:'test'};},
 link:async()=>true, context:async()=>null,record:async()=>{throw Error('Authorization must never register payment');},
 sync:async p=>{synced.push(p);return true;},
 fetch:async(url,init)=>{calls.push({url,init});
  if(url.endsWith('/users/me'))return Response.json({id:7});
  if(url.endsWith('/preapproval')&&init.method==='POST'){creates++;return Response.json({id:'sub-1',init_point:'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=sub-1',auto_recurring:JSON.parse(init.body).auto_recurring});}
  if(url.endsWith('/preapproval/sub-1'))return Response.json({id:'sub-1',external_reference:reference,collector_id:collector,status,last_modified:now,
   auto_recurring:{start_date:end,frequency:1,frequency_type:'months',transaction_amount:149.90,currency_id:'BRL'},next_payment_date:end});
  throw Error('Unexpected external request');}};
const req=(body)=>new Request('https://server.test/checkout',{method:'POST',headers:{authorization:'Bearer valid',origin:deps.publicUrl,'content-type':'application/json'},body:JSON.stringify({empresa_id:company,...body})});
const handler=createCheckoutHandler(deps);
assert.equal((await handler(req({inicio_cobranca:now,valor:1}))).status,200);
const payload=JSON.parse(calls[0].init.body);
assert.equal(payload.auto_recurring.start_date,end,'database controls first charge, not browser');
assert.equal(payload.auto_recurring.transaction_amount,149.90);
assert.equal(payload.status,'pending','creating checkout never authorizes payment');
assert.equal(synced.length,0);
reservation={...reservation,url:'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=sub-1',preapproval_id:'sub-1'};
let result=await handler(req({}));assert.equal(result.status,200);assert.equal((await result.json()).estado,'authorized');
assert.equal(creates,1,'confirmed contract never creates a second recurring subscription');
const before=reserves;
result=await handler(req({consultar:true}));assert.equal(result.status,200);assert.equal(reserves,before,'return status is read without creating a new checkout');
collector=99;const n=synced.length;assert.equal((await handler(req({consultar:true}))).status,400);assert.equal(synced.length,n);collector=7;
reference=company;assert.equal((await handler(req({consultar:true}))).status,400);reference=id;
status='pending';assert.equal((await handler(req({}))).status,200);assert.equal(creates,1,'pending checkout reuses existing URL');
status='paused';assert.equal((await handler(req({}))).status,409);
reservation={id,email:'buyer@example.test',valor:149.90,ambiente:'test',inicio_cobranca:'invalid',servidor_em:now};
assert.equal((await handler(req({}))).status,400);
reservation={...reservation,inicio_cobranca:null};calls=[];assert.equal((await handler(req({}))).status,200);
assert.equal('start_date' in JSON.parse(calls[0].init.body).auto_recurring,false,'expired trial uses normal immediate checkout');
function notification(bad=false){const ts='1793109600',requestId='early-test';const sig=createHmac('sha256',deps.webhookSecret).update(`id:sub-1;request-id:${requestId};ts:${ts};`).digest('hex');
 return new Request('https://server.test/webhook?data.id=sub-1&type=subscription_preapproval',{method:'POST',headers:{'x-request-id':requestId,'x-signature':`ts=${ts},v1=${bad?'0'.repeat(64):sig}`},body:JSON.stringify({type:'subscription_preapproval',data:{id:'sub-1'}})});}
status='authorized';const webhook=createSubscriptionWebhook(deps);calls=[];
assert.equal((await webhook(notification(true))).status,401);assert.equal(calls.length,0);
assert.equal((await webhook(notification())).status,200);assert.equal(synced.at(-1).p_inicio_cobranca,end);
assert.equal(synced.at(-1).p_status,'authorized');
// Real provider timestamps omit fractional seconds. Simulate that behavior and
// an earlier failed creation cached under the original idempotency key.
const fractionalEnd='2026-11-28T14:51:45.334Z';
const roundedEnd='2026-11-28T14:51:46.000Z';
const cachedOld={id:'sub-old',init_point:'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=sub-old',auto_recurring:{start_date:'2026-11-28T14:51:45.000Z'}};
const providerCache=new Map([[id,cachedOld]]);const productionCalls=[];const productionLinks=[];
const productionHandler=createCheckoutHandler({...deps,live:true,
 reserve:async()=>({id,email:'buyer@example.test',valor:149.90,ambiente:'production',inicio_cobranca:fractionalEnd,servidor_em:now}),
 link:async(...args)=>{productionLinks.push(args);return true;},
 fetch:async(_url,init)=>{
  const key=init.headers['X-Idempotency-Key'];const body=JSON.parse(init.body);productionCalls.push({key,body});
  if(!providerCache.has(key))providerCache.set(key,{id:'sub-rounded',init_point:'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=sub-rounded',auto_recurring:{...body.auto_recurring,start_date:new Date(Math.floor(Date.parse(body.auto_recurring.start_date)/1000)*1000).toISOString()}});
  return Response.json(providerCache.get(key));
 }});
for(let attempt=0;attempt<2;attempt++){
 const response=await productionHandler(req({}));assert.equal(response.status,200,'whole-second provider response must preserve the full trial');
 assert.match((await response.json()).url,/preapproval_id=sub-rounded$/);
}
assert.equal(productionCalls[0].body.auto_recurring.start_date,roundedEnd);
assert.ok(Date.parse(roundedEnd)>=Date.parse(fractionalEnd),'normalization never charges before the original trial end');
assert.ok(Date.parse(roundedEnd)-Date.parse(fractionalEnd)<1000);
assert.notEqual(productionCalls[0].key,id,'corrected request cannot reuse the failed fractional schedule');
assert.equal(productionCalls[0].key,productionCalls[1].key,'retries reuse the same corrected subscription');
assert.equal(providerCache.size,2);assert.equal(productionLinks.length,2);
console.log('PASS: early checkout preserves exact trial end; fixed price; status reconciliation; no duplicate subscription; safe return; wrong merchant/company refused; expired trial; signed preapproval without granting paid access. No external API called.');
