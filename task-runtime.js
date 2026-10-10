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
function taskFailureExplanation(code){
  return ({
    CLIENT_WORKER_ERROR:'Il worker non ha completato l’attività. Il problema riguarda l’esecuzione, non la chat. Controlla il servizio worker prima di ritentare.',
    QA_GATE_FAILED:'Il risultato non ha superato il controllo di qualità: questa attività non è stata consegnata.',
    CHAT_LOCAL_KIND_NOT_CLAIMED:'Questa attività non è stata presa in carico dal worker locale.',
  })[String(code||'')]||'Attività non completata. Consulta il dettaglio tecnico e lo stato del worker.';
}
function statusLabel(s){
  return ({queued:'Queued',claimed:'Worker assigned',running:'Running',qa:'Quality check',completed:'Completed',failed:'Failed',cancelled:'Cancelled'})[s]||String(s||'Task');
}
function stepState(key,status){
  const active=['claimed','running'].includes(status);
  if(key==='created')return 'done';
  if(key==='execute'){
    if(status==='completed'||status==='qa')return 'done';
    if(['failed','cancelled'].includes(status))return 'error';
    return active?'active':'pending';
  }
  if(key==='quality')return status==='qa'?'active':status==='completed'?'done':'pending';
  if(key==='deliver')return status==='completed'?'done':'pending';
  return 'pending';
}
// Show only real job phases. Do not claim that an agent performed a QA stage
// or multi-step plan unless the event stream confirms it actually happened.
function derivePlan(payload){
  const job=payload.job||{};
  const events=payload.events||[];
  const qaOccurred=job.status==='qa'||events.some(e=>e.event_type==='task_qa');
  const stages=[
    {key:'created',title:'Task accepted'},
    {key:'execute',title:'Worker execution'}
  ];
  if(qaOccurred)stages.push({key:'quality',title:'Quality check'});
  stages.push({key:'deliver',title:'Result delivered'});
  return stages;
}
function renderPlan(payload){
  const box=el('taskRuntimePlan');box.innerHTML='';
  const plan=derivePlan(payload),status=payload.job?.status;
  plan.forEach((s,i)=>{
    const state=stepState(s.key,status);
    const row=document.createElement('div');row.className='runtime-step '+state;
    const dot=document.createElement('span');dot.className='runtime-step-dot';dot.textContent=state==='done'?'✓':state==='error'?'!':String(i+1);
    const copy=document.createElement('div');const strong=document.createElement('strong');strong.textContent=s.title||s.key;
    const small=document.createElement('small');small.textContent=state==='done'?'Confirmed':state==='active'?'Running':state==='error'?'Stopped':'Pending';
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
  const charged=Number(job.charged_credits??0);
  const billing=job.status==='failed'||job.status==='cancelled'
    ? (charged===0?'0 credits retained':'Credit reconciliation pending')
    : (charged===0?'0 credits charged':charged+' credits '+(job.status==='completed'?'used':'reserved'));
  el('taskRuntimeMeta').textContent=[
    job.level?String(job.level).toUpperCase():null,
    job.worker_id?'Worker '+job.worker_id:null,
    billing
  ].filter(Boolean).join(' · ');
  renderPlan(payload);renderEvents(payload);
  const result=el('taskRuntimeResult');
  if(job.status==='completed'&&job.output_summary){
    result.hidden=false;result.textContent=job.output_summary;
  }else if(job.status==='failed'||job.status==='cancelled'){
    result.hidden=false;result.replaceChildren();
    const message=document.createElement('div');
    message.textContent=job.status==='cancelled'?'Attività annullata.':taskFailureExplanation(job.error_code);
    result.appendChild(message);
    if(job.error_code){
      const detail=document.createElement('details');detail.className='nexus-job-technical';
      const summary=document.createElement('summary');summary.textContent='Codice tecnico';
      const code=document.createElement('code');code.textContent=String(job.error_code);
      detail.append(summary,code);result.appendChild(detail);
    }
  }else result.hidden=true;
  const sig=JSON.stringify([job.status,job.output_summary,(payload.events||[]).map(e=>e.id)]);
  lastSignature=sig;
}
async function load(jobId=currentJobId){
  if(!ctx?.getUser?.()||!jobId)return null;
  const r=await ctx.client.rpc('nexus_task_timeline',{p_job_id:jobId});
  if(r.error)throw r.error;
  const payload=scalar(r.data)||{};
  if(String(jobId)!==String(currentJobId))return null;
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
