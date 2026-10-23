import assert from 'node:assert/strict';
import puppeteer from 'puppeteer-core';
import { createServer } from 'vite';
import ts from 'typescript';
const moduleId='\0virtual:company-identity-test';
const harness=`import '/src/index.css';import React from 'react';import {createRoot} from 'react-dom/client';
import {AuthGate} from '/src/components/AuthGate.tsx';import {CompanySettings} from '/src/components/CompanySettings.tsx';import {Sidebar} from '/src/components/layout/Sidebar.tsx';import {notifyCompanyNameChanged} from '/src/lib/companyIdentity.ts';
window.notifyCompanyNameChanged=notifyCompanyNameChanged;
createRoot(document.getElementById('root')).render(new URLSearchParams(location.search).get('view')==='auth'?<AuthGate><p>Área autenticada</p></AuthGate>:<div className="flex"><Sidebar activeTab="settings" onTabChange={()=>{}}/><main className="p-6"><CompanySettings/></main></div>);`;
const fake=`export const isSupabaseConfigured=true;window.calls=[];window.companyName='Essenza Condomínios';window.saveFailure=false;const id='11111111-1111-1111-1111-111111111111';
const user={id:'manager',email:'manager@example.test',user_metadata:{name:'Gestor'}};const session=new URLSearchParams(location.search).get('view')==='auth'?null:{access_token:'synthetic',user};
export const supabase={auth:{getSession:async()=>({data:{session}}),getUser:async()=>({data:{user}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signUp:async(args)=>{window.signup=args;return {data:{user:{id:'new-manager'},session:null}};},signOut:async()=>({})},
from(table){const params={table};const q={select(){return q;},eq(key,value){params[key]=value;return q;},single:async()=>{window.calls.push(params);return {data:{nome:params.id===id?window.companyName:'OTHER COMPANY'}};}};return q;},
rpc:async(name,args)=>{window.calls.push({name,args});if(name==='obter_meu_status_acesso')return {data:{empresa_id:id,papel:'gestor',status:'aprovado'}};if(name==='configurar_nome_empresa'){if(window.saveFailure)return {error:{message:'not authorized'}};if(args.p_empresa_id!==id)throw Error('Wrong company');window.companyName=args.p_nome;return {data:{sucesso:true}};}return {data:{sucesso:true}};}};`;
const server=await createServer({server:{host:'127.0.0.1',port:0},plugins:[{name:'company-identity-test',enforce:'pre',resolveId(id){if(id==='virtual:company-identity-test')return moduleId;},load(id){if(id.replaceAll('\\','/').endsWith('/src/lib/supabase.ts'))return fake;if(id===moduleId)return ts.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText;},configureServer(s){s.middlewares.use('/__identity_test',async(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(await s.transformIndexHtml('/__identity_test','<html><head><meta name="viewport" content="width=device-width,initial-scale=1"/></head><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:company-identity-test"></script></body></html>'));});}}]});
let browser;
try{
 await server.listen();const port=server.httpServer.address().port;
 browser=await puppeteer.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const base='http://127.0.0.1:'+port+'/__identity_test';
 await page.setViewport({width:390,height:844});await page.goto(base+'?view=auth');await page.waitForSelector('input[type="email"]');
 assert.equal(await page.$('#company-name'),null,'Existing login must not require company name on every sign-in.');
 await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Criar empresa')).click());await page.waitForSelector('#company-name');
 assert.equal(await page.$eval('#company-name',e=>e.autocomplete),'organization');assert.match(await page.$eval('#company-name-help',e=>e.textContent),/mensagens.*acompanhamento.*comprovantes/);
 await page.type('input[placeholder="Ex: Carlos Oliveira"]','Gestor Teste');await page.type('#company-name','  Essenza Condomínios  ');await page.type('input[type="email"]','new@example.test');await page.type('input[autocomplete="new-password"]','test-password');
 await page.evaluate(()=>document.querySelector('form').requestSubmit());await page.waitForFunction(()=>window.signup);
 assert.equal(await page.evaluate(()=>window.signup.options.data.empresa_nome),'Essenza Condomínios');assert.equal(await page.evaluate(()=>window.calls.some(c=>c.table==='empresas')),false,'No direct company writes without a confirmed session.');
 await page.setViewport({width:1100,height:900});await page.goto(base+'?view=branding');await page.waitForFunction(()=>document.querySelector('[data-company-identity]')?.textContent==='Essenza Condomínios');await page.waitForFunction(()=>document.querySelector('main input')?.value==='Essenza Condomínios');
 const name=await page.$('main input');await name.focus();await page.keyboard.down('Control');await page.keyboard.press('KeyA');await page.keyboard.up('Control');await page.keyboard.press('Backspace');await name.type('Gaia Serviços');
 assert.equal(await page.$eval('[data-company-identity]',e=>e.textContent),'Essenza Condomínios','Unsaved preview must not rename the company.');
 await page.screenshot({path:'C:/Src/NewV10/company-identity-20261023/settings-preview.png',fullPage:true});await page.click('main button');await page.waitForFunction(()=>document.querySelector('[data-company-identity]')?.textContent==='Gaia Serviços',{timeout:5000}).catch(async error=>{console.log(await page.evaluate(()=>({name:document.querySelector('main input').value,heading:document.querySelector('[data-company-identity]').textContent,calls:window.calls,body:document.querySelector('main').innerText})));throw error;});
 assert.ok(await page.evaluate(()=>window.calls.find(c=>c.name==='configurar_nome_empresa'&&c.args.p_nome==='Gaia Serviços')));
 await page.evaluate(()=>window.notifyCompanyNameChanged('other-company','FOREIGN NAME'));assert.equal(await page.$eval('[data-company-identity]',e=>e.textContent),'Gaia Serviços');
 await page.evaluate(()=>{window.saveFailure=true;});await name.focus();await page.keyboard.down('Control');await page.keyboard.press('KeyA');await page.keyboard.up('Control');await page.keyboard.press('Backspace');await name.type('Não deve salvar');await page.click('main button');await page.waitForSelector('[role="alert"]');assert.equal(await page.$eval('[data-company-identity]',e=>e.textContent),'Gaia Serviços');
 assert.deepEqual(errors,[]);console.log('PASS: company name in signup metadata, no company prompt at login, authenticated scoped lookup, preview separated from saved identity, successful rename refreshes sidebar, failed/foreign updates ignored.');
}finally{await browser?.close();await server.close();}
