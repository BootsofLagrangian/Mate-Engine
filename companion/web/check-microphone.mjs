import {chromium} from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
// A real browser microphone pipeline fed a known WAV, not a mocked STT response.
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/home/hard2251/.codex/chrome-for-testing/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream',`--use-file-for-fake-audio-capture=${path.resolve('../assets/reference.wav')}`,'--autoplay-policy=no-user-gesture-required']});
try{
 const context=await browser.newContext({permissions:['microphone']});const page=await context.newPage();const errors=[];let chatRequests=0;page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.url().endsWith('/chat/stream'))chatRequests++;});await page.goto('http://127.0.0.1:8765');await page.waitForFunction(()=>window.avatarReady);
 await page.locator('#mic').click();await page.waitForFunction(()=>document.querySelector('#mic').textContent==='녹음 끝내기');await page.locator('#text').fill('should not submit during recording');await page.locator('#text').press('Enter');await page.waitForTimeout(5200);assert.equal(chatRequests,0);
 const sttPromise=page.waitForResponse(r=>r.url().endsWith('/stt'),{timeout:180000});const chatPromise=page.waitForResponse(r=>r.url().endsWith('/chat/stream'),{timeout:300000});await page.locator('#mic').click();const stt=await(await sttPromise).json();await chatPromise;await page.waitForFunction(()=>window.lastReply,null,{timeout:90000});const chat=await page.evaluate(()=>window.lastReply);await page.waitForFunction(()=>!document.querySelector('#send').disabled,null,{timeout:10000});
 const report={stt,chat,chatRequests,errors};fs.writeFileSync('../logs/microphone-validation.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));assert(stt.text.length>0);assert(chat.audio_url);assert.equal(chatRequests,1);assert.deepEqual(errors,[]);
}finally{await browser.close();}
