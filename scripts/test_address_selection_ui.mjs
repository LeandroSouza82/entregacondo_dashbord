import assert from 'node:assert/strict';
import puppeteer from 'puppeteer-core';
import { createServer } from 'vite';

const moduleId = '\0virtual:address-regression';
const harness = `
import React, {useState} from 'react';
import {createRoot} from 'react-dom/client';
import {PlacesAutocompleteInput} from '/src/components/routing/PlacesAutocompleteInput.tsx';
function Harness() {
 const [value,setValue]=useState(''); const [selected,setSelected]=useState(null);
 return <><PlacesAutocompleteInput value={value} onChange={text=>{setValue(text);setSelected(null);}}
   coordenadas={selected?.coordenadas ?? null} onAddressSelect={data=>{setSelected(data);setValue(data.enderecoCompleto);}} />
   <pre id="selected">{JSON.stringify(selected)}</pre></>;
}
createRoot(document.getElementById('root')).render(<Harness/>);
`;
const server = await createServer({
  server: {host:'127.0.0.1',port:0},
  plugins:[{
    name:'address-regression-harness',
    resolveId(id) { if(id==='virtual:address-regression') return moduleId; },
    async load(id) { if(id===moduleId) return (await import('typescript')).default.transpileModule(harness,{compilerOptions:{jsx:4,module:99,target:9}}).outputText; },
    configureServer(server) {
      server.middlewares.use('/__address_regression', async (_req,res) => {
        res.setHeader('Content-Type','text/html');
        res.end(await server.transformIndexHtml('/__address_regression','<html><body><div id="root"></div><script type="module" src="/@id/__x00__virtual:address-regression"></script></body></html>'));
      });
    },
  }],
});
let browser;
try {
 await server.listen();
 const port=server.httpServer.address().port;
 browser=await puppeteer.launch({executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',headless:true});
 const page=await browser.newPage();
 let mode='failure';
 const pageErrors=[];
 page.on('pageerror',e=>pageErrors.push(e.message));
 await page.setRequestInterception(true);
 page.on('request',async req=>{
   const url=new URL(req.url());
   if(url.hostname==='127.0.0.1'||url.protocol==='data:') return req.continue();
   if(url.hostname==='nominatim.openstreetmap.org') {
     const query=url.searchParams.get('q') || '';
     if(mode==='race'&&query.startsWith('Endereço antigo')) await new Promise(r=>setTimeout(r,500));
     const body=mode==='failure'?[]:[{place_id:1,lat:query.startsWith('Endereço antigo')?'-27.59':'-27.65',lon:'-48.67',display_name:query}];
     return req.respond({status:200,contentType:'application/json',headers:{'Access-Control-Allow-Origin':'*'},body:JSON.stringify(body)});
   }
   return req.respond({status:200,contentType:'application/json',headers:{'Access-Control-Allow-Origin':'*'},body:'[]'});
 });
 await page.goto(`http://127.0.0.1:${port}/__address_regression`);
 await page.waitForSelector('input');
 const type=async value=>{await page.focus('input');await page.keyboard.down('Control');await page.keyboard.press('A');await page.keyboard.up('Control');await page.keyboard.type(value);};
 const selected=()=>page.$eval('#selected',el=>JSON.parse(el.textContent));
 await type('Rua Vereador Jacob Knabben da Silva, 3080, Palhoça');
 await page.keyboard.press('Enter');
 await page.waitForSelector('[role="alert"]');
 assert.equal(await selected(),null);
 console.log('PASS: lookup failure shows feedback without a Florianópolis fallback');
 mode='success';
 await type('Rua Vereador Jacob Knabben da Silva, 3080, Palhoça');
 await page.keyboard.press('Enter');
 await page.waitForFunction(()=>document.querySelector('#selected').textContent.includes('-27.65'));
 assert.equal((await selected()).coordenadas.lng,-48.67);
 console.log('PASS: selected lookup coordinates reach the parent unchanged');
 mode='failure';
 await type('Outro endereço, Palhoça');
 assert.equal(await selected(),null);
 await page.keyboard.press('Enter');
 await page.waitForSelector('[role="alert"]');
 assert.equal(await selected(),null);
 console.log('PASS: editing clears the old destination, including when the new lookup fails');
 mode='race';
 await type('Endereço antigo, Florianópolis');
 await page.keyboard.press('Enter');
 await type('Endereço novo, Palhoça');
 await page.keyboard.press('Enter');
 await page.waitForFunction(()=>document.querySelector('#selected').textContent.includes('Endereço novo'));
 await new Promise(r=>setTimeout(r,650));
 assert.match((await selected()).enderecoCompleto,/Endereço novo/);
 assert.equal((await selected()).coordenadas.lat,-27.65);
 assert.deepEqual(pageErrors,[]);
 console.log('PASS: delayed lookup cannot overwrite a newer selection; no browser errors');
} finally { await browser?.close(); await server.close(); }
