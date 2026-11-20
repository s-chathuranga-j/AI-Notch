// Usage alerts: when a metered window crosses one of the chosen thresholds, the notch comes out on
// its own for a few seconds, even when it is folded (on hover) or hidden, then goes back to the
// chosen visibility. A window that was alerted on and then resets brings the notch out once more,
// in green, to say the limit is back.
const THRESHOLD=90;
const THRESHOLDS=[75,90,100];
const ALERT_SECONDS={min:3,max:60,default:10};
// Below this, a window that had alerted counts as reset.
const RECOVERED_BELOW=50;
// A pace warning needs this much use already and a run-out within this long.
const PACE={minPercent:50,within:60*60000};

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
function cleanThresholds(value){
 const list=Array.isArray(value)?[...new Set(value.map(Number).filter(n=>THRESHOLDS.includes(n)))].sort((a,b)=>a-b):[];
 return list.length?list:[THRESHOLD];
}
// "HH:MM" → minutes after midnight, or null.
function minutes(text){const m=/^(\d{1,2}):(\d{2})$/.exec(String(text||''));if(!m)return null;const h=+m[1],min=+m[2];return h<24&&min<60?h*60+min:null;}
// Quiet hours may wrap midnight (22:00–07:00). Equal start and end means no quiet time.
function isQuiet(quiet,now=new Date()){
 if(!quiet||!quiet.enabled)return false;
 const start=minutes(quiet.start),end=minutes(quiet.end);
 if(start===null||end===null||start===end)return false;
 const t=now.getHours()*60+now.getMinutes();
 return start<end?t>=start&&t<end:t>=start||t<end;
}

// Announces each crossing once, not on every refresh. A window re-arms once it drops back below a
// threshold. Stale readings are history: they neither alert nor re-arm.
class AlertTracker{
 constructor(){this.state=new Map();}
 key(id,label){return id+'\u001f'+label;}
 // Returns what this reading means: thresholds newly crossed, and windows that have reset.
 //
 // With `silent` (alerts off, quiet hours) the tracker still follows the window down — re-arming
 // and forgetting a reset — but never raises its level or reports anything. So when the mute ends,
 // a window still above a level is a new crossing, and a reset that happened meanwhile is not news.
 update(id,row,thresholds=[THRESHOLD],silent=false){
  const result={crossed:[],recovered:[]};
  if(!row||row.stale)return result;
  const list=cleanThresholds(thresholds);
  for(const w of row.windows||[]){
   if(!Number.isFinite(w.percent))continue;
   const key=this.key(id,w.label),s=this.state.get(key)||{level:0,alerted:false,paced:false};
   const reached=list.filter(t=>w.percent>=t).at(-1)||0;
   if(silent){
    s.level=Math.min(s.level,reached);
    if(w.percent<RECOVERED_BELOW){s.alerted=false;s.paced=false;}
    this.state.set(key,s);continue;
   }
   if(reached>s.level){result.crossed.push({label:w.label,percent:w.percent,threshold:reached});s.alerted=true;}
   s.level=reached;
   if(w.percent<RECOVERED_BELOW){if(s.alerted)result.recovered.push({label:w.label,percent:w.percent});s.alerted=false;s.paced=false;}
   this.state.set(key,s);
  }
  return result;
 }
 // True once per window cycle when the recent pace runs out before the reset, within the hour.
 pace(id,label,percent,forecast,now=Date.now()){
  if(!forecast||forecast.beforeReset!==true||!(percent>=PACE.minPercent)||forecast.eta-now>PACE.within)return false;
  const key=this.key(id,label),s=this.state.get(key)||{level:0,alerted:false,paced:false};
  if(s.paced)return false;
  s.paced=true;s.alerted=true;this.state.set(key,s);return true;
 }
 forget(id){const prefix=id+'\u001f';for(const key of [...this.state.keys()])if(key.startsWith(prefix))this.state.delete(key);}
}
// A valid "HH:MM" (00:00–23:59), as stored for quiet hours.
function validTime(text){return /^\d{2}:\d{2}$/.test(String(text))&&minutes(text)!==null;}
module.exports={validTime,THRESHOLD,THRESHOLDS,ALERT_SECONDS,RECOVERED_BELOW,PACE,levelFor,accountLevel,clampAlertSeconds,cleanThresholds,isQuiet,AlertTracker};
