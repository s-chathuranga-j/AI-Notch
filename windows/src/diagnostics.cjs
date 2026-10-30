const fs=require('node:fs');
const path=require('node:path');
const events=new Set(['start','startup','quit','session-end','resume','main-error','initialization-error','recovery-stopped','renderer-gone','renderer-unresponsive','window-closed','child-process-gone','settings-save-failed']);
const codes=new Set(['ENOENT','EACCES','EPERM','EBUSY','ENOSPC','clean-exit','abnormal-exit','killed','crashed','oom','launch-failed','integrity-failure','memory-eviction']);

// Only fixed lifecycle labels: exception messages/stacks can contain credentials.
function record(directory,event,code){
 if(!events.has(event))return;
 try{
  fs.mkdirSync(directory,{recursive:true});
  const file=path.join(directory,'lifecycle.log');
  if(fs.existsSync(file)&&fs.statSync(file).size>=32768)fs.renameSync(file,file+'.1');
  fs.appendFileSync(file,JSON.stringify({time:new Date().toISOString(),event,...(codes.has(code)?{code}:{})})+'\n',{mode:0o600});
 }catch{}
}
module.exports={record};
