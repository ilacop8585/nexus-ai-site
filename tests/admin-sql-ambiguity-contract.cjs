'use strict';
// Prevent recurrence of PL/pgSQL RETURNS TABLE(user_id...) shadowing a column.
// This is a static contract gate; runtime authentication/RPC is exercised separately.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.resolve(__dirname,'../sql/20261010_admin_privilege_user_id_fix.sql'),'utf8');
for(const name of ['nexus_admin_set_beta','nexus_admin_set_unlimited']){
 const rx=new RegExp('CREATE OR REPLACE FUNCTION public\\.'+name+'\\(','i');
 assert.match(source,rx,name+' function present');
}
assert.doesNotMatch(source,/\\bWHERE\\s+user_id\\s*=\\s*p_target\\b/i,'ambiguous function-output user_id');
assert.match(source,/WHERE sa\\.user_id\\s*=\\s*p_target/i,'qualified user_id predicate');
assert.match(source,/ON CONFLICT ON CONSTRAINT nexus_staff_accounts_pkey/,'unique conflict target');
assert.match(source,/SECURITY DEFINER/,'security contract retained');
assert.match(source,/nexus_is_owner\\(v_admin\\)/,'owner-only gate retained');
assert.match(source,/INSERT INTO public\\.nexus_admin_audit/g,'audit maintained');
assert.match(source,/RETURN QUERY SELECT p_target/,'RPC shape retained');
console.log('NEXUS_ADMIN_SQL_AMBIGUITY_PASS');
