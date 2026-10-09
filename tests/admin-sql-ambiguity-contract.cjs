'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.resolve(__dirname,'../sql/20261010_admin_privilege_user_id_fix.sql'),'utf8');
for(const name of ['nexus_admin_set_beta','nexus_admin_set_unlimited']){
 assert.ok(source.includes('CREATE OR REPLACE FUNCTION public.'+name+'('),name+' exists');
}
const normalized=source.replaceAll(String.fromCharCode(13),'').replaceAll('\n',' ').replaceAll('\t',' ').replaceAll('  ',' ');
assert.ok(!normalized.includes('WHERE user_id=p_target'),'unqualified reference forbidden');
assert.ok(!normalized.includes('WHERE user_id = p_target'),'unqualified reference forbidden');
assert.ok(source.includes('WHERE sa.user_id=p_target'),'table-qualified user_id');
assert.ok(source.includes('ON CONFLICT ON CONSTRAINT nexus_staff_accounts_pkey'),'named unique constraint');
assert.ok(source.includes('SECURITY DEFINER'),'security context retained');
assert.ok(source.includes('nexus_is_owner(v_admin)'),'owner authorization retained');
assert.ok(source.includes('nexus_admin_audit'),'audit preserved');
assert.ok(source.includes('RETURN QUERY SELECT p_target'),'RPC return shape preserved');
console.log('NEXUS_ADMIN_SQL_AMBIGUITY_PASS');
