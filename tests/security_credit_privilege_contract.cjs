// NEXUS Word red-team regressions: bounded offline code-contract tests.
// These are not live authenticated attack results. No network, credentials, or charges.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
let total=0;
function check(label,passed){
 assert.ok(passed,label);total++;console.log('PASS '+label);
}
function fn(sql,name){
 const escaped=name.replace(/[.*+?^$\{\}()|[\]\\]/g,'\\$&');
 const regex=new RegExp('(?:create|CREATE)\\s+(?:or\\s+replace\\s+|OR\\s+REPLACE\\s+)?(?:function|FUNCTION)\\s+public\\.'+escaped+'\\s*\\(');
 const match=regex.exec(sql);assert.ok(match,name+' function defined');
 const rest=sql.slice(match.index+match[0].length);
 const stop=rest.search(/\$function\$\s*;|\$\$\s*;/i);
 assert.ok(stop>=0,name+' function closes');
 return rest.slice(0,stop);
}
const admin=read('sql/20261006_beta_admin.sql');
const fixed=read('sql/20261010_admin_privilege_user_id_fix.sql');
for(const name of ['nexus_admin_grant_credits','nexus_admin_set_beta','nexus_admin_set_unlimited','nexus_admin_set_display_name']){
 const body=fn(name==='nexus_admin_set_beta'||name==='nexus_admin_set_unlimited'?fixed:admin,name);
 check(name+' calls server owner check',/auth\.user_id\(\)/i.test(body)&&/nexus_is_owner\(v_admin\)/i.test(body));
}
check('credit grant amount server bounded',/p_amount\s*<\s*1\s+or\s+p_amount\s*>\s*1000000/i.test(fn(admin,'nexus_admin_grant_credits')));
const text=read('sql/20261008_text_task_credit_guard.sql');
const file=read('sql/20261008_file_job_credit_guard.sql');
for(const [name,sql] of [['text',text],['file',file]]){
 check(name+' checked task derives caller from Auth',/v_user\s*:?=\s*\(auth\.user_id\(\)\)::uuid/i.test(sql));
 check(name+' checked task determines QA status on server',/nexus_is_internal_qa\(v_user\)/i.test(sql));
 check(name+' checked task rejects unapproved price',/p_approved_credits\s+IS\s+DISTINCT\s+FROM\s+v_quote/i.test(sql));
 check(name+' checked task revokes generic execution',/REVOKE\s+ALL\s+ON\s+FUNCTION[\s\S]+FROM\s+PUBLIC/i.test(sql));
}
const local=read('sql/20261006_chat_local_fallback.sql');
check('local chat determines free/deep from server',/v_level\s*:=\s*case\s+when\s+v_unlimited\s+then\s+'deep'\s+else\s+'free'/i.test(local));
check('local chat bounds jobs per account',/chat_local_active_limit_2/.test(local)&&/chat_local_daily_limit/.test(local));
const html=read('index.html');
check('visitor model messages rendered using textContent',/function addMsg\([\s\S]{0,400}body\.textContent=t/.test(html));
check('only checked task RPCs used by browser',html.includes("client.rpc('nexus_create_text_task_checked'")&&html.includes("client.rpc('nexus_create_job_checked'"));
const hardening=read('sql/20261022_restrict_internal_beta_rpc.sql');
check('internal Beta observer RPC permission migration staged',hardening.includes('REVOKE ALL ON FUNCTION public.nexus_beta_observation_enqueue_internal(uuid) FROM PUBLIC'));
check('internal Beta ticket RPC permission migration staged',hardening.includes('REVOKE ALL ON FUNCTION public.nexus_beta_create_ticket_from_observation_internal(uuid,jsonb) FROM PUBLIC'));
console.log('NEXUS_REDTEAM_STATIC_CONTRACT_PASS '+total+'/'+total);
