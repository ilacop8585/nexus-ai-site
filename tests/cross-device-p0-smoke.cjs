// P0 responsive acceptance for Android portrait, iPhone, Fold, tablet and desktop.
// Isolated local staging, no login, no remote role/credit mutations.
'use strict';
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const puppeteer=require(process.env.NEXUS_PUPPETEER_PATH||'puppeteer');
const root=path.resolve(__dirname,'..');
const mime={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{const part=(req.url||'/').split('?')[0];const file=path.resolve(root,'.'+(part==='/'?'/index.html':part));
 if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return}
 fs.readFile(file,(err,body)=>{if(err){res.writeHead(404).end();return}res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});res.end(body)});
});
(async()=>{await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
const chrome=await puppeteer.launch({headless:true,executablePath:process.env.NEXUS_CHROME_BIN||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',args:['--no-sandbox']});
let checks=0;
try{
 for(const [label,width,height] of [['iphone-se',375,667],['small-android',320,640],['android',390,844],['iphone-pro',402,874],['fold-closed',344,760],['fold-open',768,820],['tablet',820,1180],['ipad-landscape',1024,768],['desktop',1440,900]]){
  const page=await chrome.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.setViewport({width,height,isMobile:width<=820,hasTouch:width<=820});
  await page.evaluateOnNewDocument(()=>{try{localStorage.clear()}catch{}});
  await page.goto('http://127.0.0.1:'+server.address().port+'/',{waitUntil:'networkidle2',timeout:25000});
  const info=await page.evaluate(()=>{
    const doc=document.documentElement;
    const styles=[...document.styleSheets].filter(x=>x.href).map(x=>x.href);
    const header=document.querySelector('.top').getBoundingClientRect();
    const compose=document.querySelector('.composer-wrap').getBoundingClientRect();
    return{scroll:doc.scrollWidth,viewport:innerWidth,headerTop:header.top,headerBottom:header.bottom,composeBottom:compose.bottom,
      css:styles.some(x=>x.includes('nexus-cross-device-p0.css')),script:!!document.querySelector('[data-nexus-mobile-close]'),buttons:document.querySelectorAll('#intro .quick button').length};
  });
  assert.ok(info.css&&info.script,'assets loaded '+label);checks++;
  assert.ok(info.scroll<=width+1,'no page overflow '+label+' '+JSON.stringify(info));checks++;
  assert.equal(info.buttons,4,'original shortcuts preserved '+label);checks++;
  assert.ok(info.headerBottom<height-85,'header must leave usable room '+label+' '+JSON.stringify(info));checks++;
  assert.deepEqual(errors,[],'no client errors '+label);checks++;
  for(const modalId of ['adminModal','jobsModal','agentOsModal','privateModal','socialModal']){
    await page.evaluate(id=>{
      document.querySelectorAll('.modal.show').forEach(x=>x.classList.remove('show'));
      document.getElementById(id).classList.add('show');
    },modalId);
    const box=await page.evaluate(id=>{
      const modal=document.getElementById(id),card=modal.querySelector('.modal-card');
      const a=card.getBoundingClientRect(),b=modal.getBoundingClientRect();
      const close=card.querySelector('[data-nexus-mobile-close]');
      return{card:{left:a.left,right:a.right,top:a.top,bottom:a.bottom,width:a.width,height:a.height,scrollHeight:card.scrollHeight,clientHeight:card.clientHeight},
        modal:{top:b.top,bottom:b.bottom},close:close?{left:close.getBoundingClientRect().left,right:close.getBoundingClientRect().right,height:close.getBoundingClientRect().height,visible:getComputedStyle(close.parentElement).display!=='none'}:null};
    },modalId);
    assert.ok(box.card.left>=-2&&box.card.right<=width+2,'modal horizontal overflow '+label+' '+modalId+' '+JSON.stringify(box));checks++;
    assert.ok(box.card.top>=-2&&box.card.bottom<=height+2,'modal vertical clipping '+label+' '+modalId+' '+JSON.stringify(box));checks++;
    if(width<=820){
      assert.ok(box.close?.visible&&box.close.height>=35,'mobile close accessible '+label+' '+modalId);checks++;
      if(modalId==='adminModal'){
        const input=await page.evaluate(()=>({font:parseFloat(getComputedStyle(document.getElementById('adminUserSearch')).fontSize),width:document.getElementById('adminUserSearch').getBoundingClientRect().width}));
        assert.ok(input.font>=16&&input.width>100,'iOS input zoom avoided '+label);checks++;
      }
      if(modalId==='jobsModal'||modalId==='adminModal'){
        await page.click('#'+modalId+' [data-nexus-mobile-close]');
        const closed=await page.evaluate(id=>!document.getElementById(id).classList.contains('show'),modalId);
        assert.equal(closed,true,'mobile close button invokes existing handler '+label+' '+modalId);checks++;
      }
    }
  }
  await page.evaluate(()=>document.querySelectorAll('.modal.show').forEach(x=>x.classList.remove('show')));
  if(width<=820){
    await page.evaluate(()=>{document.getElementById('intro').style.display='none';document.getElementById('messages').classList.add('has')});
    await page.setViewport({width,height:Math.min(520,height),isMobile:true,hasTouch:true});
    const keyboard=await page.evaluate(()=>{const e=document.getElementById('prompt').getBoundingClientRect(),c=document.querySelector('.composer-wrap').getBoundingClientRect();return{height:innerHeight,promptTop:e.top,promptBottom:e.bottom,composeTop:c.top,composeBottom:c.bottom}});
    assert.ok(keyboard.composeBottom<=keyboard.height+3,'composer clipped on reduced viewport '+label+' '+JSON.stringify(keyboard));checks++;
  }
  if(process.env.NEXUS_RESPONSIVE_SHOTS){
    const dir=process.env.NEXUS_RESPONSIVE_SHOTS;fs.mkdirSync(dir,{recursive:true});
    await page.screenshot({path:path.join(dir,'nexus-'+label+'.png')});
  }
  console.log('NEXUS_DEVICE_PASS '+label+' checks='+checks+' '+JSON.stringify(info));
  await page.close();
 }
 const file=fs.readFileSync(path.resolve(root,'task-runtime.js'),'utf8');
 assert.ok(file.includes('taskFailureExplanation')&&file.includes('CLIENT_WORKER_ERROR'),'failed runtime explanation wired');checks++;
 const index=fs.readFileSync(path.resolve(root,'index.html'),'utf8');
 assert.ok(index.includes('nexus-job-failure')&&index.includes('nexus-job-technical'),'activities present technical diagnostic disclosure');checks++;
 console.log('NEXUS_CROSS_DEVICE_PASS checks='+checks);
}finally{await chrome.close();await new Promise(ok=>server.close(ok))}})().catch(e=>{console.error('NEXUS_CROSS_DEVICE_FAIL',e.stack||e);server.close();process.exitCode=1});
