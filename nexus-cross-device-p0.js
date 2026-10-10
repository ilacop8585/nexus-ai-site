/* NEXUS Word cross-device P0 interactions.
   Uses existing close buttons. No RPC, credit, role, crypto or task mutations. */
(()=>{
 'use strict';
 const ids={
  adminModal:'closeAdmin',
  jobsModal:'closeJobs',
  agentOsModal:'closeAgentOs',
  privateModal:'closePrivate',
  socialModal:'closeSocial',
  betaModal:'closeBeta',
  pluginsModal:'closePlugins',
  libraryModal:'closeLibrary',
  notificationsModal:'closeNotifications'
 };
 for(const [modalId,closeId] of Object.entries(ids)){
   const modal=document.getElementById(modalId);
   const existing=document.getElementById(closeId);
   if(!modal||!existing)continue;
   const card=modal.querySelector('.modal-card');
   if(!card||card.querySelector('[data-nexus-mobile-close]'))continue;
   const slot=document.createElement('div');
   slot.className='nexus-modal-mobile-close';
   const close=document.createElement('button');
   close.type='button';
   close.textContent='Chiudi ✕';
   close.setAttribute('aria-label','Chiudi '+(card.querySelector('h2')?.textContent||'finestra'));
   close.dataset.nexusMobileClose=modalId;
   close.addEventListener('click',()=>existing.click());
   slot.append(close);
   card.insertBefore(slot,card.firstChild);
 }
 document.addEventListener('keydown',event=>{
   if(event.key!=='Escape'||event.defaultPrevented)return;
   const shown=[...document.querySelectorAll('.modal.show')];
   if(!shown.length)return;
   const top=shown[shown.length-1],button=top.querySelector('[data-nexus-mobile-close]');
   if(button){event.preventDefault();button.click()}
 });
 function updateViewport(){
   const vv=window.visualViewport;
   if(!vv)return;
   const visualHeight=Math.round(Math.max(220,vv.height));
   const keyboardOcclusion=Math.max(0,Math.round(window.innerHeight-vv.height-vv.offsetTop));
   document.documentElement.style.setProperty('--nexus-visible-viewport',visualHeight+'px');
   document.documentElement.style.setProperty('--nexus-keyboard-occlusion',keyboardOcclusion>90?keyboardOcclusion+'px':'0px');
   document.body.classList.toggle('nexus-soft-keyboard',keyboardOcclusion>90);
 }
 if(window.visualViewport){
   window.visualViewport.addEventListener('resize',updateViewport,{passive:true});
   window.visualViewport.addEventListener('scroll',updateViewport,{passive:true});
 }
 window.addEventListener('orientationchange',updateViewport,{passive:true});
 updateViewport();
 const input=document.getElementById('prompt');
 input?.addEventListener('focus',()=>{
   if(window.innerWidth>820)return;
   updateViewport();
   // Scrolling the actual editor into view does not send a job or alter draft.
   requestAnimationFrame(()=>input.scrollIntoView({block:'nearest',behavior:'instant'}));
 });
})();
