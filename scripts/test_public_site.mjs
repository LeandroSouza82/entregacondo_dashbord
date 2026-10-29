import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import vm from 'node:vm';
import puppeteer from 'puppeteer-core';
const root=path.resolve('public');
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://test');const pathname=url.pathname==='/'?'/site/index.html':['/privacidade','/termos'].includes(url.pathname)?'/site'+url.pathname+'.html':url.pathname;
 const file=path.resolve(root,'.'+pathname);if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.writeHead(404);res.end();return;}
 const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png'};
 res.setHeader('Content-Type',mime[path.extname(file)]||'text/plain');res.end(fs.readFileSync(file));
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try{
 browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const base='http://127.0.0.1:'+server.address().port;
 for(const width of [320,390,1440]){
  await page.setViewport({width,height:900});await page.goto(base);await page.waitForSelector('h1');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'homepage fits '+width);
  assert.equal(await page.$$eval('img',imgs=>imgs.every(i=>i.complete&&i.naturalWidth>0)),true);
  assert.equal(await page.$eval('link[rel=canonical]',e=>e.href),'https://entregacondo.com.br/');
  assert.equal(await page.$eval('meta[name=robots]',e=>e.content),'index,follow');
  const structured=await page.$eval('script[type="application/ld+json"]',e=>JSON.parse(e.textContent));assert.equal(structured['@graph'][1].name,'EntregaCondo');
  assert.equal(await page.$$eval('a[href*="dashboard."]',links=>links.every(a=>a.href.startsWith('https://dashboard.entregacondo.com.br/#/'))),true);
  if(process.env.SITE_SCREENSHOT_DIR)await page.screenshot({path:path.join(process.env.SITE_SCREENSHOT_DIR,'site-entregacondo-'+width+'.png'),fullPage:true});
  for(const route of ['/privacidade','/termos']){await page.goto(base+route);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);assert.match(await page.$eval('main',e=>e.innerText),/Fast Leituras/);}
 }
 const script=fs.readFileSync('public/site/legacy-access.js','utf8');
 for(const [search,hash,expected] of [['','#/login',true],['','#/cadastro',true],['?auth_action=recovery','#access_token=synthetic&type=recovery',true],['','#/ativar?token_hash=synthetic',true],['','#/comprovante/sample',true],['','#/acompanhar/sample',true],['?utm_source=campaign','#plano',false],['','#recursos',false]]){
  let target;vm.runInNewContext(script,{URLSearchParams,window:{location:{search,hash,replace:value=>target=value},history:{replaceState(){}}}});
  assert.equal(Boolean(target),expected);if(expected)assert.equal(target,'https://dashboard.entregacondo.com.br/'+search+hash);
 }
 // Verify the committed share card without regenerating a production asset during tests.
 await page.goto(base+'/site/social.png');
 await page.waitForFunction(()=>Array.from(document.images).every(i=>i.complete&&i.naturalWidth>0));
 assert.deepEqual(errors,[]);console.log('PASS: static crawlable site, mobile/desktop, images, metadata, links, legal pages and legacy auth/public-link preservation.');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
