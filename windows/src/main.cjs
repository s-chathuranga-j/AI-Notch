const {app,BrowserWindow,Tray,Menu,nativeImage,ipcMain,screen,session}=require('electron');
const fs=require('node:fs/promises');const path=require('node:path');const os=require('node:os');
const {discover,Poller,fetchUsage}=require('./providers.cjs');
const {notchBounds}=require('./layout.cjs');
const demo=process.platform!=='win32'||process.argv.includes('--demo');
let win,tray,accounts=[],config={enabled:[],position:'top'},rows={},settings=false,expanded=false,detailId=null;
const poller=new Poller(demo?async account=>account.kind==='copilot'?[{label:'AI credits',percent:28,reset:new Date(Date.now()+604800000).toISOString()},{label:'Completions',percent:null,unlimited:true,reset:null}]:[{label:'Session',percent:account.kind==='claude'?37:62,reset:new Date(Date.now()+7200000).toISOString()},{label:'Weekly',percent:21,reset:null}]:fetchUsage,(id,row)=>{rows[id]=row;push();});
function state(){return {demo,settings,expanded,detailId,position:config.position,accounts:accounts.map(({id,label,kind})=>({id,label,kind,enabled:poller.enabled.has(id),...(rows[id]||{status:'Disabled',windows:[]})}))};}
function push(){if(win&&!win.isDestroyed())win.webContents.send('state',state());}
function place(){if(!win)return;win.setBounds(notchBounds(screen.getPrimaryDisplay().workArea,config.position,accounts.length,expanded,settings,detailId!==null));}
let saving=Promise.resolve();
function save(){if(demo)return Promise.resolve();const payload=JSON.stringify(config);saving=saving.catch(()=>{}).then(()=>fs.writeFile(path.join(app.getPath('userData'),'settings.json'),payload,{mode:0o600}));return saving;}
async function refresh(){await Promise.all(accounts.map(a=>poller.refresh(a)));}
if(!app.requestSingleInstanceLock())app.quit();else {
app.on('second-instance',()=>{win?.show();});
app.whenReady().then(async()=>{
 if(demo){accounts=[{id:'claude',kind:'claude',label:'Claude · Personal'},{id:'claude-work',kind:'claude',label:'Claude · Work'},{id:'codex',kind:'codex',label:'Codex'},{id:'copilot',kind:'copilot',label:'GitHub Copilot'}];config.enabled=accounts.map(a=>a.id);}
 else {accounts=await discover(os.homedir());try{const saved=JSON.parse(await fs.readFile(path.join(app.getPath('userData'),'settings.json'),'utf8'));config.enabled=Array.isArray(saved.enabled)?saved.enabled.filter(x=>typeof x==='string'):[];if(['top','bottom','left','right'].includes(saved.position))config.position=saved.position;}catch{}}
 config.enabled.forEach(id=>poller.enabled.add(id));
 session.defaultSession.webRequest.onBeforeRequest((details,callback)=>callback({cancel:!details.url.startsWith('file:')}));
 win=new BrowserWindow({width:80,height:6,frame:false,transparent:true,backgroundColor:'#00000000',hasShadow:false,resizable:false,alwaysOnTop:true,skipTaskbar:true,show:false,webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false}});
 win.webContents.setWindowOpenHandler(()=>({action:'deny'}));win.webContents.on('will-navigate',event=>event.preventDefault());
 win.on('close',event=>{if(!app.quitting){event.preventDefault();win.hide();}});
 tray=new Tray(nativeImage.createFromPath(path.join(__dirname,'tray.png')));tray.setToolTip('AI Notch');
 const openSettings=()=>{settings=true;expanded=true;place();win.show();push();};
 tray.setContextMenu(Menu.buildFromTemplate([{label:'Show AI Notch',click:()=>win.show()},{label:'Settings',click:openSettings},{label:'Refresh usage',click:refresh},{type:'separator'},{label:'Quit',click:()=>{app.quitting=true;app.quit();}}]));tray.on('click',()=>win.show());
 function valid(event){return event.sender===win.webContents && event.senderFrame===win.webContents.mainFrame;}
 ipcMain.handle('state',event=>valid(event)?state():null);
 ipcMain.handle('toggle',async(event,id,on)=>{if(!valid(event)||typeof on!=='boolean')return;const a=accounts.find(a=>a.id===id);if(!a)return;if(on){poller.enabled.add(id);rows[id]={status:'Loading…',windows:[]};}else poller.disable(id);config.enabled=[...poller.enabled];await save();push();if(on)await poller.refresh(a);});
 ipcMain.handle('retry',event=>{if(valid(event))return refresh();});
 ipcMain.handle('position',async(event,value)=>{if(valid(event)&&['top','bottom','left','right'].includes(value)){config.position=value;await save();place();push();}});
 ipcMain.on('expand',(event,value)=>{if(valid(event)&&typeof value==='boolean'&&!settings){expanded=value;if(!value)detailId=null;place();}});
 ipcMain.on('detail',(event,id)=>{if(valid(event)&&!settings&&(id===null||accounts.some(a=>a.id===id))){detailId=id;place();}});
 ipcMain.on('settings',event=>{if(valid(event)){settings=!settings;expanded=true;detailId=null;place();push();}});
 await win.loadFile(path.join(__dirname,'index.html'));place();win.show();push();await refresh();
 setInterval(refresh,120000).unref();screen.on('display-metrics-changed',place);
});
app.on('before-quit',()=>{app.quitting=true;for(const id of poller.enabled)poller.disable(id);});
}
