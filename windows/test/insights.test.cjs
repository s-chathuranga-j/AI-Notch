const {test}=require('node:test');
const assert=require('node:assert/strict');
const {History,forecast,dailyPeaks,MINUTE,HOUR,DAY}=require('../src/insights.cjs');
const row=(percent,label='Session')=>({status:'Updated',windows:[{label,percent}]});
const T0=new Date(2026,10,20,12,0).getTime();
test('history keeps at most one sample per five minutes, but always a drop',()=>{
 const h=new History();
 h.add('c',row(10),T0);h.add('c',row(12),T0+MINUTE);h.add('c',row(15),T0+6*MINUTE);
 assert.deepEqual(h.samples('c','Session'),[[T0,12],[T0+6*MINUTE,15]]);
 h.add('c',row(2),T0+7*MINUTE);assert.equal(h.samples('c','Session').at(-1)[1],2);
});
test('history ignores stale rows, prunes old samples, forgets accounts and round-trips',()=>{
 const h=new History();
 assert.equal(h.add('c',{...row(50),stale:true},T0),false);
 h.add('c',row(10),T0);h.add('c',row(20),T0+9*DAY);
 assert.deepEqual(h.samples('c','Session'),[[T0+9*DAY,20]]);
 const copy=new History(JSON.parse(JSON.stringify(h)));assert.deepEqual(copy.samples('c','Session'),[[T0+9*DAY,20]]);
 assert.equal(copy.forget('c'),true);assert.deepEqual(copy.samples('c','Session'),[]);
 assert.deepEqual(new History({series:{bad:'x',ok:[[1,2],['a',3]]}}).series.get('ok'),[[1,2]]);
});
test('the forecast extends the recent pace to 100%',()=>{
 // 1 point a minute: 60% at +20 min reaches 100% at +60 min, before a reset at +3 h.
 const s=[0,10,20].map(m=>[T0+m*MINUTE,40+m]);
 const f=forecast(s,T0+20*MINUTE,new Date(T0+3*HOUR).toISOString());
 assert.equal(f.eta,T0+60*MINUTE);assert.equal(f.beforeReset,true);assert.equal(f.perHour,60);
 assert.equal(forecast(s,T0+20*MINUTE,new Date(T0+30*MINUTE).toISOString()).beforeReset,false);
 assert.equal(forecast(s,T0+20*MINUTE,null).beforeReset,null);
});
test('no forecast without a real, recent, rising pace',()=>{
 assert.equal(forecast([[T0,40],[T0+5*MINUTE,50]],T0+5*MINUTE),null,'under 15 minutes');
 assert.equal(forecast([[T0,40],[T0+20*MINUTE,40]],T0+20*MINUTE),null,'flat');
 assert.equal(forecast([[T0,40],[T0+20*MINUTE,60]],T0+2*HOUR),null,'last reading too old');
 assert.equal(forecast([[T0,40],[T0+20*MINUTE,40.2]],T0+20*MINUTE),null,'runs out beyond two days');
});
test('the forecast only uses samples since the last reset',()=>{
 const s=[[T0,90],[T0+10*MINUTE,95],[T0+20*MINUTE,5],[T0+30*MINUTE,15],[T0+40*MINUTE,25]];
 assert.equal(forecast(s,T0+40*MINUTE).eta,T0+40*MINUTE+75*MINUTE);
});
test('daily peaks cover seven local days with gaps left empty',()=>{
 const today=new Date(T0);today.setHours(9);
 const s=[[today.getTime(),30],[today.getTime()+HOUR,55],[today.getTime()-2*DAY,80]];
 const peaks=dailyPeaks(s,T0);
 assert.equal(peaks.length,7);assert.equal(peaks.at(-1).peak,55);assert.equal(peaks.at(-3).peak,80);assert.equal(peaks.at(-2).peak,null);
});
