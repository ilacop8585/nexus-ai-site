// Guest-only AETHER acceptance. Local staging, no login, no send and no paid jobs.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');
const puppeteer=require(process.env.NEXUS_PUPPETEER_PATH||'puppeteer');
const root=path.resolve(__dirname,'..');
const ext={'.html':'text/html;charset=utf-8','.css':'text/css;charset=utf-8','.js':'text/javascript;charset=utf-8','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{
 const part=decodeURIComponent((req.url||'/').split('?')[0]);
 const full=path.resolve(root,'.'+(part==='/'?'/index.html':part));
 if(full!==root&&!full.startsWith(root+path.sep)){res.writeHead(403).end();return}
 fs.readFile(full,(err,data)=>{if(err)return res.writeHead(404).end();res.writeHead(200,{'Content-Type':ext[path.extname(full)]||'application/octet-stream'});res.end(data)});
});
(async()=>{
 await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
 const url='http://127.0.0.1:'+server.address().port+'/';
 const browser=await puppeteer.launch({headless:true,executablePath:process.env.NEXUS_CHROME_BIN||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',args:['--no-sandbox']});
 let checks=0;
 try{
 for(const width of [1920,1440,1024,768,390,320]){
  const page=await browser.newPage(); const issues=[];
  page.on('pageerror',e=>issues.push('JS: '+e.message));
  page.on('requestfailed',req=>{if(req.url().startsWith(url))issues.push('LOCAL: '+req.url())});
  await page.setViewport({width,height:850,isMobile:width<=768,hasTouch:width<=768});
  await page.goto(url,{waitUntil:'networkidle2',timeout:25000});
  const data=await page.evaluate(()=>{
   const hero=document.querySelector('#intro .aether-hero'),headline=document.querySelector('#intro h1'),sheet=[...document.styleSheets].some(x=>x.href?.includes('nexus-aether-v3.css'));
   const r=hero.getBoundingClientRect();return{viewport:innerWidth,documentWidth:document.documentElement.scrollWidth,sheet,heroWidth:r.width,headline:headline?.innerText,lang:document.documentElement.lang,modeCount:document.querySelectorAll('[data-nexus-mode]').length,buttons:document.querySelectorAll('#intro .quick [data-prompt]').length,licenseLinked:!!document.querySelector('script[src*="nexus-aether-v3.js"]')};
  });
  assert.equal(data.lang,'it','IT default '+width);checks++;
  assert.equal(data.sheet,true,'AETHER CSS loaded '+width);checks++;
  assert.equal(data.buttons,4,'original quick actions retained '+width);checks++;
  assert.equal(data.modeCount,5,'mode buttons retained '+width);checks++;
  assert.equal(data.documentWidth,data.viewport,'horizontal overflow '+width+': '+JSON.stringify(data));checks++;
  assert.ok(data.heroWidth>0 && data.headline?.includes('Un universo di intelligenza.'),'AETHER hero visible '+width);checks++;
  if(process.env.NEXUS_SCREENSHOT_DIR){
    fs.mkdirSync(process.env.NEXUS_SCREENSHOT_DIR,{recursive:true});
    await page.evaluate(()=>document.getElementById('betaWelcomeModal')?.classList.remove('show'));
    await page.screenshot({path:path.join(process.env.NEXUS_SCREENSHOT_DIR,'aether-'+width+'.png')});
  }
  await page.evaluate(()=>document.getElementById('betaWelcomeModal')?.classList.remove('show'));
  await page.click('#aetherStartChat');
  assert.equal(await page.evaluate(()=>document.activeElement?.id),'prompt','CTA focus '+width);checks++;
  // Inspect language conversion in new page; avoid auth, sending and charge flows.
  await page.select('#nexusLanguage','en');
  await new Promise(ok=>setTimeout(ok,170));
  const translated=await page.evaluate(()=>({lang:document.documentElement.lang,heading:document.querySelector('#intro h1')?.innerText,start:document.getElementById('aetherStartChat')?.innerText}));
  assert.equal(translated.lang,'en','locale toggle '+width);checks++;
  assert.ok(translated.heading?.includes('A universe of intelligence.'),'hero translated '+width+': '+JSON.stringify(translated));checks++;
  await page.close();
  assert.deepEqual(issues,[],'page errors '+width);checks++;
  console.log('AETHER_PASS '+width+' '+JSON.stringify({hero:data.headline,english:translated.heading,scrollWidth:data.documentWidth}));
 }
 console.log('NEXUS_AETHER_ACCEPTANCE_PASS checks='+checks);
 }finally{await browser.close();await new Promise(ok=>server.close(ok))}
})().catch(e=>{console.error('NEXUS_AETHER_ACCEPTANCE_FAIL',e.stack);server.close();process.exitCode=1});
