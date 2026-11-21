const electron=require('electron');
const {app,BrowserWindow,Tray,Menu,ipcMain,screen,session,powerMonitor,dialog,clipboard,Notification,globalShortcut,shell}=electron;
const {checkForUpdates,RELEASE_PAGE}=require('./updates.cjs');
const fs=require('node:fs/promises');const path=require('node:path');const os=require('node:os');
const {discover,Poller,fetchUsage,claudeStatusLineSettings,claudeReadingFile}=require('./providers.cjs');
const {notchBounds}=require('./layout.cjs');
const {record}=require('./diagnostics.cjs');
const {AlertTracker,accountLevel,clampAlertSeconds,cleanThresholds,isQuiet,validTime,ALERT_SECONDS}=require('./alerts.cjs');
const fsSync=require('node:fs');
const {History,forecast,dailyPeaks}=require('./insights.cjs');
const SHORTCUTS=['off','Control+Alt+N','Control+Alt+U','Control+Shift+Space'];
const NOTICE_RANK={peek:0,reset:1,pace:2,limit:3};
const demo=process.platform!=='win32'||process.argv.includes('--demo');
const icon=path.join(__dirname,process.platform==='win32'?'assets/app.ico':'tray.png');
const VISIBILITIES=['onHover','always','hidden'];
const loginOptions={path:process.execPath,args:['--startup']};
const STARTUP_NAME='AI Notch';
let win,tray,wakeTimer,refreshTimer,alertTimer,historyTimer,startupError='',shortcutError='',lastRendererRecovery=0,alerting=false,alertKind=null;
const alerts=new AlertTracker(),notices=new Map();
let history=new History();
let accounts=[],config={enabled:[],position:'top',visibility:'onHover',alerts:true,alertSeconds:ALERT_SECONDS.default,alertThresholds:[90],paceAlerts:true,quiet:{enabled:false,start:'22:00',end:'08:00'},systemNotifications:false,peekShortcut:'Control+Alt+N',display:'primary',ring:{}},rows={},settings=false,expanded=false,detailId=null;
const poller=new Poller(demo?async account=>account.kind==='copilot'?[{label:'AI credits',percent:28,reset:new Date(Date.now()+604800000).toISOString()},{label:'Completions',percent:null,unlimited:true,reset:null}]:[{label:'Session',percent:account.kind==='claude'?37:62,reset:new Date(Date.now()+7200000).toISOString()},{label:'Weekly',percent:21,reset:null}]:fetchUsage,(id,row)=>{rows[id]=row;onReading(id,row);push();});
function log(event,code){record(app.getPath('userData'),event,code);}
function startupState(){
 const startupAvailable=process.platform==='win32'&&app.isPackaged&&!demo;
 if(!startupAvailable)return {startupAvailable:false,startWithWindows:false,startupError:''};
 try{
  const settings=app.getLoginItemSettings(loginOptions);
  // Our own Run entry, by the name it was written under, is the most direct answer; the executable
  // check is the fallback for entries Windows reports differently.
  const ours=(settings.launchItems||[]).find(item=>item.name===STARTUP_NAME);
  // openAtLogin is not used: it ignores the Startup apps switch in Windows Settings.
  const on=ours?ours.enabled!==false:!!settings.executableWillLaunchAtLogin;
  const blocked=ours&&ours.enabled===false;
  return {startupAvailable:true,startWithWindows:on,startupError:startupError||(blocked?'Turned off in Windows Settings > Apps > Startup. Turn AI Notch on there, or tick the box again.':'')};
 }
 catch{return {startupAvailable:false,startWithWindows:false,startupError:'Windows startup settings could not be read.'};}
}
function forecastFor(id,w){return Number.isFinite(w.percent)?forecast(history.samples(id,w.label),Date.now(),w.reset):null;}
function insights(id,row){
 if(!row||row.stale||!poller.enabled.has(id))return {};
 const forecasts={},peaks={};
 for(const w of row.windows||[]){
  const f=forecastFor(id,w);if(f)forecasts[w.label]=f;
  const days=dailyPeaks(history.samples(id,w.label)).map(d=>d.peak);
  // Shown from the first day with a reading, so it is visibly building up rather than missing.
  if(days.some(p=>p!==null))peaks[w.label]=days;
 }
 return {forecasts,history:peaks};
}
function displays(){
 const all=typeof screen.getAllDisplays==='function'?screen.getAllDisplays():[];
 const primary=screen.getPrimaryDisplay();
 return all.map((d,i)=>({id:String(d.id),label:`Display ${i+1} · ${d.size?.width||d.workArea.width}×${d.size?.height||d.workArea.height}${d.id===primary.id?' (main)':''}`}));
}
function targetDisplay(){
 const all=typeof screen.getAllDisplays==='function'?screen.getAllDisplays():[];
 return all.find(d=>String(d.id)===String(config.display))||screen.getPrimaryDisplay();
}
function state(){return {demo,settings,expanded,detailId,alerting,alertKind,position:config.position,visibility:config.visibility,alerts:config.alerts,alertSeconds:config.alertSeconds,alertThresholds:config.alertThresholds,paceAlerts:config.paceAlerts,quiet:config.quiet,systemNotifications:config.systemNotifications,notificationsAvailable:!!Notification?.isSupported?.(),peekShortcut:config.peekShortcut,shortcutError,display:config.display,displays:displays(),historyDays:dailyPeaks([]).map(d=>d.day),...startupState(),accounts:accounts.map(({id,label,kind})=>{const row=rows[id]||{status:'Disabled',windows:[]};const account={id,label,kind,enabled:poller.enabled.has(id),...row};return {...account,...insights(id,row),level:accountLevel(account),notice:alerting?notices.get(id)||null:null,ring:config.ring[id]||'auto'};})};}
// Every reading: remember it, then decide whether it is worth interrupting for.
function onReading(id,row){
 if(!poller.enabled.has(id))return;
 if(!demo&&history.add(id,row))saveHistorySoon();
 // Alerts off silences everything, notifications included. During quiet hours the tracker follows
 // along silently, so a limit that is still high when they end is announced then, not lost.
 if(!config.alerts||isQuiet(config.quiet)){alerts.update(id,row,config.alertThresholds,true);return;}
 const result=alerts.update(id,row,config.alertThresholds);
 let kind=null,detail=null;
 // Several windows can cross in one reading; the message names the most serious.
 if(result.crossed.length){kind='limit';detail=[...result.crossed].sort((a,b)=>b.threshold-a.threshold||b.percent-a.percent)[0];}
 else if(config.paceAlerts&&!row.stale){
  for(const w of row.windows||[]){const f=forecastFor(id,w);if(alerts.pace(id,w.label,w.percent,f)){kind='pace';detail={label:w.label,percent:w.percent,eta:f.eta};break;}}
 }
 if(!kind&&result.recovered.length){kind='reset';detail=result.recovered[0];}
 if(!kind)return;
 notices.set(id,kind);
 notify(id,kind,detail);
 startAlert(kind);
}
function notify(id,kind,detail){
 if(!config.systemNotifications||!Notification?.isSupported?.())return;
 const account=accounts.find(a=>a.id===id)?.label||'AI Notch';
 const time=t=>new Date(t).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'});
 const body=kind==='limit'?`${detail.label} is at ${Math.round(detail.percent)}%.`:kind==='pace'?`${detail.label} may run out around ${time(detail.eta)}, before it resets.`:`${detail.label} has reset.`;
 try{new Notification({title:kind==='reset'?`${account} is back`:account,body,silent:kind==='reset'}).show();}catch{log('notification-failed');}
}
// A limit crossing a threshold (or a pace or reset notice, or the peek shortcut) brings the notch
// out on its own — folded or hidden — for the chosen number of seconds, then place() returns it
// to the visibility the user picked.
function startAlert(kind='limit'){
 if(app.quitting)return;
 if(!alerting||NOTICE_RANK[kind]>NOTICE_RANK[alertKind])alertKind=kind;
 alerting=true;clearTimeout(alertTimer);
 alertTimer=setTimeout(endAlert,config.alertSeconds*1000);
 place();
}
function peek(){if(!win||win.isDestroyed())createWindow();startAlert('peek');push();}
function saveHistorySoon(){
 if(historyTimer)return;
 historyTimer=setTimeout(()=>{historyTimer=null;saveHistory().catch(()=>log('history-save-failed'));},60000);
}
// Writes are chained, like save(), so two can never interleave on history.json.tmp.
let historySaving=Promise.resolve(),historyWrites=0;
function saveHistory(){
 if(demo)return Promise.resolve();
 const directory=app.getPath('userData'),file=path.join(directory,'history.json');
 historyWrites++;
 historySaving=historySaving.catch(()=>{}).then(async()=>{
  await fs.mkdir(directory,{recursive:true});
  await fs.writeFile(file+'.tmp',JSON.stringify(history),{mode:0o600});
  // Once quitting, the synchronous write owns history.json; an older snapshot must not replace it.
  if(!app.quitting)await fs.rename(file+'.tmp',file);
 }).finally(()=>{historyWrites--;});
 return historySaving;
}
// On the way out there is no time for an async write to land, so the last one is synchronous.
function saveHistoryNow(){
 if(demo)return;
 try{
  const directory=app.getPath('userData'),file=path.join(directory,'history.json');
  fsSync.mkdirSync(directory,{recursive:true});
  fsSync.writeFileSync(file+'.quit.tmp',JSON.stringify(history),{mode:0o600});
  fsSync.renameSync(file+'.quit.tmp',file);
 }catch{log('history-save-failed');}
}
function registerShortcut(){
 if(!globalShortcut)return;
 try{globalShortcut.unregisterAll();}catch{}
 shortcutError='';
 if(config.peekShortcut==='off')return;
 let ok=false;try{ok=globalShortcut.register(config.peekShortcut,peek);}catch{}
 if(!ok)shortcutError='Another app is using this shortcut. Choose a different one.';
}
function endAlert(){clearTimeout(alertTimer);alertTimer=null;notices.clear();alertKind=null;if(!alerting)return;alerting=false;place();push();}
function push(){
 if(app.quitting||!win||win.isDestroyed()||win.webContents.isDestroyed())return;
 try{win.webContents.send('state',state());}catch{log('renderer-gone');}
}
function place(){
 if(!win||win.isDestroyed()||app.quitting)return;
 const open=expanded||alerting||config.visibility==='always';
 const area=targetDisplay().workArea;
 if(area.width<=0||area.height<=0)return;
 win.setBounds(notchBounds(area,config.position,accounts.length,open,settings,detailId!==null));
 const hidden=config.visibility==='hidden'&&!settings&&!alerting;
 win.setIgnoreMouseEvents(hidden);
 if(hidden)win.hide();else if(!win.isVisible())win.showInactive();
}
let saving=Promise.resolve();
function save(){
 if(demo)return Promise.resolve();
 const payload=JSON.stringify(config),directory=app.getPath('userData');
 saving=saving.catch(()=>{}).then(async()=>{
  await fs.mkdir(directory,{recursive:true});
  const file=path.join(directory,'settings.json');
  await fs.writeFile(file+'.tmp',payload,{mode:0o600});
  await fs.rename(file+'.tmp',file);
 });
 return saving;
}
async function refresh(){await Promise.all(accounts.map(a=>poller.refresh(a)));}
function stop(){if(!app.quitting&&(historyTimer||historyWrites>0)){clearTimeout(historyTimer);historyTimer=null;saveHistoryNow();}app.quitting=true;clearTimeout(wakeTimer);clearTimeout(alertTimer);try{globalShortcut?.unregisterAll();}catch{}clearInterval(refreshTimer);poller.cancelPending();}
function fatal(event,error){
 if(app.quitting)return;
 log(event,error?.code);stop();
 const previous=Number(process.argv.find(arg=>/^--ainotch-recovery=\d+$/.test(arg))?.split('=')[1]||0);
 if(Date.now()-previous<60000){
  log('recovery-stopped');
  dialog.showErrorBox('AI Notch could not recover','AI Notch stopped repeatedly. Please open it again or reinstall the latest version. A small local lifecycle.log in the app data folder records the failure category.');
 }else{
  app.relaunch({args:[...process.argv.slice(1).filter(arg=>!arg.startsWith('--ainotch-recovery=')),'--ainotch-recovery='+Date.now()]});
 }
 app.exit(1);
}
function openSettings(){if(!win||win.isDestroyed())createWindow();settings=true;expanded=true;detailId=null;place();win.show();push();}
function showNotch(){
 if(!win||win.isDestroyed())createWindow();
 if(config.visibility==='hidden'){config.visibility='onHover';save().catch(()=>log('settings-save-failed'));}
 settings=false;expanded=true;detailId=null;place();win.show();push();
}
async function recoverRenderer(window){
 if(app.quitting||window.isDestroyed())return;
 if(Date.now()-lastRendererRecovery<60000)return fatal('main-error');
 lastRendererRecovery=Date.now();detailId=null;expanded=config.visibility==='always';
 try{await window.loadFile(path.join(__dirname,'index.html'));}catch(error){fatal('initialization-error',error);}
}
function createWindow(){
 const window=new BrowserWindow({icon,width:80,height:10,frame:false,transparent:true,backgroundColor:'#00000000',hasShadow:false,resizable:false,minimizable:false,maximizable:false,alwaysOnTop:true,skipTaskbar:true,show:false,webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false,backgroundThrottling:false}});
 win=window;
 window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
 window.webContents.on('will-navigate',event=>event.preventDefault());
 window.webContents.on('did-finish-load',()=>{place();push();});
 window.webContents.on('render-process-gone',(_event,details)=>{
  if(app.quitting)return;log('renderer-gone',details.reason);recoverRenderer(window).catch(error=>fatal('main-error',error));
 });
 window.on('unresponsive',()=>{if(!app.quitting){log('renderer-unresponsive');window.webContents.forcefullyCrashRenderer();}});
 window.on('close',event=>{if(!app.quitting){event.preventDefault();window.hide();}});
 window.on('closed',()=>{
  if(win===window)win=null;
  if(!app.quitting){log('window-closed');createWindow();}
 });
 window.on('session-end',()=>{log('session-end');stop();});
 window.on('focus',push);
 window.loadFile(path.join(__dirname,'index.html')).catch(error=>fatal('initialization-error',error));
}
function wake(){
 clearTimeout(wakeTimer);
 wakeTimer=setTimeout(()=>{if(!app.quitting){log('resume');place();push();refresh().catch(error=>fatal('main-error',error));}},500);
}
if(!app.requestSingleInstanceLock())app.quit();else {
 process.on('uncaughtException',error=>fatal('main-error',error));
 process.on('unhandledRejection',error=>fatal('main-error',error));
 // A tray app must survive losing its last native window.
 app.on('window-all-closed',()=>{});
 app.on('second-instance',()=>{app.whenReady().then(showNotch).catch(error=>fatal('initialization-error',error));});
 app.on('child-process-gone',(_event,details)=>log('child-process-gone',details.reason));
 app.on('before-quit',stop);
 app.on('quit',()=>log('quit'));
 app.whenReady().then(async()=>{
  log(process.argv.includes('--startup')?'startup':'start');
  if(process.platform==='win32')app.setAppUserModelId('com.fourforge.ainotch.windows');
  if(demo){accounts=[{id:'claude',kind:'claude',label:'Claude · Personal'},{id:'claude-work',kind:'claude',label:'Claude · Work'},{id:'codex',kind:'codex',label:'Codex'},{id:'copilot',kind:'copilot',label:'GitHub Copilot'}];config.enabled=accounts.map(a=>a.id);}
  else {
   accounts=await discover(os.homedir());
   try{const saved=JSON.parse(await fs.readFile(path.join(app.getPath('userData'),'settings.json'),'utf8'));config.enabled=Array.isArray(saved.enabled)?saved.enabled.filter(x=>typeof x==='string'):[];if(['top','bottom','left','right'].includes(saved.position))config.position=saved.position;if(VISIBILITIES.includes(saved.visibility))config.visibility=saved.visibility;if(typeof saved.alerts==='boolean')config.alerts=saved.alerts;if(saved.alertSeconds!==undefined)config.alertSeconds=clampAlertSeconds(saved.alertSeconds);
    if(saved.alertThresholds!==undefined)config.alertThresholds=cleanThresholds(saved.alertThresholds);
    if(typeof saved.paceAlerts==='boolean')config.paceAlerts=saved.paceAlerts;
    if(saved.quiet&&typeof saved.quiet==='object')config.quiet={enabled:saved.quiet.enabled===true,start:validTime(saved.quiet.start)?saved.quiet.start:'22:00',end:validTime(saved.quiet.end)?saved.quiet.end:'08:00'};
    if(typeof saved.systemNotifications==='boolean')config.systemNotifications=saved.systemNotifications;
    if(SHORTCUTS.includes(saved.peekShortcut))config.peekShortcut=saved.peekShortcut;
    if(typeof saved.display==='string')config.display=saved.display;
    if(saved.ring&&typeof saved.ring==='object')config.ring=Object.fromEntries(Object.entries(saved.ring).filter(([k,v])=>typeof k==='string'&&typeof v==='string'));}catch{}
   try{history=new History(JSON.parse(await fs.readFile(path.join(app.getPath('userData'),'history.json'),'utf8')));}catch{}
   // Anything left from an account that is now disabled goes, in case its deletion never landed.
   let stale=false;for(const id of [...history.series.keys()].map(k=>k.split('\u001f')[0]))if(!config.enabled.includes(id)&&history.forget(id))stale=true;
   if(stale)saveHistory().catch(()=>log('history-save-failed'));
  }
  config.enabled.forEach(id=>poller.enabled.add(id));
  session.defaultSession.webRequest.onBeforeRequest((details,callback)=>callback({cancel:!details.url.startsWith('file:')}));
  tray=new Tray(icon);tray.setToolTip('AI Notch');
  tray.setContextMenu(Menu.buildFromTemplate([{label:'Show AI Notch',click:showNotch},{label:'Peek at usage',click:peek},{label:'Settings',click:openSettings},{label:'Refresh usage',click:()=>refresh().catch(error=>fatal('main-error',error))},{type:'separator'},{label:'Quit',click:()=>app.quit()}]));
  tray.on('click',openSettings);
  createWindow();
  function valid(event){return win&&!win.isDestroyed()&&event.sender===win.webContents&&event.senderFrame===win.webContents.mainFrame;}
  ipcMain.handle('state',event=>valid(event)?state():null);
  ipcMain.handle('toggle',async(event,id,on)=>{if(!valid(event)||typeof on!=='boolean')return;const a=accounts.find(a=>a.id===id);if(!a)return;if(on){poller.enabled.add(id);rows[id]={status:'Loading…',windows:[]};}else {poller.disable(id);alerts.forget(id);notices.delete(id);if(history.forget(id))saveHistory().catch(()=>log('history-save-failed'));}config.enabled=[...poller.enabled];await save();if(!on&&!demo&&a.kind==='claude')await fs.rm(path.join(a.dir,claudeReadingFile),{force:true}).catch(()=>{});push();if(on)await poller.refresh(a);});
  ipcMain.handle('claude-status-line', (event,id) => {
   if(!valid(event)||demo)return false;
   const account=accounts.find(a=>a.id===id&&a.kind==='claude');
   if(!account)return false;
   clipboard.writeText(claudeStatusLineSettings(account,path.join(app.getPath('userData'),'settings.json')));
   return true;
  });
  ipcMain.handle('retry',event=>{if(valid(event))return refresh();});
  ipcMain.handle('check-updates',async event=>valid(event)?checkForUpdates(app.getVersion()):null);
  ipcMain.handle('open-release',(event,url)=>{if(valid(event)&&typeof url==='string'&&RELEASE_PAGE.test(url))return shell?.openExternal(url);});
  ipcMain.handle('position',async(event,value)=>{if(valid(event)&&['top','bottom','left','right'].includes(value)){config.position=value;await save();place();push();}});
  ipcMain.handle('visibility',async(event,value)=>{if(valid(event)&&VISIBILITIES.includes(value)){config.visibility=value;expanded=value==='always';detailId=null;endAlert();await save();place();push();}});
  ipcMain.handle('alerts',async(event,value)=>{
   if(!valid(event)||!value||typeof value!=='object')return;
   if(typeof value.enabled==='boolean'){config.alerts=value.enabled;if(!value.enabled&&alerting)endAlert();}
   if(value.seconds!==undefined)config.alertSeconds=clampAlertSeconds(value.seconds);
   if(value.thresholds!==undefined)config.alertThresholds=cleanThresholds(value.thresholds);
   if(typeof value.pace==='boolean')config.paceAlerts=value.pace;
   if(typeof value.notifications==='boolean')config.systemNotifications=value.notifications;
   if(value.quiet&&typeof value.quiet==='object'){const q=value.quiet;config.quiet={enabled:typeof q.enabled==='boolean'?q.enabled:config.quiet.enabled,start:validTime(q.start)?q.start:config.quiet.start,end:validTime(q.end)?q.end:config.quiet.end};}
   await save();push();
  });
  ipcMain.handle('display',async(event,value)=>{if(valid(event)&&typeof value==='string'&&(value==='primary'||displays().some(d=>d.id===value))){config.display=value;await save();place();push();}});
  ipcMain.handle('shortcut',async(event,value)=>{if(valid(event)&&SHORTCUTS.includes(value)){config.peekShortcut=value;registerShortcut();await save();push();}});
  ipcMain.handle('ring',async(event,id,value)=>{if(valid(event)&&accounts.some(a=>a.id===id)&&typeof value==='string'&&value.length<64){if(value==='auto')delete config.ring[id];else config.ring[id]=value;await save();push();}});
  ipcMain.handle('startup',(event,value)=>{
   if(!valid(event)||typeof value!=='boolean'||!startupState().startupAvailable)return;
   try{app.setLoginItemSettings({...loginOptions,name:STARTUP_NAME,openAtLogin:value,enabled:value});startupError='';
    if(startupState().startWithWindows!==value)startupError='Windows did not keep this change. Check Settings > Apps > Startup.';}
   catch{startupError='Windows could not change startup settings. Check Settings → Apps → Startup.';}
   push();
  });
  ipcMain.on('expand',(event,value)=>{if(valid(event)&&typeof value==='boolean'&&!settings){expanded=value||config.visibility==='always';if(!expanded)detailId=null;place();}});
  ipcMain.on('detail',(event,id)=>{if(valid(event)&&!settings&&(id===null||accounts.some(a=>a.id===id))){detailId=id;place();}});
  ipcMain.on('settings',event=>{if(valid(event)){settings=!settings;expanded=true;detailId=null;place();push();}});
  registerShortcut();push();
  refresh().catch(error=>fatal('main-error',error));
  refreshTimer=setInterval(()=>refresh().catch(error=>fatal('main-error',error)),120000);
  screen.on('display-metrics-changed',place);screen.on('display-added',()=>{place();push();});screen.on('display-removed',()=>{place();push();});
  powerMonitor.on('suspend',()=>poller.cancelPending());
  powerMonitor.on('resume',wake);powerMonitor.on('unlock-screen',wake);
 }).catch(error=>fatal('initialization-error',error));
}
