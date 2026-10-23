import assert from 'node:assert/strict';import fs from 'node:fs';
import puppeteer from 'puppeteer-core';import {createServer} from 'vite';import ts from 'typescript';
const moduleId='\0virtual:receipt-sharing-test';
const harness=`
import '/src/index.css';import React from 'react';import {createRoot} from 'react-dom/client';
import {App} from '/src/App.tsx';import {ReceiptsView} from '/src/components/dashboard/ReceiptsView.tsx';
window.mode='valid';window.calls=[];window.signed=[];window.copied='';window.signFailure=false;window.copyFailure=false;
Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{if(window.copyFailure)throw Error('Clipboard unavailable');window.copied=text;}}});
localStorage.setItem('receipt_cache_da100000-0000-0000-0000-000000000001',JSON.stringify({entrega_id:'da100000-0000-0000-0000-000000000001',destinatario_nome:'POISONED CACHE',foto_url:'https://attacker.test/private.png'}));
createRoot(document.getElementById('root')).render(new URLSearchParams(location.search).get('view')==='manage'?<ReceiptsView/>:<App/>);
`;
const fake=`
export const supabaseUrl='https://test.supabase.co';export const isSupabaseConfigured=true;
const company='11111111-1111-1111-1111-111111111111',id='da100000-0000-0000-0000-000000000001';
const path=company+'/cccccccc-cccc-cccc-cccc-cccccccccccc/'+id+'/foto.jpg';
function signed(p){return supabaseUrl+'/storage/v1/object/sign/entregas-comprovantes/'+p+'?token=synthetic.signature';}
const receipt={entrega_id:id,empresa_id:company,registrado_por:'driver',recebedor_tipo:'porteiro',recebedor_nome:'Pessoa A',observacao:'Conteúdo teste',foto_path:path,assinatura_path:null,concluida_em:new Date().toISOString(),duracao_segundos:90,entregas:{destinatario_nome:'CLIENT A',motorista_id:'driver'}};
function query(value){const q={select(){return q;},eq(){return q;},gte(){return q;},lt(){return q;},order(){return q;},range(){return q;},then(ok,bad){return Promise.resolve(value).then(ok,bad);}};return q;}
function abortable(p){return Object.assign(p,{abortSignal(){return p;}});}
export const supabase={auth:{getSession:async()=>({data:{session:{access_token:'synthetic-test-session',user:{id:'manager'}}}})},
from(table){window.calls.push({table});return query({data:table==='entrega_comprovantes'?[receipt]:[]});},
storage:{from(bucket){return{createSignedUrl:async(p,ttl)=>{window.signed.push({bucket,p,ttl});return window.signFailure?{error:{message:'denied'}}:{data:{signedUrl:signed(p)}};}};}},
rpc(name,args){window.calls.push({name,args});let value;
if(name==='sincronizar_meu_perfil')value={data:{}};
else if(name==='obter_meu_status_acesso')value={data:{empresa_id:company,papel:'gestor',status:'aprovado'}};
else if(name==='criar_compartilhamento_comprovante')value={data:{sucesso:true,expira_em:new Date(Date.now()+3300000).toISOString()}};
else if(name==='revogar_compartilhamento_comprovante')value={data:{sucesso:true}};
else if(name==='obter_comprovante_compartilhado'){
 if(window.mode==='network')value={error:{message:'network'}};
 else if(window.mode==='revoked')value={data:{sucesso:false}};
 else value={data:{sucesso:true,entrega_id:id,destinatario_nome:args.p_token==='b'.repeat(64)?'CLIENT B':'CLIENT A',empresa_nome:'Empresa teste',recebedor_tipo:'porteiro',recebedor_nome:'Pessoa A',duracao_segundos:90,concluida_em:new Date().toISOString(),foto_url:window.mode==='foreign'?signed(path).replace('test.supabase.co','attacker.test'):signed(path),expira_em:new Date(Date.now()+(window.mode==='short'?500:3300000)).toISOString(),servidor_em:new Date().toISOString()}};
 if(window.mode==='slow')return abortable(new Promise(resolve=>{window.resolveOld=()=>resolve(value);}));
}else value={data:[]};return abortable(Promise.resolve(value));}};
`;
const server=await createServer({server:{host:'127.0.0.1',port:0},plugins:[{name:'receipt-sharing-test',enforce:'pre',resolveId(id){if(id==='virtual:receipt-sharing-test')return moduleId;},load(id){if(id.replaceAll('\\','/').endsWith('/src/lib/supabase.ts'))return fake;if(id===moduleId)return ts.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText;},configureServer(s){s.middlewares.use('/__receipt_test',async(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(await s.transformIndexHtml('/__receipt_test','<html><head><meta name="viewport" content="width=device-width,initial-scale=1"/></head><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:receipt-sharing-test"></script></body></html>'));});}}]});
let browser;
try{
 await server.listen();const port=server.httpServer.address().port;
 browser=await puppeteer.launch({executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',headless:true});
 const page=await browser.newPage();await page.setViewport({width:390,height:844});
 const errors=[],imageRequests=[];page.on('pageerror',e=>errors.push(e.message));
 await page.setRequestInterception(true);page.on('request',req=>{const u=new URL(req.url());if(u.hostname==='127.0.0.1'||u.protocol==='data:'||u.protocol==='blob:')return req.continue();imageRequests.push(req.url());return req.respond({status:200,contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jJp8AAAAASUVORK5CYII=','base64')});});
 const token='a'.repeat(64),base='http://127.0.0.1:'+port+'/__receipt_test';
 let run=0;const open=async(fragment='')=>page.goto(base+(fragment.startsWith('?')?fragment.replace('?','?run='+(++run)+'&'):'?run='+(++run)+fragment));
 const refresh=()=>page.evaluate(()=>document.dispatchEvent(new Event('visibilitychange')));
 await open('?view=manage');await page.waitForSelector('[aria-label="Copiar dados do comprovante"]');
 await page.click('[aria-label="Copiar dados do comprovante"]');await page.waitForFunction(()=>window.copied.includes('#/comprovante/'));
 const shared=await page.evaluate(()=>({text:window.copied,calls:window.calls,signed:window.signed}));
 assert.match(shared.text,/#\/comprovante\/[a-f0-9]{64}/);assert.equal(shared.text.includes('/comprovante/da100000'),false);assert.equal(shared.signed[0].ttl,3600);
 assert.equal(shared.calls.filter(c=>c.name==='criar_compartilhamento_comprovante').length,1);
 assert.equal(await page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('receipt_cache_')).length),1); // Only the intentionally poisoned legacy fixture, no new cache.
 await page.click('[aria-label="Revogar link do comprovante"]');await page.waitForFunction(()=>document.body.textContent.includes('Link de acesso ao comprovante revogado'));
 assert.equal(await page.evaluate(()=>window.calls.find(c=>c.name==='revogar_compartilhamento_comprovante').args.p_entrega_id),'da100000-0000-0000-0000-000000000001');
 console.log('PASS: real management view signs private media, copies a random fragment link, stores no new receipt cache, and revokes the selected share');
 await page.evaluate(()=>{window.signFailure=true;window.copied='';window.calls=[];});await page.click('[aria-label="Copiar dados do comprovante"]');await page.waitForSelector('[role="alert"]');
 assert.equal(await page.evaluate(()=>window.copied),'');assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='criar_compartilhamento_comprovante')),false);
 await page.evaluate(()=>{window.signFailure=false;window.copyFailure=true;});await page.click('[aria-label="Copiar dados do comprovante"]');await page.waitForFunction(()=>document.body.textContent.includes('Clipboard unavailable'));
 console.log('PASS: signing/clipboard failures expose feedback without false confirmation or public URL fallback');
 await open('#/comprovante/da100000-0000-0000-0000-000000000001');await page.waitForFunction(()=>document.body.textContent.includes('Link antigo ou inválido'));
 assert.equal(await page.evaluate(()=>window.calls.length),0);assert.equal(await page.evaluate(()=>document.body.textContent.includes('POISONED CACHE')),false);
 await open('#/comprovante/'+token);await page.waitForFunction(()=>document.body.textContent.includes('CLIENT A'));
 assert.equal(await page.evaluate(()=>window.signed.length),0);assert.equal(await page.evaluate(()=>window.calls.some(c=>c.table)),false);
 assert.equal(await page.$eval('meta[name="robots"]',e=>e.content),'noindex, nofollow, noarchive');assert.equal(await page.$eval('meta[name="referrer"]',e=>e.content),'no-referrer');
 assert.deepEqual(await page.evaluate(()=>window.calls.find(c=>c.name==='obter_comprovante_compartilhado').args),{p_token:token});
 await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Ampliar')).click());await page.waitForSelector('[role="dialog"]');
 await page.evaluate(()=>{window.mode='revoked';});await refresh();await page.waitForFunction(()=>document.body.textContent.includes('expirado ou revogado'));
 assert.equal(await page.$('[role="dialog"]'),null);assert.equal(await page.evaluate(()=>document.body.textContent.includes('CLIENT A')),false);
 console.log('PASS: legacy UUID/cache ignored; anonymous reader uses token RPC only; revocation clears receipt, image and zoom');
 await open('#/comprovante/'+token);await page.waitForFunction(()=>document.body.textContent.includes('CLIENT A'));
 await page.evaluate(()=>{window.mode='short';});await refresh();await page.waitForFunction(()=>document.body.textContent.includes('Este link expirou'));
 assert.equal(await page.$('img[src*="object/sign"]'),null);
 await open('#/comprovante/'+token);await page.waitForFunction(()=>document.body.textContent.includes('CLIENT A'));
 await page.evaluate(()=>{window.mode='network';});await refresh();await page.waitForFunction(()=>document.body.textContent.includes('Não foi possível atualizar'));
 assert.equal(await page.evaluate(()=>document.body.textContent.includes('CLIENT A')),false);
 console.log('PASS: local lifetime timer and network errors discard protected data');
 await open('#/comprovante/'+token);await page.waitForFunction(()=>document.body.textContent.includes('CLIENT A'));
 await page.evaluate(()=>{window.mode='slow';});await refresh();await page.waitForFunction(()=>typeof window.resolveOld==='function');
 await page.evaluate(()=>{window.mode='valid';location.hash='/comprovante/'+'b'.repeat(64);});await page.waitForFunction(()=>document.body.textContent.includes('CLIENT B'));
 await page.evaluate(()=>window.resolveOld());await page.waitForFunction(()=>document.body.textContent.includes('CLIENT B'));
 assert.equal(await page.evaluate(()=>document.body.textContent.includes('CLIENT A')),false);
 await page.evaluate(()=>{window.mode='foreign';});await refresh();await page.waitForFunction(()=>!document.querySelector('img[src*="object/sign"]'));
 assert.equal(imageRequests.some(u=>u.includes('attacker.test')),false);
 console.log('PASS: old asynchronous response cannot replace another token; foreign image origins are never requested');
 await open('#/comprovante/'+token);await page.waitForFunction(()=>document.body.textContent.includes('CLIENT A'));
 fs.mkdirSync('docs/previews',{recursive:true});await page.screenshot({path:'docs/previews/secure-receipt-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS: mobile layout, no browser exceptions and no messages actually sent');
}finally{await browser?.close();await server.close();}
