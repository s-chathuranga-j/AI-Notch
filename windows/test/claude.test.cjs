const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const {claudeStatusLineSettings,claudeReadingFile,fetchUsage,Poller}=require('../src/providers.cjs');

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
  assert.ok(script.includes("$readingPath = 'C:/Users/O''Neil/.claude-work/ai-notch-usage-windows.json'"));
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
