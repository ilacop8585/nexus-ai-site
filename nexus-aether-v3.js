/* NEXUS AETHER UX bridge.
   Keep existing application event handlers for chat, projects, credits and jobs.
   No external scripts, no billed jobs, no new auth or business-logic requests. */
(()=>{
  const start=document.getElementById('aetherStartChat');
  const explore=document.getElementById('aetherExploreProjects');
  const composer=document.getElementById('prompt');
  start?.addEventListener('click',()=>{
    composer?.focus({preventScroll:true});
    if(window.innerWidth<=820)composer?.scrollIntoView({block:'nearest',behavior:'smooth'});
  });
  explore?.addEventListener('click',()=>document.getElementById('projectsBtn')?.click());
})();
