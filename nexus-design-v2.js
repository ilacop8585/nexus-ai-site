// Responsive NEXUS shell enhancements. No changes to auth, chat, credits or backend.
import {getMode,setMode} from './launch-os.js';

const menu=document.getElementById('mobileChatsBtn');
const backdrop=document.getElementById('sideBackdrop');
const sidebar=document.querySelector('.side');
const select=document.getElementById('mobileModeSelect');
function syncMenu(){
  if(!menu||!sidebar)return;
  const expanded=sidebar.classList.contains('open');
  menu.setAttribute('aria-expanded',String(expanded));
  menu.setAttribute('aria-label',expanded?'Chiudi menu NEXUS':'Apri menu NEXUS');
}
function syncMode(){
  if(select)select.value=getMode();
}
function init(){
  menu?.setAttribute('aria-controls','nexusSidebar');
  menu?.setAttribute('aria-expanded','false');
  if(sidebar)sidebar.id='nexusSidebar';
  menu?.addEventListener('click',()=>requestAnimationFrame(syncMenu));
  backdrop?.addEventListener('click',()=>requestAnimationFrame(syncMenu));
  sidebar?.addEventListener('click',event=>{
    if(event.target.closest('.navbtn,.newchat,.historyitem,.historymore')){
      if(backdrop?.classList.contains('show'))backdrop.click();
    }
  });
  document.addEventListener('keydown',event=>{
    if(event.key==='Escape'&&sidebar?.classList.contains('open')){
      backdrop?.click();
      menu?.focus();
    }
  });
  select?.addEventListener('change',()=>setMode(select.value));
  window.addEventListener('nexus-mode-change',syncMode);
  window.addEventListener('nexus-execution-settings',syncMode);
  window.addEventListener('resize',()=>{
    if(window.innerWidth>820&&sidebar?.classList.contains('open'))backdrop?.click();
    syncMenu();
  });
  syncMode();syncMenu();
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
