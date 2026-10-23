import assert from 'node:assert/strict';
import fs from 'node:fs';
import puppeteer from 'puppeteer-core';
import { createServer } from 'vite';
import ts from 'typescript';

// Real React views in Chrome; only external RPC and map tiles are stubbed.
const moduleId='\0virtual:customer-arrival-harness';
const harness=`
import '/src/index.css';
import React from 'react';import {createRoot} from 'react-dom/client';
import {CustomerTrackingView} from '/src/components/public/CustomerTrackingView.tsx';
import {App} from '/src/App.tsx';
import {NewRouteView} from '/src/components/routing/NewRouteView.tsx';
import {CompanySettings} from '/src/components/CompanySettings.tsx';
import {normalizeCustomerWhatsApp,legacyAddressNotes} from '/src/features/routes/services/customerContact.ts';
window.normalizeCustomerWhatsApp=normalizeCustomerWhatsApp;window.legacyAddressNotes=legacyAddressNotes;
const view=new URLSearchParams(location.search).get('view');
createRoot(document.getElementById('root')).render(view==='publicApp'?<App/>:view==='form'?<NewRouteView/>:view==='settings'?<CompanySettings/>:<CustomerTrackingView token={'a'.repeat(64)}/>);
`;
const server=await createServer({server:{host:'127.0.0.1',port:0},plugins:[{
 name:'customer-arrival-harness',
 resolveId(id){if(id==='virtual:customer-arrival-harness')return moduleId;},
 async load(id){if(id===moduleId)return ts.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText;},
 configureServer(server){server.middlewares.use('/__arrival_test',async(_req,res)=>{res.setHeader('Content-Type','text/html');res.end(await server.transformIndexHtml('/__arrival_test','<html><head><meta name="viewport" content="width=device-width, initial-scale=1" /></head><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:customer-arrival-harness"></script></body></html>'));});},
}],define:{'import.meta.env.VITE_MAPBOX_TOKEN':JSON.stringify('')}});
let browser;
try{
 await server.listen();const port=server.httpServer.address().port;
 browser=await puppeteer.launch({executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',headless:true});
 const page=await browser.newPage();await page.setViewport({width:390,height:844,deviceScaleFactor:1});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')console.log('Browser:',m.text().slice(0,180));});
 let state='active';const calls=[];
 await page.setRequestInterception(true);
 page.on('request',req=>{
  const url=new URL(req.url());if(url.hostname==='127.0.0.1'||url.protocol==='data:')return req.continue();
  if(url.pathname.includes('/rpc/obter_acompanhamento_cliente')){
   if (req.method()==='OPTIONS') return req.respond({status:204,headers:{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Access-Control-Allow-Methods':'POST, OPTIONS'}});
   calls.push(JSON.parse(req.postData()||'{}'));
   const now=Date.now();
   const body=state==='closed'?{estado:'encerrado'}:state==='invalid'?{estado:'indisponivel'}:{estado:'ativo',empresa:'Empresa teste',tipo_tarefa:'coleta',destino:{latitude:-27.63,longitude:-48.68},posicao:{latitude:-27.62,longitude:-48.67},atualizada_em:new Date(now-(state==='stale'?600000:5000)).toISOString(),previsao_atualizada_em:new Date(now-5000).toISOString(),previsao_chegada_em:new Date(now+600000).toISOString(),servidor_em:new Date(now).toISOString()};
   return req.respond({status:state==='error'?503:200,contentType:'application/json',headers:{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*' },body:JSON.stringify(body)});
  }
  return req.respond({status:200,contentType:'application/json',headers:{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*' },body:'[]'});
 });
 const open=async(view='tracking')=>{await page.goto(`http://127.0.0.1:${port}/__arrival_test?view=${view}`);};
 await open();await page.waitForFunction(()=>document.body.textContent.includes('Coleta a caminho'));
 assert.match(await page.$eval('main',el=>el.textContent),/Previsão de chegada: \d\d:\d\d/);
 assert.deepEqual(calls[0],{p_token:'a'.repeat(64)});
 const brandLink=await page.$eval('footer a',a=>({href:a.getAttribute('href'),target:a.target,rel:a.rel}));
 assert.deepEqual(brandLink,{href:'/#/conheca',target:'_blank',rel:'noopener noreferrer'});
 assert.equal(brandLink.href.includes('a'.repeat(64)),false);
 assert.equal(await page.$eval('meta[name="robots"]',el=>el.content),'noindex, nofollow, noarchive');
 assert.equal(await page.$eval('main',el=>el.textContent.includes('INTERNAL NAME')),false);
 state='closed';await page.waitForFunction(()=>document.body.textContent.includes('Acompanhamento encerrado'),{timeout:20000});
 assert.equal(await page.$('[aria-label="Mapa do atendimento"]'),null);
 console.log('PASS: active page, token-only request, ETA, anonymous access and live terminal transition');
 state='stale';await open();await page.waitForFunction(()=>document.body.textContent.includes('Localização desatualizada'));
 assert.match(await page.$eval('main',el=>el.textContent),/Última atualização:/);assert.match(await page.$eval('main',el=>el.textContent),/Previsão de chegada indisponível/);
 await page.waitForFunction(()=>!document.body.textContent.includes('Carregando mapa…'));
 const previewDir=process.env.EC_PREVIEW_DIR || 'docs/previews';
 fs.mkdirSync(previewDir,{recursive:true});await page.screenshot({path:previewDir+'/customer-tracking-stale.png',fullPage:true});
 console.log('PASS: stale GPS shows original timestamp and suppresses ETA');
 state='invalid';await open();await page.waitForFunction(()=>document.body.textContent.includes('Link inválido'));
 state='error';await open();await page.waitForSelector('[role="alert"]');assert.equal(await page.$('[aria-label="Mapa do atendimento"]'),null);
 console.log('PASS: invalid link and network error expose no cached GPS');
 const callsBeforePresentation=calls.length;
 await page.goto(`http://127.0.0.1:${port}/__arrival_test?view=publicApp#/conheca`);
 await page.waitForSelector('#presentation-title');
 assert.match(await page.$eval('h1',el=>el.textContent),/Entregas e coletas com mais organização/);
 assert.equal(calls.length,callsBeforePresentation);
 assert.equal(await page.$eval('header a',el=>el.getAttribute('href')),'/');
 assert.equal(await page.$$eval('article',els=>els.length),3);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 await page.screenshot({path:previewDir+'/entregacondo-presentation.png',fullPage:true});
 console.log('PASS: brand link carries no tracking token; real App renders public presentation without login, requests or horizontal overflow');
 await open('form');await page.waitForSelector('input[name="whatsapp_cliente_ec"]');
 assert.equal(await page.$('input[name="bloco_apartamento_ec"]'),null);
 const result=await page.evaluate(()=>({phone:window.normalizeCustomerWhatsApp('(48) 99999-0000'),notes:window.legacyAddressNotes('Interfonar','302')}));
 assert.deepEqual(result,{phone:'5548999990000',notes:'Interfonar\nApartamento/complemento: 302'});
 await assert.rejects(()=>page.evaluate(()=>window.normalizeCustomerWhatsApp('302')));
 assert.deepEqual(errors,[]);
 console.log('PASS: actual dashboard form, DDD normalization, legacy apartment preservation; no browser exceptions');
}finally{await browser?.close();await server.close();}
