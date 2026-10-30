const {test}=require('node:test');
const assert=require('node:assert/strict');
const {EventEmitter}=require('node:events');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const vm=require('node:vm');
const {Poller}=require('../src/providers.cjs');
const plain=value=>JSON.parse(JSON.stringify(value));

async function boot(t,options={}){
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ainotch-life-'));
 t.after(()=>fs.rmSync(directory,{recursive:true,force:true}));
 fs.writeFileSync(path.join(directory,'settings.json'),JSON.stringify({enabled:[],position:'right',visibility:options.visibility||'onHover'}));
 const app=new EventEmitter(),ipc=new EventEmitter(),power=new EventEmitter(),screen=new EventEmitter(),processMock=new EventEmitter();
 const windows=[],trays=[],handlers=new Map(),ready=[],timers=new Map(),intervals=new Map(),exits=[],relaunches=[],dialogs=[],loginWrites=[];
 let nextTimer=0,approved=options.approved!==false,registered=!!options.registered;
 app.isPackaged=options.packaged!==false;app.quits=0;
 app.getPath=()=>directory;
 app.whenReady=()=>({then:fn=>{const work=Promise.resolve().then(fn);ready.push(work);return work;}});
 app.requestSingleInstanceLock=()=>options.ownsLock!==false;
 app.setAppUserModelId=()=>{};
 app.getLoginItemSettings=()=>({openAtLogin:registered,executableWillLaunchAtLogin:registered&&approved});
 app.setLoginItemSettings=settings=>{if(options.loginDenied)throw new Error('synthetic-private-error');loginWrites.push(plain(settings));registered=settings.openAtLogin;approved=settings.enabled;};
 app.relaunch=value=>relaunches.push(plain(value));app.exit=value=>exits.push(value);
 app.quit=()=>{app.quits++;app.emit('before-quit');for(const window of [...windows])if(!window.destroyed)window.destroy();app.emit('quit');};
 class Window extends EventEmitter{
  constructor(settings){
   super();this.options=settings;this.visible=false;this.destroyed=false;this.loads=0;
   this.webContents=new EventEmitter();this.webContents.mainFrame={};this.webContents.sent=[];
   this.webContents.isDestroyed=()=>this.destroyed;
   this.webContents.setWindowOpenHandler=()=>{};
   this.webContents.send=(_channel,state)=>{if(this.failSend)throw new Error('Render frame was disposed');this.webContents.sent.push(plain(state));};
   this.webContents.forcefullyCrashRenderer=()=>this.webContents.emit('render-process-gone',{}, {reason:'killed'});
   windows.push(this);
  }
  isDestroyed(){return this.destroyed;}
  isVisible(){return this.visible;}
  setBounds(value){this.bounds=value;}
  setIgnoreMouseEvents(value){this.ignoresMouse=value;}
  showInactive(){this.visible=true;}
  show(){this.visible=true;}
  hide(){this.visible=false;}
  loadFile(){this.loads++;this.failSend=false;this.webContents.emit('did-finish-load');return Promise.resolve();}
  destroy(){this.destroyed=true;this.emit('closed');app.emit('window-all-closed');}
 }
 class Tray extends EventEmitter{constructor(){super();trays.push(this);}setToolTip(){}setContextMenu(menu){this.menu=menu;}}
 ipc.handle=(name,callback)=>handlers.set(name,callback);
 screen.getPrimaryDisplay=()=>({workArea:{x:0,y:0,width:1920,height:1040}});
 Object.assign(processMock,{platform:options.platform||'win32',argv:['AI Notch.exe',...(options.args||[])],execPath:'C:\\Users\\Example\\AppData\\Local\\Programs\\AI Notch\\AI Notch.exe'});
 const electron={app,ipcMain:ipc,powerMonitor:power,screen,BrowserWindow:Window,Tray,Menu:{buildFromTemplate:items=>items},session:{defaultSession:{webRequest:{onBeforeRequest(){}}}},dialog:{showErrorBox:(...args)=>dialogs.push(args)}};
 const context={
  require:name=>name==='electron'?electron:name==='./providers.cjs'?{Poller,discover:async()=>{if(options.discoveryFails)throw new Error('Bearer synthetic-secret');return [{id:'claude',kind:'claude',label:'Claude',dir:'/synthetic'}];},fetchUsage:async()=>[]}:name.startsWith('./')?require('../src/'+name.slice(2)):require(name),
  process:processMock,__dirname:path.dirname(require.resolve('../src/main.cjs')),
  setTimeout:fn=>{const id=++nextTimer;timers.set(id,fn);return id;},clearTimeout:id=>timers.delete(id),
  setInterval:fn=>{const id=++nextTimer;intervals.set(id,fn);return id;},clearInterval:id=>intervals.delete(id)
 };
 vm.runInNewContext(fs.readFileSync(require.resolve('../src/main.cjs'),'utf8'),context);
 await ready[0]?.catch(()=>{});await Promise.resolve();
 const event=()=>({sender:windows.at(-1).webContents,senderFrame:windows.at(-1).webContents.mainFrame});
 return {app,ipc,power,screen,windows,trays,exits,relaunches,dialogs,loginWrites,processMock,directory,ready,
  state:()=>windows.at(-1).webContents.sent.at(-1),
  invoke:(name,...args)=>handlers.get(name)(event(),...args),
  invokeInvalid:(name,...args)=>handlers.get(name)({sender:windows.at(-1).webContents,senderFrame:{}},...args),
  runTimers:()=>{for(const [id,callback] of [...timers]){timers.delete(id);callback();}},
  intervals,timers};
}

test('a lost last window is recreated while the tray app stays alive',async t=>{
 const ui=await boot(t);assert.equal(ui.app.listenerCount('window-all-closed'),1);
 ui.windows[0].destroy();
 assert.equal(ui.windows.length,2);assert.equal(ui.windows[1].visible,true);assert.equal(ui.app.quits,0);
 assert.equal(ui.trays.length,1);
});
test('renderer crash and unresponsive renderer restore the display with bounded recovery',async t=>{
 const ui=await boot(t);const window=ui.windows[0];
 window.emit('unresponsive');await Promise.resolve();
 assert.equal(window.loads,2);assert.equal(ui.relaunches.length,0);
 window.webContents.emit('render-process-gone',{}, {reason:'crashed'});await Promise.resolve();
 assert.equal(ui.relaunches.length,1);assert.deepEqual(ui.exits,[1]);
});
test('sleep cancels polling and wake or unlock restores a hidden window and its placement',async t=>{
 const ui=await boot(t);const window=ui.windows[0];window.hide();
 ui.power.emit('suspend');ui.power.emit('resume');ui.power.emit('unlock-screen');
 assert.equal(ui.timers.size,1);ui.runTimers();
 assert.equal(window.visible,true);assert.equal(window.bounds.x+window.bounds.width,1920);
 assert.equal(ui.relaunches.length,0);
});
test('a transient zero-sized display while docking or waking cannot destroy the notch',async t=>{
 const ui=await boot(t);const previous=ui.windows[0].bounds;
 ui.screen.getPrimaryDisplay=()=>({workArea:{x:0,y:0,width:0,height:0}});
 ui.screen.emit('display-removed');
 assert.equal(ui.windows[0].bounds,previous);assert.equal(ui.relaunches.length,0);
 ui.screen.getPrimaryDisplay=()=>({workArea:{x:-1280,y:0,width:1280,height:800}});
 ui.screen.emit('display-added');
 assert.equal(ui.windows[0].bounds.x+ui.windows[0].bounds.width,0);
});
test('Show AI Notch genuinely restores hidden mode and double launch uses the same path',async t=>{
 const ui=await boot(t,{visibility:'hidden'});const window=ui.windows[0];assert.equal(window.visible,false);
 ui.trays[0].menu.find(item=>item.label==='Show AI Notch').click();
 assert.equal(window.visible,true);assert.equal(window.ignoresMouse,false);
 assert.equal(ui.state().visibility,'onHover');assert.equal(ui.state().expanded,true);
 ui.app.emit('second-instance');await ui.ready.at(-1);
 assert.equal(ui.windows.length,1);assert.equal(window.visible,true);
 await ui.invoke('position','right');
 assert.equal(JSON.parse(fs.readFileSync(path.join(ui.directory,'settings.json'),'utf8')).visibility,'onHover');
});
test('explicit quit and Windows session end never respawn the window',async t=>{
 const ui=await boot(t);ui.trays[0].menu.find(item=>item.label==='Quit').click();
 assert.equal(ui.app.quits,1);assert.equal(ui.windows.length,1);assert.equal(ui.intervals.size,0);
 const session=await boot(t);session.windows[0].emit('session-end');session.windows[0].destroy();
 assert.equal(session.windows.length,1);assert.equal(session.relaunches.length,0);
});
test('startup uses the installed executable and exposes the actual Windows approval status',async t=>{
 const ui=await boot(t,{registered:true,approved:false});
 assert.equal(ui.state().startupAvailable,true);assert.equal(ui.state().startWithWindows,false);
 ui.invokeInvalid('startup',true);ui.invoke('startup','true');assert.equal(ui.loginWrites.length,0);
 ui.invoke('startup',true);
 assert.deepEqual(ui.loginWrites[0],{path:ui.processMock.execPath,args:['--startup'],name:'AI Notch',openAtLogin:true,enabled:true});
 assert.equal(ui.state().startWithWindows,true);
 ui.invoke('startup',false);assert.equal(ui.state().startWithWindows,false);
});
test('startup is opt-in, cannot be registered in preview, and handles Windows refusal',async t=>{
 const ui=await boot(t);assert.equal(ui.loginWrites.length,0);
 const preview=await boot(t,{platform:'darwin'});
 preview.invoke('startup',true);assert.equal(preview.loginWrites.length,0);assert.equal(preview.state().startupAvailable,false);
 const denied=await boot(t,{loginDenied:true});denied.invoke('startup',true);
 assert.match(denied.state().startupError,/Windows could not change/);
 assert.ok(!JSON.stringify(denied.state()).includes('synthetic-private-error'));
});
test('initialization and main-process exceptions restart once without leaking errors',async t=>{
 const ui=await boot(t,{discoveryFails:true});assert.equal(ui.relaunches.length,1);
 assert.match(ui.relaunches[0].args.at(-1),/^--ainotch-recovery=\d+$/);
 assert.ok(!fs.readFileSync(path.join(ui.directory,'lifecycle.log'),'utf8').includes('synthetic-secret'));
 const repeat=await boot(t,{args:['--ainotch-recovery='+Date.now()],discoveryFails:true});
 assert.equal(repeat.relaunches.length,0);assert.equal(repeat.dialogs.length,1);assert.deepEqual(repeat.exits,[1]);
 const main=await boot(t);main.processMock.emit('uncaughtException',new Error('Bearer synthetic-secret'));
 assert.equal(main.relaunches.length,1);assert.ok(!fs.readFileSync(path.join(main.directory,'lifecycle.log'),'utf8').includes('synthetic-secret'));
});
test('a transient renderer send failure cannot reject polling or kill the app',async t=>{
 const ui=await boot(t);ui.windows[0].failSend=true;
 assert.doesNotThrow(()=>ui.windows[0].emit('focus'));
 assert.equal(ui.exits.length,0);
});
test('a second process exits without installing recovery or startup hooks',async t=>{
 const ui=await boot(t,{ownsLock:false});
 assert.equal(ui.app.quits,1);assert.equal(ui.windows.length,0);
 assert.equal(ui.processMock.listenerCount('uncaughtException'),0);assert.equal(ui.loginWrites.length,0);
});
test('settings writes remain readable and preserve the existing account choices',async t=>{
 const ui=await boot(t);
 await ui.invoke('position','left');await ui.invoke('visibility','always');
 const saved=JSON.parse(fs.readFileSync(path.join(ui.directory,'settings.json'),'utf8'));
 assert.deepEqual(saved,{enabled:[],position:'left',visibility:'always'});
 assert.equal(fs.existsSync(path.join(ui.directory,'settings.json.tmp')),false);
});
