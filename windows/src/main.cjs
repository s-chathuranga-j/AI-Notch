const {app,BrowserWindow,Tray,Menu,ipcMain,screen,session,powerMonitor,dialog}=require('electron');
const fs=require('node:fs/promises');const path=require('node:path');const os=require('node:os');
const {discover,Poller,fetchUsage}=require('./providers.cjs');
const {notchBounds}=require('./layout.cjs');
const {record}=require('./diagnostics.cjs');
const demo=process.platform!=='win32'||process.argv.includes('--demo');
const icon=path.join(__dirname,process.platform==='win32'?'assets/app.ico':'tray.png');
const VISIBILITIES=['onHover','always','hidden'];
const loginOptions={path:process.execPath,args:['--startup']};
let win,tray,wakeTimer,refreshTimer,startupError='',lastRendererRecovery=0;
let accounts=[],config={enabled:[],position:'top',visibility:'onHover'},rows={},settings=false,expanded=false,detailId=null;
const poller=new Poller(demo?async account=>account.kind==='copilot'?[{label:'AI credits',percent:28,reset:new Date(Date.now()+604800000).toISOString()},{label:'Completions',percent:null,unlimited:true,reset:null}]:[{label:'Session',percent:account.kind==='claude'?37:62,reset:new Date(Date.now()+7200000).toISOString()},{label:'Weekly',percent:21,reset:null}]:fetchUsage,(id,row)=>{rows[id]=row;push();});
function log(event,code){record(app.getPath('userData'),event,code);}
function startupState(){
 const startupAvailable=process.platform==='win32'&&app.isPackaged&&!demo;
 if(!startupAvailable)return {startupAvailable:false,startWithWindows:false,startupError:''};
 try{return {startupAvailable:true,startWithWindows:app.getLoginItemSettings(loginOptions).executableWillLaunchAtLogin,startupError};}
 catch{return {startupAvailable:false,startWithWindows:false,startupError:'Windows startup settings could not be read.'};}
}
function state(){return {demo,settings,expanded,detailId,position:config.position,visibility:config.visibility,...startupState(),accounts:accounts.map(({id,label,kind})=>({id,label,kind,enabled:poller.enabled.has(id),...(rows[id]||{status:'Disabled',windows:[]})}))};}
function push(){
 if(app.quitting||!win||win.isDestroyed()||win.webContents.isDestroyed())return;
 try{win.webContents.send('state',state());}catch{log('renderer-gone');}
}
function place(){
 if(!win||win.isDestroyed()||app.quitting)return;
 const open=expanded||config.visibility==='always';
 const area=screen.getPrimaryDisplay().workArea;
 if(area.width<=0||area.height<=0)return;
 win.setBounds(notchBounds(area,config.position,accounts.length,open,settings,detailId!==null));
 const hidden=config.visibility==='hidden'&&!settings;
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
function stop(){app.quitting=true;clearTimeout(wakeTimer);clearInterval(refreshTimer);poller.cancelPending();}
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
   try{const saved=JSON.parse(await fs.readFile(path.join(app.getPath('userData'),'settings.json'),'utf8'));config.enabled=Array.isArray(saved.enabled)?saved.enabled.filter(x=>typeof x==='string'):[];if(['top','bottom','left','right'].includes(saved.position))config.position=saved.position;if(VISIBILITIES.includes(saved.visibility))config.visibility=saved.visibility;}catch{}
  }
  config.enabled.forEach(id=>poller.enabled.add(id));
  session.defaultSession.webRequest.onBeforeRequest((details,callback)=>callback({cancel:!details.url.startsWith('file:')}));
  tray=new Tray(icon);tray.setToolTip('AI Notch');
  tray.setContextMenu(Menu.buildFromTemplate([{label:'Show AI Notch',click:showNotch},{label:'Settings',click:openSettings},{label:'Refresh usage',click:()=>refresh().catch(error=>fatal('main-error',error))},{type:'separator'},{label:'Quit',click:()=>app.quit()}]));
  tray.on('click',openSettings);
  createWindow();
  function valid(event){return win&&!win.isDestroyed()&&event.sender===win.webContents&&event.senderFrame===win.webContents.mainFrame;}
  ipcMain.handle('state',event=>valid(event)?state():null);
  ipcMain.handle('toggle',async(event,id,on)=>{if(!valid(event)||typeof on!=='boolean')return;const a=accounts.find(a=>a.id===id);if(!a)return;if(on){poller.enabled.add(id);rows[id]={status:'Loading…',windows:[]};}else poller.disable(id);config.enabled=[...poller.enabled];await save();push();if(on)await poller.refresh(a);});
  ipcMain.handle('retry',event=>{if(valid(event))return refresh();});
  ipcMain.handle('position',async(event,value)=>{if(valid(event)&&['top','bottom','left','right'].includes(value)){config.position=value;await save();place();push();}});
  ipcMain.handle('visibility',async(event,value)=>{if(valid(event)&&VISIBILITIES.includes(value)){config.visibility=value;expanded=value==='always';detailId=null;await save();place();push();}});
  ipcMain.handle('startup',(event,value)=>{
   if(!valid(event)||typeof value!=='boolean'||!startupState().startupAvailable)return;
   try{app.setLoginItemSettings({...loginOptions,name:'AI Notch',openAtLogin:value,enabled:value});startupError='';}
   catch{startupError='Windows could not change startup settings. Check Settings → Apps → Startup.';}
   push();
  });
  ipcMain.on('expand',(event,value)=>{if(valid(event)&&typeof value==='boolean'&&!settings){expanded=value||config.visibility==='always';if(!expanded)detailId=null;place();}});
  ipcMain.on('detail',(event,id)=>{if(valid(event)&&!settings&&(id===null||accounts.some(a=>a.id===id))){detailId=id;place();}});
  ipcMain.on('settings',event=>{if(valid(event)){settings=!settings;expanded=true;detailId=null;place();push();}});
  refresh().catch(error=>fatal('main-error',error));
  refreshTimer=setInterval(()=>refresh().catch(error=>fatal('main-error',error)),120000);
  screen.on('display-metrics-changed',place);screen.on('display-added',place);screen.on('display-removed',place);
  powerMonitor.on('suspend',()=>poller.cancelPending());
  powerMonitor.on('resume',wake);powerMonitor.on('unlock-screen',wake);
 }).catch(error=>fatal('initialization-error',error));
}
