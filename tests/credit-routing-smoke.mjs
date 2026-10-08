import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const read=path=>readFileSync(root+path,'utf8');
const strip=source=>source
  .replace(/\bexport\s+(?=(?:async\s+)?function|const|let|var|class)/g,'')
  .replace(/export\s*\{[^}]+\};?/g,'');
const tests=[];
async function check(name,fn){
  try{await fn();tests.push({name,pass:true});console.log('PASS '+name)}
  catch(e){tests.push({name,pass:false});console.error('FAIL '+name+' '+e.message)}
}

const doc={querySelectorAll:()=>[],getElementById:()=>null};
const store={getItem:()=>null,setItem:()=>{},removeItem:()=>{}};
const browserWindow={dispatchEvent:()=>{}};
const CustomEventMock=function(){};
const launch=read('launch-os.js');
const task=read('task-runtime.js');
const agent=read('agent-os.js');
const html=read('index.html');
const exposedLaunch=new Function('document','sessionStorage','window','CustomEvent',strip(launch)+'\nreturn{classify,quote,init};')(doc,store,browserWindow,CustomEventMock);
let quoteResult={data:10,error:null};
let userAccess={unlimited:false};
exposedLaunch.init({
  getUser:()=>({id:'test-user'}),
  getAccess:()=>userAccess,
  client:{rpc:async()=>quoteResult}
});

await check('Basic questions mentioning code remain free Chat',()=>{
  for(const q of ["Cos'è un bug di Python?","Spiegami come funziona una API.","Come posso imparare a scrivere codice?","Why does this API return an error?"]){
    assert.equal(exposedLaunch.classify(q).mode,'chat',q);
  }
});
await check('Explicit coding operations become Code tasks',()=>{
  for(const q of ['Scrivi una funzione Python che analizza CSV.','Correggi il bug nel mio repository JavaScript.','Crea una app Android e compila il codice.']){
    assert.equal(exposedLaunch.classify(q).mode,'code',q);
  }
});
await check('Explicit substantial work becomes Work',()=>{
  for(const q of ['Analizza approfonditamente la strategia SEO.','Procedi autonomamente con la migrazione del database.']){
    assert.equal(exposedLaunch.classify(q).mode,'work',q);
  }
});
await check('Attachment classifier requires file task',()=>{
  assert.equal(exposedLaunch.classify('ciao',[{name:'demo.txt'}]).mode,'work');
});
await check('A long conversational request is not charged on length alone',()=>{
  assert.equal(exposedLaunch.classify('Ciao, '+('spiegami questo. '.repeat(120))).mode,'chat');
});
await check('Valid quote is positive integer',async()=>{
  quoteResult={data:10,error:null};assert.equal(await exposedLaunch.quote('agent','smart'),10);
});
await check('Bad, zero, missing and failing quotes abort safely',async()=>{
  for(const result of [{data:null,error:null},{data:0,error:null},{data:'NaN',error:null},{data:null,error:{message:'down'}}]){
    quoteResult=result;
    await assert.rejects(()=>exposedLaunch.quote('agent','smart'),/quote_unavailable/);
  }
});
await check('Unlimited mode exposes zero while server validates entitlement',async()=>{
  userAccess={unlimited:true};assert.equal(await exposedLaunch.quote('agent','smart'),0);
  userAccess={unlimited:false};
});
await check('No-Project default context uses one RPC for repeated chat turns',async()=>{
  const contextSource=strip(agent).replace('function init(options){ctx=options;bind()}','function init(options){ctx=options}');
  const api=new Function('document','window','CustomEvent','navigator','Intl',contextSource+'\nreturn{init,getContext};')(doc,browserWindow,CustomEventMock,{language:'it-IT'},Intl);
  let calls=0;
  api.init({getUser:()=>({id:'test-user'}),client:{rpc:async()=>{calls++;return{data:{project_id:null,agent_id:null,prompt_prefix:'',language:'it'},error:null}}}});
  await api.getContext();await api.getContext();
  assert.equal(calls,1);
});
await check('Task Runtime does not invent QA events',()=>{
  const api=new Function('document',strip(task)+'\nreturn{derivePlan};')(doc);
  const noQa=api.derivePlan({job:{status:'completed'},events:[{event_type:'task_completed'}]}).map(x=>x.key);
  const yesQa=api.derivePlan({job:{status:'completed'},events:[{event_type:'task_qa'},{event_type:'task_completed'}]}).map(x=>x.key);
  assert.deepEqual(noQa,['created','execute','deliver']);
  assert.deepEqual(yesQa,['created','execute','quality','deliver']);
});
await check('All public JavaScript modules remain parseable',()=>{
  for(const code of [strip(launch),strip(task),strip(agent),strip(read('project-workspace.js'))])new Function(code);
  const mainScript=html.match(/<script type="module">([\s\S]*?)<\/script>/)?.[1]||'';
  assert.ok(mainScript.length>1000);
  new Function(mainScript.replace(/^\s*import.*$/gm,''));
});
await check('Only guarded paid task endpoints are called by the website',()=>{
  assert.ok(html.includes("client.rpc('nexus_create_text_task_checked'"));
  assert.ok(html.includes("client.rpc('nexus_create_job_checked'"));
  assert.ok(!html.includes("client.rpc('nexus_create_text_task',"));
  assert.ok(!html.includes("client.rpc('nexus_create_job',"));
});
await check('File estimate and approval precede any file upload',()=>{
  const handler=html.slice(html.indexOf("document.getElementById('sendBtn').onclick=async()=>{"));
  const quoteAt=handler.indexOf("const estimate=await client.rpc('nexus_quote_job_credits'");
  const approveAt=handler.indexOf("reason:'attachments',allowBasicChat:false");
  const uploadAt=handler.indexOf('uploaded.push(await uploadOne');
  assert.ok(quoteAt>=0&&approveAt>quoteAt&&uploadAt>approveAt);
});
await check('Database has server-enforced consent and revokes older APIs',()=>{
  for(const path of ['sql/20261008_text_task_credit_guard.sql','sql/20261008_file_job_credit_guard.sql']){
    const source=read(path);
    assert.match(source,/p_approved_credits IS DISTINCT FROM v_quote/);
    assert.match(source,/nexus_is_internal_qa/);
  }
  assert.match(read('sql/20261008_disable_legacy_paid_task_rpc.sql'),/REVOKE EXECUTE/);
  assert.match(read('sql/20261008_disable_legacy_file_job_rpc.sql'),/FROM PUBLIC/);
});
const failures=tests.filter(t=>!t.pass);
console.log('\nNEXUS BETA SAFETY '+(failures.length?'FAIL':'PASS')+' '+(tests.length-failures.length)+'/'+tests.length);
if(failures.length)process.exitCode=1;
