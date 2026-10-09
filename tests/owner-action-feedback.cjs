// Unit-level browser test against actual inline admin UI code; fake local RPC only.
// Does NOT authenticate, contact Neon/Supabase for grants, or mutate production.
'use strict';
const fs=require('node:fs'), path=require('node:path'), http=require('node:http');
const assert=require('node:assert/strict');
const puppeteer=require(process.env.NEXUS_PUPPETEER_PATH||'puppeteer');
const root=path.resolve(__dirname,'..'), index=fs.readFileSync(path.join(root,'index.html'),'utf8');
const a=index.indexOf('// Single-source-of-truth: an Owner action is confirmed only after a fresh'),b=index.indexOf('function adminNextBetaStates(',a);
assert.ok(a>0 && b>a,'Admin action functions available');
const source=index.slice(a,b);
const mime={'.html':'text/html;charset=utf-8','.js':'text/javascript;charset=utf-8','.css':'text/css;charset=utf-8','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{const p=(req.url||'/').split('?')[0],loc=path.resolve(root,'.'+(p==='/'?'/index.html':p));
 if(!loc.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 fs.readFile(loc,(err,body)=>{if(err){res.writeHead(404).end();return;}res.writeHead(200,{'Content-Type':mime[path.extname(loc)]||'application/octet-stream'});res.end(body)});
});
(async()=>{
 await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
 const chrome=process.env.NEXUS_CHROME_BIN||'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
 const browser=await puppeteer.launch({headless:true,executablePath:chrome,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();const pageErrors=[];
  page.on('pageerror',e=>pageErrors.push(e.message));
  await page.goto('http://127.0.0.1:'+server.address().port+'/',{waitUntil:'networkidle2',timeout:27000});
  const info=await page.evaluate(async code=>{
    const state={
      users:[{user_id:'qa-1',email:'example@invalid.test',display_name:'Persona QA',staff_role:'user',credits:10,unlimited:false,email_verified:true}],
      calls:[],mutations:0,skipNextMutation:false
    };
    const fakeClient={rpc:async(name,args)=>{
      state.calls.push({name,args});
      if(name==='nexus_admin_list_users')return{data:state.users.map(x=>({...x}))};
      // Simulate latency so double-click protection can be exercised.
      await new Promise(r=>setTimeout(r,85));
      if(!state.skipNextMutation){
        state.mutations++;
        let u=state.users[0];
        if(name==='nexus_admin_set_beta'){u.staff_role=args.p_enabled?'beta_tester':'user';u.unlimited=!!args.p_enabled;}
        if(name==='nexus_admin_set_unlimited')u.unlimited=args.p_unlimited;
        if(name==='nexus_admin_grant_credits')u.credits+=args.p_amount;
      }else state.skipNextMutation=false;
      return{data:true};
    }};
    const unit=new Function('client','filterAdminUsers',code+'\nreturn {adminUserRow,renderAdminUserData,runAdminUserAction,fetchAdminUserData};')(fakeClient,()=>{});
    const notice=document.getElementById('adminActionFeedback');
    unit.renderAdminUserData(state.users);
    const clickAction=label=>{const button=[...document.querySelectorAll('#adminUsers button')].find(b=>b.textContent===label);if(!button)throw Error('missing '+label);button.click();};
    const wait=async()=>{
      const deadline=Date.now()+3000;
      while(Date.now()<deadline){
       if(![...document.querySelectorAll('#adminUsers button')].some(x=>x.disabled&&x.textContent==='Assegna crediti')&&['success','warning','error'].includes(notice.dataset.kind))return;
       await new Promise(r=>setTimeout(r,30));
      }
      throw Error('No action completion: '+notice.textContent);
    };
    clickAction('Assegna Beta Tester');clickAction('Assegna Beta Tester');await wait();
    const beta={role:state.users[0].staff_role,unlimited:state.users[0].unlimited,notice:notice.textContent,invocations:state.calls.filter(x=>x.name==='nexus_admin_set_beta').length};
    // Beta automatically enabled unlimited; exercise separate toggle both ways.
    clickAction('Disattiva illimitato');await wait();
    if(state.users[0].unlimited!==false)throw Error('Separate unlimited off toggle failed');
    clickAction('Attiva illimitato');await wait();
    const unlimited={value:state.users[0].unlimited,notice:notice.textContent};
    clickAction('Assegna crediti');await wait();
    const credits={value:state.users[0].credits,notice:notice.textContent,invocations:state.calls.filter(x=>x.name==='nexus_admin_grant_credits').length};
    state.skipNextMutation=true;
    clickAction('Disattiva illimitato');await wait();
    const mismatch={value:state.users[0].unlimited,kind:notice.dataset.kind,notice:notice.textContent};
    return{beta,unlimited,credits,mismatch,readBacks:state.calls.filter(x=>x.name==='nexus_admin_list_users').length};
  },source);
  assert.equal(info.beta.role,'beta_tester');
  assert.equal(info.beta.invocations,1,'double click blocked');
  assert.equal(info.beta.unlimited,true);
  assert.ok(info.beta.notice.includes('confermat'));
  assert.equal(info.unlimited.value,true);
  assert.ok(info.unlimited.notice.includes('confermato'));
  assert.equal(info.credits.value,110);
  assert.equal(info.credits.invocations,1);
  assert.ok(info.credits.notice.includes('110'));
  assert.equal(info.mismatch.value,true,'simulated stale read unchanged');
  assert.equal(info.mismatch.kind,'warning','must not falsely claim completed');
  assert.ok(info.readBacks>=4,'each admin action requires server state readback');
  assert.deepEqual(pageErrors,[],'no browser errors');
  console.log('NEXUS_OWNER_ACTION_GATE_PASS',JSON.stringify(info));
  await page.close();
 }finally{await browser.close();await new Promise(ok=>server.close(ok))}
})().catch(e=>{console.error('NEXUS_OWNER_ACTION_GATE_FAIL',e.stack||e);server.close();process.exitCode=1});
