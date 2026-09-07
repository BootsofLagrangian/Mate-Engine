import {PCMPlayer} from './stream-client.js';
import assert from 'node:assert/strict';
const starts=[];const context={currentTime:0,createBuffer:(_,n,rate)=>({duration:n/rate,getChannelData:()=>new Float32Array(n)}),createBufferSource:()=>({connect(){},disconnect(){},stop(){},start(t){starts.push(t);}})};
const player=new PCMPlayer(context,{});const pcm=Buffer.alloc(1280).toString('base64');player.enqueue(pcm,32000);assert.equal(starts[0],.035);
context.currentTime=.045;player.enqueue(pcm,32000);assert(Math.abs(starts[1]-.055)<1e-9);assert.deepEqual(player.gaps,[]);
context.currentTime=.100;player.enqueue(pcm,32000);assert(Math.abs(player.gaps[0]-28)<.00001);player.stop();assert.equal(player.frames,0);assert.equal(player.playing,false);console.log('PCM continuity / true scheduled-gap checks passed');
