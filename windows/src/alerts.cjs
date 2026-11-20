// Usage alerts: when a metered window reaches 90%, the notch comes out on its own for a few
// seconds, even when it is folded (on hover) or hidden, then goes back to the chosen visibility.
const THRESHOLD=90;
const ALERT_SECONDS={min:3,max:60,default:10};
// Yellow from 90%, red once the limit is spent.
function levelFor(percent){return Number.isFinite(percent)?percent>=100?'critical':percent>=THRESHOLD?'warning':null:null;}
function accountLevel(account){
 if(!account||account.enabled===false||account.stale)return null;
 let level=null;
 for(const w of account.windows||[]){const l=levelFor(w.percent);if(l==='critical')return l;if(l)level=l;}
 return level;
}
function clampAlertSeconds(value){
 const n=Math.round(Number(value));
 return Number.isFinite(n)?Math.min(ALERT_SECONDS.max,Math.max(ALERT_SECONDS.min,n)):ALERT_SECONDS.default;
}
// Announces each crossing once, not on every refresh, and re-arms once the window drops back
// below the threshold (a reset). Stale readings are history: they neither alert nor re-arm.
class AlertTracker{
 constructor(){this.announced=new Set();}
 update(id,row){
  const prefix=id+'\u001f';
  if(!row||row.stale)return false;
  const high=new Set();
  for(const w of row.windows||[])if(Number.isFinite(w.percent)&&w.percent>=THRESHOLD)high.add(prefix+w.label);
  let fresh=false;
  for(const key of high)if(!this.announced.has(key))fresh=true;
  for(const key of [...this.announced])if(key.startsWith(prefix)&&!high.has(key))this.announced.delete(key);
  for(const key of high)this.announced.add(key);
  return fresh;
 }
 forget(id){const prefix=id+'\u001f';for(const key of [...this.announced])if(key.startsWith(prefix))this.announced.delete(key);}
}
module.exports={THRESHOLD,ALERT_SECONDS,levelFor,accountLevel,clampAlertSeconds,AlertTracker};
