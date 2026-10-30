const {test}=require('node:test');
const assert=require('node:assert/strict');
const {notchPath}=require('../src/notch-shape.js');
function commands(path){return [...path.matchAll(/([MLA]) ([^MLAZ]+)/g)].map(([,type,values])=>({type,values:values.trim().split(/\s+/).map(Number)}));}
function ends(path){return commands(path).map(({values})=>values.slice(-2));}
const round=n=>Number(n.toFixed(3));
test('Mac flares are circular arcs with the same corner-first clamping',()=>{
 const arcs=commands(notchPath(70,420,'right')).filter(c=>c.type==='A');
 assert.deepEqual(arcs.map(c=>c.values[0]),[38.735,29.634,29.634,38.735]);
 const small=commands(notchPath(10,80,'right')).filter(c=>c.type==='A');
 assert.deepEqual(small.map(c=>c.values[0]),[5,5,5,5]);
});
test('one canonical path rotates and mirrors onto all four screen edges',()=>{
 const right=ends(notchPath(70,420,'right'));
 assert.deepEqual(ends(notchPath(70,420,'left')),right.map(([u,v])=>[round(70-u),v]));
 assert.deepEqual(ends(notchPath(420,70,'top')),right.map(([u,v])=>[v,round(70-u)]));
 assert.deepEqual(ends(notchPath(420,70,'bottom')),right.map(([u,v])=>[v,u]));
 const rightSweeps=commands(notchPath(70,420,'right')).filter(c=>c.type==='A').map(c=>c.values[4]);
 assert.deepEqual(commands(notchPath(70,420,'left')).filter(c=>c.type==='A').map(c=>c.values[4]),rightSweeps.map(n=>1-n));
});
test('short and narrow shapes never emit invalid radii or leave their window',()=>{
 for(const edge of ['top','bottom','left','right'])for(const [w,h] of [[80,10],[10,80],[4,8],[1,1],[490,620]]){
  const path=notchPath(w,h,edge);assert.ok(!/NaN|Infinity/.test(path));
  for(const {type,values} of commands(path)){
   const [x,y]=values.slice(-2);assert.ok(x>=0&&x<=w);assert.ok(y>=0&&y<=h);
   if(type==='A')assert.ok(values[0]>0&&values[1]>0);
  }
 }
 assert.equal(notchPath(0,80,'top'),'');assert.equal(notchPath(Infinity,80,'right'),'');
});
