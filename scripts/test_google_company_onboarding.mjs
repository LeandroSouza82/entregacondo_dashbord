import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import puppeteer from 'puppeteer-core';
import { createServer } from 'vite';
import ts from 'typescript';

// Exercise the real AuthGate/company client with an OAuth session, without creating production users.
const id = '\0virtual:google-company';
const old = process.argv.includes('--before');
const beforeRef = '04af9ad55c104b4316704c49337404e8b6a1cde7';
const harness = `import '/src/index.css';import React from 'react';import {createRoot} from 'react-dom/client';import {AuthGate} from '/src/components/AuthGate.tsx';createRoot(document.getElementById('root')).render(<AuthGate><div id="dashboard">Painel autorizado</div></AuthGate>);`;
const fake = `export const isSupabaseConfigured=true;window.calls=[];
window.phase=new URLSearchParams(location.search).get('phase')||'google';window.fail=false;window.created={};
let listener;let session={access_token:'synthetic',user:{id:'google-user',email:'google@example.test',user_metadata:{full_name:'Gestor Google'}}};
window.switchAccount=()=>{session={access_token:'other',user:{id:'other-user',email:'other@example.test',user_metadata:{}}};listener('SIGNED_IN',session);};
window.signOut=()=>{session=null;listener('SIGNED_OUT',null);};
export const supabase={auth:{getSession:async()=>({data:{session}}),onAuthStateChange:cb=>{listener=cb;return {data:{subscription:{unsubscribe(){}}}};},signOut:async()=>{window.signOut();return {}; }},
rpc:async(name,args)=>{window.calls.push({name,args});
if(name==='sincronizar_meu_perfil')return {data:{sucesso:true}};
if(name==='obter_meu_status_acesso'){
 if(['driver','pending','suspended'].includes(window.phase))return {data:{status:window.phase==='driver'?'aprovado':window.phase==='pending'?'pendente':'suspenso',papel:window.phase==='driver'?'motorista':'admin',mensagem:'Acesso não autorizado.'}};
 if(window.phase==='api-error')return {error:{message:'offline'}};
 return {data:window.created[session?.user.id]?{status:'aprovado',papel:'admin',empresa_id:'company'}:{status:'sem_vinculo'}};
}
if(name==='registrar_teste_empresa'||name==='iniciar_teste_empresa'){
 const userId=session.user.id;
 if(name==='iniciar_teste_empresa'&&!args?.p_nome_empresa)return {error:{message:'Informe o nome da empresa entre 2 e 120 caracteres.'}};
 if(name==='registrar_teste_empresa'&&!args?.p_cadastro?.documento)return {error:{message:'Documento obrigatório.'}};
 if(window.phase==='delayed')await new Promise(resolve=>window.finishSetup=resolve);
 if(window.fail)return {error:{message:'Falha temporária. Tente novamente.'}};
 window.created[userId]=true;return {data:{sucesso:true,empresa_id:'company'}};
}return {data:[]};}};`;
const server = await createServer({ server:{ host:'127.0.0.1',port:0 }, plugins:[{
  name:'google-company',enforce:'pre',resolveId(s){if(s==='virtual:google-company')return id;},
  load(s){const path=s.replaceAll('\\','/');if(path.endsWith('/src/lib/supabase.ts'))return fake;
    if(old&&path.endsWith('/src/components/AuthGate.tsx'))return execFileSync('git',['show',beforeRef+':src/components/AuthGate.tsx'],{encoding:'utf8'});
    if(old&&path.endsWith('/src/lib/company.ts'))return execFileSync('git',['show',beforeRef+':src/lib/company.ts'],{encoding:'utf8'});
    if(s===id)return ts.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText;},
  configureServer(s){s.middlewares.use('/__google',async(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(await s.transformIndexHtml('/__google','<html><head><meta name="viewport" content="width=device-width,initial-scale=1"/></head><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:google-company"></script></body></html>'));});}
}]});
let browser;
try {
  await server.listen();browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.setViewport({width:390,height:844});
  const base='http://127.0.0.1:'+server.httpServer.address().port+'/__google';
  await page.goto(base);
  if(old){await page.waitForFunction(()=>document.body.textContent.includes('Informe o nome da empresa entre 2 e 120 caracteres.'));assert.equal(await page.$('#setup-company-name'),null);assert.equal(await page.$('#dashboard'),null);console.log('REPRODUCED: Google session without company metadata is trapped in an error with no name input.');}
  else {
    await page.waitForSelector('#trial-document');
    assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='iniciar_teste_empresa')),false,'no creation before explicit company name');
    assert.equal(await page.$('#dashboard'),null);
    if(process.env.GOOGLE_SCREENSHOT_PATH)await page.screenshot({path:process.env.GOOGLE_SCREENSHOT_PATH,fullPage:true});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'mobile fits');
    await page.type('#company-name','  Empresa Google  ');
    await page.type('#trial-document','52998224725');
    await page.type('#trial-phone','48999999999');
    await page.evaluate(()=>{window.fail=true;document.querySelector('form').requestSubmit();});
    await page.waitForFunction(()=>document.body.textContent.includes('Falha temporária'));
    assert.equal(await page.$eval('#company-name',e=>e.value),'  Empresa Google  ','retry retains name');
    await page.evaluate(()=>{window.fail=false;document.querySelector('form').requestSubmit();});await page.waitForSelector('#dashboard');
    assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='registrar_teste_empresa').at(-1).args.p_cadastro.nome_fantasia),'Empresa Google');
    assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='iniciar_teste_empresa')),false,'Google signup also requires documentary registration');
    const before=await page.evaluate(()=>window.calls.filter(c=>c.name==='registrar_teste_empresa').length);
    await page.evaluate(()=>{window.created['other-user']=true;window.switchAccount();});await page.waitForSelector('#dashboard');
    assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='registrar_teste_empresa').length),before,'existing membership never creates another company');
    for(const phase of ['driver','pending','suspended','api-error']){
      await page.goto(base+'?phase='+phase);await page.waitForFunction(()=>document.body.textContent.includes('Atualizar acesso'));
      assert.equal(await page.$('#trial-document'),null);assert.equal(await page.$('#dashboard'),null);
      assert.equal(await page.evaluate(()=>window.calls.some(c=>['iniciar_teste_empresa','registrar_teste_empresa'].includes(c.name))),false);
    }
    await page.goto(base+'?phase=delayed');await page.waitForSelector('#trial-document');await page.type('#company-name','Empresa antiga');
    await page.type('#trial-document','52998224725');await page.type('#trial-phone','48999999999');
    await page.evaluate(()=>document.querySelector('form').requestSubmit());await page.waitForFunction(()=>Boolean(window.finishSetup));
    await page.evaluate(()=>{window.switchAccount();window.finishSetup();});await page.waitForFunction(()=>document.body.textContent.includes('other@example.test'));
    assert.equal(await page.$('#dashboard'),null,'stale response cannot admit a different account');
    await page.waitForSelector('#trial-document');assert.equal(await page.$eval('#company-name',e=>e.value),'','account switch clears previous name');
    assert.equal(await page.$eval('#trial-document',e=>e.value),'','account switch clears previous document');
    await page.evaluate(()=>window.signOut());await page.waitForSelector('input[type=email]');
    assert.deepEqual(errors,[]);console.log('PASS: Google documentary registration, mobile layout, retry, trimmed name, existing membership, blocked roles/API failure, account-switch race and sign-out.');
  }
} finally {await browser?.close();await server.close();}
