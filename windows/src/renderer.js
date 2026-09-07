const $=id=>document.getElementById(id);let current;let timer;
function text(tag,value,className){const el=document.createElement(tag);el.textContent=value;if(className)el.className=className;return el;}
function render(state){if(!state)return;current=state;document.body.classList.toggle('settings',state.settings);$('preferences').hidden=!state.settings;$('position').value=state.position;$('mode').textContent=state.demo?'Preview · sample data':'Subscription usage';$('accounts').replaceChildren();$('compact').replaceChildren();
 for(const a of state.accounts){if(a.enabled){$('compact').append(text('span',`${a.kind==='claude'?'C':'O'} ${a.windows[0]?Math.round(a.windows[0].percent)+'%':'—'}`));}
 const row=text('article','');const title=text('div','','title');title.append(text('strong',a.label));if(state.settings){const toggle=document.createElement('input');toggle.type='checkbox';toggle.checked=a.enabled;toggle.setAttribute('aria-label',`Enable ${a.label}`);toggle.onchange=()=>window.notch.toggle(a.id,toggle.checked);title.append(toggle);}row.append(title);
 if(a.enabled){for(const w of a.windows){const line=text('div','','meter');line.append(text('span',w.label),text('b',`${Math.round(w.percent)}%`));const progress=document.createElement('progress');progress.max=100;progress.value=Math.max(0,Math.min(100,w.percent));line.append(progress);row.append(line);if(w.reset)row.append(text('small',`Resets ${new Date(w.reset).toLocaleString()}`));}row.append(text('small',a.status==='Updated'?`Updated ${new Date(a.updated).toLocaleTimeString()}`:a.status,'status'));}else row.append(text('small','Disabled · enable in settings'));
 $('accounts').append(row);}
 $('footer').textContent=state.demo?'Demo on macOS · no credentials accessed':'Refreshes every 2 minutes · right-click tray icon to quit';
}
$('settings').onclick=()=>window.notch.settings();$('retry').onclick=()=>window.notch.retry();$('position').onchange=e=>window.notch.position(e.target.value);
document.body.onmouseenter=()=>{clearTimeout(timer);document.body.classList.add('expanded');window.notch.expand(true);};document.body.onmouseleave=()=>{timer=setTimeout(()=>{if(!current?.settings){document.body.classList.remove('expanded');window.notch.expand(false);}},350);};
window.notch.onState(render);window.notch.state().then(render);
