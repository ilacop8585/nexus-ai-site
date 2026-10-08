let ctx=null;
let projects=[];
let workspace=null;
let currentProjectId=null;
let activeTab='overview';

const el=id=>document.getElementById(id);
const scalar=data=>Array.isArray(data)?data[0]:data;
const fmt=v=>{try{return new Date(v).toLocaleString()}catch{return ''}};
const bytes=n=>{const x=Number(n||0);if(x<1024)return x+' B';if(x<1024*1024)return (x/1024).toFixed(1)+' KB';if(x<1024*1024*1024)return (x/1024/1024).toFixed(1)+' MB';return (x/1024/1024/1024).toFixed(2)+' GB'};

async function rpc(name,args={}){
 const r=await ctx.client.rpc(name,args);
 if(r.error)throw r.error;
 return r.data;
}
function showSurface(){el('projectWorkspace').classList.add('open');document.body.classList.add('project-workspace-open')}
function close(){el('projectWorkspace')?.classList.remove('open');document.body.classList.remove('project-workspace-open')}
function setNotice(text,error=false){const n=el('projectWorkspaceNotice');n.textContent=text||'';n.classList.toggle('danger',!!error)}
function setTab(tab){
 activeTab=tab;
 document.querySelectorAll('[data-project-tab]').forEach(b=>b.classList.toggle('active',b.dataset.projectTab===tab));
 document.querySelectorAll('[data-project-pane]').forEach(p=>p.hidden=p.dataset.projectPane!==tab);
 renderActivePane();
}
function countCard(label,value){
 const d=document.createElement('div');d.className='project-kpi';
 const s=document.createElement('strong');s.textContent=String(value||0);
 const l=document.createElement('span');l.textContent=label;d.append(s,l);return d;
}
function empty(box,text){box.innerHTML='';const d=document.createElement('div');d.className='project-empty';d.textContent=text;box.appendChild(d)}
function item(title,meta='',body=''){
 const row=document.createElement('div');row.className='project-item';
 const h=document.createElement('div');h.className='project-item-head';
 const s=document.createElement('strong');s.textContent=title;
 const m=document.createElement('span');m.textContent=meta;h.append(s,m);row.appendChild(h);
 if(body){const b=document.createElement('div');b.className='project-item-body';b.textContent=body;row.appendChild(b)}
 return row;
}
async function loadProjects(){
 const data=scalar(await rpc('nexus_workspace_bootstrap'))||{};
 projects=data.projects||[];
 const defaults=data.settings||{};
 renderProjectList();
 if(!currentProjectId){
   currentProjectId=defaults.default_project_id||projects[0]?.id||null;
 }
 if(currentProjectId&&!projects.some(p=>String(p.id)===String(currentProjectId))){
   currentProjectId=projects[0]?.id||null;
 }
 if(currentProjectId)await loadProject(currentProjectId);
 else renderNoProject();
}
function renderProjectList(){
 const box=el('projectWorkspaceList');box.innerHTML='';
 if(!projects.length){empty(box,'No Projects yet.');return}
 projects.forEach(p=>{
   const b=document.createElement('button');b.type='button';b.className='project-nav-item'+(String(p.id)===String(currentProjectId)?' active':'');
   const strong=document.createElement('strong');strong.textContent=p.name;
   const small=document.createElement('span');small.textContent=(p.default_level||'free').toUpperCase()+' · '+fmt(p.updated_at);
   b.append(strong,small);b.onclick=()=>selectProject(p.id);box.appendChild(b);
 });
}
async function selectProject(id){
 currentProjectId=String(id);renderProjectList();await loadProject(id);
}
async function loadProject(id){
 setNotice('Loading Project workspace…');
 const data=scalar(await rpc('nexus_project_workspace',{p_project_id:id}))||{};
 workspace=data;
 const p=data.project||{};
 el('projectWorkspaceTitle').textContent=p.name||'Project';
 el('projectWorkspaceSubtitle').textContent=p.description||'Persistent NEXUS workspace';
 el('projectWorkspaceLevel').textContent=String(p.default_level||'free').toUpperCase();
 renderProjectList();renderActivePane();setNotice('');
}
function renderNoProject(){
 workspace=null;el('projectWorkspaceTitle').textContent='Projects';el('projectWorkspaceSubtitle').textContent='Create a Project to group chats, tasks and context.';el('projectWorkspaceLevel').textContent='—';
 const panes=['Overview','Chats','Tasks','Files','Agents','Skills'];
 for(const x of panes){const box=el('projectPane'+x);if(box)empty(box,'No Project selected.')}
}
function renderOverview(){
 const box=el('projectPaneOverview');box.innerHTML='';
 if(!workspace){empty(box,'No Project selected.');return}
 const counts=workspace.counts||{},p=workspace.project||{};
 const k=document.createElement('div');k.className='project-kpis';
 k.append(countCard('Chats',counts.chats),countCard('Tasks',counts.tasks),countCard('Files',counts.files),countCard('Agents',counts.agents),countCard('Skills',counts.skills));box.appendChild(k);
 const info=document.createElement('div');info.className='project-overview-grid';
 const desc=document.createElement('div');desc.className='project-card';desc.innerHTML='<h4>Description</h4>';
 const d=document.createElement('p');d.textContent=p.description||'No Project description yet.';desc.appendChild(d);
 const inst=document.createElement('div');inst.className='project-card';inst.innerHTML='<h4>Persistent instructions</h4>';
 const it=document.createElement('p');it.textContent=p.instructions||'No persistent instructions yet.';inst.appendChild(it);
 info.append(desc,inst);box.appendChild(info);
}
function renderChats(){
 const box=el('projectPaneChats');box.innerHTML='';const rows=workspace?.chats||[];
 if(!rows.length){empty(box,'No chats in this Project yet.');return}
 rows.forEach(c=>{
   const row=item(c.title||'Chat',(c.level||'free').toUpperCase()+' · '+fmt(c.updated_at));
   row.classList.add('clickable');row.onclick=async()=>{close();await ctx.openChat(c.id,c.level||'free')};box.appendChild(row);
 });
}
function renderTasks(){
 const box=el('projectPaneTasks');box.innerHTML='';const rows=workspace?.tasks||[];
 if(!rows.length){empty(box,'No tasks in this Project yet.');return}
 rows.forEach(t=>{
   const mode=t.execution_metadata?.execution_mode?String(t.execution_metadata.execution_mode).toUpperCase():String(t.kind||'task').replaceAll('_',' ').toUpperCase();
   const row=item(mode+' · '+String(t.id).slice(0,8),String(t.status||'')+' · '+String(t.level||'').toUpperCase(),t.input_summary||'');
   const actions=document.createElement('div');actions.className='project-item-actions';
   const run=document.createElement('button');run.type='button';run.textContent='Open runtime';run.onclick=e=>{e.stopPropagation();close();ctx.openTask(t.id)};
   actions.appendChild(run);
   if(t.conversation_id){const chat=document.createElement('button');chat.type='button';chat.textContent='Open chat';chat.onclick=async e=>{e.stopPropagation();close();await ctx.openChat(t.conversation_id,t.level||'free')};actions.appendChild(chat)}
   row.appendChild(actions);box.appendChild(row);
 });
}
function renderFiles(){
 const box=el('projectPaneFiles');box.innerHTML='';const rows=workspace?.files||[];
 if(!rows.length){empty(box,'No Project files yet. Attachments from Project chats/tasks will appear here.');return}
 rows.forEach(f=>{
   box.appendChild(item(f.filename||'File',[bytes(f.size_bytes),f.status,fmt(f.created_at)].filter(Boolean).join(' · '),f.mime_type||''));
 });
}
function renderAgents(){
 const box=el('projectPaneAgents');box.innerHTML='';const rows=workspace?.agents||[];
 if(!rows.length){empty(box,'No persistent Agent assigned to this Project.');return}
 rows.forEach(a=>box.appendChild(item(a.name,[a.routing_profile,a.autonomy_level].filter(Boolean).join(' · '),a.description||a.mission||'')));
}
function renderSkills(){
 const box=el('projectPaneSkills');box.innerHTML='';const rows=workspace?.skills||[];
 if(!rows.length){empty(box,'No Skill assigned to this Project.');return}
 rows.forEach(s=>box.appendChild(item(s.name,s.slug+' · v'+s.version+(s.enabled?' · enabled':' · disabled'),s.description||'')));
}
function renderActivePane(){
 if(activeTab==='overview')renderOverview();
 if(activeTab==='chats')renderChats();
 if(activeTab==='tasks')renderTasks();
 if(activeTab==='files')renderFiles();
 if(activeTab==='agents')renderAgents();
 if(activeTab==='skills')renderSkills();
}
async function open(projectId=null){
 if(!ctx?.getUser?.()){ctx.requestSignIn?.('Sign in to open your Projects.');return}
 showSurface();setTab(activeTab);
 if(projectId)currentProjectId=String(projectId);
 try{await loadProjects()}catch(e){setNotice('Project workspace unavailable: '+String(e?.message||e),true)}
}
async function newChat(){
 if(!currentProjectId)return;
 close();await ctx.startProjectChat(currentProjectId);
}
function openSettings(){close();ctx.openProjectSettings?.()}
function openLibrary(){close();ctx.openLibrary?.()}
function reset(){projects=[];workspace=null;currentProjectId=null;activeTab='overview';close()}
function init(options){
 ctx=options;
 el('projectsBtn').onclick=()=>open();
 el('closeProjectWorkspace').onclick=close;
 el('projectNewChat').onclick=newChat;
 el('projectEdit').onclick=openSettings;
 el('projectOpenLibrary').onclick=openLibrary;
 el('projectRefresh').onclick=()=>currentProjectId&&loadProject(currentProjectId).catch(e=>setNotice(String(e?.message||e),true));
 el('projectCreate').onclick=openSettings;
 document.querySelectorAll('[data-project-tab]').forEach(b=>b.onclick=()=>setTab(b.dataset.projectTab));
}
export {init,open,close,reset};
