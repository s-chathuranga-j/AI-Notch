const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const {claude,parseClaudeCredits,discover,claudeStatusLineSettings,claudeReadingFile,fetchUsage,Poller}=require('../src/providers.cjs');

test('Claude polls local usage and keeps the original timestamp when it goes stale',async t=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'ainotch-claude-'));
  t.after(()=>fs.rm(dir,{recursive:true,force:true}));
  const account={id:'claude-work',kind:'claude',dir};
  const file=path.join(dir,claudeReadingFile);
  let row;
  const poller=new Poller(fetchUsage,(_id,value)=>{row=value;});
  poller.enabled.add(account.id);
  await poller.refresh(account);
  assert.match(row.status,/copy the Claude status line/);

  const observedAt=Date.now()-1000;
  const reset=Math.floor(observedAt/1000)+3600;
  const reading={observedAt,five_hour:{used_percentage:0,resets_at:reset},seven_day:{used_percentage:55.5,resets_at:reset}};
  await fs.writeFile(file,JSON.stringify(reading));
  await poller.refresh(account);
  assert.equal(row.updated,observedAt);
  assert.deepEqual(row.windows.map(w=>w.percent),[0,55.5]);
  assert.equal(row.stale,undefined);

  reading.observedAt-=16*60*1000;
  await fs.writeFile(file,JSON.stringify(reading));
  await poller.refresh(account);
  assert.equal(row.stale,true);
  assert.equal(row.updated,reading.observedAt);

  reading.observedAt=Date.now()-1000;
  reading.five_hour.resets_at=reading.observedAt/1000+0.5;
  await fs.writeFile(file,JSON.stringify(reading));
  await poller.refresh(account);
  assert.deepEqual(row.windows.map(w=>w.label),['Weekly']);
});

test('Claude setup quotes profile paths and passes PowerShell a shell-safe argument',()=>{
  const dir="C:/Users/O'Neil/.claude-work";
  const data=JSON.parse(claudeStatusLineSettings({id:'claude-work',dir},'C:/AI Notch/settings.json'));
  const encoded=data.statusLine.command.match(/^powershell\.exe -NoProfile -NonInteractive -EncodedCommand ([A-Za-z0-9+/=]+)$/)[1];
  const script=Buffer.from(encoded,'base64').toString('utf16le');
  assert.ok(script.includes("$settingsPath = 'C:/AI Notch/settings.json'"));
  const readingPath=path.join("C:/Users/O''Neil/.claude-work",'ai-notch-usage-windows.json');
  assert.ok(script.includes(`$readingPath = '${readingPath}'`));
  assert.ok(script.includes("$profileId = 'claude-work'"));
  assert.ok(script.includes("@('five_hour', 'seven_day', 'spend_limit')"));
});

test('Claude shows a spend-only reading, including zero, overages, and expired limits',async t=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'ainotch-spend-'));
  t.after(()=>fs.rm(dir,{recursive:true,force:true}));
  const account={id:'claude-work',kind:'claude',dir};
  const signal=new AbortController().signal;
  const observedAt=Date.now()-2000;
  const resets_at=Math.floor(observedAt/1000)+3600;
  const reading={observedAt,spend_limit:{used_percentage:0,resets_at}};
  const file=path.join(dir,claudeReadingFile);

  await fs.writeFile(file,JSON.stringify(reading));
  const fresh=await fetchUsage(account,signal);
  assert.deepEqual(fresh.windows,[{label:'Spend limit',percent:0,reset:new Date(resets_at*1000).toISOString()}]);
  assert.equal(fresh.updated,observedAt);

  reading.spend_limit.used_percentage=125;
  await fs.writeFile(file,JSON.stringify(reading));
  assert.equal((await fetchUsage(account,signal)).windows[0].percent,125);

  reading.spend_limit.resets_at=Math.floor(observedAt/1000)+1;
  await fs.writeFile(file,JSON.stringify(reading));
  assert.equal((await fetchUsage(account,signal)).stale,true);
});

const credentials=(plan,token='synthetic-token')=>'﻿'+JSON.stringify({claudeAiOauth:{accessToken:token,subscriptionType:plan,rateLimitTier:'synthetic'}});
const enterpriseUsage={five_hour:null,seven_day:null,limits:[],extra_usage:{is_enabled:true,monthly_limit:10000,used_credits:2500,utilization:25,currency:'USD'},spend:{used:{amount_minor:2500,exponent:2,currency:'USD'},limit:{amount_minor:10000,exponent:2,currency:'USD'},percent:25,severity:'ok',enabled:true}};
async function tempAccount(t,files={}){
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'ainotch-credits-'));
  t.after(()=>fs.rm(dir,{recursive:true,force:true}));
  for(const [name,body] of Object.entries(files))await fs.writeFile(path.join(dir,name),body);
  return {id:'claude',kind:'claude',dir};
}
const respond=(status,body)=>async()=>({status,ok:status>=200&&status<300,json:async()=>typeof body==='string'?JSON.parse(body):body});

test('credits come from spend, else extra_usage, capped and validated',()=>{
  assert.deepEqual(parseClaudeCredits({spend:{percent:25,enabled:true}}),[{label:'Credits',percent:25,reset:null}]);
  assert.deepEqual(parseClaudeCredits({extra_usage:{utilization:40.5,is_enabled:true}}),[{label:'Credits',percent:40.5,reset:null}]);
  assert.deepEqual(parseClaudeCredits({spend:{percent:10,enabled:false},extra_usage:{utilization:60}}),[{label:'Credits',percent:60,reset:null}]);
  assert.deepEqual(parseClaudeCredits({spend:{percent:10,enabled:false},extra_usage:{utilization:60,is_enabled:false}}),[]);
  assert.equal(parseClaudeCredits({spend:{percent:140}})[0].percent,100);
  assert.deepEqual(parseClaudeCredits({spend:{percent:-5}}),[]);
  assert.deepEqual(parseClaudeCredits({spend:{percent:'25'},extra_usage:{utilization:NaN}}),[]);
  assert.deepEqual(parseClaudeCredits(null),[]);
});

test('Claude falls back to credits when there is no status line reading',async t=>{
  const account=await tempAccount(t,{'.credentials.json':credentials('enterprise')});
  let request;
  const result=await claude(account,new AbortController().signal,{fetch:async(url,options)=>{request={url,options};return respond(200,enterpriseUsage)();}});
  assert.deepEqual(result,[{label:'Credits',percent:25,reset:null}]);
  assert.equal(request.url,'https://api.anthropic.com/api/oauth/usage');
  assert.equal(request.options.headers.Authorization,'Bearer synthetic-token');
  assert.equal(request.options.headers['anthropic-beta'],'oauth-2025-04-20');
  assert.equal(request.options.redirect,'error');
});

test('a status line reading still wins over credits',async t=>{
  const observedAt=Date.now()-1000,reset=Math.floor(observedAt/1000)+3600;
  const account=await tempAccount(t,{'.credentials.json':credentials('enterprise'),[claudeReadingFile]:JSON.stringify({observedAt,five_hour:{used_percentage:12,resets_at:reset}})});
  const row=await claude(account,new AbortController().signal,{fetch:async()=>{throw new Error('must not be called');}});
  assert.deepEqual(row.windows.map(w=>[w.label,w.percent]),[['Session',12]]);
});

test('credits requests explain failures without exposing the token',async t=>{
  const account=await tempAccount(t,{'.credentials.json':credentials('enterprise','secret-synthetic')});
  const signal=new AbortController().signal;
  for(const [status,message] of [[401,/Sign in again in Claude Code/],[403,/Sign in again/],[429,/rate limit/],[500,/HTTP 500/]]){
    await assert.rejects(claude(account,signal,{fetch:respond(status,{})}),error=>message.test(error.message)&&!error.message.includes('secret'));
  }
  await assert.rejects(claude(account,signal,{fetch:respond(200,'not json')}),/unreadable response/);
  await assert.rejects(claude(account,signal,{fetch:respond(200,{limits:[]})}),/copy the Claude status line/);
  const none=await tempAccount(t);
  await assert.rejects(claude(none,signal,{fetch:async()=>{throw new Error('must not be called');}}),/copy the Claude status line/);
});

test('discover labels enterprise and team logins as Work and keeps the account id',async t=>{
  const home=await fs.mkdtemp(path.join(os.tmpdir(),'ainotch-home-'));
  t.after(()=>fs.rm(home,{recursive:true,force:true}));
  await fs.mkdir(path.join(home,'.claude'));
  await fs.writeFile(path.join(home,'.claude','.credentials.json'),credentials('enterprise'));
  let accounts=await discover(home);
  assert.deepEqual([accounts[0].id,accounts[0].label],['claude','Claude · Work']);

  await fs.writeFile(path.join(home,'.claude','.credentials.json'),credentials('max'));
  assert.equal((await discover(home))[0].label,'Claude · Personal');
  await fs.writeFile(path.join(home,'.claude','.credentials.json'),'{broken');
  assert.equal((await discover(home))[0].label,'Claude · Personal');

  await fs.writeFile(path.join(home,'.claude','.credentials.json'),credentials('pro'));
  await fs.mkdir(path.join(home,'.claude-acme'));await fs.writeFile(path.join(home,'.claude-acme','.credentials.json'),credentials('team'));
  await fs.mkdir(path.join(home,'.claude-2'));await fs.writeFile(path.join(home,'.claude-2','.credentials.json'),credentials('enterprise'));
  accounts=await discover(home);
  assert.deepEqual(accounts.filter(a=>a.kind==='claude').map(a=>[a.id,a.label]).sort(),[['claude','Claude · Personal'],['claude-2','Claude · Work'],['claude-acme','Claude · acme']]);
});
