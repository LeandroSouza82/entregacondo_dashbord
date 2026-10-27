import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {createCheckoutHandler,createSubscriptionWebhook} from '../supabase/functions/_shared/subscriptionBilling.ts';
const company='11111111-1111-1111-1111-111111111111',checkout='ab000000-0000-0000-0000-000000000001';
let requests=[],records=[],links=[],amount=149.90,status='approved',refund=0,collector=77,live=false,available=true,failRecord=false;
const config={accessToken:'TEST-server-only',webhookSecret:'private-webhook-test',publicUrl:'https://entregacondo.com.br',live:false,
 reserve:async(jwt,id)=>{assert.equal(jwt,'valid-jwt');assert.equal(id,company);if(!available)throw Error('not authorized');return {id:checkout,email:'payer@example.test',valor:149.90,ambiente:'test'};},
 link:async(...args)=>{links.push(args);return true;},context:async id=>id==='123'?{checkout_id:checkout,preapproval_id:'sub-1'}:null,
 sync:async()=>true,record:async args=>{records.push(args);if(failRecord)throw Error('DB unavailable');return true;},
 fetch:async(url,init)=>{requests.push({url,init});assert.equal(init.headers.Authorization,'Bearer TEST-server-only');let data;
 if(url.endsWith('/users/me'))data={id:77};
 else if(url.endsWith('/preapproval')&&init.method==='POST'){data={id:'sub-1',init_point:'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=sub-1'};}
 else if(url.endsWith('/authorized_payments/555'))data={id:555,preapproval_id:'sub-1',external_reference:checkout,currency_id:'BRL',transaction_amount:149.90,payment:{id:123}};
 else if(url.endsWith('/preapproval/sub-1'))data={id:'sub-1',external_reference:checkout,collector_id:collector,auto_recurring:{transaction_amount:149.90,currency_id:'BRL',frequency:1,frequency_type:'months'},status:'pending',last_modified:'2026-10-23T12:00:00Z'};
 else if(url.endsWith('/v1/payments/123'))data={id:123,collector_id:collector,live_mode:live,status,transaction_amount:amount,currency_id:'BRL',transaction_amount_refunded:refund,date_approved:'2026-10-23T12:00:00Z',date_last_updated:'2026-10-23T12:00:01Z'};
 else throw Error('Unexpected API URL');return new Response(JSON.stringify(data));}};
const request=(body,options={})=>new Request('https://server.test/checkout',{method:'POST',headers:{authorization:'Bearer valid-jwt',origin:'https://entregacondo.com.br','content-type':'application/json',...options.headers},body:JSON.stringify(body)});
const checkoutHandler=createCheckoutHandler(config);
assert.equal((await checkoutHandler(request({empresa_id:company},{headers:{origin:'https://attacker.test'}}))).status,403);
assert.equal((await checkoutHandler(request({empresa_id:company},{headers:{authorization:''}}))).status,401);
assert.equal(requests.length,0);
assert.equal((await checkoutHandler(request({empresa_id:company,valor:0.01,back_url:'https://attacker.test'}))).status,200);
const wrongEnvironment = createCheckoutHandler({...config,reserve:async()=>({id:checkout,email:'payer@example.test',valor:149.90,ambiente:'production'})});
const beforeWrongEnvironment=requests.length;
assert.equal((await wrongEnvironment(request({empresa_id:company}))).status,503);
assert.equal(requests.length,beforeWrongEnvironment,'test credentials never create checkout for a real company');
const created=JSON.parse(requests[0].init.body);assert.equal(created.auto_recurring.transaction_amount,149.90);assert.equal(created.auto_recurring.frequency_type,'months');assert.equal(created.status,'pending');assert.equal(created.external_reference,checkout);assert.equal(created.back_url,'https://entregacondo.com.br/#/assinatura');assert.equal(requests[0].init.headers['X-Idempotency-Key'],checkout);assert.equal(links.length,1);assert.equal(records.length,0);
const migratedHandler=createCheckoutHandler({...config,publicUrl:'https://dashboard.entregacondo.com.br',allowedOrigins:['https://entregacondo.com.br']});
for(const origin of ['https://entregacondo.com.br','https://dashboard.entregacondo.com.br']){
 const preflight=await migratedHandler(new Request('https://server.test/checkout',{method:'OPTIONS',headers:{origin}}));
 assert.equal(preflight.status,200);assert.equal(preflight.headers.get('Access-Control-Allow-Origin'),origin);
 assert.equal((await migratedHandler(request({empresa_id:company},{headers:{origin}}))).status,200);
 assert.equal(JSON.parse(requests.at(-1).init.body).back_url,'https://dashboard.entregacondo.com.br/#/assinatura');
}
assert.equal((await migratedHandler(request({empresa_id:company},{headers:{origin:'https://dashboard.entregacondo.com.br.attacker.test'}}))).status,403);
available=false;assert.equal((await checkoutHandler(request({empresa_id:company}))).status,400);available=true;
assert.equal((await createCheckoutHandler({...config,accessToken:''})(request({empresa_id:company}))).status,503);
function notification(type,id,bad=false){const ts='1704908010',reqId='request-test';const signature=createHmac('sha256',config.webhookSecret).update(`id:${id};request-id:${reqId};ts:${ts};`).digest('hex');return new Request(`https://server.test/webhook?data.id=${id}&type=${type}`,{method:'POST',headers:{'x-signature':`ts=${ts},v1=${bad?'0'.repeat(64):signature}`,'x-request-id':reqId,'content-type':'application/json'},body:JSON.stringify({type,data:{id}})});}
const webhook=createSubscriptionWebhook(config);requests=[];
assert.equal((await webhook(notification('subscription_authorized_payment','555',true))).status,401);assert.equal(requests.length,0);
assert.equal((await webhook(notification('subscription_preapproval','sub-1'))).status,200);assert.equal(records.length,0);
assert.equal((await webhook(notification('payment','999'))).status,200);assert.equal(records.length,0,'unregistered standalone payment cannot grant access');
assert.equal((await webhook(notification('subscription_authorized_payment','555'))).status,200);assert.equal(records.length,1);assert.equal(records[0].p_status,'approved');assert.equal(records[0].p_checkout_id,checkout);assert.equal(records[0].p_preapproval_id,'sub-1');
status='refunded';assert.equal((await webhook(notification('payment','123'))).status,200);assert.equal(records.at(-1).p_status,'refunded');
status='approved';refund=1;assert.equal((await webhook(notification('payment','123'))).status,200);assert.equal(records.at(-1).p_status,'refunded','partial refund cannot preserve full paid access');refund=0;
for(const field of ['amount','collector','live']){const before=records.length;if(field==='amount')amount=1;if(field==='collector')collector=99;if(field==='live')live=true;assert.equal((await webhook(notification('subscription_authorized_payment','555'))).status,500);assert.equal(records.length,before);amount=149.90;collector=77;live=false;}
failRecord=true;assert.equal((await webhook(notification('payment','123'))).status,500,'DB failures are retried by MP instead of acknowledged');
assert.equal((await createSubscriptionWebhook({...config,webhookSecret:''})(notification('payment','123'))).status,503);
console.log('PASS: authenticated scoped checkout, fixed server price, pending state, HMAC before network, live API reconciliation, merchant and environment checks, subscription linkage, refunds, replay-safe recording and retriable failures. No external API called.');
