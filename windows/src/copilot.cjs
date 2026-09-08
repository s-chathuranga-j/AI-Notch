const {execFile} = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');

// Internal entitlement endpoint also used by VS Code. Never follow returned endpoints.
const USAGE_URL = 'https://api.github.com/copilot_internal/user';
const numeric = value => typeof value === 'number' && Number.isFinite(value);
function resetDate(value) {
  if (typeof value !== 'string' && !numeric(value)) return null;
  const date = new Date(typeof value === 'number' ? value * 1000 : value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}
function parseCopilot(data) {
  const reset = resetDate(data?.quota_reset_date_utc || data?.quota_reset_date || data?.limited_user_reset_date);
  return [['premium_interactions', data?.token_based_billing ? 'AI credits' : 'Premium requests'], ['chat', 'Chat'], ['completions', 'Completions']].flatMap(([key,label]) => {
    const quota = data?.quota_snapshots?.[key];
    if (!quota || typeof quota !== 'object') return [];
    const windowReset = resetDate(quota.quota_reset_at) || reset;
    if (quota.unlimited === true) return [{label, percent:null, unlimited:true, reset:windowReset}];
    if (quota.entitlement === 0 || quota.entitlement === '0') return [];
    let percent;
    if (numeric(quota.percent_remaining)) percent = 100 - Math.min(100,Math.max(0,quota.percent_remaining));
    else if (numeric(quota.entitlement) && quota.entitlement > 0 && numeric(quota.remaining) && quota.remaining >= 0) percent = Math.max(0,Math.min(100,100*(1-quota.remaining/quota.entitlement)));
    if (!numeric(percent)) return [];
    return [{label:quota.token_based_billing && key === 'premium_interactions' ? 'AI credits' : label, percent, reset:windowReset}];
  });
}
function githubExecutable() {
  const candidates = (process.env.PATH || '').split(path.delimiter).filter(Boolean).map(dir=>path.join(dir,'gh.exe'));
  if (process.env.ProgramFiles) candidates.push(path.join(process.env.ProgramFiles,'GitHub CLI','gh.exe'));
  return candidates.find(candidate=>{try{return fs.statSync(candidate).isFile();}catch{return false;}}) || 'gh.exe';
}
function readToken(signal) {
  if (signal.aborted) return Promise.reject(new Error('Cancelled'));
  if (process.env.COPILOT_GITHUB_TOKEN?.trim()) return Promise.resolve(process.env.COPILOT_GITHUB_TOKEN.trim());
  return new Promise((resolve,reject)=>{
    execFile(githubExecutable(),['auth','token','--hostname','github.com'],{windowsHide:true,timeout:10000,maxBuffer:16384,signal},(error,stdout)=>{
      // Never expose subprocess output/errors: they can contain authentication data.
      if(error || !stdout.trim()) return reject(new Error('Sign in with gh auth login on Windows, then Refresh. See Copilot setup in settings.'));
      resolve(stdout.trim());
    });
  });
}
async function copilot(_account, signal, dependencies = {}) {
  const token = await (dependencies.readToken || readToken)(signal);
  if (signal.aborted) throw new Error('Cancelled');
  let response;
  try {
    response = await (dependencies.fetch || fetch)(USAGE_URL,{
      headers:{Authorization:`Bearer ${token}`,Accept:'application/json','User-Agent':'AI-Notch-Windows'},
      redirect:'error',signal:AbortSignal.any([signal,AbortSignal.timeout(20000)])
    });
  } catch { throw new Error('Copilot connection failed or timed out. Refresh to try again.'); }
  if(response.status === 401 || response.status === 403) throw new Error('GitHub denied Copilot quota access. See Copilot setup in settings.');
  if(response.status === 404) throw new Error('Copilot quota endpoint unavailable for this account.');
  if(response.status === 429) throw new Error('Copilot rate limit. Refresh in a few minutes.');
  if(!response.ok) throw new Error(`Copilot unavailable (HTTP ${response.status}).`);
  let data;
  try { data = await response.json(); } catch { throw new Error('Copilot returned an unreadable response.'); }
  const windows = parseCopilot(data);
  if(!windows.length) throw new Error('GitHub returned no supported Copilot quotas for this account.');
  return windows;
}
module.exports = {parseCopilot,copilot};
