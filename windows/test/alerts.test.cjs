const {test}=require('node:test');
const assert=require('node:assert/strict');
const {AlertTracker,levelFor,accountLevel,clampAlertSeconds}=require('../src/alerts.cjs');
const row=(...percents)=>({status:'Updated',windows:percents.map((percent,i)=>({label:['Session','Weekly'][i],percent}))});
test('a window reaching 90% alerts once per crossing',()=>{
 const t=new AlertTracker();
 assert.equal(t.update('claude',row(89,10)),false);
 assert.equal(t.update('claude',row(90,10)),true);
 assert.equal(t.update('claude',row(95,10)),false);
 assert.equal(t.update('claude',row(95,92)),true,'a second window crossing is new');
});
test('dropping back below the threshold re-arms the alert',()=>{
 const t=new AlertTracker();
 t.update('claude',row(93));assert.equal(t.update('claude',row(4)),false);
 assert.equal(t.update('claude',row(91)),true);
});
test('stale readings neither alert nor re-arm',()=>{
 const t=new AlertTracker();
 assert.equal(t.update('codex',{...row(99),stale:true}),false);
 t.update('codex',row(95));t.update('codex',{...row(1),stale:true});
 assert.equal(t.update('codex',row(96)),false);
});
test('accounts are tracked independently and can be forgotten',()=>{
 const t=new AlertTracker();
 assert.equal(t.update('claude',row(95)),true);assert.equal(t.update('claude-work',row(95)),true);
 t.forget('claude');assert.equal(t.update('claude',row(95)),true);assert.equal(t.update('claude-work',row(95)),false);
});
test('levels are yellow from 90% and red at the limit',()=>{
 assert.equal(levelFor(89.9),null);assert.equal(levelFor(90),'warning');assert.equal(levelFor(100),'critical');assert.equal(levelFor(null),null);
 assert.equal(accountLevel({enabled:true,...row(20,95)}),'warning');
 assert.equal(accountLevel({enabled:true,...row(100,95)}),'critical');
 assert.equal(accountLevel({enabled:true,stale:true,...row(100)}),null);
 assert.equal(accountLevel({enabled:false,...row(100)}),null);
});
test('alert duration is clamped to a sensible range',()=>{
 assert.equal(clampAlertSeconds(10),10);assert.equal(clampAlertSeconds(0),3);assert.equal(clampAlertSeconds(500),60);assert.equal(clampAlertSeconds('x'),10);
});
