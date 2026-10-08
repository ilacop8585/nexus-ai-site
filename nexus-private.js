const enc=new TextEncoder(),dec=new TextDecoder();
let ctx=null,device=null,rooms=[],currentRoom=null,pollTimer=null,localCryptoOk=false;
const peerVerifiedRooms=new Set();

function stable(v){
  if(Array.isArray(v))return '['+v.map(stable).join(',')+']';
  if(v&&typeof v==='object')return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+stable(v[k])).join(',')+'}';
  return JSON.stringify(v);
}
function b64(bytes){
  let s='';const a=bytes instanceof Uint8Array?bytes:new Uint8Array(bytes);
  for(let i=0;i<a.length;i+=0x8000)s+=String.fromCharCode(...a.subarray(i,i+0x8000));
  return btoa(s);
}
function ub64(s){const raw=atob(String(s||'')),a=new Uint8Array(raw.length);for(let i=0;i<raw.length;i++)a[i]=raw.charCodeAt(i);return a}
function hex(bytes){return [...new Uint8Array(bytes)].map(x=>x.toString(16).padStart(2,'0')).join('').toUpperCase()}
function fmtFp(v){return String(v||'').replace(/[^A-Fa-f0-9]/g,'').match(/.{1,4}/g)?.join(' ')||String(v||'')}
function trustKey(fp){return 'nexus_private_trust:'+String(fp||'').replace(/[^A-Fa-f0-9]/g,'').toUpperCase()}
function isTrusted(fp){try{return localStorage.getItem(trustKey(fp))==='1'}catch{return false}}
function setTrusted(fp,on){try{if(on)localStorage.setItem(trustKey(fp),'1');else localStorage.removeItem(trustKey(fp))}catch{}}
function aad(roomId,messageId,senderDeviceId,version){return enc.encode(['NEXUS-E2EE-v1',roomId,messageId,senderDeviceId,String(version)].join('|'))}
function canonical(roomId,messageId,senderDeviceId,version,salt,payloadIv,ciphertext,eph){
  return enc.encode([roomId,messageId,senderDeviceId,String(version),salt,payloadIv,ciphertext,stable(eph)].join('|'));
}
function label(){const p=navigator.userAgentData?.platform||navigator.platform||'Browser';return String(p+' · '+(navigator.userAgentData?.brands?.[0]?.brand||'NEXUS Web')).slice(0,150)}

function dbOpen(){return new Promise((resolve,reject)=>{const r=indexedDB.open('nexus_private_v1',1);r.onupgradeneeded=()=>{if(!r.result.objectStoreNames.contains('kv'))r.result.createObjectStore('kv')};r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)})}
async function kvGet(k){const db=await dbOpen();return new Promise((resolve,reject)=>{const tx=db.transaction('kv','readonly'),r=tx.objectStore('kv').get(k);r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)})}
async function kvPut(k,v){const db=await dbOpen();return new Promise((resolve,reject)=>{const tx=db.transaction('kv','readwrite'),r=tx.objectStore('kv').put(v,k);r.onsuccess=()=>resolve(v);r.onerror=()=>reject(r.error)})}
async function kvDel(k){const db=await dbOpen();return new Promise((resolve,reject)=>{const tx=db.transaction('kv','readwrite'),r=tx.objectStore('kv').delete(k);r.onsuccess=()=>resolve();r.onerror=()=>reject(r.error)})}

async function makePrivatePair(kind){
  const isEcdh=kind==='ECDH';
  const alg={name:kind,namedCurve:'P-256'};
  const pair=await crypto.subtle.generateKey(alg,true,isEcdh?['deriveBits']:['sign','verify']);
  const publicJwk=await crypto.subtle.exportKey('jwk',pair.publicKey);
  const privateJwk=await crypto.subtle.exportKey('jwk',pair.privateKey);
  const privateKey=await crypto.subtle.importKey('jwk',privateJwk,alg,false,isEcdh?['deriveBits']:['sign']);
  for(const k of Object.keys(privateJwk))delete privateJwk[k];
  return {privateKey,publicJwk};
}
async function freshDevice(user){
  const ecdh=await makePrivatePair('ECDH'),sign=await makePrivatePair('ECDSA');
  const digest=await crypto.subtle.digest('SHA-256',enc.encode(stable({ecdh:ecdh.publicJwk,signing:sign.publicJwk})));
  return {userId:user.id,ecdhPrivate:ecdh.privateKey,signPrivate:sign.privateKey,ecdhPublicJwk:ecdh.publicJwk,signPublicJwk:sign.publicJwk,fingerprint:hex(digest),serverId:null};
}
async function ensureDevice(){
  const user=ctx.getUser();if(!user)throw new Error('Accedi prima a NEXUS');
  const key='device:'+user.id;
  let d=await kvGet(key);
  if(!d||!d.ecdhPrivate||!d.signPrivate||!d.ecdhPublicJwk||!d.signPublicJwk)d=await freshDevice(user);
  let r=await ctx.client.rpc('nexus_secure_register_device',{
    p_device_label:label(),p_ecdh_public_jwk:d.ecdhPublicJwk,p_signing_public_jwk:d.signPublicJwk,p_identity_fingerprint:d.fingerprint
  });
  if(r.error&&String(r.error.message||r.error).includes('device_revoked')){
    await kvDel(key);d=await freshDevice(user);
    r=await ctx.client.rpc('nexus_secure_register_device',{
      p_device_label:label(),p_ecdh_public_jwk:d.ecdhPublicJwk,p_signing_public_jwk:d.signPublicJwk,p_identity_fingerprint:d.fingerprint
    });
  }
  if(r.error)throw r.error;
  d.serverId=Array.isArray(r.data)?r.data[0]:r.data;await kvPut(key,d);device=d;return d;
}
async function deriveWrap(privateKey,publicJwk,saltBytes,aadBytes){
  const pub=await crypto.subtle.importKey('jwk',publicJwk,{name:'ECDH',namedCurve:'P-256'},true,[]);
  const bits=await crypto.subtle.deriveBits({name:'ECDH',public:pub},privateKey,256);
  const base=await crypto.subtle.importKey('raw',bits,'HKDF',false,['deriveKey']);
  return crypto.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:saltBytes,info:aadBytes},base,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
async function cryptoSelfTest(){
  try{
    const a=await makePrivatePair('ECDH'),b=await makePrivatePair('ECDH'),sig=await makePrivatePair('ECDSA');
    const salt=crypto.getRandomValues(new Uint8Array(32)),aadv=enc.encode('NEXUS-E2EE-v1-selftest');
    const key=await crypto.subtle.generateKey({name:'AES-GCM',length:256},true,['encrypt','decrypt']);
    const raw=new Uint8Array(await crypto.subtle.exportKey('raw',key)),iv=crypto.getRandomValues(new Uint8Array(12));
    const cipher=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:aadv},key,enc.encode('NEXUS')));
    const wk=await deriveWrap(a.privateKey,b.publicJwk,salt,aadv),wiv=crypto.getRandomValues(new Uint8Array(12));
    const wrapped=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv:wiv,additionalData:aadv},wk,raw));
    const uw=await deriveWrap(b.privateKey,a.publicJwk,salt,aadv);
    const raw2=await crypto.subtle.decrypt({name:'AES-GCM',iv:wiv,additionalData:aadv},uw,wrapped);
    const k2=await crypto.subtle.importKey('raw',raw2,{name:'AES-GCM'},false,['decrypt']);
    const plain=dec.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv,additionalData:aadv},k2,cipher));
    const signed=enc.encode('NEXUS-E2EE-v1-signature'),s=await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},sig.privateKey,signed);
    const sp=await crypto.subtle.importKey('jwk',sig.publicJwk,{name:'ECDSA',namedCurve:'P-256'},true,['verify']);
    localCryptoOk=plain==='NEXUS'&&await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},sp,s,signed);
  }catch{localCryptoOk=false}
  return localCryptoOk;
}

function isOwner(){return ctx.getAccess()?.staff_role==='owner'}
function isBeta(){return ctx.getAccess()?.staff_role==='beta_tester'}
function el(id){return document.getElementById(id)}
function setState(t){const x=el('privateState');if(x)x.textContent=t}
function clearNode(n){while(n?.firstChild)n.removeChild(n.firstChild)}
function addText(parent,tag,text,cls){const x=document.createElement(tag);if(cls)x.className=cls;x.textContent=text;parent.appendChild(x);return x}

async function prepareRooms(){
  if(isOwner()){
    const g=await ctx.client.rpc('nexus_secure_sync_beta_group',{p_display_name:'Comitiva Beta'});if(g.error)throw g.error;
    const u=await ctx.client.rpc('nexus_admin_list_users');
    const sel=el('privateBetaSelect');if(sel){sel.innerHTML='<option value="">Privato con…</option>';for(const x of u.data||[]){if(x.staff_role!=='beta_tester')continue;const o=document.createElement('option');o.value=x.user_id;o.textContent=x.display_name||x.name||x.email||'Beta tester';sel.appendChild(o)}}
  }else if(isBeta()){
    const d=await ctx.client.rpc('nexus_secure_open_owner_dm');if(d.error)throw d.error;
  }
}
async function loadRooms(){
  const r=await ctx.client.rpc('nexus_secure_list_rooms');if(r.error)throw r.error;rooms=r.data||[];
  const box=el('privateRooms');clearNode(box);
  if(!rooms.length){addText(box,'div','Nessuna stanza disponibile.','notice');return}
  for(const room of rooms){
    const b=document.createElement('button');b.type='button';b.className='private-room'+(currentRoom?.id===room.id?' active':'');
    addText(b,'strong',room.display_name||'NEXUS Private');addText(b,'span',(room.room_type==='beta_group'?'Gruppo':'Privato')+' · '+room.member_count+' membri · '+room.active_device_count+' dispositivi','small');
    b.onclick=()=>selectRoom(room.id);box.appendChild(b);
  }
}
async function roomDevices(roomId){
  const r=await ctx.client.rpc('nexus_secure_list_member_devices',{p_room_id:roomId});if(r.error)throw r.error;return r.data||[];
}
async function fetchMessages(roomId){
  const r=await ctx.client.rpc('nexus_secure_fetch_messages',{p_room_id:roomId,p_device_id:device.serverId,p_after:null,p_limit:300});if(r.error)throw r.error;return r.data||[];
}

async function decryptRow(room,row){
  const aadv=aad(room.id,row.client_message_id,row.sender_device_id,row.membership_version);
  const canon=canonical(room.id,row.client_message_id,row.sender_device_id,row.membership_version,row.salt,row.payload_iv,row.ciphertext,row.ephemeral_public_jwk);
  const signPub=await crypto.subtle.importKey('jwk',row.sender_signing_public_jwk,{name:'ECDSA',namedCurve:'P-256'},true,['verify']);
  const sigOk=await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},signPub,ub64(row.signature),canon);
  if(!sigOk)throw new Error('Firma mittente non valida');
  const wk=await deriveWrap(device.ecdhPrivate,row.ephemeral_public_jwk,ub64(row.salt),aadv);
  const raw=await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(row.wrap_iv),additionalData:aadv},wk,ub64(row.wrapped_key));
  const ck=await crypto.subtle.importKey('raw',raw,{name:'AES-GCM'},false,['decrypt']);
  const plain=dec.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:ub64(row.payload_iv),additionalData:aadv},ck,ub64(row.ciphertext)));
  if(row.sender_device_id!==device.serverId)peerVerifiedRooms.add(room.id);
  return {plain,sigOk};
}
async function renderSecurity(room,devices){
  const box=el('privateSecurity');clearNode(box);
  const peers=devices.filter(d=>d.device_id!==device.serverId);
  const peerOk=peerVerifiedRooms.has(room.id);
  const fingerprintsOk=peers.length>0&&peers.every(d=>isTrusted(d.identity_fingerprint));
  const full=localCryptoOk&&peerOk&&fingerprintsOk;
  const status=full?'E2EE VERIFICATA · PEER CONFERMATI':!localCryptoOk?'VERIFICA CRITTOGRAFICA FALLITA':!peerOk?'CRITTOGRAFIA OK · ATTESA MESSAGGIO PEER':'CRITTOGRAFIA OK · VERIFICA I FINGERPRINT';
  addText(box,'strong',status);
  addText(box,'div','Protocollo: NEXUS-E2EE-v1','small');
  addText(box,'div','ECDH P-256 · HKDF-SHA-256 · AES-256-GCM · ECDSA P-256/SHA-256','small');
  addText(box,'div','Versione membri: '+room.membership_version+' · '+room.member_count+' membri · '+devices.length+' dispositivi attivi','small');
  addText(box,'div','Questo dispositivo: '+fmtFp(device.fingerprint),'small');
  if(Number(room.member_count)>devices.length)addText(box,'div','Attenzione: almeno un membro non ha ancora registrato un dispositivo NEXUS Private. I messaggi inviati ora non saranno recuperabili retroattivamente da quel futuro dispositivo.','notice');
  for(const d of devices){
    const row=document.createElement('div');row.className='private-fingerprint';
    const mine=d.device_id===device.serverId;
    const txt=document.createElement('span');txt.textContent=(mine?'Questo dispositivo':'Peer')+' · '+d.device_label+' · '+fmtFp(d.identity_fingerprint)+(mine?'':(isTrusted(d.identity_fingerprint)?' · VERIFICATO':' · NON VERIFICATO'));row.appendChild(txt);
    if(!mine){
      const b=document.createElement('button');b.type='button';b.className='iconbtn';b.style.marginLeft='8px';b.style.padding='4px 7px';b.style.fontSize='10px';
      b.textContent=isTrusted(d.identity_fingerprint)?'Rimuovi verifica':'Segna verificato';
      b.title='Confronta prima il fingerprint con il beta tramite un canale indipendente.';
      b.onclick=()=>{setTrusted(d.identity_fingerprint,!isTrusted(d.identity_fingerprint));renderSecurity(room,devices)};
      row.appendChild(b);
    }
    box.appendChild(row);
  }
  addText(box,'div','Per il lucchetto verde, confronta i fingerprint con l’altra persona tramite un canale indipendente e marca i dispositivi corretti.','small');
  addText(box,'div','Il server conserva ciphertext e chiavi contenuto avvolte per dispositivo. NEXUS AI non riceve il testo in chiaro.','small');
}
async function renderMessages(room,rows){
  const box=el('privateMessages');clearNode(box);
  if(!rows.length){addText(box,'div','Nessun messaggio ancora.','notice');return}
  for(const row of rows){
    const wrap=document.createElement('div');wrap.className='private-message '+(row.sender_user_id===ctx.getUser()?.id?'mine':'theirs');
    try{
      const d=await decryptRow(room,row);
      const h=document.createElement('div');h.className='private-message-head';h.textContent=(row.sender_user_id===ctx.getUser()?.id?'Tu':row.sender_device_label)+' · firma verificata · '+new Date(row.created_at).toLocaleString();wrap.appendChild(h);
      addText(wrap,'div',d.plain);
    }catch(e){
      const h=document.createElement('div');h.className='private-message-head';h.textContent='MESSAGGIO NON VERIFICATO';wrap.appendChild(h);addText(wrap,'div',String(e?.message||e),'small');
    }
    box.appendChild(wrap);
  }
}
async function loadCurrent(){
  if(!currentRoom)return;
  const latest=(await ctx.client.rpc('nexus_secure_list_rooms')).data||[];
  currentRoom=latest.find(x=>x.id===currentRoom.id)||currentRoom;
  const [devices,rows]=await Promise.all([roomDevices(currentRoom.id),fetchMessages(currentRoom.id)]);
  await renderMessages(currentRoom,rows);await renderSecurity(currentRoom,devices);await loadRooms();
}
async function selectRoom(id){
  currentRoom=rooms.find(x=>x.id===id)||null;if(!currentRoom)return;
  el('privateRoomTitle').textContent=currentRoom.display_name;setState('Decifrazione locale…');
  try{await loadCurrent();setState('Pronto')}catch(e){setState('Errore: '+(e?.message||String(e)))}
}
async function sendCurrent(){
  const ta=el('privateComposer'),text=(ta?.value||'').trim();if(!text||!currentRoom||!device)return;
  if(text.length>12000){setState('Messaggio troppo lungo (max 12.000 caratteri).');return}
  const send=el('privateSend');send.disabled=true;setState('Cifratura sul dispositivo…');
  try{
    const rr=await ctx.client.rpc('nexus_secure_list_rooms');if(rr.error)throw rr.error;
    const room=(rr.data||[]).find(x=>x.id===currentRoom.id);if(!room)throw new Error('Stanza non più disponibile');
    currentRoom=room;
    const devices=await roomDevices(room.id);if(!devices.length)throw new Error('Nessun dispositivo attivo nella stanza');
    const messageId=crypto.randomUUID(),aadv=aad(room.id,messageId,device.serverId,room.membership_version);
    const salt=crypto.getRandomValues(new Uint8Array(32)),payloadIv=crypto.getRandomValues(new Uint8Array(12));
    const contentKey=await crypto.subtle.generateKey({name:'AES-GCM',length:256},true,['encrypt','decrypt']);
    const rawContent=new Uint8Array(await crypto.subtle.exportKey('raw',contentKey));
    const cipher=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv:payloadIv,additionalData:aadv},contentKey,enc.encode(text)));
    const eph=await crypto.subtle.generateKey({name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);
    const ephPub=await crypto.subtle.exportKey('jwk',eph.publicKey);
    const keys=[];
    for(const d of devices){
      const wk=await deriveWrap(eph.privateKey,d.ecdh_public_jwk,salt,aadv),wiv=crypto.getRandomValues(new Uint8Array(12));
      const wrapped=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv:wiv,additionalData:aadv},wk,rawContent));
      keys.push({device_id:d.device_id,wrap_iv:b64(wiv),wrapped_key:b64(wrapped)});
    }
    const salt64=b64(salt),iv64=b64(payloadIv),cipher64=b64(cipher);
    const canon=canonical(room.id,messageId,device.serverId,room.membership_version,salt64,iv64,cipher64,ephPub);
    const signature=b64(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},device.signPrivate,canon));
    const r=await ctx.client.rpc('nexus_secure_send_envelope',{
      p_room_id:room.id,p_sender_device_id:device.serverId,p_client_message_id:messageId,p_membership_version:room.membership_version,
      p_payload_iv:iv64,p_salt:salt64,p_ephemeral_public_jwk:ephPub,p_ciphertext:cipher64,p_signature:signature,p_recipient_keys:keys
    });
    if(r.error)throw r.error;ta.value='';await loadCurrent();setState('Inviato · ciphertext salvato');
  }catch(e){setState('Invio fallito: '+(e?.message||String(e)))}finally{send.disabled=false}
}

async function openPrivate(){
  if(!(isOwner()||isBeta()))return;
  el('privateModal').classList.add('show');setState('Inizializzazione E2EE…');
  try{
    await ensureDevice();await cryptoSelfTest();if(!localCryptoOk)throw new Error('Web Crypto self-test fallito');
    await prepareRooms();await loadRooms();
    if(isOwner())el('privateOwnerTools').hidden=false;else el('privateOwnerTools').hidden=true;
    if(!currentRoom&&rooms.length)await selectRoom(rooms[0].id);else if(currentRoom)await loadCurrent();
    setState('NEXUS Private pronto');
    clearInterval(pollTimer);pollTimer=setInterval(()=>{if(el('privateModal')?.classList.contains('show')&&currentRoom)loadCurrent().catch(()=>{})},4000);
  }catch(e){setState('NEXUS Private non disponibile: '+(e?.message||String(e)))}
}
function closePrivate(){el('privateModal').classList.remove('show');clearInterval(pollTimer);pollTimer=null}
async function createDm(){
  const id=el('privateBetaSelect')?.value;if(!id)return;
  setState('Creazione privato…');const r=await ctx.client.rpc('nexus_secure_create_owner_beta_dm',{p_beta_user_id:id});
  if(r.error){setState('Errore: '+(r.error.message||r.error));return}await loadRooms();await selectRoom(Array.isArray(r.data)?r.data[0]:r.data);
}
async function syncGroup(){
  setState('Sincronizzazione membri Beta…');const r=await ctx.client.rpc('nexus_secure_sync_beta_group',{p_display_name:'Comitiva Beta'});
  if(r.error){setState('Errore: '+(r.error.message||r.error));return}await loadRooms();const id=Array.isArray(r.data)?r.data[0]:r.data;await selectRoom(id);
}

export function init(options){
  ctx=options;
  const btn=el('privateBtn');if(btn)btn.onclick=openPrivate;
  const close=el('closePrivate');if(close)close.onclick=closePrivate;
  const send=el('privateSend');if(send)send.onclick=sendCurrent;
  const sync=el('privateSyncGroup');if(sync)sync.onclick=syncGroup;
  const dm=el('privateCreateDm');if(dm)dm.onclick=createDm;
  const refresh=el('privateRefresh');if(refresh)refresh.onclick=()=>loadCurrent().catch(e=>setState('Errore: '+(e?.message||String(e))));
  const ta=el('privateComposer');if(ta)ta.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();sendCurrent()}});
  const modal=el('privateModal');if(modal)modal.onclick=e=>{if(e.target.id==='privateModal')closePrivate()};
}
export function applyAccess(){
  const a=ctx?.getAccess?.(),btn=el('privateBtn');if(btn)btn.hidden=!(a?.staff_role==='owner'||a?.staff_role==='beta_tester');
}
export function reset(){device=null;rooms=[];currentRoom=null;peerVerifiedRooms.clear();clearInterval(pollTimer);pollTimer=null;const btn=el('privateBtn');if(btn)btn.hidden=true}
