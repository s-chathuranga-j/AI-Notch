const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
function setup(){
 class Element{
  constructor(){this.children=[];this.dataset={};this.attributes={};this.classes=new Set();this.classList={toggle:(key,on)=>on?this.classes.add(key):this.classes.delete(key)};}
  append(...children){this.children.push(...children);}
  replaceChildren(){this.children=[];}
  setAttribute(key,value){this.attributes[key]=value;}
 }
 const ids=Object.fromEntries(['settings','preferences','position','visibility','mode','accounts','compact','footer','retry'].map(id=>[id,new Element()]));
 const body=new Element();const calls=[];let callback;let delayed;
 const state={settings:false,expanded:false,position:'left',demo:true,accounts:['claude','codex'].map(id=>({id,kind:id,label:id,enabled:true,status:'Updated',windows:[{label:'Session',percent:25}],updated:Date.now()}))};
 const notch={onState:fn=>callback=fn,state:()=>({then:fn=>fn(state)}),detail:id=>calls.push(['detail',id]),expand:on=>calls.push(['expand',on]),settings:()=>calls.push(['settings']),retry(){},position(){},visibility(){}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/renderer.js'),'utf8'),{document:{body,getElementById:id=>ids[id],createElement:()=>new Element(),addEventListener(){}},window:{notch},setTimeout:fn=>{delayed=fn;return 1;},clearTimeout:()=>{delayed=null;}});
 return {ids,body,calls,state,push:callback,leave:()=>{body.onmouseleave();delayed?.();}};
}
test('hover first reveals overview, then only the selected account; leaving collapses',()=>{
 const ui=setup();assert.ok(!ui.body.classes.has('expanded'));
 ui.body.onmouseenter();assert.ok(ui.body.classes.has('expanded'));assert.ok(!ui.body.classes.has('details'));
 ui.ids.compact.children[0].onmouseenter();assert.ok(ui.body.classes.has('details'));
 assert.deepEqual(ui.ids.accounts.children.map(row=>row.hidden),[false,true]);
 ui.ids.compact.children[1].onmouseenter();assert.deepEqual(ui.ids.accounts.children.map(row=>row.hidden),[true,false]);
 ui.leave();assert.ok(!ui.body.classes.has('expanded'));assert.ok(!ui.body.classes.has('details'));
 assert.deepEqual(ui.calls.at(-1),['expand',false]);
});
test('settings hover clears details; clicking opens settings and leaving keeps them open',()=>{
 const ui=setup();ui.body.onmouseenter();ui.ids.compact.children[0].onmouseenter();ui.ids.settings.onmouseenter();
 assert.ok(!ui.body.classes.has('details'));assert.deepEqual(ui.calls.at(-1),['detail',null]);
 ui.ids.settings.onclick();assert.deepEqual(ui.calls.at(-1),['settings']);
 ui.push({...ui.state,settings:true,expanded:true});ui.leave();assert.ok(ui.body.classes.has('expanded'));
 assert.deepEqual(ui.ids.accounts.children.map(row=>row.hidden),[false,false]);
 ui.push({...ui.state,settings:false,expanded:true});assert.ok(!ui.body.classes.has('details'));
 ui.leave();assert.ok(!ui.body.classes.has('expanded'));
});
test('Always visibility keeps the overview open when the pointer leaves',()=>{
 const ui=setup();ui.push({...ui.state,visibility:'always'});
 assert.ok(ui.body.classes.has('expanded'));assert.equal(ui.ids.visibility.value,'always');
 ui.leave();assert.ok(ui.body.classes.has('expanded'));
 assert.ok(!ui.calls.some(([name,value])=>name==='expand'&&value===false));
 ui.push({...ui.state,visibility:'onHover'});ui.leave();assert.ok(!ui.body.classes.has('expanded'));
});
