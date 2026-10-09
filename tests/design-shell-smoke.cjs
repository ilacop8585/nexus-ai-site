// NEXUS design shell smoke — local, guest-only, no production mutations.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');
const puppeteer=require(process.env.NEXUS_PUPPETEER_PATH||'puppeteer');
const root=path.resolve(__dirname,'..');
const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.cjs':'text/javascript','.svg':'image/svg+xml','.json':'application/json'};
const server=http.createServer((req,res)=>{
 const pathname=decodeURIComponent((req.url||'/').split('?')[0]);
 const name=pathname==='/'?'/index.html':pathname;
 const file=path.resolve(root,'.'+name);
 if(file!==root&&!file.startsWith(root+path.sep)){res.writeHead(403).end();return}
 fs.readFile(file,(err,data)=>{if(err){res.writeHead(404).end();return}res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});res.end(data)});
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const url='http://127.0.0.1:'+server.address().port+'/';
 const chrome=process.env.NEXUS_CHROME_BIN||(process.platform==='win32'?'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe':undefined);
 const browser=await puppeteer.launch({headless:true,...(chrome?{executablePath:chrome}:{}),args:['--no-sandbox','--disable-dev-shm-usage']});
 let count=0;
 try{
  for(const width of [1440,768,390,320]){
   const page=await browser.newPage();
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   page.on('requestfailed',r=>{if(r.url().startsWith(url))errors.push('failed-local '+r.url())});
   await page.setViewport({width,height:850,isMobile:width<=768,hasTouch:width<=768});
   await page.goto(url,{waitUntil:'networkidle2',timeout:35000});
   await page.waitForSelector('#mobileModeSelect',{timeout:8000});
   await page.evaluate(()=>{const m=document.querySelector('#betaWelcomeModal');if(m)m.classList.remove('show')});
   const initial=await page.evaluate(()=>{
    const box=sel=>{const e=document.querySelector(sel);if(!e)return null;const r=e.getBoundingClientRect(),s=getComputedStyle(e);return {visible:r.width>0&&r.height>0&&s.display!=='none',x:r.x,right:r.right,height:r.height}};
    return{viewport:innerWidth,scrollWidth:document.documentElement.scrollWidth,brand:box('.mobile-brand'),menu:box('#mobileChatsBtn'),mode:box('#mobileModeSelect'),logo:!!document.querySelector('.brand img'),language:document.querySelector('#nexusLanguage')?.value};
   });
   assert.equal(initial.language,'it','Italian default at '+width);
   assert.equal(initial.logo,true,'SVG branding at '+width);
   assert.ok(initial.scrollWidth<=width+1,'root overflow at '+width+': '+JSON.stringify(initial));
   if(width<=768){
    assert.ok(initial.brand?.visible && initial.menu?.visible && initial.mode?.visible,'mobile shell visible at '+width);
    await page.click('#mobileChatsBtn');
    assert.equal(await page.$eval('.side',e=>e.classList.contains('open')),true,'drawer opens');
    assert.equal(await page.$eval('#mobileChatsBtn',e=>e.getAttribute('aria-expanded')),'true');
    await page.select('#mobileModeSelect','work');
    assert.equal(await page.$eval('[data-nexus-mode="work"]',e=>e.getAttribute('aria-pressed')),'true','Work available on mobile');
    await page.keyboard.press('Escape');
    assert.equal(await page.$eval('.side',e=>e.classList.contains('open')),false,'Escape closes drawer');
    count+=3;
   }else{
    assert.equal(initial.brand?.visible,false,'desktop mobile brand hidden');
    count++;
   }
   // Force open UI, only in ephemeral guest DOM. Verify actual scroll mechanics.
   const scrolls=await page.evaluate(()=>{
    const runtime=document.querySelector('#taskRuntimePanel');
    runtime.classList.add('open');
    const rs=document.querySelector('.runtime-scroll');
    for(let i=0;i<32;i++){const e=document.createElement('div');e.className='runtime-step';e.textContent='QA scroll row '+i;rs.appendChild(e)}
    rs.scrollTop=rs.scrollHeight;
    const r={scrollHeight:rs.scrollHeight,clientHeight:rs.clientHeight,scrollTop:rs.scrollTop};
    runtime.classList.remove('open');
    const project=document.querySelector('#projectWorkspace');project.classList.add('open');
    const body=document.querySelector('#projectPaneOverview');
    for(let i=0;i<45;i++){const e=document.createElement('div');e.className='project-item';e.textContent='QA project scroll row '+i;body.appendChild(e)}
    const ps=document.querySelector('.project-ws-content');ps.scrollTop=ps.scrollHeight;
    const p={scrollHeight:ps.scrollHeight,clientHeight:ps.clientHeight,scrollTop:ps.scrollTop};
    return{runtime:r,project:p};
   });
   assert.ok(scrolls.runtime.scrollHeight>scrolls.runtime.clientHeight && scrolls.runtime.scrollTop>0,'task runtime scroll fails: '+JSON.stringify(scrolls));
   assert.ok(scrolls.project.scrollHeight>scrolls.project.clientHeight && scrolls.project.scrollTop>0,'project workspace scroll fails: '+JSON.stringify(scrolls));
   assert.deepEqual(errors,[],'browser errors at '+width);
   count+=3;
   console.log('PASS',width,JSON.stringify({initial,scrolls}));
   await page.close();
  }
  console.log('NEXUS_DESIGN_SHELL_PASS assertions='+count);
 }finally{await browser.close();await new Promise(r=>server.close(r))}
})().catch(err=>{console.error('NEXUS_DESIGN_SHELL_FAIL',err.stack||err);server.close();process.exitCode=1});
