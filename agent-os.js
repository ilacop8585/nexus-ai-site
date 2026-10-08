let ctx=null;
let state={settings:{},execution:{default_mode:'auto',agent_effort:'smart',work_effort:'smart',code_effort:'smart',auto_escalate:true,response_style:'balanced'},projects:[],agents:[],skills:[]};
let runtimeContext={project_id:null,project_name:null,project_default_level:'free',agent_id:null,agent_name:null,routing_profile:'balanced',autonomy_level:'supervised',approval_policy:'risk_based',language:'it',timezone:'UTC',notifications_in_app:true,skills:[],prompt_prefix:''};
let defaultContext={...runtimeContext};
let conversationOverride=false;
let activeTab='defaults';
let editingProject=null,editingAgent=null,editingSkill=null;

const el=id=>document.getElementById(id);
const scalar=data=>Array.isArray(data)?data[0]:data;
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const user=()=>ctx?.getUser?.()||null;

function showNotice(text,error=false){
 const n=el('agentOsNotice');if(!n)return;
 n.textContent=text||'';n.classList.toggle('danger',!!error);
}
function updateBadge(){
 const b=el('agentOsBadge');
 if(b)b.textContent=(state.projects?.length||0)+'P · '+(state.agents?.length||0)+'A';
 if(el('agentOsProjectsKpi'))el('agentOsProjectsKpi').textContent=String(state.projects?.length||0);
 if(el('agentOsAgentsKpi'))el('agentOsAgentsKpi').textContent=String(state.agents?.length||0);
 if(el('agentOsSkillsKpi'))el('agentOsSkillsKpi').textContent=String(state.skills?.length||0);
}
function updateContextPill(){
 const parts=[runtimeContext.project_name,runtimeContext.agent_name].filter(Boolean);
 const label=parts.length?parts.join(' · '):'Default NEXUS';
 const pill=el('agentOsContextPill');if(pill)pill.textContent=label;
 const top=el('agentRuntimeTop');
 if(top){
   top.hidden=!parts.length;
   const span=top.querySelector('span');if(span)span.textContent=label;
   top.title='Agent OS runtime · '+runtimeContext.routing_profile+' · '+runtimeContext.autonomy_level;
 }
}
function optionRows(items,selected,emptyLabel){
 return '<option value="">'+esc(emptyLabel)+'</option>'+items.map(x=>'<option value="'+esc(x.id)+'" '+(String(selected||'')===String(x.id)?'selected':'')+'>'+esc(x.name)+'</option>').join('');
}
function setTab(tab){
 activeTab=tab;
 document.querySelectorAll('[data-agentos-tab]').forEach(b=>b.classList.toggle('active',b.dataset.agentosTab===tab));
 document.querySelectorAll('[data-agentos-pane]').forEach(p=>p.hidden=p.dataset.agentosPane!==tab);
}
async function rpc(name,args={}){
 const r=await ctx.client.rpc(name,args);
 if(r.error)throw r.error;
 return r.data;
}
async function load(){
 if(!user())return;
 showNotice('Caricamento Agent OS…');
 const [workspaceData,executionData]=await Promise.all([
   rpc('nexus_workspace_bootstrap'),
   rpc('nexus_execution_settings_get')
 ]);
 const data=scalar(workspaceData)||{};
 const execution=scalar(executionData)||{};
 state={settings:data.settings||{},execution:{...state.execution,...execution},projects:data.projects||[],agents:data.agents||[],skills:data.skills||[]};
 await refreshContext();
 render();
 showNotice('Agent OS sincronizzato.');
 window.dispatchEvent(new CustomEvent('nexus-agentos-settings',{detail:{notifications_in_app:state.settings?.notifications_in_app!==false,execution:{...state.execution}}}));
}
async function refreshContext(){
 if(!user())return runtimeContext;
 const data=scalar(await rpc('nexus_agent_os_context'))||{};
 defaultContext={
   project_id:data.project_id||null,
   project_name:data.project_name||null,
   project_default_level:data.project_default_level||'free',
   agent_id:data.agent_id||null,
   agent_name:data.agent_name||null,
   routing_profile:data.routing_profile||state.settings?.routing_profile||'balanced',
   autonomy_level:data.autonomy_level||state.settings?.autonomy_level||'supervised',
   approval_policy:data.approval_policy||state.settings?.approval_policy||'risk_based',
   language:data.language||state.settings?.language||'it',
   timezone:data.timezone||state.settings?.timezone||'UTC',
   notifications_in_app:data.notifications_in_app!==false,
   skills:Array.isArray(data.skills)?data.skills:[],
   prompt_prefix:String(data.prompt_prefix||'')
 };
 if(!conversationOverride)runtimeContext={...defaultContext};
 updateContextPill();
 return runtimeContext;
}
function renderDefaults(){
 const s=state.settings||{};
 el('agentDefaultProject').innerHTML=optionRows(state.projects,s.default_project_id,'No default project');
 el('agentDefaultAgent').innerHTML=optionRows(state.agents,s.default_agent_id,'No default agent');
 el('agentRoutingProfile').value=s.routing_profile||'local_first';
 el('agentAutonomyLevel').value=s.autonomy_level||'supervised';
 el('agentApprovalPolicy').value=s.approval_policy||'risk_based';
 el('agentTimezone').value=s.timezone||Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
 el('agentLanguage').value=s.language||((navigator.language||'it').split('-')[0]);
 el('agentNotifications').checked=s.notifications_in_app!==false;
 const x=state.execution||{};
 if(el('defaultWorkMode'))el('defaultWorkMode').value=x.default_mode||'auto';
 if(el('agentEffort'))el('agentEffort').value=x.agent_effort||'smart';
 if(el('workEffort'))el('workEffort').value=x.work_effort||'smart';
 if(el('codeEffort'))el('codeEffort').value=x.code_effort||'smart';
 if(el('autoEscalate'))el('autoEscalate').checked=x.auto_escalate!==false;
 if(el('responseStyle'))el('responseStyle').value=x.response_style||'balanced';
 const summary=el('agentRuntimeSummary');
 summary.textContent='Runtime: '+(runtimeContext.project_name||'nessun progetto')+' · '+(runtimeContext.agent_name||'NEXUS base')+' · '+runtimeContext.routing_profile+' · '+runtimeContext.autonomy_level+' · '+runtimeContext.skills.length+' skill attive'+(conversationOverride?' · contesto fissato dalla chat':'');
}
function renderProjects(){
 const box=el('agentProjectsList');box.innerHTML='';
 if(!state.projects.length)box.innerHTML='<div class="notice">Nessun Project. Creane uno per dare istruzioni persistenti a chat e task.</div>';
 state.projects.forEach(p=>{
   const row=document.createElement('button');row.type='button';row.className='agentos-row'+(editingProject?.id===p.id?' active':'');
   row.innerHTML='<strong>'+esc(p.name)+'</strong><span>'+esc(p.default_level)+' · '+new Date(p.updated_at).toLocaleString()+'</span><small>'+esc(p.description||'Nessuna descrizione')+'</small>';
   row.onclick=()=>{editingProject=p;fillProjectForm();renderProjects()};box.appendChild(row);
 });
}
function fillProjectForm(){
 const p=editingProject||{};
 el('projectName').value=p.name||'';
 el('projectDescription').value=p.description||'';
 el('projectInstructions').value=p.instructions||'';
 el('projectDefaultLevel').value=p.default_level||'free';
 el('projectArchive').hidden=!editingProject;
}
function renderAgents(){
 const box=el('agentAgentsList');box.innerHTML='';
 if(!state.agents.length)box.innerHTML='<div class="notice">Nessun Agent persistente. Creane uno con missione, routing e autonomia.</div>';
 state.agents.forEach(a=>{
   const p=state.projects.find(x=>x.id===a.project_id);
   const row=document.createElement('button');row.type='button';row.className='agentos-row'+(editingAgent?.id===a.id?' active':'');
   row.innerHTML='<strong>'+esc(a.name)+'</strong><span>'+esc(a.routing_profile)+' · '+esc(a.autonomy_level)+'</span><small>'+esc(p?.name||'Agent globale')+' · '+esc(a.description||'Nessuna descrizione')+'</small>';
   row.onclick=()=>{editingAgent=a;fillAgentForm();renderAgents()};box.appendChild(row);
 });
}
function fillAgentForm(){
 const a=editingAgent||{};
 el('agentName').value=a.name||'';
 el('agentDescription').value=a.description||'';
 el('agentMission').value=a.mission||'';
 el('agentProject').innerHTML=optionRows(state.projects,a.project_id,'Agent globale / nessun Project');
 el('agentRouting').value=a.routing_profile||'local_first';
 el('agentAutonomy').value=a.autonomy_level||'supervised';
 el('agentApproval').value=a.approval_policy||'risk_based';
 el('agentArchive').hidden=!editingAgent;
 renderAgentSkillChecks();
}
function renderSkills(){
 const box=el('agentSkillsList');box.innerHTML='';
 if(!state.skills.length)box.innerHTML='<div class="notice">Nessuna Skill personale. Una Skill è un workflow/istruzione riutilizzabile, non un semplice pulsante.</div>';
 state.skills.forEach(s=>{
   const row=document.createElement('button');row.type='button';row.className='agentos-row'+(editingSkill?.id===s.id?' active':'');
   row.innerHTML='<strong>'+esc(s.name)+'</strong><span>'+esc(s.slug)+' · v'+esc(s.version)+' · '+esc(s.scope)+'</span><small>'+(s.enabled?'ENABLED':'DISABLED')+' · '+esc(s.description||'Nessuna descrizione')+'</small>';
   row.onclick=()=>{editingSkill=s;fillSkillForm();renderSkills()};box.appendChild(row);
 });
}
function fillSkillForm(){
 const s=editingSkill||{};
 el('skillName').value=s.name||'';
 el('skillSlug').value=s.slug||'';
 el('skillVersion').value=s.version||'1.0.0';
 el('skillDescription').value=s.description||'';
 el('skillInstructions').value=s.instructions||'';
 el('skillScope').value=s.scope||'personal';
 el('skillEnabled').checked=s.enabled!==false;
 el('skillArchive').hidden=!editingSkill;
 renderSkillAssignments();
}
function renderAgentSkillChecks(){
 const box=el('agentSkillAssignments');box.innerHTML='';
 if(!state.skills.length){box.innerHTML='<span class="small">Crea prima una Skill.</span>';return}
 const selected=new Set(editingAgent?.skill_ids||[]);
 state.skills.forEach(s=>{
   const label=document.createElement('label');label.className='agentos-check';
   const input=document.createElement('input');input.type='checkbox';input.checked=selected.has(s.id);input.dataset.skillId=s.id;
   label.append(input,document.createTextNode(' '+s.name));box.appendChild(label);
 });
}
function renderSkillAssignments(){
 const pbox=el('skillProjectAssignments'),abox=el('skillAgentAssignments');pbox.innerHTML='';abox.innerHTML='';
 const psel=new Set(editingSkill?.project_ids||[]),asel=new Set(editingSkill?.agent_ids||[]);
 if(!state.projects.length)pbox.innerHTML='<span class="small">Nessun Project.</span>';
 state.projects.forEach(p=>{const l=document.createElement('label');l.className='agentos-check';const i=document.createElement('input');i.type='checkbox';i.checked=psel.has(p.id);i.dataset.projectId=p.id;l.append(i,document.createTextNode(' '+p.name));pbox.appendChild(l)});
 if(!state.agents.length)abox.innerHTML='<span class="small">Nessun Agent.</span>';
 state.agents.forEach(a=>{const l=document.createElement('label');l.className='agentos-check';const i=document.createElement('input');i.type='checkbox';i.checked=asel.has(a.id);i.dataset.agentId=a.id;l.append(i,document.createTextNode(' '+a.name));abox.appendChild(l)});
}
function render(){
 updateBadge();renderDefaults();renderProjects();fillProjectForm();renderAgents();fillAgentForm();renderSkills();fillSkillForm();
}
async function saveDefaults(){
 showNotice('Salvataggio impostazioni…');
 const args={
  p_default_project_id:el('agentDefaultProject').value||null,
  p_default_agent_id:el('agentDefaultAgent').value||null,
  p_routing_profile:el('agentRoutingProfile').value,
  p_autonomy_level:el('agentAutonomyLevel').value,
  p_approval_policy:el('agentApprovalPolicy').value,
  p_timezone:(el('agentTimezone').value||'UTC').trim(),
  p_language:(el('agentLanguage').value||'it').trim(),
  p_notifications_in_app:el('agentNotifications').checked
 };
 state.settings=scalar(await rpc('nexus_settings_save',args))||state.settings;
 const execArgs={
   p_default_mode:el('defaultWorkMode')?.value||'auto',
   p_agent_effort:el('agentEffort')?.value||'smart',
   p_work_effort:el('workEffort')?.value||'smart',
   p_code_effort:el('codeEffort')?.value||'smart',
   p_auto_escalate:el('autoEscalate')?.checked!==false,
   p_response_style:el('responseStyle')?.value||'balanced'
 };
 state.execution={...state.execution,...(scalar(await rpc('nexus_execution_settings_save',execArgs))||{})};
 await refreshContext();renderDefaults();
 window.dispatchEvent(new CustomEvent('nexus-agentos-settings',{detail:{notifications_in_app:state.settings?.notifications_in_app!==false,execution:{...state.execution}}}));
 showNotice('Impostazioni Agent OS salvate.');
}
async function saveProject(){
 const args={p_id:editingProject?.id||null,p_name:el('projectName').value.trim(),p_description:el('projectDescription').value,p_instructions:el('projectInstructions').value,p_default_level:el('projectDefaultLevel').value};
 const id=scalar(await rpc('nexus_project_save',args));editingProject={id};await load();editingProject=state.projects.find(x=>x.id===id)||null;render();showNotice('Project salvato.');
}
async function archiveProject(){
 if(!editingProject)return;
 await rpc('nexus_project_archive',{p_id:editingProject.id});editingProject=null;await load();showNotice('Project archiviato.');
}
async function saveAgent(){
 const args={p_id:editingAgent?.id||null,p_project_id:el('agentProject').value||null,p_name:el('agentName').value.trim(),p_description:el('agentDescription').value,p_mission:el('agentMission').value,p_routing_profile:el('agentRouting').value,p_autonomy_level:el('agentAutonomy').value,p_approval_policy:el('agentApproval').value};
 const id=scalar(await rpc('nexus_agent_save',args));
 const checked=[...el('agentSkillAssignments').querySelectorAll('input[data-skill-id]')].filter(i=>i.checked).map(i=>i.dataset.skillId);
 for(const s of state.skills)await rpc('nexus_agent_skill_set',{p_agent_id:id,p_skill_id:s.id,p_enabled:checked.includes(s.id)});
 editingAgent={id};await load();editingAgent=state.agents.find(x=>x.id===id)||null;render();showNotice('Agent salvato.');
}
async function archiveAgent(){
 if(!editingAgent)return;
 await rpc('nexus_agent_archive',{p_id:editingAgent.id});editingAgent=null;await load();showNotice('Agent archiviato.');
}
async function saveSkill(){
 const slug=(el('skillSlug').value.trim()||el('skillName').value.trim().toLowerCase().replace(/[^a-z0-9._-]+/g,'-').replace(/^-+|-+$/g,'')).slice(0,120);
 const args={p_id:editingSkill?.id||null,p_name:el('skillName').value.trim(),p_slug:slug,p_version:el('skillVersion').value.trim()||'1.0.0',p_description:el('skillDescription').value,p_instructions:el('skillInstructions').value,p_scope:el('skillScope').value,p_source_type:'inline',p_source_ref:null,p_enabled:el('skillEnabled').checked};
 const id=scalar(await rpc('nexus_skill_save',args));
 const pchecked=[...el('skillProjectAssignments').querySelectorAll('input[data-project-id]')].filter(i=>i.checked).map(i=>i.dataset.projectId);
 const achecked=[...el('skillAgentAssignments').querySelectorAll('input[data-agent-id]')].filter(i=>i.checked).map(i=>i.dataset.agentId);
 for(const p of state.projects)await rpc('nexus_project_skill_set',{p_project_id:p.id,p_skill_id:id,p_enabled:pchecked.includes(p.id)});
 for(const a of state.agents)await rpc('nexus_agent_skill_set',{p_agent_id:a.id,p_skill_id:id,p_enabled:achecked.includes(a.id)});
 editingSkill={id};await load();editingSkill=state.skills.find(x=>x.id===id)||null;render();showNotice('Skill salvata e assegnazioni aggiornate.');
}
async function archiveSkill(){
 if(!editingSkill)return;
 await rpc('nexus_skill_archive',{p_id:editingSkill.id});editingSkill=null;await load();showNotice('Skill archiviata.');
}
function bind(){
 el('agentOsBtn').onclick=open;
 el('closeAgentOs').onclick=close;
 el('agentOsModal').onclick=e=>{if(e.target.id==='agentOsModal')close()};
 document.querySelectorAll('[data-agentos-tab]').forEach(b=>b.onclick=()=>setTab(b.dataset.agentosTab));
 el('saveAgentDefaults').onclick=()=>saveDefaults().catch(e=>showNotice(e.message||String(e),true));
 el('newProject').onclick=()=>{editingProject=null;fillProjectForm();renderProjects()};
 el('saveProject').onclick=()=>saveProject().catch(e=>showNotice(e.message||String(e),true));
 el('projectArchive').onclick=()=>archiveProject().catch(e=>showNotice(e.message||String(e),true));
 el('newAgent').onclick=()=>{editingAgent=null;fillAgentForm();renderAgents()};
 el('saveAgent').onclick=()=>saveAgent().catch(e=>showNotice(e.message||String(e),true));
 el('agentArchive').onclick=()=>archiveAgent().catch(e=>showNotice(e.message||String(e),true));
 el('newSkill').onclick=()=>{editingSkill=null;fillSkillForm();renderSkills()};
 el('saveSkill').onclick=()=>saveSkill().catch(e=>showNotice(e.message||String(e),true));
 el('skillArchive').onclick=()=>archiveSkill().catch(e=>showNotice(e.message||String(e),true));
 el('agentOpenPlugins').onclick=()=>{close();ctx.openPlugins?.()};
}
export function init(options){ctx=options;bind()}
export async function applySession(){
 const b=el('agentOsBtn');if(!b)return;
 b.hidden=!user();
 if(user()){try{await load()}catch(e){console.warn('Agent OS unavailable',e);showNotice('Agent OS non disponibile: '+(e?.message||String(e)),true)}}
}
export function reset(){
 state={settings:{},execution:{default_mode:'auto',agent_effort:'smart',work_effort:'smart',code_effort:'smart',auto_escalate:true,response_style:'balanced'},projects:[],agents:[],skills:[]};runtimeContext={project_id:null,project_name:null,project_default_level:'free',agent_id:null,agent_name:null,routing_profile:'balanced',autonomy_level:'supervised',approval_policy:'risk_based',language:'it',timezone:'UTC',notifications_in_app:true,skills:[],prompt_prefix:''};defaultContext={...runtimeContext};conversationOverride=false;
 editingProject=editingAgent=editingSkill=null;const b=el('agentOsBtn');if(b)b.hidden=true;updateBadge();
}
export async function open(){
 if(!user())return;
 el('agentOsModal').classList.add('show');setTab(activeTab);await load();
}
export function close(){el('agentOsModal')?.classList.remove('show')}
export async function getContext(){if(user()&&!runtimeContext?.project_id&&!runtimeContext?.agent_id&&!runtimeContext?.prompt_prefix){try{await refreshContext()}catch{}}return runtimeContext}
export async function useConversationContext(projectId,agentId){
 if(!user())return runtimeContext;
 if(!projectId&&!agentId){conversationOverride=false;runtimeContext={...defaultContext};updateContextPill();renderDefaults();return runtimeContext}
 const data=scalar(await rpc('nexus_agent_os_context_for',{p_project_id:projectId||null,p_agent_id:agentId||null}))||{};
 runtimeContext={
   project_id:data.project_id||null,project_name:data.project_name||null,project_default_level:data.project_default_level||'free',
   agent_id:data.agent_id||null,agent_name:data.agent_name||null,
   routing_profile:data.routing_profile||defaultContext.routing_profile,
   autonomy_level:data.autonomy_level||defaultContext.autonomy_level,
   approval_policy:data.approval_policy||defaultContext.approval_policy,
   language:data.language||defaultContext.language,
   timezone:data.timezone||defaultContext.timezone,
   notifications_in_app:data.notifications_in_app!==false,
   skills:Array.isArray(data.skills)?data.skills:[],
   prompt_prefix:String(data.prompt_prefix||'')
 };
 conversationOverride=true;updateContextPill();renderDefaults();return runtimeContext;
}
export function clearConversationContext(){conversationOverride=false;runtimeContext={...defaultContext};updateContextPill();if(el('agentRuntimeSummary'))renderDefaults()}
export function decoratePrompt(text,context=runtimeContext){
 const request=String(text||'').slice(0,8000);
 const prefix=String(context?.prompt_prefix||'').trim();
 if(!prefix)return request;
 const marker='\nUSER REQUEST:\n';
 const budget=Math.max(0,11900-request.length-marker.length);
 return prefix.slice(0,budget)+marker+request;
}
export function notificationsEnabled(){return state.settings?.notifications_in_app!==false}
export function getExecutionSettings(){return {...state.execution}}
export async function bindJob(jobId,context=runtimeContext){
 if(!jobId||!user())return false;
 const r=await ctx.client.rpc('nexus_job_bind_context',{
   p_job_id:jobId,
   p_project_id:context?.project_id||null,
   p_agent_id:context?.agent_id||null,
   p_routing_profile:context?.routing_profile||null,
   p_approval_policy:context?.approval_policy||null
 });
 if(r.error){console.warn('Could not bind Agent OS context to job',r.error);return false}
 return !!scalar(r.data);
}
