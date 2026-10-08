let ctx=null;
let mode='auto';
let settings={
  default_mode:'auto',
  agent_effort:'smart',
  work_effort:'smart',
  code_effort:'smart',
  auto_escalate:true,
  response_style:'balanced'
};

const el=id=>document.getElementById(id);
const scalar=data=>Array.isArray(data)?data[0]:data;

function modeLabel(m){
  return ({auto:'Auto',chat:'Chat',agent:'Agent',work:'Work',code:'Code'})[m]||'Auto';
}
function modeHint(m=mode){
  if(m==='chat')return 'Fast chat · included · no task queue';
  if(m==='agent')return 'Agent task · tools/compute · credits';
  if(m==='work')return 'Work task · multi-step execution · credits';
  if(m==='code')return 'Code task · coding runtime · credits';
  return 'Auto · simple chat stays included; heavier work becomes a task';
}
function render(){
  document.querySelectorAll('[data-nexus-mode]').forEach(b=>{
    const active=b.dataset.nexusMode===mode;
    b.classList.toggle('active',active);
    b.setAttribute('aria-pressed',active?'true':'false');
  });
  const h=el('modeHintTop');if(h)h.textContent=modeHint();
  const composer=el('modeHintComposer');if(composer)composer.textContent=modeHint();
}
async function loadSettings(){
  if(!ctx?.getUser?.())return settings;
  const r=await ctx.client.rpc('nexus_execution_settings_get');
  if(!r.error){
    settings={...settings,...(scalar(r.data)||{})};
    mode=['auto','chat','agent','work','code'].includes(settings.default_mode)?settings.default_mode:'auto';
    render();
  }
  window.dispatchEvent(new CustomEvent('nexus-execution-settings',{detail:{...settings,mode}}));
  return settings;
}
function setMode(next,{userAction=true}={}){
  if(!['auto','chat','agent','work','code'].includes(next))next='auto';
  mode=next;render();
  if(userAction)sessionStorage.setItem('nexus_execution_mode',mode);
  window.dispatchEvent(new CustomEvent('nexus-mode-change',{detail:{mode,settings:{...settings}}}));
}
function wordCount(s){return String(s||'').trim().split(/\s+/).filter(Boolean).length}
function classify(text,files=[]){
  const q=String(text||'').trim();
  const lower=q.toLowerCase();
  if(files?.length)return {heavy:true,mode:'work',reason:'attachments'};
  const code=/\b(codice|code|debug|bug|repository|repo|commit|pull request|typescript|javascript|python|java|sql|html|css|api|endpoint|compila|build|deploy|refactor|funzione|function|class|classe)\b/i.test(q);
  const deep=/\b(analizza approfonditamente|ricerca approfondita|deep research|audit|benchmark|confronta dettagliatamente|report completo|strategia completa|piano completo|progetta|costruisci|sviluppa|crea (?:un|una) (?:sito|app|applicazione|programma|workflow)|automazione|seo completo|scansiona|scansione approfondita|multi[- ]step)\b/i.test(q);
  const multi=/\n\s*(?:[-*]|\d+[.)])\s+/.test(q)||/\bprima\b[\s\S]{0,300}\bpoi\b/i.test(q);
  const long=q.length>700||wordCount(q)>120;
  const explicitAgent=/\b(agent|agente|esegui|procedi autonomamente|porta a termine|fai tutto|one[- ]shot)\b/i.test(q);
  const heavy=code||deep||multi||long||explicitAgent;
  let suggested='agent';
  if(code)suggested='code';
  else if(deep||multi||long)suggested='work';
  return {heavy,mode:heavy?suggested:'chat',reason:code?'code':deep?'complex_work':multi?'multi_step':long?'long_request':explicitAgent?'agent_request':'simple_chat'};
}
function effortFor(m){
  if(m==='code')return settings.code_effort||'smart';
  if(m==='work')return settings.work_effort||'smart';
  return settings.agent_effort||'smart';
}
function resolve(text,files=[]){
  if(mode!=='auto')return {mode,heavy:mode!=='chat',level:mode==='chat'?'free':effortFor(mode),reason:'explicit_mode'};
  if(settings.auto_escalate===false)return {mode:'chat',heavy:false,level:'free',reason:'auto_escalation_disabled'};
  const c=classify(text,files);
  return {...c,level:c.mode==='chat'?'free':effortFor(c.mode)};
}
async function quote(m,level){
  if(!ctx?.getUser?.()||!['agent','work','code'].includes(m))return 0;
  if(ctx?.getAccess?.()?.unlimited)return 0;
  const r=await ctx.client.rpc('nexus_quote_text_task_credits',{p_mode:m,p_level:level});
  if(r.error)throw r.error;
  return Number(scalar(r.data)||0);
}
function decorateChat(text){
  const q=String(text||'');
  if(settings.response_style==='concise')return 'RESPONSE STYLE: concise and direct.\n\nUSER REQUEST:\n'+q;
  if(settings.response_style==='detailed')return 'RESPONSE STYLE: detailed but structured.\n\nUSER REQUEST:\n'+q;
  return q;
}
function reset(){
  settings={default_mode:'auto',agent_effort:'smart',work_effort:'smart',code_effort:'smart',auto_escalate:true,response_style:'balanced'};
  mode='auto';render();
}
function init(options){
  ctx=options;
  document.querySelectorAll('[data-nexus-mode]').forEach(b=>b.addEventListener('click',()=>setMode(b.dataset.nexusMode)));
  const remembered=sessionStorage.getItem('nexus_execution_mode');
  if(['auto','chat','agent','work','code'].includes(remembered))mode=remembered;
  render();
}
export {init,loadSettings,setMode,resolve,quote,decorateChat,reset,modeLabel,modeHint};
export function getMode(){return mode}
export function getSettings(){return {...settings}}
