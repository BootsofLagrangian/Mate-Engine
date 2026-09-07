import {chromium} from 'playwright';
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/home/hard2251/.codex/chrome-for-testing/chrome-linux64/chrome',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try{
const page=await browser.newPage({viewport:{width:1280,height:850}});const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:8765');await page.waitForFunction(()=>window.avatarReady===true,null,{timeout:30000});await page.screenshot({path:'../logs/cheval-render.png'});console.log(JSON.stringify({avatarReady:await page.evaluate(()=>window.avatarReady),errors,body:await page.locator('body').innerText()}));
}finally{await browser.close();}
