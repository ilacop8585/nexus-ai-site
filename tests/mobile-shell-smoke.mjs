import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const html=readFileSync(root+'index.html','utf8');
const modes=['auto','chat','agent','work','code'];
let passed=0;
function check(label,fn){fn();passed++;console.log('PASS '+label)}

check('All five execution modes have real buttons',()=>{
  for(const m of modes)assert.ok(html.includes('data-nexus-mode="'+m+'"'),'missing '+m);
});
check('Mobile overrides the legacy Work display:none',()=>{
  const hidden=html.indexOf('.mode-switch button[data-nexus-mode="work"]{display:none}');
  const visible=html.lastIndexOf('.mode-switch button[data-nexus-mode="work"]{display:inline-flex!important');
  assert.ok(hidden>=0&&visible>hidden,'mobile Work must be restored after old media CSS');
});
check('Mobile switch supports five touch targets and horizontal scrolling',()=>{
  assert.match(html,/\.mode-switch\{display:flex;flex-wrap:nowrap;min-width:0;max-width:100%;overflow-x:auto/);
  assert.match(html,/min-width:44px;min-height:36px/);
});
check('Beta public disclosure has an accessible mobile details button',()=>{
  assert.ok(html.includes('id="betaReleaseStrip"'));
  assert.ok(html.includes('id="openBetaWelcome"'));
  assert.match(html,/\.beta-release-strip>button\{flex:0 0 auto;min-height:28px/);
  assert.match(html,/\.beta-release-strip>span\{display:none\}/);
});
check('Mobile beta modal allows scrolling on short screens',()=>{
  assert.match(html,/\.beta-welcome-card\{max-height:calc\(100dvh - 32px\);overflow-y:auto/);
});
console.log('NEXUS MOBILE UI SAFETY PASS '+passed+'/'+passed);
