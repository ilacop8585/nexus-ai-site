// NEXUS admin accessibility regression: guest-only, no auth, no database writes.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const http=require('node:http');
const path=require('node:path');
const p=require(process.env.NEXUS_PUPPETEER_PATH||'puppeteer');
const root=path.resolve(__dirname,'..');
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{const part=decodeURIComponent((req.url||'/').split('?')[0]);const f=path.resolve(root,'.'+(part==='/'?'/index.html':part));if(!f.startsWith(root+path.sep))return res.writeHead(403).end();fs.readFile(f,(e,d)=>{if(e)return res.writeHead(404).end();res.writeHead(200,{'Content-Type':mime[path.extname(f)]||'application/octet-stream'});res.end(d)})});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const base='http://127.0.0.1:'+server.address().port+'/';
 const browser=await p.launch({headless:true,executablePath:process.env.NEXUS_CHROME_BIN||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',args:['--no-sandbox']});
 let checks=0;
 try{
  for(const [width,height] of [[1280,620],[1024,600],[390,730],[320,650]]){
   const page=await browser.newPage(); const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.setViewport({width,height,isMobile:width<800,hasTouch:width<800});
   await page.goto(base,{waitUntil:'networkidle2',timeout:30000});
   assert.equal(await page.$eval('#ownerQuickAdmin',e=>e.hidden),true,'guest shortcut hidden');checks++;
   await page.evaluate(()=>{
     document.getElementById('betaWelcomeModal').classList.remove('show');
     document.getElementById('ownerQuickAdmin').hidden=false;
     document.getElementById('adminBtn').hidden=false;
     document.getElementById('ownerNav').hidden=false;
     document.getElementById('adminBtn').onclick=()=>{document.body.dataset.ownerShortcutTest='clicked'};
   });
   if(width<800){await page.click('#mobileChatsBtn');await new Promise(r=>setTimeout(r,350));}
   const state=await page.evaluate(()=>{
     const side=document.querySelector('.side'),quick=document.querySelector('#ownerQuickAdmin'),owner=document.querySelector('#ownerNav'),admin=document.querySelector('#adminBtn');
     let q=quick.getBoundingClientRect(),s=side.getBoundingClientRect(),a=admin.getBoundingClientRect();
     const initial={sideScrollHeight:side.scrollHeight,sideClientHeight:side.clientHeight,overflow:getComputedStyle(side).overflowY,quickVisible:q.height>0&&q.top>=s.top&&q.bottom<=s.bottom,ownerTop:a.top,sideBottom:s.bottom};
     side.scrollTop=side.scrollHeight;
     const after={scrollTop:side.scrollTop,adminBottom:admin.getBoundingClientRect().bottom,sideBottom:side.getBoundingClientRect().bottom};
     side.scrollTop=0;
     return {initial,after,root:document.documentElement.scrollWidth,width:innerWidth};
   });
   assert.equal(state.initial.overflow,'auto','sidebar should scroll '+width);checks++;
   assert.ok(state.initial.quickVisible,'owner shortcut visible without scrolling '+width);checks++;
   assert.ok(state.after.adminBottom<=state.after.sideBottom+2,'admin item scroll reachable '+width+': '+JSON.stringify(state));checks++;
   assert.equal(state.root,state.width,'no root x overflow '+width);checks++;
   await page.click('#ownerQuickAdmin');
   assert.equal(await page.evaluate(()=>document.body.dataset.ownerShortcutTest),'clicked','owner quick delegates to existing admin button');checks++;
   await page.evaluate(()=>{document.getElementById('adminModal').classList.add('show');const box=document.getElementById('adminUsers');for(let i=0;i<35;i++){const row=document.createElement('div');row.className='jobrow';row.textContent='QA-only user '+i;box.appendChild(row)}});
   const modal=await page.evaluate(()=>{const e=document.querySelector('#adminModal .modal-card'),s=getComputedStyle(e);e.scrollTop=e.scrollHeight;return{scroll:e.scrollTop,canScroll:e.scrollHeight>e.clientHeight,overflow:s.overflowY}});
   assert.ok(modal.canScroll && modal.scroll>0,'admin modal scroll '+width+' '+JSON.stringify(modal));checks++;
   assert.deepEqual(errors,[],'JS errors '+width);checks++;
   console.log('OWNER_QA_PASS '+width+'x'+height+' '+JSON.stringify(state));
   await page.close();
  }
  console.log('NEXUS_OWNER_ADMIN_ACCESS_PASS checks='+checks);
 }finally{await browser.close();await new Promise(r=>server.close(r))}
})().catch(e=>{console.error('NEXUS_OWNER_ADMIN_ACCESS_FAIL '+e.stack);server.close();process.exitCode=1});
