const {test}=require('node:test');
const assert=require('node:assert/strict');
const {latestWindowsRelease,checkForUpdates,parseVersion}=require('../src/updates.cjs');
const page=v=>`https://github.com/s-chathuranga-j/AI-Notch/releases/tag/windows-v${v}`;
const releases=[
 {tag_name:'macos-v0.9.0',html_url:'https://github.com/s-chathuranga-j/AI-Notch/releases/tag/macos-v0.9.0'},
 {tag_name:'windows-v0.5.0',html_url:page('0.5.0'),draft:true},
 {tag_name:'windows-v0.4.10',html_url:page('0.4.10')},
 {tag_name:'windows-v0.4.9',html_url:page('0.4.9')},
 {tag_name:'windows-v0.6.0',html_url:'https://evil.example/windows-v0.6.0'}
];
const respond=(status,body)=>async()=>({status,ok:status>=200&&status<300,json:async()=>body});
test('the newest published Windows release is picked, by version not by order',()=>{
 assert.deepEqual(latestWindowsRelease(releases),{version:[0,4,10],url:page('0.4.10'),name:'0.4.10'});
 assert.equal(latestWindowsRelease('x'),null);assert.deepEqual(parseVersion('v1.2.3'),[1,2,3]);assert.equal(parseVersion('1.2'),null);
});
test('the check reports an available update, the latest version, or a clear error',async()=>{
 const available=await checkForUpdates('0.4.2',{fetch:respond(200,releases)});
 assert.equal(available.state,'available');assert.equal(available.url,page('0.4.10'));assert.match(available.message,/0\.4\.10 is available/);
 assert.equal((await checkForUpdates('0.4.10',{fetch:respond(200,releases)})).state,'current');
 assert.match((await checkForUpdates('0.4.2',{fetch:respond(403,{})})).message,/HTTP 403/);
 assert.match((await checkForUpdates('0.4.2',{fetch:async()=>{throw new Error('offline');}})).message,/Could not reach GitHub/);
 let options;await checkForUpdates('0.4.2',{fetch:async(_url,o)=>{options=o;return respond(200,[])();}});assert.equal(options.redirect,'error');
});
