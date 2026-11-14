const {test}=require('node:test');const assert=require('node:assert/strict');const {Poller,parseCodex,discover}=require('../src/providers.cjs');const fs=require('node:fs/promises');const os=require('node:os');const path=require('node:path');
test('Codex parses the reset timestamp',()=>{assert.equal(parseCodex({rateLimits:{primary:{usedPercent:42,resetsAt:100}}})[0].reset,'1970-01-01T00:01:40.000Z');});
test('disabled accounts never fetch, and late results cannot restore disabled data',async()=>{let resolve,calls=0;const rows=[];const p=new Poller(()=>{calls++;return new Promise(r=>resolve=r);},(id,row)=>rows.push(row));const account={id:'a'};await p.refresh(account);assert.equal(calls,0);p.enabled.add('a');const work=p.refresh(account);p.disable('a');resolve([{percent:99}]);await work;assert.deepEqual(rows,[{status:'Disabled',windows:[]}]);});
test('old request cannot overwrite a re-enabled account',async()=>{const promises=[];let last;const p=new Poller(()=>new Promise(resolve=>promises.push(resolve)),(_id,row)=>last=row);p.enabled.add('a');const old=p.refresh({id:'a'});p.disable('a');p.enabled.add('a');const fresh=p.refresh({id:'a'});promises[1]([{percent:20}]);await fresh;promises[0]([{percent:90}]);await old;assert.equal(last.windows[0].percent,20);});
test('initialized profiles retain separate paths',async()=>{const home=await fs.mkdtemp(path.join(os.tmpdir(),'notch-test-'));try{await fs.mkdir(path.join(home,'.claude-work'));await fs.mkdir(path.join(home,'.claude-mem'));await fs.writeFile(path.join(home,'.claude-work','settings.json'),'{}');const accounts=await discover(home);assert.deepEqual(accounts.map(a=>a.id),['claude','claude-work','codex','copilot']);assert.equal(accounts[1].dir,path.join(home,'.claude-work'));}finally{await fs.rm(home,{recursive:true});}});
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
test('an unavailable home directory does not prevent the default accounts from starting',async()=>{
 const home=path.join(os.tmpdir(),'ainotch-missing-home-'+require('node:crypto').randomUUID());
 const accounts=await discover(home);
 assert.deepEqual(accounts.map(a=>a.id),['claude','codex','copilot']);
});
test('sleep cancels old work while preserving opt-in and allowing an immediate fresh request',async()=>{
 const work=[];const rows=[];
 const p=new Poller((_a,signal)=>new Promise(resolve=>work.push({resolve,signal})),(_id,row)=>rows.push(row));
 p.enabled.add('a');const old=p.refresh({id:'a'});p.cancelPending();
 assert.equal(work[0].signal.aborted,true);assert.equal(p.enabled.has('a'),true);
 const fresh=p.refresh({id:'a'});work[1].resolve([{percent:20}]);await fresh;
 work[0].resolve([{percent:90}]);await old;
 assert.equal(rows.at(-1).windows[0].percent,20);
});
test('notch shape and startup controls keep the strict renderer CSP without inline code or styles',async()=>{
 const html=await fs.readFile(require.resolve('../src/index.html'),'utf8');
 assert.match(html,/script-src 'self'; style-src 'self'/);
 assert.ok(!html.includes('unsafe-inline'));
 assert.doesNotMatch(html,/\s(?:style|on\w+)=/i);
});
