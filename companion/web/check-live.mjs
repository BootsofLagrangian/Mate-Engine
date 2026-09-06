import {chromium} from 'playwright';
import fs from 'node:fs';
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/home/hard2251/.codex/chrome-for-testing/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required']});
try{
 const page=await browser.newPage({viewport:{width:1280,height:850}});const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:8765');await page.waitForFunction(()=>window.avatarReady===true);
 await page.locator('#text').fill('슈발, 나한테 인사하고 손 흔들어줘.');await page.locator('#send').click();await page.waitForFunction(()=>window.lastReply&&window.streamPlayback?.playing,null,{timeout:90000});const result=await page.evaluate(()=>window.lastReply);await page.screenshot({path:'../logs/cheval-speaking.png'});
 const audio=await page.evaluate(()=>window.streamPlayback);const metrics=await page.evaluate(()=>window.streamMetrics);const report={result,audio,metrics,action:await page.evaluate(()=>window.lastAction),errors};fs.writeFileSync('../logs/browser-live.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
 if(!result.audio_url||result.voice_error||errors.length||!audio.playing||audio.gaps.length)throw Error('Live pipeline failed');
}finally{await browser.close();}
