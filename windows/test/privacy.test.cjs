const {test}=require('node:test');const assert=require('node:assert/strict');const {Poller,parseClaude,parseCodex,request,discover}=require('../src/providers.cjs');const fs=require('node:fs/promises');const os=require('node:os');const path=require('node:path');
test('zero usage is a reading and malformed percentages are ignored',()=>{assert.equal(parseClaude({five_hour:{utilization:0}})[0].percent,0);assert.deepEqual(parseClaude({five_hour:{utilization:'70'}}),[]);assert.equal(parseCodex({rateLimits:{primary:{usedPercent:42,resetsAt:100}}})[0].reset,'1970-01-01T00:01:40.000Z');});
test('disabled accounts never fetch, and late results cannot restore disabled data',async()=>{let resolve,calls=0;const rows=[];const p=new Poller(()=>{calls++;return new Promise(r=>resolve=r);},(id,row)=>rows.push(row));const account={id:'a'};await p.refresh(account);assert.equal(calls,0);p.enabled.add('a');const work=p.refresh(account);p.disable('a');resolve([{percent:99}]);await work;assert.deepEqual(rows,[{status:'Disabled',windows:[]}]);});
test('old request cannot overwrite a re-enabled account',async()=>{const promises=[];let last;const p=new Poller(()=>new Promise(resolve=>promises.push(resolve)),(_id,row)=>last=row);p.enabled.add('a');const old=p.refresh({id:'a'});p.disable('a');p.enabled.add('a');const fresh=p.refresh({id:'a'});promises[1]([{percent:20}]);await fresh;promises[0]([{percent:90}]);await old;assert.equal(last.windows[0].percent,20);});
test('credential requests reject other destinations before fetch',async()=>{for(const url of ['http://api.anthropic.com/api/oauth/usage','https://evil.example','https://api.anthropic.com.evil.example','https://api.anthropic.com:8443','https://user@api.anthropic.com'])await assert.rejects(request(url,'synthetic',new AbortController().signal),/Blocked destination/);});
test('profiles require credential files and retain separate paths',async()=>{const home=await fs.mkdtemp(path.join(os.tmpdir(),'notch-test-'));try{await fs.mkdir(path.join(home,'.claude-work'));await fs.mkdir(path.join(home,'.claude-mem'));await fs.writeFile(path.join(home,'.claude-work','.credentials.json'),'{}');const accounts=await discover(home);assert.deepEqual(accounts.map(a=>a.id),['claude','claude-work','codex','copilot']);assert.equal(accounts[1].dir,path.join(home,'.claude-work'));}finally{await fs.rm(home,{recursive:true});}});
test('a failed refresh keeps the last reading and marks it stale, and disabling drops it',async()=>{
 let next;const rows=[];
 const p=new Poller(()=>next(),(id,row)=>rows.push(row));p.enabled.add('a');
 next=()=>Promise.resolve([{label:'Credits',percent:36,reset:null}]);await p.refresh({id:'a'});
 assert.equal(rows.at(-1).status,'Updated');assert.equal(rows.at(-1).stale,undefined);
 next=()=>Promise.reject(new Error('Provider rate limit. Retry in a few minutes.'));await p.refresh({id:'a'});
 assert.equal(rows.at(-1).status,'Provider rate limit. Retry in a few minutes.');
 assert.equal(rows.at(-1).stale,true);assert.equal(rows.at(-1).windows[0].percent,36);
 assert.ok(rows.at(-1).updated>0,'the stale row keeps the time of the reading it shows');
 p.disable('a');assert.deepEqual(rows.at(-1),{status:'Disabled',windows:[]});
 p.enabled.add('a');await p.refresh({id:'a'});
 assert.deepEqual(rows.at(-1),{status:'Provider rate limit. Retry in a few minutes.',windows:[]},'a disabled account cannot resurrect its cached reading');
});
test('an account that never had a reading reports the failure without inventing one',async()=>{
 const rows=[];const p=new Poller(()=>Promise.reject(new Error('Sign in again in Claude Code, then Retry.')),(id,row)=>rows.push(row));
 p.enabled.add('a');await p.refresh({id:'a'});
 assert.deepEqual(rows.at(-1),{status:'Sign in again in Claude Code, then Retry.',windows:[]});
});
