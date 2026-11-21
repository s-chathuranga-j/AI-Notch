// Manual update check: runs only when the user presses Check for updates. Nothing is sent but the
// request itself, and nothing is downloaded or installed; the user opens the release page.
const RELEASES_URL='https://api.github.com/repos/s-chathuranga-j/AI-Notch/releases?per_page=30';
const RELEASE_PAGE=/^https:\/\/github\.com\/s-chathuranga-j\/AI-Notch\/releases\/tag\/windows-v\d+\.\d+\.\d+$/;

function parseVersion(text){const m=/^v?(\d+)\.(\d+)\.(\d+)$/.exec(String(text||'').trim());return m?m.slice(1).map(Number):null;}
function compareVersions(a,b){for(let i=0;i<3;i++)if(a[i]!==b[i])return a[i]-b[i];return 0;}
// The newest published Windows release, or null. The repository also publishes macOS releases.
function latestWindowsRelease(releases){
 let best=null;
 for(const r of Array.isArray(releases)?releases:[]){
  if(!r||r.draft||r.prerelease||typeof r.tag_name!=='string'||!r.tag_name.startsWith('windows-v'))continue;
  const version=parseVersion(r.tag_name.slice('windows-v'.length));
  const url=typeof r.html_url==='string'&&RELEASE_PAGE.test(r.html_url)?r.html_url:null;
  if(version&&url&&(!best||compareVersions(version,best.version)>0))best={version,url,name:version.join('.')};
 }
 return best;
}
async function checkForUpdates(current,dependencies={}){
 const mine=parseVersion(current);
 let response;
 try{
  response=await (dependencies.fetch||fetch)(RELEASES_URL,{headers:{Accept:'application/vnd.github+json','User-Agent':'AI-Notch-Windows'},redirect:'error',signal:AbortSignal.timeout(15000)});
 }catch{return {state:'error',message:'Could not reach GitHub. Try again later.'};}
 if(!response.ok)return {state:'error',message:`GitHub is unavailable (HTTP ${response.status}). Try again later.`};
 let data;
 try{data=await response.json();}catch{return {state:'error',message:'GitHub returned an unreadable response.'};}
 const latest=latestWindowsRelease(data);
 if(!latest||!mine)return {state:'error',message:'No Windows release found.'};
 return compareVersions(latest.version,mine)>0
  ?{state:'available',version:latest.name,url:latest.url,message:`Version ${latest.name} is available. You have ${mine.join('.')}.`}
  :{state:'current',version:mine.join('.'),message:`You have the latest version (${mine.join('.')}).`};
}
module.exports={parseVersion,compareVersions,latestWindowsRelease,checkForUpdates,RELEASE_PAGE};
