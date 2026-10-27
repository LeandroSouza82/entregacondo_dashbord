import assert from 'node:assert/strict';
import puppeteer from 'puppeteer-core';
import {createServer} from 'vite';
import ts from 'typescript';
const moduleId='\0virtual:company-trial-ui';
const harness=`import '/src/index.css';import React from 'react';import {createRoot} from 'react-dom/client';import {App} from '/src/App.tsx';createRoot(document.getElementById('root')).render(<App/>);`;
const fake=`export const isSupabaseConfigured=true;export const supabaseUrl='https://example.supabase.co';
window.calls=[];window.phase=new URLSearchParams(location.search).get('phase')||'confirmed';window.provisioned=false;
const user={id:'manager',email:'manager@example.test',user_metadata:{name:'Gestor',empresa_nome:'Essenza Teste',papel:'admin'}};
const session=window.phase==='anonymous'?null:{access_token:'synthetic',user};
function query(table){const q={select(){return q;},eq(){return q;},in(){return q;},gte(){return q;},lt(){return q;},order(){return q;},limit(){return q;},range(){return q;},single:async()=>({data:{nome:'Essenza Teste'}}),maybeSingle:async()=>({data:null}),then(ok,bad){return Promise.resolve({data:[],count:0}).then(ok,bad);}};return q;}
export const supabase={auth:{getSession:async()=>({data:{session}}),getUser:async()=>({data:{user}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signUp:async args=>{window.signup=args;return {data:{user:{...user,email_confirmed_at:null},session:null}};},signOut:async()=>({})},
from(table){window.calls.push({table});return query(table);},channel(){return{on(){return this;},subscribe(){return this;}};},removeChannel(){},
functions:{invoke:async(name,body)=>{window.calls.push({name,body});if(window.checkoutMode==='validation')return {error:{context:{json:async()=>({error:'Pagamentos ainda estão em validação.'})}}};if(window.checkoutMode==='authorized'){window.checkoutState='authorized';return {data:{estado:'authorized'}};}return {error:{message:'not configured'}};}},
rpc:async(name,args)=>{window.calls.push({name,args});
if(name==='sincronizar_meu_perfil')return {data:{sucesso:true}};
if(name==='obter_meu_status_acesso'){
 if(window.phase==='missing')return {error:{code:'PGRST202',message:'missing RPC'}};
 if(window.phase==='suspended')return {data:{status:'suspenso',papel:'admin',empresa_id:'11111111-1111-1111-1111-111111111111',mensagem:'Sua conta está suspensa.'}};
 if(window.phase==='driver')return {data:{status:'aprovado',papel:'motorista',empresa_id:'11111111-1111-1111-1111-111111111111',mensagem:'Perfil de motorista.'}};
 return {data:window.provisioned?{status:'aprovado',papel:'admin',empresa_id:'11111111-1111-1111-1111-111111111111'}:{status:'sem_vinculo'}};
}
if(name==='iniciar_teste_empresa'){window.provisioned=true;return {data:{sucesso:true,empresa_id:'11111111-1111-1111-1111-111111111111'}};}
if(name==='obter_minha_assinatura')return {data:{legado:false,operacional:window.phase!=='expired',estado:window.phase==='expired'?'expirada':window.phase==='paid'?'ativa':'teste',dias_restantes:30,atendimentos_mes:0,checkout_estado:window.checkoutState||null,checkout_pendente:window.checkoutState==='pending',cobranca_inicio:new Date(Date.now()+2592000000).toISOString(),servidor_em:new Date().toISOString(),teste_fim:new Date(Date.now()+(window.phase==='expired'?-1000:2592000000)).toISOString()}};
return {data:[]};}};`;
const server=await createServer({server:{host:'127.0.0.1',port:0},plugins:[{name:'company-trial-ui',enforce:'pre',resolveId(id){if(id==='virtual:company-trial-ui')return moduleId;},load(id){if(id.replaceAll('\\','/').endsWith('/src/lib/supabase.ts'))return fake;if(id===moduleId)return ts.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText;},configureServer(s){s.middlewares.use('/__trial_ui',async(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(await s.transformIndexHtml('/__trial_ui','<html><head><meta name="viewport" content="width=device-width,initial-scale=1"/></head><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:company-trial-ui"></script></body></html>'));});}}]});
let browser;
try{
 await server.listen();browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));const base='http://127.0.0.1:'+server.httpServer.address().port+'/__trial_ui';
 await page.setViewport({width:390,height:844});await page.goto(base+'?phase=anonymous#/conheca');await page.waitForSelector('#presentation-title');
 assert.equal(await page.$$eval('a[href="/#/cadastro"]',a=>a.length),2);assert.equal(await page.evaluate(()=>document.body.textContent.includes('Acessar painel')),false);
 await page.goto(base+'?phase=anonymous#/cadastro');await page.waitForSelector('#company-name');assert.match(await page.evaluate(()=>document.body.innerText),/30 dias grátis, sem cartão/);
 await page.type('input[placeholder="Ex: Carlos Oliveira"]','Gestor');await page.type('#company-name','Essenza Teste');await page.type('input[type="email"]','test@example.test');await page.type('input[autocomplete="new-password"]','password-123');await page.evaluate(()=>document.querySelector('form').requestSubmit());await page.waitForFunction(()=>window.signup);
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='iniciar_teste_empresa')),false,'no provisioning before confirmation/session');
 await page.setViewport({width:1200,height:900});await page.goto(base+'?phase=confirmed');await page.waitForSelector('[aria-label="Assinatura da empresa"]');
 assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='iniciar_teste_empresa').length),1);assert.equal(await page.evaluate(()=>document.body.textContent.includes('30 dias restantes')),true);assert.equal(await page.evaluate(()=>window.calls.some(c=>['empresas','empresa_membros'].includes(c.table)&&c.write)),false);
 assert.match(await page.$eval('[aria-label="Assinatura da empresa"]',e=>e.innerText),/primeira mensalidade fica prevista para o fim do teste/);
 assert.equal(await page.$$eval('[aria-label="Assinatura da empresa"] button',buttons=>buttons.some(b=>b.textContent.includes('Assinar por R$ 149,90'))),true,'early subscribe is visible');
 await page.click('[aria-label="Assinatura da empresa"] button');await page.waitForFunction(()=>document.body.textContent.includes('Não foi possível abrir o pagamento'));
 assert.equal(await page.evaluate(()=>window.calls.at(-1).name==='assinatura-checkout'||window.calls.some(c=>c.name==='assinatura-checkout')),true);
 await page.evaluate(()=>{window.checkoutMode='validation';});await page.click('[aria-label="Assinatura da empresa"] button');
 await page.waitForFunction(()=>document.body.textContent.includes('A contratação real ainda não está disponível'));
 await page.evaluate(()=>{window.checkoutMode='authorized';});await page.click('[aria-label="Assinatura da empresa"] button');
 await page.waitForFunction(()=>document.body.textContent.includes('Contratação confirmada no Mercado Pago'));
 assert.equal(await page.$$eval('[aria-label="Assinatura da empresa"] button',buttons=>buttons.some(b=>b.textContent.includes('Assinar por'))),false,'confirmed contract cannot be duplicated');
 await page.evaluate(()=>{location.hash='/assinatura';});await page.waitForFunction(()=>document.body.textContent.includes('Você voltou do Mercado Pago'));
 assert.equal(await page.evaluate(()=>document.body.textContent.includes('Assinatura ativa')),false,'return never marks payment paid');
 await page.click('[aria-label="Assinatura da empresa"] button');await page.waitForFunction(()=>window.calls.some(c=>c.name==='assinatura-checkout'&&c.body.body.consultar===true));
 await page.setViewport({width:1200,height:900});
 assert.equal(await page.$eval('[aria-label="Assinatura da empresa"]',e=>e.scrollWidth<=e.clientWidth),true,'subscription panel has no horizontal overflow');
 await page.screenshot({path:'../../outputs/assinatura-durante-teste.png',fullPage:true});
 await page.evaluate(()=>{window.checkoutState=null;window.checkoutMode='error';window.calls=[];location.hash='';});
 await page.evaluate(()=>{window.phase='expired';window.dispatchEvent(new Event('focus'));});await page.waitForFunction(()=>document.body.innerText.includes('Seu período de acesso terminou'));assert.match(await page.$eval('[aria-label="Assinatura da empresa"]',e=>e.innerText),/R\$ 149,90/);
 await page.click('[aria-label="Assinatura da empresa"] button');await page.waitForFunction(()=>document.body.textContent.includes('Não foi possível abrir o pagamento'));assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='assinatura-checkout').length),1);assert.equal(await page.evaluate(()=>document.body.innerText.includes('Seu período de acesso terminou')),true,'checkout failure never activates access');
 await page.evaluate(()=>{window.phase='paid';window.dispatchEvent(new Event('focus'));});await page.waitForFunction(()=>document.body.textContent.includes('Assinatura ativa'));
 for(const phase of ['missing','suspended','driver']){await page.goto(base+'?phase='+phase);await page.waitForFunction(()=>document.body.textContent.includes('Atualizar acesso'));assert.equal(await page.$('[data-company-identity]'),null);assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='iniciar_teste_empresa')),false);}
 assert.deepEqual(errors,[]);console.log('PASS: public trial CTA, company signup, confirmation before provisioning, idempotent first access, server-owned trial notice, expired consultation and checkout errors, confirmed reactivation, and rejection of missing/suspended/driver authorization.');
}finally{await browser?.close();await server.close();}
