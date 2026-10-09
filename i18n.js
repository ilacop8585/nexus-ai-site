// NEXUS language layer V1 — Italian-first, reversible and persistent.
// Never translate user messages, file contents or AI-generated responses.
const KEY='nexus_ui_language_v1';
const SUPPORTED=new Set(['it','en']);
const DICTIONARY={
  "BETA · ACTIVE DEVELOPMENT": "BETA · IN SVILUPPO",
  "NEXUS Word is live while we expand agents, connectors and apps.": "NEXUS Word è online: stiamo ampliando agenti, connettori e applicazioni.",
  "What this means": "Cosa significa",
  "PUBLIC BETA": "BETA PUBBLICA",
  "＋ New chat": "＋ Nuova chat",
  "Work": "Lavoro",
  "Projects": "Progetti",
  "WORKSPACE": "AREA DI LAVORO",
  "Tasks & jobs": "Attività e lavori",
  "Library": "Libreria",
  "Files": "File",
  "Platform": "Piattaforma",
  "Workspace & settings": "Area di lavoro e impostazioni",
  "Connectors": "Connettori",
  "Collaboration": "Collaborazione",
  "Social Publisher": "Pubblicazione social",
  "Beta Workspace": "Area Beta",
  "Owner": "Titolare",
  "Admin Center": "Centro amministrazione",
  "Your chats": "Le tue chat",
  "Sign in to load chats.": "Accedi per caricare le chat.",
  "Load more chats": "Carica altre chat",
  "Credits": "Crediti",
  "Sign in to load your real NEXUS balance.": "Accedi per vedere il saldo crediti NEXUS.",
  "＋ Buy credits": "＋ Acquista crediti",
  "Auto · simple chat stays included; heavier work becomes a task": "Auto · chat semplice inclusa; i lavori complessi diventano attività",
  "Fast chat · included · no task queue": "Chat veloce · inclusa · senza coda",
  "Agent task · AI worker · credits": "Attività Agent · elaborazione IA · crediti",
  "Work task · analysis worker · credits": "Attività Work · analisi IA · crediti",
  "Code task · coding assistant · credits": "Attività Code · assistente programmazione · crediti",
  "Default NEXUS": "NEXUS predefinito",
  "Checking…": "Verifica in corso…",
  "Chats": "Chat",
  "New chat": "Nuova chat",
  "Jobs": "Lavori",
  "Buy credits": "Acquista crediti",
  "Sign in": "Accedi",
  "Sign out": "Esci",
  "NEXUS WORD · PUBLIC BETA": "NEXUS WORD · BETA PUBBLICA",
  "Chat fast. Hand off real work.": "Chat immediata. Affida a NEXUS i lavori complessi.",
  "Simple conversation stays fast and included. Research, coding, files and multi-step execution become trackable NEXUS tasks with explicit compute and credit usage.": "Le conversazioni semplici sono rapide e incluse. Ricerche, programmazione, file e lavori complessi diventano attività tracciabili, con costi in crediti espliciti.",
  "● Chat live": "● Chat attiva",
  "● Projects & Agents live": "● Progetti e agenti attivi",
  "● Beta workspace live": "● Area Beta attiva",
  "Connectors expanding": "Connettori in ampliamento",
  "Native apps in development": "App native in sviluppo",
  "📄 Analyse a document": "📄 Analizza un documento",
  "🖼️ Work with an image": "🖼️ Lavora su un'immagine",
  "💻 Work on code": "💻 Lavora sul codice",
  "⚙️ Run an agent task": "⚙️ Avvia un'attività Agent",
  "NEXUS WORD · PROJECT WORKSPACE": "NEXUS WORD · AREA PROGETTI",
  "Organize chats, tasks, files and agents with persistent context.": "Organizza chat, attività, file e agenti con un contesto persistente.",
  "Refresh": "Aggiorna",
  "Your Projects": "I tuoi progetti",
  "Loading Projects…": "Caricamento progetti…",
  "＋ Create Project": "＋ Crea progetto",
  "＋ New chat in Project": "＋ Nuova chat nel progetto",
  "Project settings": "Impostazioni progetto",
  "Overview": "Panoramica",
  "Tasks": "Attività",
  "Agents": "Agenti",
  "Skills": "Competenze",
  "NEXUS Task": "Attività NEXUS",
  "Task": "Attività",
  "No task selected.": "Nessuna attività selezionata.",
  "Plan": "Piano",
  "Timeline": "Cronologia",
  "Result": "Risultato",
  "Execution mode": "Modalità di esecuzione",
  "＋ Attach": "＋ Allega",
  "Any file type · up to 250 MB each · 5 files per job": "Qualsiasi tipo di file · fino a 250 MB ciascuno · 5 file per attività",
  "Send": "Invia",
  "NEXUS Word is in Public Beta": "NEXUS Word è in beta pubblica",
  "The service is live and usable while the platform, connectors and native apps continue to evolve.": "Il servizio è online e utilizzabile mentre continuiamo a sviluppare la piattaforma, i connettori e le app native.",
  "What is live": "Cosa è già attivo",
  "Accounts, persistent chats, file jobs, Projects, Agents, Skills, Beta Workspace, Owner notifications and NEXUS Private are already online.": "Account, chat persistenti, lavori sui file, progetti, agenti, competenze, area Beta, notifiche del titolare e NEXUS Private sono già online.",
  "What is still expanding": "Cosa è ancora in sviluppo",
  "The connector ecosystem, agent execution surfaces, native applications and some advanced automation paths are under active development.": "L'ecosistema dei connettori, le funzioni avanzate degli agenti, le applicazioni native e alcune automazioni sono in sviluppo.",
  "Billing rule": "Regola sui crediti",
  "Ordinary text chat is included. NEXUS shows a credit estimate before compute-heavy Agent, Work or Code tasks are reserved.": "La chat testuale ordinaria è inclusa. NEXUS mostra il preventivo crediti prima di avviare attività Agent, Work o Code più impegnative.",
  "Beta means features can change and occasional defects may occur. We prefer stating that clearly rather than presenting unfinished capabilities as finished.": "Essendo una beta, le funzioni possono cambiare e possono verificarsi errori. Preferiamo dichiararlo chiaramente, senza presentare come finite le parti ancora in sviluppo.",
  "Continue to NEXUS": "Entra in NEXUS",
  "Run as NEXUS task?": "Avviare come attività NEXUS?",
  "This request needs more than basic chat.": "Questa richiesta va oltre la chat di base.",
  "Estimated reservation": "Crediti previsti",
  "Cancel": "Annulla",
  "Use basic Chat instead": "Usa invece la chat base",
  "Run task": "Avvia attività",
  "Sign in to NEXUS": "Accedi a NEXUS",
  "Your account preserves chats, credits and jobs. Files and private content remain tied to your account.": "Il tuo account conserva chat, crediti e attività. File e contenuti privati restano associati al tuo account.",
  "Continue with Google": "Continua con Google",
  "Create account": "Crea account",
  "Forgot password?": "Password dimenticata?",
  "Close": "Chiudi",
  "NEXUS accounts are powered by Neon Auth. Passwords are handled by the authentication service, not stored in the page.": "Gli account NEXUS usano Neon Auth. Le password sono gestite dal servizio di autenticazione, non dalla pagina.",
  "Buy NEXUS credits": "Acquista crediti NEXUS",
  "One-time credit packs for compute-heavy jobs, files and media. Ordinary text chat is included.": "Pacchetti crediti una tantum per lavori complessi, file e contenuti multimediali. La chat testuale ordinaria è inclusa.",
  "500 credits": "500 crediti",
  "1,500 credits": "1.500 crediti",
  "4,000 credits": "4.000 crediti",
  "€4.99 · starter top-up": "4,99 € · pacchetto iniziale",
  "€9.99 · better value": "9,99 € · più conveniente",
  "€19.99 · heavy use": "19,99 € · uso intensivo",
  "Text chat is included.": "La chat testuale è inclusa.",
  "My NEXUS jobs": "Le mie attività NEXUS",
  "Real queued and completed work tied to your account.": "Attività reali in coda e completate, collegate al tuo account.",
  "Loading…": "Caricamento…",
  "Name": "Nome",
  "Your private NEXUS files. Files stay tied to your account and can reopen the chat they belong to.": "I tuoi file privati NEXUS. Restano collegati all'account e permettono di riaprire la chat di origine.",
  "NEXUS Agent OS · Settings": "NEXUS Agent OS · Impostazioni",
  "Defaults": "Impostazioni predefinite",
  "Runtime defaults": "Impostazioni di esecuzione",
  "Local first": "Prima locale",
  "Balanced": "Bilanciato",
  "Max": "Massimo",
  "Assist": "Assistenza",
  "Supervised": "Supervisionato",
  "Autonomous": "Autonomo",
  "Always confirm": "Conferma sempre",
  "Risk based": "In base al rischio",
  "Trusted low risk": "Basso rischio affidabile",
  "AI & execution": "IA ed esecuzione",
  "Concise": "Conciso",
  "Detailed": "Dettagliato",
  "Persistent Agents": "Agenti persistenti",
  "Personal": "Personale",
  "Connectors & Plugins": "Connettori e plugin",
  "Connect real external tools to NEXUS. Operational connectors are shown first; future integrations stay separated as Preview.": "Collega strumenti esterni reali a NEXUS. I connettori operativi sono mostrati per primi; quelli futuri restano separati come anteprima.",
  "Connect anything with MCP — available now.": "Collega servizi tramite MCP — disponibile ora.",
  "＋ Add custom MCP server": "＋ Aggiungi server MCP personalizzato",
  "Core tools": "Strumenti principali",
  "Loading NEXUS capabilities…": "Caricamento funzionalità NEXUS…",
  "All categories": "Tutte le categorie",
  "Loading connector catalog…": "Caricamento catalogo connettori…",
  "Show planned connectors": "Mostra connettori futuri",
  "Preview future connectors": "Anteprima connettori futuri",
  "External services must be connected through a server-side OAuth/MCP bridge. NEXUS will not store third-party secrets in the browser.": "I servizi esterni vanno collegati tramite il bridge OAuth/MCP lato server. NEXUS non salva le credenziali di terzi nel browser.",
  "Connect service": "Collega servizio",
  "Use a provider credential scoped as narrowly as possible. NEXUS verifies it before storing it encrypted.": "Usa credenziali con i permessi minimi necessari. NEXUS le verifica prima di archiviarle cifrate.",
  "Project ID": "ID progetto",
  "API key": "Chiave API",
  "The key is verified through the NEXUS connector bridge and stored encrypted only after verification.": "La chiave viene verificata tramite il bridge NEXUS e salvata cifrata soltanto dopo la verifica.",
  "Verify & connect": "Verifica e collega",
  "Search connectors…": "Cerca connettori…",
  "Search chats": "Cerca nelle chat",
  "Ask NEXUS or describe what you want done…": "Scrivi a NEXUS o descrivi cosa vuoi realizzare…",
  "Attach files": "Allega file",
  "Send message": "Invia messaggio",
  "Close Projects": "Chiudi progetti",
  "Project sections": "Sezioni del progetto",
  "Task runtime": "Esecuzione attività",
  "Search connectors": "Cerca connettori",
  "Connector category": "Categoria connettori",
  "Optional for a project-scoped key": "Facoltativo per una chiave limitata al progetto",
  "Paste the project-scoped key": "Incolla la chiave del progetto",
  "Task created": "Attività creata",
  "Execution plan": "Piano di esecuzione",
  "Worker assigned": "Worker assegnato",
  "Execution started": "Esecuzione avviata",
  "Quality check": "Controllo qualità",
  "Task completed": "Attività completata",
  "Task failed": "Attività non riuscita",
  "Task cancelled": "Attività annullata",
  "Waiting in queue": "In attesa in coda",
  "Worker execution": "Esecuzione worker",
  "Task accepted": "Attività accettata",
  "Result delivered": "Risultato consegnato",
  "Confirmed": "Confermato",
  "Running": "In esecuzione",
  "Pending": "In attesa",
  "Stopped": "Arrestato",
  "Queued": "In coda",
  "Completed": "Completato",
  "Failed": "Non riuscito",
  "Cancelled": "Annullato",
  "Open runtime": "Apri esecuzione",
  "Open chat": "Apri chat",
  "New conversation": "Nuova conversazione",
  "0 credits retained": "0 crediti trattenuti",
  "Credit reconciliation pending": "Verifica crediti in corso",
  "No Project yet": "Nessun progetto disponibile",
  "No chats yet": "Nessuna chat",
  "No tasks yet": "Nessuna attività",
  "No files yet": "Nessun file",
  "No agents yet": "Nessun agente",
  "No skills yet": "Nessuna competenza",
  "No projects yet": "Nessun progetto",
  "Create a Project": "Crea un progetto",
  "New Project": "Nuovo progetto",
  "Edit": "Modifica",
  "Save": "Salva",
  "Delete": "Elimina",
  "Archive": "Archivia",
  "Settings": "Impostazioni",
  "New task": "Nuova attività",
  "Instructions": "Istruzioni",
  "Description": "Descrizione",
  "Installed": "Installati",
  "Directory": "Catalogo",
  "Preview": "Anteprima",
  "Available": "Disponibile",
  "Connected": "Collegato",
  "Reconnect": "Ricollega",
  "Disconnect": "Disconnetti",
  "Disabled": "Disattivato",
  "Enabled": "Attivato",
  "NEXUS is replying…": "NEXUS sta rispondendo…",
  "NEXUS is replying in chat…": "NEXUS sta rispondendo in chat…",
  "Task runtime unavailable": "Esecuzione attività non disponibile"
};
DICTIONARY['Language']='Lingua';
DICTIONARY['Select interface language']="Seleziona la lingua dell'interfaccia";
const REVERSE=Object.fromEntries(Object.entries(DICTIONARY).map(([en,it])=>[it,en]));
const ROOT_SELECTORS=[
  '#betaReleaseStrip','.side','.top','#intro','.composer',
  '#betaWelcomeModal','#computeConfirmModal','#loginModal',
  '#creditsModal','#jobsModal','#libraryModal','#pluginsModal',
  '#agentOsModal','#projectWorkspace','#taskRuntimePanel'
];
const SKIP_SELECTOR='#messages,#historyList,#chatList,#prompt,#projectWorkspaceNotice,#projectWorkspaceTitle,#taskRuntimeResult,#taskRuntimeRequest,.project-item-head,.project-item-body,.project-list,.msg,.jobsummary,[contenteditable="true"]';
let locale='it';
try{
  const param=new URLSearchParams(location.search).get('lang');
  const saved=localStorage.getItem(KEY);
  locale=SUPPORTED.has(param)?param:SUPPORTED.has(saved)?saved:'it';
}catch{}
const textState=new WeakMap();
const attrState=new WeakMap();
let scheduled=false;
let observer=null;

function transformText(node){
  if(!node||node.nodeType!==Node.TEXT_NODE||!node.parentElement)return;
  const parent=node.parentElement;
  if(parent.closest(SKIP_SELECTOR)||/^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA)$/.test(parent.tagName))return;
  const raw=node.nodeValue;
  const clean=raw.trim();
  if(!clean)return;
  const cached=textState.get(node);
  const base=cached&&raw===cached.rendered?cached.base:(REVERSE[clean]||clean);
  const target=(locale==='it'?DICTIONARY[base]||base:base);
  // Re-apply only whole UI labels, never arbitrary prose.
  if(!(base in DICTIONARY)&&!(clean in REVERSE)&&!cached)return;
  const rendered=raw.replace(clean,target);
  textState.set(node,{base,rendered});
  if(rendered!==raw)node.nodeValue=rendered;
}
function transformAttrs(root){
 const list=[root,...root.querySelectorAll('[placeholder],[aria-label],[title]')];
 for(const item of list){
  if(item.closest(SKIP_SELECTOR))continue;
  for(const attr of ['placeholder','aria-label','title']){
   const value=item.getAttribute?.(attr);
   if(!value)continue;
   let states=attrState.get(item)||{};
   const saved=states[attr];
   const base=saved&&value===saved.rendered?saved.base:(REVERSE[value]||value);
   if(!(base in DICTIONARY)&&!(value in REVERSE)&&!saved)continue;
   const rendered=locale==='it'?DICTIONARY[base]||base:base;
   states[attr]={base,rendered};attrState.set(item,states);
   if(value!==rendered)item.setAttribute(attr,rendered);
  }
 }
}
function translateRoot(root){
 if(!root)return;
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 const nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);
 for(const node of nodes)transformText(node);
 transformAttrs(root);
}
function apply(){
 document.documentElement.lang=locale;
 document.documentElement.dataset.locale=locale;
 const select=document.getElementById('nexusLanguage');
 if(select)select.value=locale;
 for(const selector of ROOT_SELECTORS){
  for(const root of document.querySelectorAll(selector))translateRoot(root);
 }
 document.title=locale==='it'?'NEXUS Word Beta — Chat IA, agenti e progetti':'NEXUS Word Beta — AI Chat, Agents & Projects';
 const desc=document.querySelector('meta[name="description"]');
 if(desc)desc.content=locale==='it'
  ?"NEXUS Word è una piattaforma IA in beta pubblica: chat inclusa, agenti, programmazione, progetti e lavori con crediti dichiarati prima dell’esecuzione."
  :"NEXUS Word is a public-beta AI workspace with included chat, agents, coding, projects and transparent credit-based tasks.";
}
function schedule(){
 if(scheduled)return;scheduled=true;
 requestAnimationFrame(()=>{scheduled=false;apply()});
}
function setLanguage(next,{persist=true}={}){
 if(!SUPPORTED.has(next))return;
 const changed=next!==locale;locale=next;
 if(persist)try{localStorage.setItem(KEY,next)}catch{}
 if(persist)try{
   const u=new URL(location.href);if(next==='it')u.searchParams.delete('lang');else u.searchParams.set('lang',next);
   history.replaceState(history.state,'',u.pathname+u.search+u.hash);
 }catch{}
 apply();
 if(changed)window.dispatchEvent(new CustomEvent('nexus-language-change',{detail:{language:locale}}));
}
function init(){
 const select=document.getElementById('nexusLanguage');
 if(select)select.addEventListener('change',()=>setLanguage(select.value));
 apply();
 observer=new MutationObserver(records=>{
   const relevant=records.some(record=>{
     const node=record.target.nodeType===Node.TEXT_NODE?record.target.parentElement:record.target;
     if(!node||node.closest?.(SKIP_SELECTOR))return false;
     return ROOT_SELECTORS.some(selector=>node.closest?.(selector));
   });
   if(relevant)schedule();
 });
 observer.observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['placeholder','title','aria-label']});
}
export {init,setLanguage,apply};
export function getLanguage(){return locale}
