const fs = require('node:fs/promises');
const {copilot} = require('./copilot.cjs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const syncFS = require('node:fs');
const claudeReadingFile = 'ai-notch-usage-windows.json';
const claudeSetup = 'In AI Notch Settings, copy the Claude status line settings, then use Claude Code normally.';

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
async function discover(home) {
  const entries=await fs.readdir(home,{withFileTypes:true}).catch(()=>[]);
  const claude=[{id:'claude',label:'Claude · Personal',kind:'claude',dir:path.join(home,'.claude')}];
  for(const e of entries) if(e.isDirectory() && /^\.claude-[a-zA-Z0-9_-]+$/.test(e.name)) {
    const dir=path.join(home,e.name);
    const files=await fs.readdir(dir).catch(()=>[]);
    if(files.some(name=>['.credentials.json','settings.json','history.jsonl','projects'].includes(name))) claude.push({id:e.name.slice(1),label:`Claude · ${e.name.slice(8)}`,kind:'claude',dir});
  }
  return [...claude,{id:'codex',label:'Codex',kind:'codex',dir:path.join(home,'.codex')},{id:'copilot',label:'GitHub Copilot',kind:'copilot'}];
}
async function claude(account, signal) {
  let reading;
  try {
    reading = JSON.parse(await fs.readFile(path.join(account.dir, claudeReadingFile), {encoding:'utf8', signal}));
  } catch {
    throw new Error(claudeSetup);
  }
  const now = Date.now();
  const updated = reading?.observedAt;
  if (!Number.isFinite(updated) || updated <= 0 || updated > now) throw new Error(claudeSetup);

  const windows = [['five_hour','Session'],['seven_day','Weekly']].flatMap(([key,label]) => {
    const entry = reading[key];
    const percent = entry?.used_percentage;
    const reset = new Date(typeof entry?.resets_at === 'number' ? entry.resets_at * 1000 : NaN);
    if (!Number.isFinite(percent) || percent < 0 || percent > 100 || !(reset.getTime() > updated)) return [];
    return [{label, percent, reset:reset.toISOString()}];
  });
  if (!windows.length) throw new Error(claudeSetup);
  const active = windows.filter(window => Date.parse(window.reset) > now);
  if (!active.length || now - updated > 15 * 60 * 1000) {
    return {status:'Waiting for updated usage from Claude Code.', windows, updated, stale:true};
  }
  return {status:'Updated', windows:active, updated};
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
module.exports={claudeStatusLineSettings,claudeReadingFile,parseCodex,discover,Poller,fetchUsage:(account,signal)=>account.kind==='claude'?claude(account,signal):account.kind==='codex'?codex(account,signal):account.kind==='copilot'?copilot(account,signal):Promise.reject(new Error('Unsupported provider.'))};
