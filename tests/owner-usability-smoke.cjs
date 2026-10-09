// Guest-only regression of owner navigation/layout; no login, grants, role changes or RPC calls.
'use strict';
const http=require('node:http'),path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
const puppeteer=require(process.env.NEXUS_PUPPETEER_PATH||'puppeteer'),root=path.resolve(__dirname,'..');
const ext={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{const p=decodeURIComponent((req.url||'/').split('?')[0]);const file=path.resolve(root,'.'+(p==='/'?'/index.html':p));if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}fs.readFile(file,(e,data)=>{if(e){res.writeHead(404).end();return;}res.writeHead(200,{'Content-Type':ext[path.extname(file)]||'application/octet-stream'});res.end(data)});});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await puppeteer.launch({headless:true,executablePath:process.env.NEXUS_CHROME_BIN||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',args:['--no-sandbox']});
let checks=0;
try{for(const [width,height] of [[1440,800],[1280,680],[1024,650],[768,730],[390,844],[320,700]]){
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('requestfailed',r=>{if(r.url().startsWith('http://127.0.0.1'))errors.push(r.url())});
 await page.setViewport({width,height,isMobile:width<=768,hasTouch:width<=768});await page.goto('http://127.0.0.1:'+server.address().port+'/',{waitUntil:'networkidle2',timeout:25000});
 await new Promise(r=>setTimeout(r,420));
 const onboarding=await page.evaluate(()=>({
   blocked:document.getElementById('betaWelcomeModal').classList.contains('show'),
   banner:document.getElementById('betaReleaseStrip')?.textContent.includes('BETA'),
   infoLink:!!document.getElementById('openBetaWelcome')
 }));
 assert.equal(onboarding.blocked,false,'first visit must not require dismissing Beta modal '+width);checks++;
 assert.equal(onboarding.banner,true,'prominent beta disclosure must remain '+width);checks++;
 assert.equal(onboarding.infoLink,true,'on-demand Beta information must remain '+width);checks++;
 let state=await page.evaluate(()=>{
  const owner=document.getElementById('ownerNav'),btn=document.getElementById('adminBtn');
  const guestHidden=owner.hidden&&btn.hidden, guestStyle=getComputedStyle(owner).display;
  owner.hidden=false;btn.hidden=false;
  const side=document.querySelector('.side'),first=side.querySelector('.navgroup:not(#ownerNav)'),rect=(x)=>x.getBoundingClientRect();
  const adminTop=rect(btn).top,firstTop=rect(first).top;
  const beforeScroll=side.scrollTop,overflow=side.scrollHeight>side.clientHeight;
  side.scrollTop=side.scrollHeight;
  const scrolled=side.scrollTop>0;
  const adminVisible=getComputedStyle(btn).display!=='none';
  const docWidth=document.documentElement.scrollWidth;
  return{guestHidden,guestStyle,adminVisible,adminTop,firstTop,overflow,scrolled,beforeScroll,docWidth,width:innerWidth};
 });
 assert.ok(state.guestHidden && state.guestStyle==='none','guest must not see owner nav '+width);checks++;
 assert.ok(state.adminVisible && state.adminTop<state.firstTop,'admin before ordinary navigation '+width);checks++;
 assert.ok(state.docWidth<=width+1,'no root horizontal overflow '+width);checks++;
 if(width>820){
  assert.ok(state.adminTop>=0 && state.adminTop<height,'admin direct access visible on laptop '+JSON.stringify(state));checks++;
  assert.ok(state.overflow && state.scrolled,'sidebar must scroll on laptop '+JSON.stringify(state));checks++;
 }
 const search=await page.evaluate(()=>{
  const modal=document.getElementById('adminModal'),list=document.getElementById('adminUsers');modal.classList.add('show');
  list.replaceChildren();
  for(const entry of [['Mario Rossi','example1@invalid.test'],['Giulia Verdi','example2@invalid.test']]){
   const row=document.createElement('div');row.className='admin-user jobrow';
   const head=document.createElement('div');head.className='jobhead';const strong=document.createElement('strong');strong.textContent=entry[0];head.append(strong);
   const meta=document.createElement('div');meta.className='jobmeta';meta.textContent=entry[1];row.append(head,meta);list.append(row);
  }
  const input=document.getElementById('adminUserSearch');input.value='giulia';input.dispatchEvent(new Event('input',{bubbles:true}));
  return {found:[...list.children].filter(x=>!x.hidden).length,summary:document.getElementById('adminUserSearchResult').textContent.trim(),searchVisible:input.getBoundingClientRect().width>0};
 });
 assert.equal(search.found,1,'search filters matching registered-user rows '+width);checks++;
 assert.ok(search.searchVisible&&search.summary.startsWith('1 di 2'),'owner search UX available '+width);checks++;
 const authenticated=await page.evaluate(()=>{
  const demo=document.querySelector('#intro .aether-showcase');
  const before=getComputedStyle(demo).display;
  document.body.classList.add('nexus-authenticated');
  const after=getComputedStyle(demo).display;
  const composer=document.querySelector('#prompt');
  return {before,after,composerVisible:composer.getBoundingClientRect().width>0,headline:document.querySelector('#intro h1')?.textContent.trim()};
 });
 assert.equal(authenticated.before,'none','compact guest layout must avoid misleading decorative chat '+width);
 assert.equal(authenticated.after,'none','real users must not see duplicate fake chat '+width);checks++;
 assert.equal(authenticated.composerVisible,true,'actual chat input available '+width);checks++;
 assert.deepEqual(errors,[],'no JS/load errors '+width);checks++;
 if(process.env.NEXUS_OWNER_SCREENSHOT_DIR){await page.evaluate(()=>{document.getElementById('adminModal').classList.remove('show');document.querySelector('.side').scrollTop=0;document.getElementById('betaWelcomeModal').classList.remove('show')});fs.mkdirSync(process.env.NEXUS_OWNER_SCREENSHOT_DIR,{recursive:true});await page.screenshot({path:path.join(process.env.NEXUS_OWNER_SCREENSHOT_DIR,'owner-'+width+'.png')})}
 console.log('OWNER_UX_PASS',width,JSON.stringify(state));await page.close();
 }console.log('NEXUS_OWNER_UX_PASS checks='+checks);
}finally{await browser.close();await new Promise(r=>server.close(r))}})().catch(e=>{console.error('NEXUS_OWNER_UX_FAIL',e.stack);server.close();process.exitCode=1});
