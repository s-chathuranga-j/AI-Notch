const $=id=>document.getElementById(id);
let current,timer,selected=null,isExpanded=false;
function text(tag,value,className){const el=document.createElement(tag);el.textContent=value;if(className)el.className=className;return el;}
function logo(kind){
 const img=document.createElement('img');
 img.src=`assets/${kind==='claude'?'claude':kind==='copilot'?'copilot':'openai'}.svg`;
 img.className='provider-logo';img.alt=kind==='claude'?'Claude':kind==='copilot'?'GitHub Copilot':'OpenAI';return img;
}
function usageSummary(account){
 if(!account.enabled)return '—';
 const quota=account.windows.find(w=>Number.isFinite(w.percent));
 return quota?Math.round(quota.percent)+'%':account.windows.some(w=>w.unlimited)?'∞':'—';
}
function render(state){
 if(!state)return;
 if(state.settings!==current?.settings){selected=null;isExpanded=state.expanded;}
 if(state.visibility==='always')isExpanded=true;
 current=state;document.body.dataset.position=state.position;
 $('settings').setAttribute('aria-expanded',String(state.settings));
 document.body.classList.toggle('settings',state.settings);
 $('preferences').hidden=!state.settings;$('position').value=state.position;$('visibility').value=state.visibility||'onHover';
 $('mode').textContent=state.demo?'Preview · sample data':'Subscription usage';
 $('accounts').replaceChildren();$('compact').replaceChildren();
 for(const a of state.accounts){
  const chip=text('button','',`subscription-chip${a.enabled?'':' disabled'}`);chip.type='button';
  chip.setAttribute('aria-label',`${a.label}: ${a.enabled?a.status:'Disabled'}`);
  chip.setAttribute('aria-controls','accounts');chip.dataset.account=a.id;
  chip.onmouseenter=()=>showDetail(a.id);chip.onfocus=()=>showDetail(a.id);chip.onclick=()=>showDetail(a.id);
  chip.append(logo(a.kind),text('span',usageSummary(a)));$('compact').append(chip);
  const row=text('article','');row.dataset.account=a.id;row.dataset.provider=a.kind;
  const title=text('div','','title');const identity=text('div','','account-identity');
  identity.append(logo(a.kind),text('strong',a.label));title.append(identity);
  if(state.settings){const toggle=document.createElement('input');toggle.type='checkbox';toggle.checked=a.enabled;toggle.setAttribute('aria-label',`Enable ${a.label}`);toggle.onchange=()=>window.notch.toggle(a.id,toggle.checked);title.append(toggle);}
  row.append(title);
  if(a.enabled){
   for(const w of a.windows){
    const line=text('div','','meter');line.append(text('span',w.label),text('b',w.unlimited?'Unlimited':`${Math.round(w.percent)}%`));
    if(!w.unlimited){const progress=document.createElement('progress');progress.setAttribute('aria-label',`${a.label} ${w.label} usage`);progress.max=100;progress.value=Math.max(0,Math.min(100,w.percent));line.append(progress);}
    row.append(line);if(w.reset)row.append(text('small',`Resets ${new Date(w.reset).toLocaleString()}`));
   }
   row.append(text('small',a.status==='Updated'?`Updated ${new Date(a.updated).toLocaleTimeString()}`:a.status,'status'));
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
}
function showDetail(id){clearTimeout(timer);if(current?.settings||selected===id)return;selected=id;isExpanded=true;updateView();window.notch.detail(id);}
function expand(){clearTimeout(timer);if(isExpanded)return;isExpanded=true;updateView();window.notch.expand(true);}
function collapse(){if(current?.settings||current?.visibility==='always')return;selected=null;isExpanded=false;updateView();window.notch.expand(false);}
$('settings').onmouseenter=()=>{if(!current?.settings&&selected!==null){selected=null;updateView();window.notch.detail(null);}};
$('settings').onclick=()=>{clearTimeout(timer);window.notch.settings();};
$('retry').onclick=()=>window.notch.retry();
$('position').onchange=e=>window.notch.position(e.target.value);
$('visibility').onchange=e=>window.notch.visibility(e.target.value);
document.body.onmouseenter=expand;
document.body.onmouseleave=()=>{clearTimeout(timer);timer=setTimeout(collapse,350);};
document.body.onfocusin=expand;
document.addEventListener('keydown',e=>{if(e.key==='Escape'){if(current?.settings)window.notch.settings();else collapse();}});
window.notch.onState(render);window.notch.state().then(render);
