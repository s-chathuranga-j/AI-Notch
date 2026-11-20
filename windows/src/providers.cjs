const fs = require('node:fs/promises');
const {copilot} = require('./copilot.cjs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const syncFS = require('node:fs');
const claudeReadingFile = 'ai-notch-usage-windows.json';
const CLAUDE_USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';
const claudeSetup = 'In AI Notch Settings, copy the Claude status line settings, then use Claude Code normally. If no usage appears after a response, check Claude\'s Usage page. Your account may not report limits to the status line.';

function claudeStatusLineSettings(account, settingsPath) {
  const quote = value => "'" + value.replace(/'/g, "''") + "'";
  const script = [
    '$settingsPath = ' + quote(settingsPath),
    '$profileId = ' + quote(account.id),
    '$readingPath = ' + quote(path.join(account.dir, claudeReadingFile)),
    syncFS.readFileSync(path.join(__dirname, 'claude-status-line.ps1'), 'utf8')
  ].join('\n');
  const encoded = Buffer.from(script, 'utf16le').toString('base64');
  return JSON.stringify({statusLine:{type:'command', command:'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + encoded}}, null, 2);
}
// Never throws: a missing, locked or malformed file just means no plan is known.
async function claudeOAuth(dir) {
  try {
    const text = (await fs.readFile(path.join(dir, '.credentials.json'), 'utf8')).replace(/^\uFEFF/, '');
    const oauth = JSON.parse(text)?.claudeAiOauth;
    return oauth && typeof oauth === 'object' ? oauth : null;
  } catch { return null; }
}
const isWorkPlan = oauth => ['enterprise','team'].includes(String(oauth?.subscriptionType || '').toLowerCase());
async function discover(home) {
  const entries=await fs.readdir(home,{withFileTypes:true}).catch(()=>[]);
  const defaultDir=path.join(home,'.claude');
  // The id stays 'claude' whatever the label, so saved settings, history and the status line profile still match.
  const claude=[{id:'claude',label:isWorkPlan(await claudeOAuth(defaultDir))?'Claude · Work':'Claude · Personal',kind:'claude',dir:defaultDir}];
  for(const e of entries) if(e.isDirectory() && /^\.claude-[a-zA-Z0-9_-]+$/.test(e.name)) {
    const dir=path.join(home,e.name);
    const files=await fs.readdir(dir).catch(()=>[]);
    if(!files.some(name=>['.credentials.json','settings.json','history.jsonl','projects'].includes(name))) continue;
    const name=e.name.slice(8);
    const work=isWorkPlan(await claudeOAuth(dir));
    claude.push({id:e.name.slice(1),label:`Claude · ${work&&/^(work|enterprise|team|\d+)$/i.test(name)?'Work':name}`,kind:'claude',dir});
  }
  // Two profiles must never share a label, or the rings and settings rows cannot be told apart.
  const seen=new Map();
  for(const account of claude){const key=account.label.toLowerCase();seen.set(key,(seen.get(key)||0)+1);}
  for(const account of claude) if(seen.get(account.label.toLowerCase())>1) account.label+=` (${path.basename(account.dir)})`;
  return [...claude,{id:'codex',label:'Codex',kind:'codex',dir:path.join(home,'.codex')},{id:'copilot',label:'GitHub Copilot',kind:'copilot'}];
}
// Returns null when there is no usable reading, so the caller can fall back to credits.
async function claudeStatusLine(account, signal) {
  let reading;
  try {
    reading = JSON.parse(await fs.readFile(path.join(account.dir, claudeReadingFile), {encoding:'utf8', signal}));
  } catch {
    if (signal?.aborted) throw new Error('Cancelled');
    return null;
  }
  const now = Date.now();
  const updated = reading?.observedAt;
  if (!Number.isFinite(updated) || updated <= 0 || updated > now) return null;

  const windows = [['five_hour','Session'],['seven_day','Weekly'],['spend_limit','Spend limit']].flatMap(([key,label]) => {
    const entry = reading[key];
    const percent = entry?.used_percentage;
    const reset = new Date(typeof entry?.resets_at === 'number' ? entry.resets_at * 1000 : NaN);
    if (!Number.isFinite(percent) || percent < 0 || (key !== 'spend_limit' && percent > 100) || !(reset.getTime() > updated)) return [];
    return [{label, percent, reset:reset.toISOString()}];
  });
  if (!windows.length) return null;
  const active = windows.filter(window => Date.parse(window.reset) > now);
  if (!active.length || now - updated > 15 * 60 * 1000) {
    return {status:'Waiting for updated usage from Claude Code.', windows, updated, stale:true};
  }
  return {status:'Updated', windows:active, updated};
}
function parseClaudeCredits(data) {
  const percent = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.min(100, value) : null;
  const spend = data?.spend, extra = data?.extra_usage;
  const used = (spend && spend.enabled !== false ? percent(spend.percent) : null)
    ?? (extra && extra.is_enabled !== false ? percent(extra.utilization) : null);
  return used === null ? [] : [{label:'Credits', percent:used, reset:null}];
}
async function claudeCredits(account, signal, dependencies) {
  const oauth = await claudeOAuth(account.dir);
  const token = typeof oauth?.accessToken === 'string' ? oauth.accessToken : '';
  if (!token) throw new Error(claudeSetup);
  let response;
  try {
    response = await (dependencies.fetch || fetch)(CLAUDE_USAGE_URL, {
      headers:{Authorization:`Bearer ${token}`,'anthropic-beta':'oauth-2025-04-20',Accept:'application/json','User-Agent':'AI-Notch-Windows'},
      redirect:'error', signal:AbortSignal.any([signal, AbortSignal.timeout(20000)])
    });
  } catch {
    if (signal.aborted) throw new Error('Cancelled');
    throw new Error('Claude connection failed or timed out. Refresh to try again.');
  }
  // Claude Code owns the login, so an expired or rejected token is never refreshed here.
  if (response.status === 401 || response.status === 403) throw new Error('Sign in again in Claude Code, then Refresh.');
  if (response.status === 429) throw new Error('Provider rate limit. Retry in a few minutes.');
  if (!response.ok) throw new Error(`Provider unavailable (HTTP ${response.status}).`);
  let data;
  try { data = await response.json(); } catch { throw new Error('Provider returned an unreadable response.'); }
  const windows = parseClaudeCredits(data);
  if (!windows.length) throw new Error(claudeSetup);
  return windows;
}
async function claude(account, signal, dependencies = {}) {
  return await claudeStatusLine(account, signal) ?? claudeCredits(account, signal, dependencies);
}
function parseCodex(result) {
  const rates=result?.rateLimits;
  return [['primary','Session'],['secondary','Weekly']].flatMap(([key,label])=>{
    const w=rates?.[key];
    if(typeof w?.usedPercent!=='number'||!Number.isFinite(w.usedPercent))return [];
    const date=typeof w.resetsAt==='number'&&w.resetsAt>0?new Date(w.resetsAt*1000):null;
    return [{label,percent:w.usedPercent,reset:date&&Number.isFinite(date.getTime())?date.toISOString():null}];
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
    child.stdout.on('error',()=>finish(new Error('Codex connection closed. Retry.')));
    child.stdout.on('data',chunk=>{
      buffer+=chunk.toString(); if(buffer.length>1024*1024)return finish(new Error('Unexpected Codex response.'));
      let n; while((n=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,n);buffer=buffer.slice(n+1);let message;try{message=JSON.parse(line);}catch{continue;}
        if(!message||typeof message!=='object')continue;
        if(message.id===1){child.stdin.write(JSON.stringify({method:'initialized'})+'\n');child.stdin.write(JSON.stringify({id:2,method:'account/rateLimits/read'})+'\n');}
        if(message.id===2){const windows=parseCodex(message.result);finish(windows.length?null:new Error('No subscription limits. Sign in to Codex with your subscription.'),windows);}
      }
    });
    child.stdin.write(JSON.stringify({id:1,method:'initialize',params:{clientInfo:{name:'ai_notch',version:'0.1.0'}}})+'\n');
  });
}
class Poller {
  constructor(fetcher,publish){this.fetcher=fetcher;this.publish=publish;this.jobs=new Map();this.enabled=new Set();this.last=new Map();}
  cancelPending(){for(const job of this.jobs.values())job.abort();this.jobs.clear();}
  // Disabling drops the cached reading with everything else, so it cannot reappear on re-enable.
  disable(id){this.enabled.delete(id);this.jobs.get(id)?.abort();this.jobs.delete(id);this.last.delete(id);this.publish(id,{status:'Disabled',windows:[]});}
  async refresh(account){if(!this.enabled.has(account.id)||this.jobs.has(account.id))return;const controller=new AbortController();this.jobs.set(account.id,controller);
    try{const result=await this.fetcher(account,controller.signal);if(this.jobs.get(account.id)===controller && this.enabled.has(account.id)){const row=Array.isArray(result)?{status:'Updated',windows:result,updated:Date.now()}:result;this.last.set(account.id,row);this.publish(account.id,row);}}
    catch(error){if(!controller.signal.aborted && this.jobs.get(account.id)===controller){
      // A failed refresh keeps the last reading rather than blanking it. The row is marked stale so
      // the frame can say the number is old; a reading was never invented for an account that has none.
      const cached=this.last.get(account.id);
      this.publish(account.id,cached&&cached.windows.length?{...cached,status:error.message,stale:true}:{status:error.message,windows:[]});
    }}
    finally{if(this.jobs.get(account.id)===controller)this.jobs.delete(account.id);}
  }
}
module.exports={claude,parseClaudeCredits,claudeStatusLineSettings,claudeReadingFile,parseCodex,discover,Poller,fetchUsage:(account,signal)=>account.kind==='claude'?claude(account,signal):account.kind==='codex'?codex(account,signal):account.kind==='copilot'?copilot(account,signal):Promise.reject(new Error('Unsupported provider.'))};
