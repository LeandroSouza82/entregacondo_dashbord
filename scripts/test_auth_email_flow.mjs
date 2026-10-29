import assert from 'node:assert/strict';
import puppeteer from 'puppeteer-core';
import {createServer} from 'vite';
import ts from 'typescript';
const id='\0virtual:auth-email-flow';
const harness=`import '/src/index.css';import React from 'react';import {createRoot} from 'react-dom/client';import {App} from '/src/App.tsx';createRoot(document.getElementById('root')).render(<App/>);`;
const fake=`export const isSupabaseConfigured=true;export const supabaseUrl='https://example.supabase.co';window.calls=[];
const record=(name,args)=>{window.calls.push({name,args});sessionStorage.setItem('auth-test-calls',JSON.stringify(window.calls));};
let notify=()=>{}, activeSession=null;
const user={id:'user',email:'new@example.test',email_confirmed_at:'2026-10-27T00:00:00Z'};
const auth={getSession:async()=>({data:{session:location.search.includes('auth_action=')?{access_token:'synthetic',user}:activeSession}}),getUser:async()=>({data:{user}}),onAuthStateChange:callback=>{notify=callback;return {data:{subscription:{unsubscribe(){}}}};},
signUp:async args=>{record('signup',args);return {data:{session:null,user:{...user,email_confirmed_at:null,identities:args.email.startsWith('existing')?[]:[{provider:'email'}]}}};},
resend:async args=>{record('resend',args);return {};},resetPasswordForEmail:async(...args)=>{record('recovery',args);return {};},signInWithOAuth:async args=>{record('google',args);return {};},
signOut:async args=>{record('signout',args);activeSession=null;notify('SIGNED_OUT',null);return {};},updateUser:async args=>{record('updateUser',{passwordLength:args.password.length});return {};},
verifyOtp:async args=>{record('verify',args);if(args.token){if(args.token!=='123456')return {error:{code:'otp_expired'}};const session={access_token:'synthetic',user};activeSession=session;notify('SIGNED_IN',session);return {data:{user,session}};}return args.token_hash.startsWith('0')?{error:{message:'expired'}}:{data:{user,session:{access_token:'synthetic',user}}};}};
export const supabase={auth,rpc:async name=>{record(name,{});if(name==='sincronizar_meu_perfil')return {data:{sucesso:true}};if(name==='obter_meu_status_acesso')return {data:{status:'sem_vinculo'}};return {error:{message:'Provisioning must not run in email actions'}};}};
export function createEmailActionClient(){return {auth};}`;
const server=await createServer({server:{host:'127.0.0.1',port:0},plugins:[{name:'auth-email-flow',enforce:'pre',resolveId(s){if(s==='virtual:auth-email-flow')return id;},load(s){if(s.replaceAll('\\','/').endsWith('/src/lib/supabase.ts'))return fake;if(s===id)return ts.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText;},configureServer(s){s.middlewares.use(async(req,res,next)=>{if(new URL(req.url,'http://test').pathname!=='/')return next();res.setHeader('Content-Type','text/html');res.end(await s.transformIndexHtml('/','<html><head><meta name="viewport" content="width=device-width,initial-scale=1"/></head><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:auth-email-flow"></script></body></html>'));});}}]});
let browser;
try{
 await server.listen();browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:process.env.CHROME_PATH ? ['--no-sandbox','--disable-dev-shm-usage'] : []});
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));const base='http://127.0.0.1:'+server.httpServer.address().port;
 await page.setViewport({width:390,height:844});await page.goto(base+'/#/cadastro');await page.waitForSelector('input[autocomplete=new-password]');
 await page.type('input[placeholder="Ex: Carlos Oliveira"]','Gestor');await page.type('input[type=email]','existing@example.test');await page.type('input[autocomplete=new-password]','password-test');
 await page.evaluate(()=>document.querySelector('form').requestSubmit());await page.waitForFunction(()=>document.body.innerText.includes('Este e-mail já possui cadastro'));
 assert.equal(await page.$eval('input[type=password]',e=>e.value),'','repeated signup never treats new password as changed');
 assert.equal(await page.evaluate(()=>document.body.innerText.includes('Cadastro recebido!')),false);
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='iniciar_teste_empresa')),false);

 await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Esqueci ou quero')).click());await page.waitForFunction(()=>window.calls.some(c=>c.name==='recovery'));
 assert.match(await page.evaluate(()=>window.calls.find(c=>c.name==='recovery').args[1].redirectTo),/\?auth_action=recovery$/);
 assert.equal(await page.$$eval('button',buttons=>buttons.find(b=>b.textContent.includes('Reenviar confirmação')).disabled),true,'email resend cooldown');
 await page.goto(base+'/#/login');await page.waitForSelector('input[type=email]');await page.evaluate(()=>{window.calls=[];});
 await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Continuar com Google')).click());
 await page.waitForFunction(()=>window.calls.some(c=>c.name==='google'));
 assert.equal(await page.evaluate(()=>window.calls.find(c=>c.name==='google').args.options.queryParams.prompt),'select_account','Google always offers a choice when switching accounts');
 assert.equal(await page.evaluate(()=>window.calls.find(c=>c.name==='google').args.options.redirectTo),base+'/');
 await page.evaluate(()=>{window.calls=[];});
 await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Reenviar confirmação')).click());
 await page.waitForFunction(()=>document.body.innerText.includes('Preencha seu e-mail'));
 assert.equal(await page.evaluate(()=>window.calls.length),0,'missing email never sends');
 await page.type('input[type=email]','new@example.test');await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Reenviar confirmação')).click());
 await page.waitForFunction(()=>window.calls.some(c=>c.name==='resend'));
 assert.match(await page.evaluate(()=>window.calls.find(c=>c.name==='resend').args.options.emailRedirectTo),/\?auth_action=signup$/);
 await page.waitForSelector('input[autocomplete=one-time-code]');
 assert.equal(await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.includes('Reenviar código')).disabled),true);
 await page.type('input[autocomplete=one-time-code]','000000');await page.evaluate(()=>document.querySelector('form').requestSubmit());
 await page.waitForFunction(()=>document.body.innerText.includes('Código incorreto, expirado ou já utilizado'));
 assert.equal(await page.$('#trial-document'),null,'invalid OTP never releases registration');
 await page.$eval('input[autocomplete=one-time-code]',e=>{Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,'123456');e.dispatchEvent(new Event('input',{bubbles:true}));});
 await page.evaluate(()=>document.querySelector('form').requestSubmit());await page.waitForSelector('#trial-document');
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='registrar_teste_empresa')),false,'OTP alone never grants trial');

 await page.goto(base+'/#/ativar?token_hash='+'a'.repeat(64));await page.waitForFunction(()=>location.hash.includes('ativado=1'));
 await page.waitForFunction(()=>document.body.innerText.includes('Acesso ativado!'));
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='iniciar_teste_empresa')),false,'activation returns login without provisioning');
 assert.equal(await page.evaluate(()=>location.href.includes('token_hash')),false,'one-time token removed from URL');
 await page.goto(base+'/#/ativar?token_hash='+'0'.repeat(64));await page.waitForFunction(()=>document.body.innerText.includes('Este link está inválido'));
 await page.goto(base+'/#/definir-senha?token_hash='+'b'.repeat(64));await page.waitForSelector('input[autocomplete=new-password]');
 const inputs=await page.$$('input[type=password]');await inputs[0].type('new-password');await inputs[1].type('mismatch');await page.evaluate(()=>document.querySelector('form').requestSubmit());
 await page.waitForFunction(()=>document.body.innerText.includes('As senhas precisam ser iguais'));
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='updateUser')),false);
 await inputs[1].focus();await page.keyboard.down('Control');await page.keyboard.press('KeyA');await page.keyboard.up('Control');await page.keyboard.press('Backspace');await inputs[1].type('new-password');await page.evaluate(()=>document.querySelector('form').requestSubmit());
 await page.waitForFunction(()=>location.hash.includes('senha=definida'),{timeout:8000}).catch(async e=>{console.error(await page.evaluate(()=>({hash:location.hash,body:document.body.innerText,calls:window.calls.map(c=>c.name),inputs:[...document.querySelectorAll('input[type=password]')].map(x=>x.value.length)})));throw e;});await page.waitForFunction(()=>document.body.innerText.includes('Senha definida!'),{timeout:8000});
 assert.equal(await page.evaluate(()=>location.href.includes('token_hash')),false);
 await page.goto(base+'/?auth_action=signup');await page.waitForFunction(()=>location.hash.includes('ativado=1'),{timeout:8000});await page.waitForFunction(()=>document.body.innerText.includes('Acesso ativado!'));
 assert.equal(await page.evaluate(()=>window.calls.some(c=>c.name==='iniciar_teste_empresa')),false,'native confirmation callback returns login before provisioning');
 await page.goto(base+'/?auth_action=recovery');await page.waitForSelector('input[autocomplete=new-password]',{timeout:8000});
 assert.equal(await page.evaluate(()=>document.body.innerText.includes('Defina sua senha')),true,'native recovery callback is handled before dashboard access');
 assert.deepEqual(errors,[]);
 console.log('PASS: existing Google/email accounts get actionable message, no fake confirmation; no implicit password change; recovery/resend and cooldown; token activation returns login; expired tokens denied; password confirmation and login return. Mock APIs only, no email sent.');
}finally{await browser?.close();await server.close();}
