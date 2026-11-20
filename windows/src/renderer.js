const $=id=>document.getElementById(id);
let current,timer,selected=null,isExpanded=false,displayKey='';
function text(tag,value,className){const el=document.createElement(tag);el.textContent=value;if(className)el.className=className;return el;}
function logo(kind){
 const img=document.createElement('img');
 img.src=`assets/${kind==='claude'?'claude':kind==='copilot'?'copilot':'openai'}.svg`;
 img.className='provider-logo';img.alt=kind==='claude'?'Claude':kind==='copilot'?'GitHub Copilot':'OpenAI';return img;
}
// Which window the ring and its number show: the account's choice, or the first with a percentage.
function ringWindow(a){
 const finite=(a.windows||[]).filter(w=>Number.isFinite(w.percent));
 if(a.ring==='highest')return finite.reduce((m,w)=>!m||w.percent>m.percent?w:m,null);
 return finite.find(w=>w.label===a.ring)||finite[0]||null;
}
function clock(t){return new Date(t).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'});}
function forecastLine(f){
 const when=f.eta-Date.now()<60000?'any minute now':'around '+clock(f.eta);
 const tail=f.beforeReset===true?', before it resets':f.beforeReset===false?', after it resets':'';
 return text('small',`At this pace: runs out ${when}${tail}`,f.beforeReset===true?'forecast soon':'forecast');
}
// Seven bars, one per day, each the highest reading that day. Days with no reading stay empty.
function historyChart(peaks,days,label,guide=90){
 const ns='http://www.w3.org/2000/svg',w=280,h=44,bw=26,gap=(w-7*bw)/6;
 const box=text('div','','history');
 const known=peaks.filter(p=>p!==null);
 const head=text('div','','history-head');head.append(text('span',`${label} peak · 7 days`),text('span',`avg ${Math.round(known.reduce((a,b)=>a+b,0)/known.length)}%`));
 const svg=document.createElementNS(ns,'svg');svg.setAttribute('viewBox',`0 0 ${w} ${h+13}`);svg.setAttribute('role','img');
 svg.setAttribute('aria-label',`${label} daily peaks: `+peaks.map((p,i)=>`${new Date(days[i]).toLocaleDateString([],{weekday:'short'})} ${p===null?'no data':Math.round(p)+'%'}`).join(', '));
 const line=document.createElementNS(ns,'line');for(const [k,v] of Object.entries({x1:0,x2:w,y1:h-h*guide/100,y2:h-h*guide/100,class:'history-line'}))line.setAttribute(k,String(v));svg.append(line);
 peaks.forEach((p,i)=>{
  const x=i*(bw+gap);
  if(p!==null){const r=document.createElementNS(ns,'rect'),bh=Math.max(2,h*Math.min(100,p)/100),level=levelFor(p);
   for(const [k,v] of Object.entries({x,y:h-bh,width:bw,height:bh,rx:3,class:'history-bar'+(level?' level-'+level:'')+(i===6?' today':'')}))r.setAttribute(k,String(v));svg.append(r);}
  const t=document.createElementNS(ns,'text');for(const [k,v] of Object.entries({x:x+bw/2,y:h+11,'text-anchor':'middle',class:'history-day'}))t.setAttribute(k,String(v));
  t.textContent=new Date(days[i]).toLocaleDateString([],{weekday:'narrow'});svg.append(t);
 });
 box.append(head,svg);return box;
}
function usageRing(account){
 const ring=text('span','','usage-ring');ring.setAttribute('aria-hidden','true');
 const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 44 44');
 const quota=account.enabled&&!account.stale&&ringWindow(account);
 const percent=quota?Math.max(0,Math.min(100,quota.percent)):0;
 for(const progress of [false,true]){
  const circle=document.createElementNS('http://www.w3.org/2000/svg','circle');
  for(const [name,value] of Object.entries({cx:22,cy:22,r:19,fill:'none',class:progress?'ring-progress':'ring-track'}))circle.setAttribute(name,String(value));
  if(progress){circle.setAttribute('stroke-dasharray',`${percent*2*Math.PI*19/100} ${2*Math.PI*19}`);circle.setAttribute('visibility',percent>0?'visible':'hidden');}
  svg.append(circle);
 }
 ring.append(svg,logo(account.kind));return ring;
}
function updateShape(){
 $('notch-outline').setAttribute('d',notchPath(window.innerWidth,window.innerHeight,current?.position||'top'));
}
function levelFor(percent){return Number.isFinite(percent)?percent>=100?'critical':percent>=90?'warning':null:null;}
function usageSummary(account){
 if(!account.enabled)return '—';
 if(account.stale)return 'Stale';
 const quota=ringWindow(account);
 return quota?Math.round(quota.percent)+'%':account.windows.some(w=>w.unlimited)?'∞':'—';
}
function render(state){
 if(!state)return;
 if(state.settings!==current?.settings){selected=null;isExpanded=state.expanded;}
 if(state.alerting)isExpanded=true;
 else if(current?.alerting&&!current?.settings&&!state.settings){isExpanded=!!state.expanded;if(!isExpanded)selected=null;}
 if(state.visibility==='always')isExpanded=true;
 current=state;document.body.dataset.position=state.position;updateShape();
 $('settings').setAttribute('aria-expanded',String(state.settings));
 document.body.classList.toggle('settings',state.settings);document.body.classList.toggle('alerting',!!state.alerting);
 $('preferences').hidden=!state.settings;$('position').value=state.position;$('visibility').value=state.visibility||'onHover';
 $('alerts').checked=state.alerts!==false;$('alert-seconds').value=String(state.alertSeconds||10);
 const thresholds=state.alertThresholds||[90];
 for(const id of ['t75','t90','t100']){$(id).checked=thresholds.includes(Number($(id).value));$(id).disabled=state.alerts===false;}
 $('pace').checked=state.paceAlerts!==false;
 const quiet=state.quiet||{};$('quiet').checked=!!quiet.enabled;$('quiet-start').value=quiet.start||'22:00';$('quiet-end').value=quiet.end||'08:00';
 $('quiet-start').disabled=$('quiet-end').disabled=!quiet.enabled;
 $('notifications').checked=!!state.systemNotifications;$('notifications').disabled=!state.notificationsAvailable;
 for(const id of ['pace','alert-seconds','quiet'])$(id).disabled=state.alerts===false;
 if(state.alerts===false)$('notifications').disabled=$('quiet-start').disabled=$('quiet-end').disabled=true;
 $('shortcut').value=state.peekShortcut||'off';$('shortcut-status').textContent=state.shortcutError||(state.peekShortcut&&state.peekShortcut!=='off'?'Shows the notch for a few seconds from anywhere.':'');
 // Rebuilt only when the displays change, so a poll cannot close the list while it is open.
 const display=$('display'),list=(state.displays||[]).length>1?state.displays:[];
 const key=list.map(d=>d.id+d.label).join('|');
 if(key!==displayKey&&display.replaceChildren){displayKey=key;display.replaceChildren();const main=document.createElement('option');main.value='primary';main.textContent='Main display';display.append(main);
  for(const d of list){const o=document.createElement('option');o.value=d.id;o.textContent=d.label;display.append(o);}}
 // A saved display that is no longer connected falls back to the main one, as the notch does.
 display.value=list.some(d=>d.id===state.display)?state.display:'primary';display.disabled=!list.length;
 $('startup').checked=!!state.startWithWindows;$('startup').disabled=!state.startupAvailable;
 $('startup-status').textContent=state.startupError||(state.startupAvailable?'':'Available in the installed Windows app.');
 $('mode').textContent=state.demo?'Preview · sample data':'Subscription usage';
 $('accounts').replaceChildren();$('compact').replaceChildren();
 for(const a of state.accounts){
  const stale=!!a.stale&&a.enabled&&a.windows.length>0;
  const chip=text('button','',`subscription-chip${a.enabled?'':' disabled'}${stale?' stale':''}${a.level?' level-'+a.level:''}${a.notice?' notice-'+a.notice:''}`);chip.type='button';
  chip.setAttribute('aria-label',`${a.label}: ${usageSummary(a)}. ${a.enabled?(stale?`${a.status} Showing the last reading.`:a.status):'Disabled'}`);
  chip.setAttribute('aria-controls','accounts');chip.dataset.account=a.id;chip.dataset.provider=a.kind;
  chip.onmouseenter=()=>showDetail(a.id);chip.onfocus=()=>showDetail(a.id);chip.onclick=()=>showDetail(a.id);
  chip.append(usageRing(a),text('span',usageSummary(a)));
  if(stale)chip.append(text('span','⚠','warn'));
  $('compact').append(chip);
  const row=text('article','',stale?'stale':undefined);row.dataset.account=a.id;row.dataset.provider=a.kind;
  const title=text('div','','title');const identity=text('div','','account-identity');
  identity.append(logo(a.kind),text('strong',a.label));title.append(identity);
  if(state.settings&&a.enabled&&a.windows.filter(w=>Number.isFinite(w.percent)).length>1){
   const pick=document.createElement('select');pick.className='ring-pick';pick.setAttribute('aria-label',`${a.label}: ring shows`);
   for(const [value,name] of [['auto','Ring: first limit'],['highest','Ring: closest to limit'],...a.windows.filter(w=>Number.isFinite(w.percent)).map(w=>[w.label,'Ring: '+w.label])]){const o=document.createElement('option');o.value=value;o.textContent=name;pick.append(o);}
   // A saved choice whose limit is no longer reported shows as the fallback the ring actually uses.
   pick.value=a.ring==='highest'||a.windows.some(w=>w.label===a.ring&&Number.isFinite(w.percent))?a.ring:'auto';pick.onchange=()=>window.notch.ring(a.id,pick.value);title.append(pick);
  }
  if(state.settings){const toggle=document.createElement('input');toggle.type='checkbox';toggle.checked=a.enabled;toggle.setAttribute('aria-label',`Enable ${a.label}`);toggle.onchange=()=>window.notch.toggle(a.id,toggle.checked);title.append(toggle);}
  row.append(title);
  if(a.enabled){
   if(state.settings&&!state.demo&&a.kind==='claude'){
    const copy=text('button','Copy status line settings');copy.type='button';
    copy.onclick=async()=>{if(await window.notch.copyClaudeStatusLine(a.id))copy.textContent='Copied';};
    row.append(copy,text('small','Add the copied statusLine entry to this Claude profile’s settings.json. Keep any existing status line by calling the collector from its script.'));
   }
   if(stale){
    row.append(text('small',a.status,'status stale'));
    if(a.updated)row.append(text('small',`Last reading · ${new Date(a.updated).toLocaleString()}`,'status'));
   }
   for(const w of a.windows){
    const level=stale?null:levelFor(w.percent);const line=text('div','',level?'meter level-'+level:'meter');line.append(text('span',w.label),text('b',w.unlimited?'Unlimited':`${Math.round(w.percent)}%`));
    if(!w.unlimited&&!stale){const progress=document.createElement('progress');progress.setAttribute('aria-label',`${a.label} ${w.label} usage`);progress.max=100;progress.value=Math.max(0,Math.min(100,w.percent));line.append(progress);}
    row.append(line);if(w.reset)row.append(text('small',`Resets ${new Date(w.reset).toLocaleString()}`));
    if(!stale&&a.forecasts?.[w.label])row.append(forecastLine(a.forecasts[w.label]));
   }
   const ringed=ringWindow(a);
   if(!stale&&!state.settings&&ringed&&a.history?.[ringed.label]&&state.historyDays)row.append(historyChart(a.history[ringed.label],state.historyDays,ringed.label,Math.min(...(state.alertThresholds||[90]))));
   if(!stale)row.append(text('small',a.status==='Updated'?`Updated ${new Date(a.updated).toLocaleTimeString()}`:a.status,'status'));
  }else row.append(text('small','Disabled · enable in settings'));
  $('accounts').append(row);
 }
 updateView();
 $('footer').textContent=state.demo?'Preview mode · sample data only':'Refreshes every 2 minutes · right-click tray icon to quit';
}
function updateView(){
 document.body.classList.toggle('expanded',isExpanded||!!current?.settings);
 document.body.classList.toggle('details',selected!==null&&!current?.settings);
 for(const row of $('accounts').children)row.hidden=!current?.settings&&row.dataset.account!==selected;
 for(const chip of $('compact').children)chip.setAttribute('aria-expanded',String(chip.dataset.account===selected&&!current?.settings));
 alignDetail();
}
// On a side edge the details card sits beside the ring it belongs to, not always at the top.
function alignDetail(){
 const content=$('content');if(!content?.style)return;
 const side=current?.position==='left'||current?.position==='right';
 const row=[...$('accounts').children].find(r=>r.dataset.account===selected);
 const chip=[...$('compact').children].find(c=>c.dataset.account===selected);
 if(!side||current?.settings||!row?.getBoundingClientRect||!chip?.firstChild?.getBoundingClientRect){content.style.paddingTop='';return;}
 const edge=14,box=content.getBoundingClientRect(),rowBox=row.getBoundingClientRect(),ring=chip.firstChild.getBoundingClientRect();
 if(!rowBox.height)return;
 const padding=parseFloat(getComputedStyle(content).paddingTop)||0;
 const above=rowBox.top-box.top-padding; // the heading, which travels with the card
 const wanted=ring.top+ring.height/2-box.top-above-rowBox.height/2;
 content.style.paddingTop=Math.round(Math.max(edge,Math.min(wanted,box.height-edge-above-rowBox.height)))+'px';
}
function showDetail(id){clearTimeout(timer);if(current?.settings||selected===id)return;selected=id;isExpanded=true;updateView();window.notch.detail(id);}
function expand(){clearTimeout(timer);if(current?.alerting){window.notch.expand(true);return;}if(isExpanded)return;isExpanded=true;updateView();window.notch.expand(true);}
function collapse(){if(current?.settings||current?.visibility==='always')return;
 // During an alert the notch stays out; only the hover state is handed back for when it ends.
 if(current?.alerting){selected=null;updateView();window.notch.expand(false);return;}
 selected=null;isExpanded=false;updateView();window.notch.expand(false);}
$('settings').onmouseenter=()=>{if(!current?.settings&&selected!==null){selected=null;updateView();window.notch.detail(null);}};
$('settings').onclick=()=>{clearTimeout(timer);window.notch.settings();};
$('retry').onclick=()=>window.notch.retry();
$('position').onchange=e=>window.notch.position(e.target.value);
$('visibility').onchange=e=>window.notch.visibility(e.target.value);
$('alerts').onchange=e=>window.notch.alerts({enabled:e.target.checked});
for(const id of ['t75','t90','t100'])$(id).onchange=e=>{
 const levels=['t75','t90','t100'].filter(t=>$(t).checked).map(t=>Number($(t).value));
 // At least one level stays chosen; unticking the last would otherwise quietly mean 90%.
 if(!levels.length){e.target.checked=true;return;}
 window.notch.alerts({thresholds:levels});
};
$('pace').onchange=e=>window.notch.alerts({pace:e.target.checked});
$('quiet').onchange=e=>window.notch.alerts({quiet:{enabled:e.target.checked}});
$('quiet-start').onchange=e=>window.notch.alerts({quiet:{start:e.target.value}});
$('quiet-end').onchange=e=>window.notch.alerts({quiet:{end:e.target.value}});
$('notifications').onchange=e=>window.notch.alerts({notifications:e.target.checked});
$('shortcut').onchange=e=>window.notch.shortcut(e.target.value);
$('display').onchange=e=>window.notch.display(e.target.value);
$('alert-seconds').onchange=e=>window.notch.alerts({seconds:Number(e.target.value)});
$('startup').onchange=e=>window.notch.startup(e.target.checked).catch(()=>{$('startup-status').textContent='Windows could not change startup settings. Try again.';});
document.body.onmouseenter=expand;
document.body.onmouseleave=()=>{clearTimeout(timer);timer=setTimeout(collapse,350);};
document.body.onfocusin=expand;
document.addEventListener('keydown',e=>{if(e.key==='Escape'){if(current?.settings)window.notch.settings();else collapse();}});
window.notch.onState(render);window.notch.state().then(render);
window.addEventListener('resize',()=>{updateShape();alignDetail();});
