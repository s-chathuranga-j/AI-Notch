const fs = require('node:fs/promises');
const {copilot} = require('./copilot.cjs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const syncFS = require('node:fs');
const hosts = new Set(['api.anthropic.com']);
const claudeLabels={session:'Session',weekly_all:'Weekly',weekly_opus:'Opus',weekly_sonnet:'Sonnet'};
function claudeLabel(kind){return claudeLabels[kind] || kind.replace(/^weekly_/,'').replace(/_/g,' ').replace(/^./,c=>c.toUpperCase());}
// Session first, then the all-model week, then everything else - the order the notch reads in.
function claudeRank(id){return id==='session'?0:id==='weekly_all'?1:id==='credits'?3:2;}
function parseClaude(data) {
  const windows=[]; const seen=new Set();
  const add=(id,label,percent,reset)=>{
    if(seen.has(id) || typeof percent!=='number' || !Number.isFinite(percent)) return;
    seen.add(id); windows.push({id,label,percent,reset:reset || null});
  };
  // `limits` grows new kinds as Anthropic adds them, so it is preferred over the named windows.
  for(const limit of Array.isArray(data?.limits)?data.limits:[]) if(limit && typeof limit.kind==='string') add(limit.kind,claudeLabel(limit.kind),limit.percent,limit.resets_at);
  // The named windows are merged in rather than used only as a fallback: an entry leaves
  // `limits` once its reset passes, while `five_hour` still carries it.
  add('session','Session',data?.five_hour?.utilization,data?.five_hour?.resets_at);
  add('weekly_all','Weekly',data?.seven_day?.utilization,data?.seven_day?.resets_at);
  // Plans billed on credits rather than rate-limit windows report only their spend.
  const extra=data?.extra_usage;
  if(extra && extra.is_enabled!==false) add('credits','Credits',extra.utilization,null);
  if(data?.spend?.enabled!==false) add('credits','Credits',data?.spend?.percent,null);
  return windows.sort((a,b)=>claudeRank(a.id)-claudeRank(b.id) || (a.id<b.id?-1:a.id>b.id?1:0)).map(({id,...w})=>w);
}
async function request(url,token,signal) {
  const u=new URL(url);
  if(u.protocol!=='https:' || !hosts.has(u.hostname) || u.username || u.password || (u.port && u.port!=='443')) throw new Error('Blocked destination');
  const r=await fetch(u,{headers:{Authorization:`Bearer ${token}`,'anthropic-beta':'oauth-2025-04-20'},redirect:'error',signal:AbortSignal.any([signal,AbortSignal.timeout(20000)])});
  if(r.status===401 || r.status===403) throw new Error('Sign in again in Claude Code, then Retry.');
  if(r.status===429) throw new Error('Provider rate limit. Retry in a few minutes.');
  if(!r.ok) throw new Error(`Provider unavailable (HTTP ${r.status}).`);
  try { return await r.json(); } catch { throw new Error("Provider returned an unreadable response."); }
}
async function discover(home) {
  const entries=await fs.readdir(home,{withFileTypes:true});
  const claude=[{id:'claude',label:'Claude · Personal',kind:'claude',dir:path.join(home,'.claude')}];
  for(const e of entries) if(e.isDirectory() && /^\.claude-[a-zA-Z0-9_-]+$/.test(e.name)) {
    const dir=path.join(home,e.name);
    if(await fs.access(path.join(dir,'.credentials.json')).then(()=>true,()=>false)) claude.push({id:e.name.slice(1),label:`Claude · ${e.name.slice(8)}`,kind:'claude',dir});
  }
  return [...claude,{id:'codex',label:'Codex',kind:'codex',dir:path.join(home,'.codex')},{id:'copilot',label:'GitHub Copilot',kind:'copilot'}];
}
async function claude(account,signal) {
  let credentials;
  try {
    const stored=JSON.parse((await fs.readFile(path.join(account.dir,'.credentials.json'),'utf8')).replace(/^\uFEFF/,''));
    credentials=stored.claudeAiOauth || stored.oauthAccount || stored;
  } catch { throw new Error(`Claude credentials not found in ${path.basename(account.dir)}. Run claude /login, then Retry.`); }
  if(!credentials?.accessToken) throw new Error('No Claude Code subscription login found. Run claude /login.');
  // Some Windows Claude Code releases write expiresAt as 0 or omit it after
  // rotation. Let Anthropic validate the token instead of rejecting it here.
  if(Number(credentials.expiresAt)>0 && Number(credentials.expiresAt)<=Date.now()) throw new Error('Claude login expired. Run /login in Claude Code, then Retry.');
  const windows=parseClaude(await request('https://api.anthropic.com/api/oauth/usage',credentials.accessToken,signal));
  if(!windows.length) throw new Error('Claude returned no usage windows.');
  return windows;
}
function parseCodex(result) {
  const rates=result?.rateLimits;
  return [['primary','Session'],['secondary','Weekly']].flatMap(([key,label])=>{
    const w=rates?.[key]; return typeof w?.usedPercent==='number' && Number.isFinite(w.usedPercent) ? [{label,percent:w.usedPercent,reset:w.resetsAt?new Date(w.resetsAt*1000).toISOString():null}]:[];
  });
}
function codexExecutable() {
  const dirs=(process.env.PATH||'').split(path.delimiter).filter(Boolean);
  if(process.env.APPDATA) dirs.push(path.join(process.env.APPDATA,'npm'));
  const triple=process.arch==='arm64'?'aarch64-pc-windows-msvc':'x86_64-pc-windows-msvc';
  const platformPackage=process.arch==='arm64'?'codex-win32-arm64':'codex-win32-x64';
  for(const dir of dirs) for(const candidate of [path.join(dir,'codex.exe'),path.join(dir,'node_modules','@openai','codex','vendor',triple,'codex','codex.exe'),path.join(dir,'node_modules','@openai',platformPackage,'vendor',triple,'codex','codex.exe'),path.join(dir,'node_modules','@openai','codex','node_modules','@openai',platformPackage,'vendor',triple,'codex','codex.exe')]) {
    try{if(syncFS.statSync(candidate).isFile())return candidate;}catch{}
  }
  return 'codex';
}
function codex(account,signal) {
  return new Promise((resolve,reject)=>{
    if(signal.aborted) return reject(new Error('Cancelled'));
    // No shell, no credential arguments, and no stderr retained.
    const child=spawn(codexExecutable(),['app-server'],{windowsHide:true,stdio:['pipe','pipe','ignore'],env:{...process.env,CODEX_HOME:account.dir}});
    let buffer='',done=false;
    const finish=(error,value)=>{if(done)return;done=true;clearTimeout(timer);signal.removeEventListener('abort',abort);child.kill();error?reject(error):resolve(value);};
    const abort=()=>finish(new Error('Cancelled'));
    const timer=setTimeout(()=>finish(new Error('Codex timed out. Open Codex and sign in, then Retry.')),20000);
    signal.addEventListener('abort',abort,{once:true});
    child.on('error',()=>finish(new Error('Codex CLI not found. Install Codex CLI and sign in.')));
    child.on('exit',()=>finish(new Error('Codex closed before returning usage.')));
    child.stdin.on('error',()=>{});
    child.stdout.on('data',chunk=>{
      buffer+=chunk.toString(); if(buffer.length>1024*1024)return finish(new Error('Unexpected Codex response.'));
      let n; while((n=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,n);buffer=buffer.slice(n+1);let message;try{message=JSON.parse(line);}catch{continue;}
        if(message.id===1){child.stdin.write(JSON.stringify({method:'initialized'})+'\n');child.stdin.write(JSON.stringify({id:2,method:'account/rateLimits/read'})+'\n');}
        if(message.id===2){const windows=parseCodex(message.result);finish(windows.length?null:new Error('No subscription limits. Sign in to Codex with your subscription.'),windows);}
      }
    });
    child.stdin.write(JSON.stringify({id:1,method:'initialize',params:{clientInfo:{name:'ai_notch',version:'0.1.0'}}})+'\n');
  });
}
class Poller {
  constructor(fetcher,publish){this.fetcher=fetcher;this.publish=publish;this.jobs=new Map();this.enabled=new Set();this.last=new Map();}
  // Disabling drops the cached reading with everything else, so it cannot reappear on re-enable.
  disable(id){this.enabled.delete(id);this.jobs.get(id)?.abort();this.jobs.delete(id);this.last.delete(id);this.publish(id,{status:'Disabled',windows:[]});}
  async refresh(account){if(!this.enabled.has(account.id)||this.jobs.has(account.id))return;const controller=new AbortController();this.jobs.set(account.id,controller);
    try{const windows=await this.fetcher(account,controller.signal);if(this.jobs.get(account.id)===controller && this.enabled.has(account.id)){const row={status:'Updated',windows,updated:Date.now()};this.last.set(account.id,row);this.publish(account.id,row);}}
    catch(error){if(!controller.signal.aborted && this.jobs.get(account.id)===controller){
      // A failed refresh keeps the last reading rather than blanking it. The row is marked stale so
      // the frame can say the number is old; a reading was never invented for an account that has none.
      const cached=this.last.get(account.id);
      this.publish(account.id,cached&&cached.windows.length?{...cached,status:error.message,stale:true}:{status:error.message,windows:[]});
    }}
    finally{if(this.jobs.get(account.id)===controller)this.jobs.delete(account.id);}
  }
}
module.exports={parseClaude,parseCodex,discover,request,Poller,fetchUsage:(account,signal)=>account.kind==='claude'?claude(account,signal):account.kind==='codex'?codex(account,signal):account.kind==='copilot'?copilot(account,signal):Promise.reject(new Error('Unsupported provider.'))};
