// NEXUS Word: first-screen usability — verify actions are not buried below fold.
// Read-only guest DOM staging with real Chrome; no user accounts, role updates or charged work.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const assert=require('node:assert/strict'),puppeteer=require(process.env.NEXUS_PUPPETEER_PATH||'puppeteer');
const root=path.resolve(__dirname,'..');
const mime={'.html':'text/html;charset=UTF-8','.css':'text/css;charset=UTF-8','.js':'application/javascript;charset=UTF-8','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{const part=(req.url||'/').split('?')[0],file=path.resolve(root,'.'+(part==='/'?'/index.html':part));if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return}fs.readFile(file,(e,d)=>{if(e){res.writeHead(404).end();return}res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});res.end(d)})});
(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await puppeteer.launch({headless:true,executablePath:process.env.NEXUS_CHROME_BIN||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',args:['--no-sandbox']});
let total=0;
try{for(const [width,height] of [[1440,900],[1280,680],[1024,650],[768,730],[390,844],[320,700]]){
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.setViewport({width,height,isMobile:width<=768,hasTouch:width<=768});
 await page.evaluateOnNewDocument(()=>{try{localStorage.clear()}catch{}});
 await page.goto('http://127.0.0.1:'+server.address().port+'/',{waitUntil:'networkidle2',timeout:24000});
 const r=await page.evaluate(()=>{const get=s=>document.querySelector(s)?.getBoundingClientRect();
 const stage=get('.stage'),quick=get('#intro .quick'),first=get('#intro .quick button'),show=document.querySelector('.aether-showcase'),fake=get('.aether-showcase'),composer=get('.composer-wrap');
 const style=[...document.styleSheets].some(x=>x.href?.includes('nexus-first-screen-clarity.css'));
 return{stage:{top:stage.top,bottom:stage.bottom},quick:{top:quick.top,bottom:quick.bottom},first:{top:first.top,bottom:first.bottom},
 showcaseDisplay:getComputedStyle(show).display,viewport:innerWidth,root:document.documentElement.scrollWidth,composerTop:composer.top,stageBottom:stage.bottom,style}});
 assert.equal(r.style,true,'clarity CSS loaded '+width);total++;
 assert.ok(r.root<=width+1,'no horizontal overflow '+width+' '+JSON.stringify(r));total++;
 if(width<=1440){
  assert.equal(r.showcaseDisplay,'none','fake chat must not displace actions '+width);total++;
  assert.ok(r.first.top<=r.stage.bottom-30,'first quick action must be visible without scrolling '+width+' '+JSON.stringify(r));total++;
  assert.ok(r.quick.top<=r.stage.bottom-30,'quick actions must not start outside stage '+width);total++;
  assert.ok(r.quick.bottom<=r.stage.bottom+2,'last quick action should be visible without scrolling '+width+' '+JSON.stringify(r));total++;
 }
 assert.ok(r.composerTop>=r.stageBottom-3,'composer must not overlap section '+width);total++;
 assert.deepEqual(errors,[],'browser errors '+width);total++;
 if(process.env.NEXUS_FIRST_SCREEN_SHOTS){fs.mkdirSync(process.env.NEXUS_FIRST_SCREEN_SHOTS,{recursive:true});await page.screenshot({path:path.join(process.env.NEXUS_FIRST_SCREEN_SHOTS,'first-'+width+'.png')})}
 console.log('FIRST_SCREEN_PASS',width,JSON.stringify(r));await page.close();
}console.log('NEXUS_FIRST_SCREEN_GATE_PASS assertions='+total);
}finally{await browser.close();await new Promise(r=>server.close(r))}})().catch(e=>{console.error('NEXUS_FIRST_SCREEN_GATE_FAIL',e.stack||e);server.close();process.exitCode=1});
