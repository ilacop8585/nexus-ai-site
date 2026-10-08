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
  if(m==='agent')return 'Agent task · AI worker · credits';
  if(m==='work')return 'Work task · analysis worker · credits';
  if(m==='code')return 'Code task · coding assistant · credits';
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
    const persisted=sessionStorage.getItem('nexus_execution_mode');
    mode=['auto','chat','agent','work','code'].includes(persisted)?persisted:(['auto','chat','agent','work','code'].includes(settings.default_mode)?settings.default_mode:'auto');
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
  if(files?.length)return {heavy:true,mode:'work',reason:'attachments'};
  // Mentioning a programming language, API, bug or repository is not enough
  // to charge for a task. Questions and explanations remain included chat.
  const ask=/^(?:ciao|salve|buongiorno|come|cosa|cos'è|cos e|perché|perche|quando|dove|chi|quanto|quale|spiegami|dimmi|puoi spiegarmi|mi spieghi|what|how|why|when|where|who|explain|tell me|is it|can you explain|help me understand)\b/i.test(q);
  const codeAction=/\b(?:scrivi|crea|costruisci|implementa|modifica|correggi|ripara|esegui|compila|deploya|debugga|refattorizza|sviluppa|genera|build|implement|fix|modify|write|create|develop|deploy|refactor|run|execute)\b[\s\S]{0,180}\b(?:codice|script|funzione|api|app|sito|website|programma|repository|repo|bug|test|python|javascript|typescript|sql|html|css|software|code|function|file)\b|\b(?:nel|sul|in|on|my)\s+(?:repo|repository|codice|code|app|sito|website)\b[\s\S]{0,120}\b(?:correggi|modifica|fix|change|patch|debug|ripara)\b/i.test(q);
  const extendedAction=/\b(?:analizza approfonditamente|ricerca approfondita|deep research|audit completo|confronta dettagliatamente|report completo|strategia completa|piano completo|scansione approfondita|esamina tutti i file|esegui una ricerca|crea un piano di lavoro|investiga e correggi|build and deploy|research and implement)\b/i.test(q);
  const multiAction=/\b(?:prima|first)\b[\s\S]{0,300}\b(?:poi|then)\b/i.test(q)&&/\b(?:esegui|crea|modifica|analizza|correggi|deploy|run|build|fix|implement|test)\b/i.test(q);
  const delegated=/\b(?:procedi autonomamente|porta a termine|esegui tutte le operazioni|one[- ]shot|implementa e verifica)\b/i.test(q);
  if(codeAction&&!ask)return {heavy:true,mode:'code',reason:'explicit_code_work'};
  if((extendedAction||multiAction||delegated)&&!ask)return {heavy:true,mode:'work',reason:'explicit_work'};
  return {heavy:false,mode:'chat',reason:'ordinary_conversation'};
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
  if(r.error)throw new Error('quote_unavailable');
  const estimate=Number(scalar(r.data));
  if(!Number.isSafeInteger(estimate)||estimate<=0)throw new Error('quote_unavailable');
  return estimate;
}
function decorateChat(text){
  const q=String(text||'');
  if(settings.response_style==='concise')return 'RESPONSE STYLE: concise and direct.\n\nUSER REQUEST:\n'+q;
  if(settings.response_style==='detailed')return 'RESPONSE STYLE: detailed but structured.\n\nUSER REQUEST:\n'+q;
  return q;
}
function reset(){
  settings={default_mode:'auto',agent_effort:'smart',work_effort:'smart',code_effort:'smart',auto_escalate:true,response_style:'balanced'};
  mode='auto';try{sessionStorage.removeItem('nexus_execution_mode')}catch{}render();
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
