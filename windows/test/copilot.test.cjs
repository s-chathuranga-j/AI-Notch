const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parseCopilot,copilot}=require('../src/copilot.cjs');
const signal=()=>new AbortController().signal;
test('Copilot converts remaining percentages into used percentages and preserves unlimited quotas',()=>{
 const windows=parseCopilot({quota_reset_date_utc:'2026-10-01T00:00:00Z',quota_snapshots:{premium_interactions:{percent_remaining:75},chat:{unlimited:true},completions:{percent_remaining:100}}});
 assert.deepEqual(windows.map(w=>w.percent),[25,null,0]);
 assert.equal(windows[1].unlimited,true);
 assert.equal(windows[0].reset,'2026-10-01T00:00:00.000Z');
});
test('Copilot supports credit billing and per-quota reset timestamps',()=>{
 const windows=parseCopilot({token_based_billing:true,quota_snapshots:{premium_interactions:{percent_remaining:0,quota_reset_at:100,entitlement:'100'}}});
 assert.equal(windows[0].label,'AI credits');assert.equal(windows[0].percent,100);
 assert.equal(windows[0].reset,'1970-01-01T00:01:40.000Z');
});
test('Copilot rejects unknown and malformed quota data without inventing usage',()=>{
 for(const data of [null,{}, {quota_snapshots:{premium_interactions:{percent_remaining:'70'}}}, {quota_snapshots:{chat:{percent_remaining:NaN}}}, {quota_snapshots:{chat:{entitlement:0,percent_remaining:0}}}])assert.deepEqual(parseCopilot(data),[]);
 assert.equal(parseCopilot({quota_snapshots:{chat:{entitlement:100,remaining:25}},quota_reset_date:'invalid'})[0].percent,75);
 assert.equal(parseCopilot({quota_snapshots:{chat:{percent_remaining:50}},quota_reset_date:'invalid'})[0].reset,null);
});
test('Copilot sends credentials only to its fixed endpoint, rejects redirects, and returns sanitized usage',async()=>{
 const windows=await copilot({},signal(),{readToken:async()=> 'synthetic-secret',fetch:async(url,options)=>{
  assert.equal(url,'https://api.github.com/copilot_internal/user');assert.equal(options.redirect,'error');
  assert.equal(options.headers.Authorization,'Bearer synthetic-secret');
  return {ok:true,json:async()=>({token:'private',quota_snapshots:{chat:{percent_remaining:75}},endpoints:{api:'https://evil.example'}})};
 }});
 assert.deepEqual(windows,[{label:'Chat',percent:25,reset:null}]);
});
test('Copilot errors never include response bodies or raw network errors',async()=>{
 await assert.rejects(copilot({},signal(),{readToken:async()=> 'synthetic',fetch:async()=>{throw new Error('synthetic-secret');}}),error=>!error.message.includes('synthetic-secret'));
 await assert.rejects(copilot({},signal(),{readToken:async()=> 'synthetic',fetch:async()=>({status:403,ok:false,json:()=>{throw new Error('must not read body');}})}),/denied Copilot quota access/);
});
test('cancellation prevents a Copilot request after token lookup',async()=>{
 const controller=new AbortController();let called=false;
 await assert.rejects(copilot({},controller.signal,{readToken:async()=>{controller.abort();return 'synthetic';},fetch:async()=>{called=true;}}),/Cancelled/);
 assert.equal(called,false);
});
