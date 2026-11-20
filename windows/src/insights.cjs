// Usage history, pace forecasts and daily peaks. Pure and clock-injected so it can be tested.
//
// Only percentages and timestamps are kept, per account and window label, never credentials or
// provider responses. Samples are at most one per SAMPLE_GAP and pruned after KEEP.
const MINUTE=60000,HOUR=60*MINUTE,DAY=24*HOUR;
const SAMPLE_GAP=5*MINUTE,KEEP=8*DAY;
const sep='\u001f';

class History{
 constructor(data){this.series=new Map();if(data&&typeof data==='object')for(const [key,list] of Object.entries(data.series||{}))if(Array.isArray(list))this.series.set(key,list.filter(s=>Array.isArray(s)&&Number.isFinite(s[0])&&Number.isFinite(s[1])));}
 // Returns true when something was stored, so the caller knows whether to save.
 add(id,row,now=Date.now()){
  if(!row||row.stale||!Array.isArray(row.windows))return false;
  // The time the source measured it, when known: a reading re-published later is not new use.
  const at=Number.isFinite(row.updated)&&row.updated<=now?row.updated:now;
  let changed=false;
  for(const w of row.windows){
   if(!Number.isFinite(w.percent))continue;
   const key=id+sep+w.label,list=this.series.get(key)||[];
   const last=list.at(-1),prev=list.at(-2);
   if(last&&at<=last[0])continue;
   // Within SAMPLE_GAP of the sample before it, the newest reading replaces the trailing one —
   // with its own timestamp, so the series never backdates a reading. A drop (a reset) is always
   // kept as a new sample so the forecast can see the new window start.
   if(last&&prev&&at-prev[0]<SAMPLE_GAP&&w.percent>=last[1]){list[list.length-1]=[at,w.percent];changed=true;continue;}
   list.push([at,w.percent]);this.series.set(key,list);changed=true;
  }
  return this.prune(now)||changed;
 }
 prune(now=Date.now()){let changed=false;for(const [key,list] of this.series){const kept=list.filter(s=>now-s[0]<=KEEP);if(kept.length!==list.length){changed=true;if(kept.length)this.series.set(key,kept);else this.series.delete(key);}}return changed;}
 forget(id){let changed=false;for(const key of [...this.series.keys()])if(key.startsWith(id+sep)){this.series.delete(key);changed=true;}return changed;}
 samples(id,label){return this.series.get(id+sep+label)||[];}
 toJSON(){return {version:1,series:Object.fromEntries(this.series)};}
}

// When the window will run out at the recent pace. Uses only samples since the last reset
// (a drop of 10 points or more) and within the last LOOKBACK, and needs at least 15 minutes of
// rising usage — two readings a minute apart are noise, not a pace.
const LOOKBACK=90*MINUTE,MIN_SPAN=15*MINUTE,HORIZON=2*DAY;
function forecast(samples,now=Date.now(),reset=null){
 if(!samples||samples.length<2)return null;
 let start=0;for(let i=1;i<samples.length;i++)if(samples[i][1]<=samples[i-1][1]-10)start=i;
 const recent=samples.slice(start).filter(s=>now-s[0]<=LOOKBACK);
 if(recent.length<2)return null;
 const first=recent[0],last=recent.at(-1);
 if(last[0]-first[0]<MIN_SPAN||now-last[0]>30*MINUTE)return null;
 // Least squares over the recent samples: steadier than first-to-last.
 const n=recent.length,mt=recent.reduce((a,s)=>a+s[0],0)/n,mp=recent.reduce((a,s)=>a+s[1],0)/n;
 let num=0,den=0;for(const [t,p] of recent){num+=(t-mt)*(p-mp);den+=(t-mt)*(t-mt);}
 const rate=den?num/den:0; // percent per ms
 if(!(rate>0))return null;
 if(last[1]>=100)return null;
 const eta=last[0]+(100-last[1])/rate;
 if(eta-now>HORIZON)return null;
 const resetAt=reset?new Date(reset).getTime():NaN;
 return {eta:Math.max(now,Math.round(eta)),beforeReset:Number.isFinite(resetAt)?eta<resetAt:null,perHour:Math.round(rate*HOUR*10)/10};
}

// The highest reading on each of the last `days` local days, oldest first. Null for a day
// with no reading, so a quiet day is not drawn as zero use.
function dailyPeaks(samples,now=Date.now(),days=7){
 const out=[];const today=new Date(now);today.setHours(0,0,0,0);
 for(let i=days-1;i>=0;i--){
  const start=new Date(today);start.setDate(today.getDate()-i);
  const end=new Date(start);end.setDate(start.getDate()+1);
  let peak=null;for(const [t,p] of samples||[])if(t>=start.getTime()&&t<end.getTime())peak=peak===null?p:Math.max(peak,p);
  out.push({day:start.getTime(),peak});
 }
 return out;
}

module.exports={History,forecast,dailyPeaks,SAMPLE_GAP,KEEP,MINUTE,HOUR,DAY};
