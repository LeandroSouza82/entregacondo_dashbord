import assert from 'node:assert/strict';
import fs from 'node:fs';
import puppeteer from 'puppeteer-core';
import {createServer} from 'vite';
import ts from 'typescript';
const id='\0virtual:rules-harness';
const harness=`
import '/src/index.css';
import React from 'react';import {createRoot} from 'react-dom/client';
import {NewRouteView} from '/src/components/routing/NewRouteView.tsx';
window.rpcCalls=[]; window.supported=false;
const which=new URLSearchParams(location.search).get('case');
const company='11111111-1111-1111-1111-111111111111',driver='c1000000-0000-0000-0000-000000000001';
const pickup='a1000000-0000-0000-0000-000000000001',delivery='a2000000-0000-0000-0000-000000000001';
const ruleDate='2099-10-22';
const base={clienteEnderecoId:'d1000000-0000-0000-0000-000000000001',coordenadas:{lat:-27.63,lng:-48.68},enderecoFormatado:'Rua teste, Palhoça',tempoMedioAtendimentoMinutos:10,prioridade:'normal',unidade:'302'};
const stops=[{...base,id:delivery,sequencia:1,nomeLocal:'Entrega teste',destinatario:'Entrega teste',tipoTarefa:'entrega',codigoRastreio:'D-1',...(which==='legacy'?{}:{coletaOrigemId:pickup,janelaData:ruleDate,janelaInicio:'09:00',janelaFim:'12:00'})},
{...base,id:pickup,sequencia:2,nomeLocal:'Coleta teste',destinatario:'Coleta teste',tipoTarefa:'coleta',codigoRastreio:'C-1'}];
localStorage.setItem('ec_draft_current_route',JSON.stringify({motoristaAtivo:driver,entregasDaRota:stops,observacaoTexto:'Manter apartamento 302',otimizarAutomatico:true,saidaPrevista:ruleDate+'T08:30',pontoPartida:{nome:'Empresa teste',endereco:'Rua origem',coordenadas:{lat:-27.62,lng:-48.67}},timestamp:Date.now()}));
createRoot(document.getElementById('root')).render(<NewRouteView/>);
`;
const fakeSupabase=`
export const isSupabaseConfigured=true;
export const supabase={auth:{getSession:async()=>({data:{session:{access_token:'synthetic-test-session'}}})},
 rpc:async(name,params)=>{window.rpcCalls.push({name,params});return {data:name==='obter_meu_status_acesso'?{empresa_id:'11111111-1111-1111-1111-111111111111',status:'aprovado',papel:'gestor'}:name==='obter_capacidades_rotas'?(window.supported?{regras_opcionais:1}:null):name==='enviar_pedidos_motorista'?{sucesso:true,mensagem:'Pedidos teste enviados'}:[]};},
 from:(table)=>{const q={select(){return q;},eq(){return q;},neq(){return q;},order(){return q;},in(){return q;},gte(){return q;},limit(){return q;},then(ok,bad){return Promise.resolve({data:table==='motoristas'?[{id:'c1000000-0000-0000-0000-000000000001',nome:'Leandro teste',veiculo_modelo:'Carro',status:'disponivel',ativo:true}]:[]}).then(ok,bad);}};return q;}};
`;
const server=await createServer({server:{host:'127.0.0.1',port:0},define:{'import.meta.env.VITE_MAPBOX_TOKEN':JSON.stringify('synthetic-token')},plugins:[{
 name:'route-rules-harness',enforce:'pre',
 resolveId(x){if(x==='virtual:rules-harness')return id;},
 load(x){if(x.replaceAll('\\','/').endsWith('/src/components/routing/RouteMap.tsx'))return 'export function RouteMap(){return null;}';if(x.replaceAll('\\','/').endsWith('/src/lib/supabase.ts'))return fakeSupabase;if(x===id)return ts.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText;},
 configureServer(s){s.middlewares.use('/__rules_test',async(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(await s.transformIndexHtml('/__rules_test','<html><head><meta name="viewport" content="width=device-width,initial-scale=1"/></head><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:rules-harness"></script></body></html>'));});},
}]});
let browser;
try {
 await server.listen();const port=server.httpServer.address().port;
 browser=await puppeteer.launch({executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',headless:true});
 const page=await browser.newPage();await page.setViewport({width:1280,height:900});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.setRequestInterception(true);
 page.on('request',req=>{
  const url=new URL(req.url());if(url.hostname==='127.0.0.1'||url.protocol==='data:'||url.protocol==='blob:')return req.continue();
  const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Access-Control-Allow-Methods':'GET,POST,OPTIONS'};
  if(req.method()==='OPTIONS')return req.respond({status:204,headers});
  if(url.pathname.includes('directions-matrix')){
   const n=url.pathname.split('/').at(-1).split(';').length;
   const ids=Array.from({length:n},(_,i)=>i);const sources=(url.searchParams.get('sources')||ids.join(';')).split(';').map(Number),destinations=(url.searchParams.get('destinations')||ids.join(';')).split(';').map(Number);
   return req.respond({status:200,headers,contentType:'application/json',body:JSON.stringify({code:'Ok',durations:sources.map(i=>destinations.map(j=>i===j?0:60))})});
  }
  if(url.pathname.includes('/directions/'))return req.respond({status:200,headers,contentType:'application/json',body:JSON.stringify({code:'Ok',routes:[{distance:2000,duration:180,geometry:{type:'LineString',coordinates:[[-48.67,-27.62],[-48.68,-27.63]]}}]})});
  return req.respond({status:200,headers,contentType:'application/json',body:'{}'});
 });
 const open=async(which)=>{await page.goto('http://127.0.0.1:'+port+'/__rules_test?case='+which);await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(b=>b.textContent.includes('Enviar serviços para Leandro')));};
 const clickText=async(text)=>page.evaluate(text=>{const b=[...document.querySelectorAll('button')].find(b=>b.textContent.includes(text));if(!b)throw Error('Botão ausente: '+text);b.click();},text);
 const draft=()=>page.evaluate(()=>JSON.parse(localStorage.getItem('ec_draft_current_route')));
 await open('legacy');
 assert.equal(await page.$('[aria-label="Planejamento com condições"]'),null);
 assert.equal((await draft()).entregasDaRota[0].unidade,'302');
 const collapsed=await page.$eval('input[name="janela_data_ec"]',input=>!!input.closest('details')&&!input.closest('details').open);assert.equal(collapsed,true);
 await clickText('Enviar serviços para Leandro');await page.waitForFunction(()=>window.rpcCalls.some(c=>c.name==='enviar_pedidos_motorista'));
 assert.equal(await page.evaluate(()=>window.rpcCalls.some(c=>c.name==='obter_capacidades_rotas')),false);
 console.log('PASS: unchanged legacy draft, old apartment preserved, optional section collapsed, rule-free dispatch skips capability gate');
 await open('rules');await page.waitForFunction(()=>document.querySelector('[aria-label="Planejamento com condições"]')?.textContent.includes('Sequência conferida'));
 assert.equal((await draft()).saidaPrevista,'2099-10-22T08:30');
 await clickText('Salvar como rascunho');assert.equal((await draft()).saidaPrevista,'2099-10-22T08:30');
 await page.evaluate(()=>document.querySelector('button[title="Remover esta parada da rota"]').click());
 await page.waitForFunction(()=>document.body.textContent.includes('Remova o vínculo'));assert.equal((await draft()).entregasDaRota.length,2);
 await clickText('Enviar serviços para Leandro');await page.waitForFunction(()=>document.body.textContent.includes('ainda não recebeu a atualização'));
 assert.equal(await page.evaluate(()=>window.rpcCalls.filter(c=>c.name==='enviar_pedidos_motorista').length),0);assert.equal((await draft()).entregasDaRota.length,2);
 console.log('PASS: pickup-first planning, parent removal blocked, missing backend capability keeps the whole draft');
 await page.evaluate(()=>{window.supported=true;});await clickText('Enviar serviços para Leandro');
 await page.waitForFunction(()=>window.rpcCalls.some(c=>c.name==='enviar_pedidos_motorista'));
 const sent=await page.evaluate(()=>window.rpcCalls.find(c=>c.name==='enviar_pedidos_motorista').params.p_dados);
 assert.equal(sent.paradas[0].tipo_tarefa,'coleta');assert.equal(sent.paradas[1].coleta_origem_id,sent.paradas[0].id);
 assert.deepEqual(sent.agenda.map(v=>v.entrega_id),sent.paradas.map(p=>p.id));assert.equal(sent.planejamento_saida_em,'2099-10-22T11:30:00.000Z');
 console.log('PASS: actual dispatch preserves stable ids, order, linked pickup, Brasília UTC departure and complete agenda');
 await open('rules');await page.waitForFunction(()=>document.body.textContent.includes('Sequência conferida'));
 await page.evaluate(()=>[...document.querySelectorAll('button')].filter(b=>b.textContent==='Editar condições')[1].click());await page.waitForSelector('dialog[open]');
 assert.equal(await page.$eval('dialog select[name="coleta_origem_ec"]',e=>e.options.length),2);
 await page.select('dialog select[name="coleta_origem_ec"]','');
 await page.$eval('dialog input[name="janela_fim_ec"]',input=>{const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;setter.call(input,'08:00');input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));});
 await clickText('Salvar condições');await page.waitForSelector('dialog [role="alert"]');assert.match(await page.$eval('dialog [role="alert"]',e=>e.textContent),/final deve ser depois/);
 await clickText('Limpar condições opcionais');await clickText('Salvar condições');await page.waitForFunction(()=>!document.querySelector('dialog[open]'));
 assert.equal((await draft()).entregasDaRota[0].coletaOrigemId,undefined);
 assert.equal(await page.$('[aria-label="Planejamento com condições"]'),null);
 await open('rules');await page.waitForFunction(()=>document.body.textContent.includes('Sequência conferida'));
 await page.$eval('input[type="datetime-local"]',input=>{const setter=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;setter.call(input,'2099-10-22T13:00');input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));});
 await clickText('Enviar serviços para Leandro');
 await page.waitForFunction(()=>document.body.textContent.includes('Não foi possível organizar estes horários'));
 assert.equal(await page.evaluate(()=>window.rpcCalls.some(c=>c.name==='enviar_pedidos_motorista')),false);
 assert.equal((await draft()).entregasDaRota.length,2);
 console.log('PASS: changing departure invalidates the previous plan; infeasible windows preserve the draft and prevent dispatch');
 await page.$eval('details',el=>{el.open=true;});
 fs.mkdirSync('docs/previews',{recursive:true});await page.setViewport({width:390,height:844});await page.screenshot({path:'docs/previews/optional-route-rules-infeasible.png',fullPage:true});
 await open('rules');await page.waitForFunction(()=>document.querySelector('[aria-label="Planejamento com condições"]')?.textContent.includes('Sequência conferida'));await page.$eval('details',el=>{el.open=true;});await page.screenshot({path:'docs/previews/optional-route-rules-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS: real dialog, selectable collection, invalid window feedback, clearing optional rules, mobile viewport, no browser exceptions');
} finally {await browser?.close();await server.close();}
