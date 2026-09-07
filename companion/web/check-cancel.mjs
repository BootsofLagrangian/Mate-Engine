import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const browser=await chromium.launch({executablePath:'/home/hard2251/.codex/chrome-for-testing/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream','--autoplay-policy=no-user-gesture-required']});
try{
 const page=await browser.newPage({permissions:['microphone']});let chats=0;const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.url().endsWith('/chat/stream'))chats++;});await page.goto('http://127.0.0.1:8765');await page.waitForFunction(()=>window.avatarReady);
 // Delayed STT transport: a canceled old transcript must not start a new turn.
 let arrived;const sttArrived=new Promise(r=>arrived=r);let release;const gate=new Promise(r=>release=r);
 await page.route('**/stt',async route=>{arrived();await gate;await route.fulfill({json:{text:'이 오래된 응답은 말하지 마.'}}).catch(()=>{});});
 await page.locator('#mic').click();await page.waitForTimeout(400);await page.locator('#mic').click();await sttArrived;await page.locator('#stop').click();release();await page.waitForTimeout(400);assert.equal(chats,0);assert.equal(await page.locator('#mic').isEnabled(),true);
 // A close() transition that resolves after cancellation must release controls.
 await page.evaluate(()=>{const original=AudioContext.prototype.close;AudioContext.prototype.close=async function(){await new Promise(r=>setTimeout(r,700));return original.call(this);};});
 await page.locator('#mic').click();await page.waitForTimeout(300);await page.locator('#mic').click();await page.locator('#stop').click();await page.waitForTimeout(900);assert.equal(await page.locator('#mic').isEnabled(),true);assert.equal(await page.locator('#send').isEnabled(),true);assert.equal(chats,0);
 await page.locator('#text').fill('슈발, 안녕.');await page.locator('#send').click();await page.waitForFunction(()=>window.streamPlayback?.playing,null,{timeout:90000});await page.locator('#stop').click();await page.waitForTimeout(200);assert.equal(await page.evaluate(()=>window.streamPlayback.playing),false);assert.equal(await page.locator('#send').isEnabled(),true);assert.deepEqual(errors,[]);
 const report={delayedSttSuppressed:true,closeTransitionReleased:true,pcmStopped:true,chats,errors};fs.writeFileSync('../logs/cancellation-validation.json',JSON.stringify(report,null,2));console.log(report);
}finally{await browser.close();}
