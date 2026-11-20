const {test}=require('node:test');
const assert=require('node:assert/strict');
const {AlertTracker,levelFor,accountLevel,clampAlertSeconds,cleanThresholds,isQuiet}=require('../src/alerts.cjs');
const row=(...percents)=>({status:'Updated',windows:percents.map((percent,i)=>({label:['Session','Weekly'][i],percent}))});
const crossed=r=>r.crossed.length>0;
test('a window reaching 90% alerts once per crossing',()=>{
 const t=new AlertTracker();
 assert.equal(crossed(t.update('claude',row(89,10))),false);
 assert.equal(crossed(t.update('claude',row(90,10))),true);
 assert.equal(crossed(t.update('claude',row(95,10))),false);
 assert.equal(crossed(t.update('claude',row(95,92))),true,'a second window crossing is new');
});
test('each chosen threshold alerts as it is crossed',()=>{
 const t=new AlertTracker(),levels=[75,90,100];
 assert.deepEqual(t.update('c',row(76),levels).crossed.map(c=>c.threshold),[75]);
 assert.deepEqual(t.update('c',row(80),levels).crossed,[]);
 assert.deepEqual(t.update('c',row(100),levels).crossed.map(c=>c.threshold),[100],'jumping past two reports the highest');
});
test('dropping back below the threshold re-arms the alert, and a reset is reported once',()=>{
 const t=new AlertTracker();
 t.update('claude',row(93));
 const reset=t.update('claude',row(4));assert.equal(crossed(reset),false);assert.deepEqual(reset.recovered.map(r=>r.label),['Session']);
 assert.deepEqual(t.update('claude',row(3)).recovered,[],'only once');
 assert.equal(crossed(t.update('claude',row(91))),true);
});
test('a window that never alerted does not announce a reset',()=>{
 const t=new AlertTracker();t.update('c',row(60));assert.deepEqual(t.update('c',row(2)).recovered,[]);
});
test('stale readings neither alert nor re-arm',()=>{
 const t=new AlertTracker();
 assert.equal(crossed(t.update('codex',{...row(99),stale:true})),false);
 t.update('codex',row(95));t.update('codex',{...row(1),stale:true});
 assert.equal(crossed(t.update('codex',row(96))),false);
});
test('accounts are tracked independently and can be forgotten',()=>{
 const t=new AlertTracker();
 assert.equal(crossed(t.update('claude',row(95))),true);assert.equal(crossed(t.update('claude-work',row(95))),true);
 t.forget('claude');assert.equal(crossed(t.update('claude',row(95))),true);assert.equal(crossed(t.update('claude-work',row(95))),false);
});
test('a pace warning fires once when the window runs out before the reset within the hour',()=>{
 const t=new AlertTracker(),now=1e12;
 const soon={eta:now+30*60000,beforeReset:true};
 assert.equal(t.pace('c','Session',40,soon,now),false,'too little used yet');
 assert.equal(t.pace('c','Session',60,{...soon,beforeReset:false},now),false);
 assert.equal(t.pace('c','Session',60,{...soon,eta:now+3*3600000},now),false);
 assert.equal(t.pace('c','Session',60,soon,now),true);assert.equal(t.pace('c','Session',70,soon,now),false);
 t.update('c',row(5));assert.equal(t.pace('c','Session',60,soon,now),true,'re-armed after a reset');
});
test('levels are yellow from 90% and red at the limit',()=>{
 assert.equal(levelFor(89.9),null);assert.equal(levelFor(90),'warning');assert.equal(levelFor(100),'critical');assert.equal(levelFor(null),null);
 assert.equal(accountLevel({enabled:true,...row(20,95)}),'warning');
 assert.equal(accountLevel({enabled:true,...row(100,95)}),'critical');
 assert.equal(accountLevel({enabled:true,stale:true,...row(100)}),null);
 assert.equal(accountLevel({enabled:false,...row(100)}),null);
});
test('alert settings are cleaned',()=>{
 assert.equal(clampAlertSeconds(10),10);assert.equal(clampAlertSeconds(0),3);assert.equal(clampAlertSeconds(500),60);assert.equal(clampAlertSeconds('x'),10);
 assert.deepEqual(cleanThresholds([100,'75',42,75]),[75,100]);assert.deepEqual(cleanThresholds([]),[90]);assert.deepEqual(cleanThresholds('x'),[90]);
});
test('quiet hours, including ones that wrap midnight',()=>{
 const at=(h,m=0)=>new Date(2026,0,1,h,m);
 const night={enabled:true,start:'22:00',end:'07:30'};
 assert.equal(isQuiet(night,at(23)),true);assert.equal(isQuiet(night,at(3)),true);assert.equal(isQuiet(night,at(7,30)),false);assert.equal(isQuiet(night,at(12)),false);
 assert.equal(isQuiet({enabled:true,start:'12:00',end:'13:00'},at(12,15)),true);
 assert.equal(isQuiet({...night,enabled:false},at(23)),false);assert.equal(isQuiet({enabled:true,start:'9',end:'10:00'},at(9,30)),false);
});
