let ctx=null;
let currentJobId=null;
let pollTimer=null;
let lastSignature='';

const el=id=>document.getElementById(id);
const scalar=data=>Array.isArray(data)?data[0]:data;
const activeStatuses=new Set(['queued','claimed','running','qa']);

function fmt(v){
  try{return new Date(v).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',second:'2-digit'})}catch{return ''}
}
function cleanSummary(v){
  return String(v||'').replace(/^\[TEXT_TASK\s+(AGENT|WORK|CODE)\]\s*/i,'').replace(/^\[CHAT_LOCAL\]\s*/i,'').trim();
}
function statusLabel(s){
  return ({queued:'Queued',claimed:'Worker assigned',running:'Running',qa:'Quality check',completed:'Completed',failed:'Failed',cancelled:'Cancelled'})[s]||String(s||'Task');
}
function stepState(key,status){
  if(status==='completed')return 'done';
  if(['failed','cancelled'].includes(status)){
    if(key==='understand')return 'done';
    if(key==='execute')return 'error';
    return 'pending';
  }
  if(status==='qa'){
    if(['understand','execute'].includes(key))return 'done';
    if(key==='quality')return 'active';
    return 'pending';
  }
  if(status==='running'){
    if(key==='understand')return 'done';
    if(key==='execute')return 'active';
    return 'pending';
  }
  if(['queued','claimed'].includes(status)){
    if(key==='understand')return 'active';
    return 'pending';
  }
  return 'pending';
}
function defaultPlan(job){
  const mode=job?.execution_metadata?.execution_mode||(/code/.test(job?.kind||'')?'code':'task');
  return [
    {key:'understand',title:'Understand request'},
    {key:'execute',title:mode==='code'?'Implement / analyse code':mode==='work'?'Execute multi-step work':mode==='agent'?'Execute agent task':'Process task'},
    {key:'quality',title:'Quality check'},
    {key:'deliver',title:'Deliver result'}
  ];
}
function derivePlan(payload){
  const event=(payload.events||[]).find(e=>e.event_type==='plan_created');
  const raw=event?.metadata?.steps;
  return Array.isArray(raw)&&raw.length?raw:defaultPlan(payload.job);
}
function renderPlan(payload){
  const box=el('taskRuntimePlan');box.innerHTML='';
  const plan=derivePlan(payload),status=payload.job?.status;
  plan.forEach((s,i)=>{
    const state=stepState(s.key,status);
    const row=document.createElement('div');row.className='runtime-step '+state;
    const dot=document.createElement('span');dot.className='runtime-step-dot';dot.textContent=state==='done'?'✓':state==='error'?'!':String(i+1);
    const copy=document.createElement('div');const strong=document.createElement('strong');strong.textContent=s.title||s.key;
    const small=document.createElement('small');small.textContent=state==='done'?'Done':state==='active'?'In progress':state==='error'?'Stopped':'Pending';
    copy.append(strong,small);row.append(dot,copy);box.appendChild(row);
  });
}
function renderEvents(payload){
  const box=el('taskRuntimeEvents');box.innerHTML='';
  const events=(payload.events||[]).filter(e=>e.event_type!=='plan_created');
  if(!events.length){box.innerHTML='<div class="runtime-empty">Waiting for the first runtime event…</div>';return}
  events.slice().reverse().forEach(e=>{
    const row=document.createElement('div');row.className='runtime-event';
    const head=document.createElement('div');head.className='runtime-event-head';
    const strong=document.createElement('strong');strong.textContent=e.title||e.event_type;
    const time=document.createElement('span');time.textContent=fmt(e.created_at);
    head.append(strong,time);row.appendChild(head);
    if(e.detail){const d=document.createElement('div');d.className='runtime-event-detail';d.textContent=e.detail;row.appendChild(d)}
    const tags=[];
    if(e.metadata?.worker_id)tags.push('worker '+e.metadata.worker_id);
    if(e.metadata?.error_code)tags.push(e.metadata.error_code);
    if(tags.length){const m=document.createElement('div');m.className='runtime-event-meta';m.textContent=tags.join(' · ');row.appendChild(m)}
    box.appendChild(row);
  });
}
function render(payload){
  const job=payload.job||{};
  el('taskRuntimeTitle').textContent=(job.execution_metadata?.execution_mode?String(job.execution_metadata.execution_mode).toUpperCase():'NEXUS')+' TASK · '+String(job.id||'').slice(0,8);
  const badge=el('taskRuntimeStatus');badge.textContent=statusLabel(job.status);badge.className='runtime-status '+String(job.status||'');
  el('taskRuntimeRequest').textContent=cleanSummary(job.input_summary)||'NEXUS task';
  const cost=Number(job.charged_credits||job.estimated_credits||0);
  el('taskRuntimeMeta').textContent=[
    job.level?String(job.level).toUpperCase():null,
    job.worker_id?'Worker '+job.worker_id:null,
    cost?cost+' credits':null
  ].filter(Boolean).join(' · ');
  renderPlan(payload);renderEvents(payload);
  const result=el('taskRuntimeResult');
  if(job.status==='completed'&&job.output_summary){
    result.hidden=false;result.textContent=job.output_summary;
  }else if(job.status==='failed'){
    result.hidden=false;result.textContent='Task failed'+(job.error_code?': '+job.error_code:'');
  }else result.hidden=true;
  const sig=JSON.stringify([job.status,job.output_summary,(payload.events||[]).map(e=>e.id)]);
  lastSignature=sig;
}
async function load(jobId=currentJobId){
  if(!ctx?.getUser?.()||!jobId)return null;
  const r=await ctx.client.rpc('nexus_task_timeline',{p_job_id:jobId});
  if(r.error)throw r.error;
  const payload=scalar(r.data)||{};
  render(payload);
  const status=payload.job?.status;
  if(activeStatuses.has(status))startPolling();else stopPolling();
  return payload;
}
function startPolling(){
  if(pollTimer)return;
  pollTimer=setInterval(()=>load().catch(e=>console.warn('Task runtime poll failed',e)),1800);
}
function stopPolling(){clearInterval(pollTimer);pollTimer=null}
async function open(jobId){
  if(jobId)currentJobId=String(jobId);
  if(!currentJobId||!ctx?.getUser?.())return;
  el('taskRuntimePanel').classList.add('open');document.body.classList.add('task-runtime-open');
  el('taskRuntimeRequest').textContent='Loading task…';
  try{await load()}catch(e){el('taskRuntimeRequest').textContent='Task runtime unavailable: '+String(e?.message||e)}
}
function close(){
  el('taskRuntimePanel')?.classList.remove('open');document.body.classList.remove('task-runtime-open');stopPolling();
}
async function watchJob(jobId,{openPanel=true}={}){
  if(!jobId)return;
  currentJobId=String(jobId);
  if(openPanel)await open(currentJobId);else startPolling();
}
function reset(){currentJobId=null;lastSignature='';close()}
function init(options){
  ctx=options;
  el('closeTaskRuntime').onclick=close;
  el('refreshTaskRuntime').onclick=()=>load().catch(e=>console.warn(e));
}
export {init,open,close,watchJob,reset};
