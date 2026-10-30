const {test}=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs');const os=require('node:os');const path=require('node:path');
const {record}=require('../src/diagnostics.cjs');
test('lifecycle logs accept only fixed labels, never arbitrary errors or tokens',t=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ainotch-log-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 record(dir,'startup');record(dir,'renderer-gone','crashed');record(dir,'main-error','Bearer synthetic-secret');record(dir,'Bearer synthetic-secret','EACCES');
 const data=fs.readFileSync(path.join(dir,'lifecycle.log'),'utf8');
 assert.ok(!data.includes('synthetic-secret'));assert.equal(data.trim().split('\n').length,3);
 assert.deepEqual(JSON.parse(data.trim().split('\n')[1]).code,'crashed');
});
test('lifecycle logs rotate and keep only one previous bounded file',t=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'ainotch-log-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 const file=path.join(dir,'lifecycle.log');
 fs.writeFileSync(file,'x'.repeat(32768));record(dir,'resume');
 assert.equal(fs.statSync(file+'.1').size,32768);assert.ok(fs.statSync(file).size<200);
 fs.writeFileSync(file,'y'.repeat(32768));record(dir,'quit');
 assert.equal(fs.statSync(file+'.1').size,32768);assert.equal(fs.readdirSync(dir).length,2);
});
