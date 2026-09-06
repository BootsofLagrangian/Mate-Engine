import {chromium} from 'playwright';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {sampleMotion} from './motion.js';
const library=JSON.parse(fs.readFileSync('../../Assets/StreamingAssets/cheval-motions.json'));
for(const m of library.motions){
 assert(m.duration>0&&m.duration<=6);
 for(const track of m.tracks){assert.deepEqual([track.keys[0].x,track.keys[0].y,track.keys[0].z],[0,0,0]);const last=track.keys.at(-1);assert.deepEqual([last.x,last.y,last.z],[0,0,0]);assert(last.time===m.duration);for(let i=1;i<track.keys.length;i++)assert(track.keys[i].time>track.keys[i-1].time);}
 assert.deepEqual(sampleMotion(m,m.duration),{});
}
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/home/hard2251/.codex/chrome-for-testing/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const results=[];
try{
 const page=await browser.newPage({viewport:{width:1280,height:850}});const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:8765');await page.waitForFunction(()=>window.avatarReady&&window.motionsReady);await page.locator('#motion-picker summary').click();
 for(const m of library.motions){await page.locator(`[data-motion="${m.name}"]`).click();await page.waitForTimeout(m.duration*350);const active=await page.evaluate(()=>window.motionState);assert.equal(active.gesture,m.name);if(m.name!=='idle')assert(Object.values(active.offsets).flat().some(x=>Math.abs(x)>1));await page.screenshot({path:`../logs/motion-${m.name}.png`});await page.waitForTimeout(m.duration*700);const end=await page.evaluate(()=>window.motionState);assert.deepEqual(end.offsets,{});results.push({motion:m.name,active,end});}
 assert.deepEqual(errors,[]);fs.writeFileSync('../logs/motion-validation.json',JSON.stringify({results,errors},null,2));console.log('PASS: 8 rendered motions; nonzero active offsets; all returned to idle; no browser errors.');
}finally{await browser.close();}
