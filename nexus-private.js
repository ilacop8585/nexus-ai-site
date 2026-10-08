import * as M from './nexus-private-crypto.js';

let ctx=null,device=null,rooms=[],currentRoom=null,pollTimer=null,runtimeOk=false;
const peerAuthenticatedRooms=new Set();

const el=id=>document.getElementById(id);
const dataOf=r=>Array.isArray(r?.data)?r.data[0]:r?.data;
const keyDevice=u=>'nexus-private:device:'+u;
const keyKp=(u,ref)=>'nexus-private:kp:'+u+':'+ref;
const keyKpRefs=u=>'nexus-private:kprefs:'+u;
const keyRoom=(u,r)=>'nexus-private:room:'+u+':'+r;
const keyTranscript=(u,r)=>'nexus-private:transcript:'+u+':'+r;
const trustKey=fp=>'nexus-private:trust:'+String(fp||'').replace(/[^a-fA-F0-9]/g,'').toUpperCase();

function fmtFp(v){return String(v||'').replace(/[^a-fA-F0-9]/g,'').match(/.{1,4}/g)?.join(' ')||String(v||'')}
function trusted(fp){try{return localStorage.getItem(trustKey(fp))==='1'}catch{return false}}
function setTrusted(fp,on){try{on?localStorage.setItem(trustKey(fp),'1'):localStorage.removeItem(trustKey(fp))}catch{}}
function label(){const p=navigator.userAgentData?.platform||navigator.platform||'Browser';return String(p+' · '+(navigator.userAgentData?.brands?.[0]?.brand||'NEXUS Web')).slice(0,150)}
function isOwner(){return ctx?.getAccess?.()?.staff_role==='owner'}
function isBeta(){return ctx?.getAccess?.()?.staff_role==='beta_tester'}
function setState(t){const x=el('privateState');if(x)x.textContent=t}
function clearNode(n){while(n?.firstChild)n.removeChild(n.firstChild)}
function addText(parent,tag,text,cls){const x=document.createElement(tag);if(cls)x.className=cls;x.textContent=text;parent.appendChild(x);return x}
function me(){return ctx?.getUser?.()?.id||null}

async function validateCredential(identity,publicKeyB64){
  const r=await ctx.client.rpc('nexus_secure_validate_credential',{p_identity:String(identity),p_signature_public_key:String(publicKeyB64)});
  if(r.error)return false;
  return !!dataOf(r);
}

async function ensureDevice(){
  const user=ctx.getUser();if(!user)throw new Error('Accedi prima a NEXUS');
  let d=await M.getSecret(keyDevice(user.id));
  if(!d?.publicKeyB64||!d?.signKeyB64||d.userId!==String(user.id))d=await M.createDeviceIdentity(user.id);
  const r=await ctx.client.rpc('nexus_secure_register_device',{
    p_device_label:label(),p_identity_public_key:d.publicKeyB64,p_identity_fingerprint:d.fingerprint
  });
  if(r.error)throw r.error;
  d.serverId=dataOf(r);await M.putSecret(keyDevice(user.id),d);device=d;return d;
}

async function processWelcomes(){
  if(!device)return;
  const r=await ctx.client.rpc('nexus_secure_fetch_welcomes',{p_device_id:device.serverId});
  if(r.error)throw r.error;
  for(const w of r.data||[]){
    const kp=await M.getSecret(keyKp(me(),w.key_package_ref));
    if(!kp?.keyPackageB64||!kp?.privatePackage)continue;
    const joined=await M.joinRoom(w.welcome_ciphertext,kp.keyPackageB64,kp.privatePackage,validateCredential);
    await M.putSecret(keyRoom(me(),w.room_id),{stateB64:joined.stateB64,pending:null});
    await M.deleteSecret(keyKp(me(),w.key_package_ref));
    const done=await ctx.client.rpc('nexus_secure_mark_welcome_consumed',{p_welcome_id:w.id});
    if(done.error)throw done.error;
  }
}

async function topUpKeyPackages(target=4){
  let refs=await M.getSecret(keyKpRefs(me()))||[],available=[];
  for(const ref of refs){
    const r=await ctx.client.rpc('nexus_secure_key_package_available',{p_device_id:device.serverId,p_key_package_ref:ref});
    if(!r.error&&dataOf(r)===true)available.push(ref);
  }
  while(available.length<target){
    const kp=await M.generateJoinPackage(me(),device);
    await M.putSecret(keyKp(me(),kp.keyPackageRef),kp);
    const r=await ctx.client.rpc('nexus_secure_publish_key_package',{
      p_device_id:device.serverId,p_key_package_ref:kp.keyPackageRef,p_key_package:kp.keyPackageB64
    });
    if(r.error){await M.deleteSecret(keyKp(me(),kp.keyPackageRef));throw r.error}
    available.push(kp.keyPackageRef);
  }
  await M.putSecret(keyKpRefs(me()),available);
}

async function roomMembers(roomId){
  const r=await ctx.client.rpc('nexus_secure_list_room_members',{p_room_id:roomId});if(r.error)throw r.error;return r.data||[];
}
async function roomDevices(roomId){
  const r=await ctx.client.rpc('nexus_secure_list_member_devices',{p_room_id:roomId});if(r.error)throw r.error;return r.data||[];
}
async function rawMessages(roomId){
  const r=await ctx.client.rpc('nexus_secure_fetch_messages',{p_room_id:roomId,p_device_id:device.serverId,p_after:null,p_limit:500});
  if(r.error)throw r.error;return r.data||[];
}
async function transcript(roomId){
  return await M.getSecret(keyTranscript(me(),roomId))||{seen:[],messages:[]};
}
async function saveTranscript(roomId,t){await M.putSecret(keyTranscript(me(),roomId),t)}

async function recoverPending(roomId){
  const holder=await M.getSecret(keyRoom(me(),roomId));
  if(!holder?.pending)return holder;
  const rows=await rawMessages(roomId).catch(()=>[]);
  const p=holder.pending;
  const found=rows.some(x=>String(x.client_message_id||'')===String(p.clientMessageId||'')||String(x.ciphertext||'')===String(p.ciphertextB64||''));
  if(found){
    holder.pending=null;delete holder.previousStateB64;await M.putSecret(keyRoom(me(),roomId),holder);return holder;
  }
  if(p.kind==='application'&&p.rpc){
    const r=await ctx.client.rpc('nexus_secure_send_ciphertext',p.rpc);
    if(!r.error){holder.pending=null;delete holder.previousStateB64;await M.putSecret(keyRoom(me(),roomId),holder);return holder}
  }
  if(holder.previousStateB64){
    holder.stateB64=holder.previousStateB64;holder.pending=null;delete holder.previousStateB64;await M.putSecret(keyRoom(me(),roomId),holder);
  }
  return holder;
}

async function ensureOwnerState(roomId){
  let h=await recoverPending(roomId);
  if(h?.stateB64)return h;
  const devices=await roomDevices(roomId);
  const ownerDevices=devices.filter(d=>String(d.user_id)===String(me()));
  if(ownerDevices.length&&!ownerDevices.some(d=>String(d.device_id)===String(device.serverId))){
    throw new Error('Questa stanza MLS è associata a un altro dispositivo Owner.');
  }
  const created=await M.createRoomState(roomId,me(),device,validateCredential);
  h={stateB64:created.stateB64,pending:null};await M.putSecret(keyRoom(me(),roomId),h);
  const bind=await ctx.client.rpc('nexus_secure_bind_owner_device',{p_room_id:roomId,p_device_id:device.serverId,p_epoch:created.epoch});
  if(bind.error){await M.deleteSecret(keyRoom(me(),roomId));throw bind.error}
  return h;
}

async function addOneBetaDevice(roomId,betaUserId){
  const holder=await ensureOwnerState(roomId);
  const take=await ctx.client.rpc('nexus_secure_owner_take_beta_key_package',{p_room_id:roomId,p_beta_user_id:betaUserId});
  if(take.error){
    if(/no_beta_key_package_available/i.test(String(take.error.message||take.error)))return false;
    throw take.error;
  }
  const k=dataOf(take);if(!k?.key_package)return false;
  const added=await M.addMember(holder.stateB64,k.key_package,validateCredential);
  const pending={previousStateB64:holder.stateB64,stateB64:added.stateB64,pending:{kind:'commit',ciphertextB64:added.commitB64}};
  await M.putSecret(keyRoom(me(),roomId),pending);
  const fin=await ctx.client.rpc('nexus_secure_owner_finalize_add',{
    p_room_id:roomId,p_beta_user_id:betaUserId,p_recipient_device_id:k.device_id,p_sender_device_id:device.serverId,
    p_key_package_ref:k.key_package_ref,p_epoch:added.epoch,p_commit_ciphertext:added.commitB64,p_welcome_ciphertext:added.welcomeB64
  });
  if(fin.error){
    await M.putSecret(keyRoom(me(),roomId),{stateB64:holder.stateB64,pending:null});throw fin.error;
  }
  await M.putSecret(keyRoom(me(),roomId),{stateB64:added.stateB64,pending:null});
  return true;
}

async function syncAllBetaDevices(roomId,betaUserId){
  let n=0;
  for(let i=0;i<12;i++){if(!(await addOneBetaDevice(roomId,betaUserId)))break;n++}
  return n;
}

async function loadCandidates(){
  if(!isOwner())return[];
  const r=await ctx.client.rpc('nexus_secure_list_beta_candidates');if(r.error)throw r.error;
  const list=r.data||[],sel=el('privateBetaSelect');
  if(sel){
    sel.innerHTML='<option value="">Privato con…</option>';
    for(const x of list){const o=document.createElement('option');o.value=x.user_id;o.textContent=(x.display_name||'Beta tester')+(Number(x.available_key_package_count||0)?' · pronto':' · deve aprire NEXUS Private');sel.appendChild(o)}
  }
  return list;
}

async function prepareOwnerGroup(){
  const g=await ctx.client.rpc('nexus_secure_create_beta_group',{p_display_name:'Comitiva Beta'});if(g.error)throw g.error;
  const roomId=dataOf(g);await ensureOwnerState(roomId);
  const candidates=await loadCandidates(),members=await roomMembers(roomId),active=new Set(members.map(x=>String(x.user_id)));
  for(const b of candidates){
    if(!active.has(String(b.user_id))||Number(b.available_key_package_count||0)>0){
      try{await syncAllBetaDevices(roomId,b.user_id)}catch(e){console.warn('NEXUS Private beta sync',b.user_id,e)}
    }
  }
  return roomId;
}

async function loadRooms(){
  const r=await ctx.client.rpc('nexus_secure_list_rooms');if(r.error)throw r.error;rooms=r.data||[];
  const box=el('privateRooms');clearNode(box);
  if(!rooms.length){addText(box,'div',isBeta()?'Nessun invito MLS ancora. Il tuo dispositivo è pronto.':'Nessuna stanza disponibile.','notice');return}
  for(const room of rooms){
    const b=document.createElement('button');b.type='button';b.className='private-room'+(currentRoom?.id===room.id?' active':'');
    addText(b,'strong',room.display_name||'NEXUS Private');
    addText(b,'span',(room.room_type==='beta_group'?'Gruppo':'Privato')+' · '+room.member_count+' membri · '+(room.enrolled_device_count||0)+' dispositivi MLS','small');
    b.onclick=()=>selectRoom(room.id);box.appendChild(b);
  }
}

async function processRoomRows(room){
  let holder=await recoverPending(room.id);
  if(!holder?.stateB64)return {messages:[],state:null};
  const t=await transcript(room.id),seen=new Set(t.seen||[]),rows=await rawMessages(room.id);
  for(const row of rows){
    if(seen.has(String(row.id)))continue;
    if(String(row.sender_device_id)===String(device.serverId)){seen.add(String(row.id));continue}
    const info=await M.getStateInfo(holder.stateB64,validateCredential);
    if(String(row.content_type).includes('mls-commit')&&Number(row.epoch)<=Number(info.epoch)){seen.add(String(row.id));continue}
    try{
      const p=await M.processWire(holder.stateB64,row.ciphertext,validateCredential);holder.stateB64=p.stateB64;
      await M.putSecret(keyRoom(me(),room.id),holder);seen.add(String(row.id));peerAuthenticatedRooms.add(room.id);
      if(p.kind==='application')t.messages.push({id:row.id,sender_user_id:row.sender_user_id,text:p.text,created_at:row.created_at});
    }catch(e){console.warn('MLS row failed',row.id,e)}
  }
  t.seen=[...seen].slice(-1200);t.messages=(t.messages||[]).slice(-500);await saveTranscript(room.id,t);
  return {messages:t.messages,state:holder.stateB64};
}

async function renderSecurity(room){
  const box=el('privateSecurity');clearNode(box);
  let holder=await M.getSecret(keyRoom(me(),room.id)),info=null;try{if(holder?.stateB64)info=await M.getStateInfo(holder.stateB64,validateCredential)}catch{}
  const devices=await roomDevices(room.id).catch(()=>[]),peers=devices.filter(d=>String(d.device_id)!==String(device.serverId));
  const peerOk=peerAuthenticatedRooms.has(room.id),trustOk=peers.length===0?false:peers.every(d=>trusted(d.identity_fingerprint));
  const verified=runtimeOk&&!!info&&peerOk&&trustOk;
  addText(box,'strong',verified?'E2EE MLS VERIFICATA':runtimeOk&&info?'E2EE MLS ATTIVA':'MLS NON INIZIALIZZATA');
  addText(box,'div','Protocollo: '+M.NEXUS_MLS_PROTOCOL,'small');
  addText(box,'div','Ciphersuite: '+M.NEXUS_MLS_SUITE,'small');
  addText(box,'div','Implementazione: '+M.NEXUS_MLS_VERSION+' · runtime self-test '+(runtimeOk?'PASS':'FAIL'),'small');
  if(info)addText(box,'div','Epoch MLS: '+info.epoch,'small');
  addText(box,'div','Questo dispositivo: '+fmtFp(device.fingerprint),'small');
  for(const d of peers){
    const row=document.createElement('div');row.className='private-fingerprint';
    const s=document.createElement('span');s.textContent=(d.display_name||d.device_label||'Peer')+' · '+fmtFp(d.identity_fingerprint)+(trusted(d.identity_fingerprint)?' · VERIFICATO':' · NON VERIFICATO');row.appendChild(s);
    const b=document.createElement('button');b.type='button';b.className='iconbtn';b.style.marginLeft='8px';b.style.padding='4px 7px';b.style.fontSize='10px';
    b.textContent=trusted(d.identity_fingerprint)?'Rimuovi verifica':'Segna verificato';b.onclick=()=>{setTrusted(d.identity_fingerprint,!trusted(d.identity_fingerprint));renderSecurity(room)};row.appendChild(b);box.appendChild(row);
  }
  addText(box,'div','Il server conserva solo messaggi MLS cifrati, Welcome/KeyPackage pubblici e metadati di consegna. Le chiavi private e lo stato MLS restano cifrati sul dispositivo.','small');
  addText(box,'div','ts-mls 1.6.4 implementa RFC 9420 ma non risulta formalmente auditata: NEXUS non la presenta come Signal Protocol.','small');
}

async function renderMessages(room,messages){
  const box=el('privateMessages');clearNode(box);
  if(!messages.length){addText(box,'div','Nessun messaggio applicativo decifrato su questo dispositivo.','notice');return}
  const members=await roomMembers(room.id).catch(()=>[]),names=new Map(members.map(x=>[String(x.user_id),x.display_name||'Beta']));
  for(const m of messages){
    const mine=String(m.sender_user_id)===String(me()),w=document.createElement('div');w.className='private-message '+(mine?'mine':'theirs');
    const h=document.createElement('div');h.className='private-message-head';h.textContent=(mine?'Tu':names.get(String(m.sender_user_id))||'Peer')+' · MLS autenticato · '+new Date(m.created_at).toLocaleString();w.appendChild(h);
    addText(w,'div',m.text);box.appendChild(w);
  }
  box.scrollTop=box.scrollHeight;
}

async function loadCurrent(){
  if(!currentRoom)return;
  const rr=await ctx.client.rpc('nexus_secure_list_rooms');if(rr.error)throw rr.error;
  currentRoom=(rr.data||[]).find(x=>String(x.id)===String(currentRoom.id))||currentRoom;
  const p=await processRoomRows(currentRoom);await renderMessages(currentRoom,p.messages);await renderSecurity(currentRoom);await loadRooms();
}

async function selectRoom(id){
  currentRoom=rooms.find(x=>String(x.id)===String(id))||null;if(!currentRoom)return;
  el('privateRoomTitle').textContent=currentRoom.display_name||'NEXUS Private';setState('Sincronizzazione MLS…');
  try{if(isOwner())await ensureOwnerState(currentRoom.id);await processWelcomes();await loadCurrent();setState('Pronto · '+M.NEXUS_MLS_PROTOCOL)}catch(e){setState('Errore: '+(e?.message||String(e)))}
}

async function sendCurrent(){
  const ta=el('privateComposer'),text=(ta?.value||'').trim();if(!text||!currentRoom||!device)return;
  if(text.length>12000){setState('Messaggio troppo lungo (max 12.000 caratteri).');return}
  const send=el('privateSend');send.disabled=true;setState('Cifratura MLS sul dispositivo…');
  try{
    let holder=await recoverPending(currentRoom.id);if(!holder?.stateB64)throw new Error('Questo dispositivo non è ancora membro MLS della stanza.');
    const clientMessageId=crypto.randomUUID(),encrypted=await M.encryptMessage(holder.stateB64,text,validateCredential);
    const rpc={p_room_id:currentRoom.id,p_sender_device_id:device.serverId,p_client_message_id:clientMessageId,p_epoch:encrypted.epoch,p_ciphertext:encrypted.ciphertextB64,p_content_type:'application/vnd.nexus.mls'};
    await M.putSecret(keyRoom(me(),currentRoom.id),{stateB64:encrypted.stateB64,previousStateB64:holder.stateB64,pending:{kind:'application',clientMessageId,ciphertextB64:encrypted.ciphertextB64,rpc}});
    let r=await ctx.client.rpc('nexus_secure_send_ciphertext',rpc);if(r.error)r=await ctx.client.rpc('nexus_secure_send_ciphertext',rpc);if(r.error)throw r.error;
    await M.putSecret(keyRoom(me(),currentRoom.id),{stateB64:encrypted.stateB64,pending:null});
    const t=await transcript(currentRoom.id),id=String(dataOf(r)||clientMessageId);t.seen=[...(t.seen||[]),id];t.messages=[...(t.messages||[]),{id,sender_user_id:me(),text,created_at:new Date().toISOString()}].slice(-500);await saveTranscript(currentRoom.id,t);
    ta.value='';await loadCurrent();setState('Inviato · plaintext mai inviato a Neon');
  }catch(e){setState('Invio sospeso: '+(e?.message||String(e)))}finally{send.disabled=false}
}

async function createDm(){
  const betaId=el('privateBetaSelect')?.value;if(!betaId)return;
  setState('Preparazione DM MLS…');
  try{
    const r=await ctx.client.rpc('nexus_secure_create_owner_beta_dm',{p_beta_user_id:betaId});if(r.error)throw r.error;
    const roomId=dataOf(r);await ensureOwnerState(roomId);const n=await syncAllBetaDevices(roomId,betaId);
    await loadRooms();await selectRoom(roomId);setState(n?'DM MLS pronto':'DM creato · il beta deve aprire NEXUS Private almeno una volta');
  }catch(e){setState('Errore DM: '+(e?.message||String(e)))}
}

async function syncGroup(){
  setState('Sincronizzazione Comitiva Beta via MLS…');
  try{
    const roomId=await prepareOwnerGroup();await loadRooms();await selectRoom(roomId);setState('Comitiva Beta sincronizzata · '+M.NEXUS_MLS_PROTOCOL);
  }catch(e){setState('Errore gruppo: '+(e?.message||String(e)))}
}

async function openPrivate(){
  if(!(isOwner()||isBeta()))return;
  el('privateModal').classList.add('show');setState('Avvio motore MLS…');
  try{
    await ensureDevice();runtimeOk=await M.selfTest();if(!runtimeOk)throw new Error('MLS runtime self-test fallito');
    await processWelcomes();await topUpKeyPackages();if(isOwner()){el('privateOwnerTools').hidden=false;await loadCandidates();await prepareOwnerGroup()}else el('privateOwnerTools').hidden=true;
    await loadRooms();if(!currentRoom&&rooms.length)await selectRoom(rooms[0].id);else if(currentRoom)await loadCurrent();
    setState('NEXUS Private pronto · '+M.NEXUS_MLS_PROTOCOL);
    clearInterval(pollTimer);pollTimer=setInterval(async()=>{if(!el('privateModal')?.classList.contains('show'))return;try{await processWelcomes();if(currentRoom)await loadCurrent()}catch{}},5000);
  }catch(e){setState('NEXUS Private non disponibile: '+(e?.message||String(e)))}
}
function closePrivate(){el('privateModal')?.classList.remove('show');clearInterval(pollTimer);pollTimer=null}

export function init(options){
  ctx=options;
  if(el('privateBtn'))el('privateBtn').onclick=openPrivate;
  if(el('closePrivate'))el('closePrivate').onclick=closePrivate;
  if(el('privateSend'))el('privateSend').onclick=sendCurrent;
  if(el('privateSyncGroup'))el('privateSyncGroup').onclick=syncGroup;
  if(el('privateCreateDm'))el('privateCreateDm').onclick=createDm;
  if(el('privateRefresh'))el('privateRefresh').onclick=()=>loadCurrent().catch(e=>setState('Errore: '+(e?.message||String(e))));
  if(el('privateComposer'))el('privateComposer').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();sendCurrent()}});
  if(el('privateModal'))el('privateModal').onclick=e=>{if(e.target.id==='privateModal')closePrivate()};
}
export function applyAccess(){const a=ctx?.getAccess?.(),b=el('privateBtn');if(b)b.hidden=!(a?.staff_role==='owner'||a?.staff_role==='beta_tester')}
export function reset(){device=null;rooms=[];currentRoom=null;peerAuthenticatedRooms.clear();clearInterval(pollTimer);pollTimer=null;const b=el('privateBtn');if(b)b.hidden=true}