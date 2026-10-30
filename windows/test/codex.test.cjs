const {test}=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs');const vm=require('node:vm');const {EventEmitter}=require('node:events');
const {parseCodex}=require('../src/providers.cjs');
function fixture(){
 const child=new EventEmitter();child.stdout=new EventEmitter();child.stdin=new EventEmitter();child.stdin.write=()=>{};child.kill=()=>{};
 const module={exports:{}};
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/providers.cjs'),'utf8'),{module,require:name=>name==='node:child_process'?{spawn:()=>child}:name==='./copilot.cjs'?{}:require(name),process:{env:{},arch:'x64'},setTimeout,clearTimeout,AbortSignal,AbortController});
 const controller=new AbortController();
 const pending=module.exports.fetchUsage({kind:'codex',dir:'/synthetic'},controller.signal);
 return {child,pending};
}
test('Codex reset timestamps cannot throw or discard an otherwise valid reading',()=>{
 for(const resetsAt of [0,-1,Infinity,NaN,Number.MAX_VALUE,'not a date',{},null]){
  assert.deepEqual(parseCodex({rateLimits:{primary:{usedPercent:42,resetsAt}}}),[{label:'Session',percent:42,reset:null}]);
 }
 assert.equal(parseCodex({rateLimits:{primary:{usedPercent:42,resetsAt:100}}})[0].reset,'1970-01-01T00:01:40.000Z');
});
test('null or primitive Codex messages are ignored instead of crashing the event handler',async()=>{
 const {child,pending}=fixture();
 const message={id:2,result:{rateLimits:{primary:{usedPercent:42,resetsAt:'unexpected'}}}};
 assert.doesNotThrow(()=>child.stdout.emit('data',Buffer.from('null\ntrue\n7\n'+JSON.stringify(message)+'\n')));
 assert.equal((await pending)[0].percent,42);
});
test('a broken Codex output stream produces a sanitized provider error',async()=>{
 const {child,pending}=fixture();
 child.stdout.emit('error',new Error('Bearer synthetic-private-token'));
 await assert.rejects(pending,error=>error.message==='Codex connection closed. Retry.');
});
