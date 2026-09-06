import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';
import './style.css';
import {sampleMotion} from './motion.js';
import {readEvents,PCMPlayer} from './stream-client.js';
const $ = id => document.getElementById(id);
let renderer;
try{renderer=new THREE.WebGLRenderer({canvas:$('avatar'),antialias:true,alpha:true});renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.outputColorSpace=THREE.SRGBColorSpace;}catch(e){$('state').textContent='WebGL을 사용할 수 없어요. 브라우저 그래픽 설정을 확인해 주세요.';console.error(e);}
const scene=new THREE.Scene(), camera=new THREE.PerspectiveCamera(30,1,.1,100);
camera.position.set(0,1.25,3.9);
const controls=renderer?new OrbitControls(camera,renderer.domElement):{target:new THREE.Vector3(),update(){}};controls.target.set(0,.9,0);controls.enablePan=false;controls.minDistance=1.4;controls.maxDistance=6;controls.update();
const gaze=new THREE.Object3D();gaze.position.set(0,1.3,3);scene.add(gaze);
const gazeTarget=gaze.position.clone();
$('stage').addEventListener('pointermove',e=>{const r=$('stage').getBoundingClientRect();gazeTarget.set(((e.clientX-r.left)/r.width-.5)*1.2,1.3+(.5-(e.clientY-r.top)/r.height)*.6,3);});
$('stage').addEventListener('pointerleave',()=>gazeTarget.set(0,1.3,3));
scene.add(new THREE.HemisphereLight(0xe5edff,0x8c8390,2.5));
const light=new THREE.DirectionalLight(0xffeedc,2.2);light.position.set(-2,3,4);scene.add(light);
const ground=new THREE.Mesh(new THREE.CircleGeometry(.72,64),new THREE.MeshBasicMaterial({color:0xaca8b9,transparent:true,opacity:.17}));ground.rotation.x=-Math.PI/2;ground.position.y=.005;scene.add(ground);
let motions={},vrm,base={},gesture='idle',emotion='neutral',started=0,until=0,analyser,audioContext,frequency;
const loader=new GLTFLoader();loader.register(parser=>new VRMLoaderPlugin(parser));
loader.load('/avatar',gltf=>{vrm=gltf.userData.vrm;VRMUtils.rotateVRM0(vrm);scene.add(vrm.scene);vrm.scene.updateMatrixWorld(true);vrm.springBoneManager?.reset();if(vrm.lookAt)vrm.lookAt.target=gaze;
 for(const n of ['head','neck','spine','chest','leftUpperArm','rightUpperArm','leftLowerArm','rightLowerArm']){const b=vrm.humanoid.getNormalizedBoneNode(n);if(b)base[n]=b.rotation.clone();}
 if(renderer){$('state').textContent='함께 있어요';window.avatarReady=true;}
},undefined,e=>{$('state').textContent='VRM 로드 실패';console.error(e);});
function pose(name,x=0,y=0,z=0){const bone=vrm?.humanoid.getNormalizedBoneNode(name);if(bone&&base[name]){bone.rotation.copy(base[name]);bone.rotation.x+=x;bone.rotation.y+=y;bone.rotation.z+=z;}}
function act(result){gesture=result.gesture;emotion=result.emotion;started=performance.now()/1000;until=started+(motions[gesture]?.duration||4);window.lastAction={gesture,emotion};}
function resize(){const r=$('stage').getBoundingClientRect();renderer?.setSize(r.width,r.height,false);camera.aspect=r.width/r.height;camera.updateProjectionMatrix();}new ResizeObserver(resize).observe($('stage'));
const clock=new THREE.Clock();let lastFrame=0;
function frame(now=performance.now()){requestAnimationFrame(frame);if(now-lastFrame<1000/30)return;lastFrame=now;const dt=Math.min(clock.getDelta(),.05),t=performance.now()/1000;
 gaze.position.lerp(gazeTarget,1-Math.exp(-dt*3));
 if(vrm){for(const name in base)pose(name);pose('leftUpperArm',0,0,1.15);pose('rightUpperArm',0,0,-1.15);pose('leftLowerArm',0,-.12,0);pose('rightLowerArm',0,.12,0);pose('spine',Math.sin(t*1.5)*.012,0,Math.sin(t*.65)*.012);
 const active=t<until;const a=active?Math.sin(Math.PI*Math.min((t-started)/.6,1)/2)*Math.min(1,(until-t)/.6):0;
 const sampled=sampleMotion(motions[gesture],t-started);
 for(const [name,rot] of Object.entries(sampled)){const b=vrm.humanoid.getNormalizedBoneNode(name);if(b){b.rotation.x-=THREE.MathUtils.degToRad(rot[0]);b.rotation.y+=THREE.MathUtils.degToRad(rot[1]);b.rotation.z+=THREE.MathUtils.degToRad(rot[2]);}}
 window.motionState={gesture,active,offsets:sampled};
 const em=vrm.expressionManager;for(const e of ['happy','sad','relaxed','surprised'])em?.setValue(e,e===emotion?.toLowerCase()?a*.45:0);
 const blink=Math.sin(t*1.1)>0.997?1:0;em?.setValue('blink',blink);
 let mouth=0;if(analyser&&(pcmPlayer?.playing||!$('speech').paused)){analyser.getByteTimeDomainData(frequency);let s=0;for(const v of frequency)s+=((v-128)/128)**2;mouth=Math.min(1,Math.sqrt(s/frequency.length)*5);}
 em?.setValue('aa',mouth);vrm.update(dt);
 }window.streamPlayback={playing:pcmPlayer?.playing||false,gaps:pcmPlayer?.gaps||[],frames:pcmPlayer?.frames||0,queuedSeconds:pcmPlayer?Math.max(0,pcmPlayer.playhead-audioContext.currentTime):0};$('stop').hidden=!busy&&!pcmPlayer?.playing;controls.update();renderer?.render(scene,camera);
}requestAnimationFrame(frame);
function bubble(text,who){const e=document.createElement('div');e.className='bubble '+who;e.textContent=text;$('messages').append(e);e.scrollIntoView({block:'nearest'});return e;}
let busy=false,stream,processor,source,recordContext,frames=[],recording=false,recordTimer,micTransition=false;
let pcmPlayer,turnId=0,streamController=null,sttController=null;
const session=crypto.randomUUID();
function setBusy(v){busy=v;$('send').disabled=v||recording;$('mic').disabled=micTransition||(v&&!streamController&&!sttController);$('reset').disabled=v||recording;}
async function audioSetup(){if(!audioContext){audioContext=new AudioContext({latencyHint:'interactive'});analyser=audioContext.createAnalyser();analyser.fftSize=256;frequency=new Uint8Array(analyser.fftSize);const src=audioContext.createMediaElementSource($('speech'));src.connect(analyser);analyser.connect(audioContext.destination);pcmPlayer=new PCMPlayer(audioContext,analyser);}await audioContext.resume();}
function stopPlayback(){pcmPlayer?.stop();$('speech').pause();}
function cancelTurn(){turnId++;streamController?.abort();sttController?.abort();streamController=null;sttController=null;micTransition=false;stopPlayback();setBusy(false);$('status').textContent='멈췄어요. 다시 이야기해 주세요.';}
$('stop').onclick=cancelTurn;
async function send(text){
 if(busy||recording||micTransition||!text.trim())return;
 const turn=++turnId;streamController=new AbortController();const controller=streamController;setBusy(true);stopPlayback();
 const useVoice=$('voice').checked,start=performance.now();let receivedDone=false,firstAudio=false,pendingAction=null;
 window.streamMetrics={};
 try{
  if(useVoice)await audioSetup();if(turn!==turnId)return;
  bubble(text,'user');const answer=bubble('…','assistant');$('text').value='';$('status').textContent='듣고 답하고 있어요…';
  const response=await fetch('/chat/stream',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text,session,voice:useVoice}),signal:controller.signal});
  for await(const event of readEvents(response)){
   if(turn!==turnId)break;
   if(event.type==='text'){answer.textContent=event.text;window.streamMetrics.firstTextMs??=performance.now()-start;}
   else if(event.type==='action'){pendingAction=event;if(firstAudio||!useVoice)act(event);}
   else if(event.type==='audio'){
    const scheduled=pcmPlayer.enqueue(event.pcm,event.sample_rate);
    if(!firstAudio){firstAudio=true;window.streamMetrics.firstAudioMs=performance.now()-start+(scheduled-audioContext.currentTime)*1000;if(pendingAction)act(pendingAction);$('status').textContent='이야기하고 있어요…';}
   }
   else if(event.type==='voice_error')$('status').textContent='음성 오류: '+event.message;
   else if(event.type==='error')throw Error(event.message);
   else if(event.type==='done'){
    receivedDone=true;window.streamMetrics.server=event.timings;window.streamMetrics.totalMs=performance.now()-start;window.lastReply=event;
    answer.textContent=event.text||answer.textContent;
    if(!pendingAction&&event.gesture)act(event);
    $('status').textContent=event.voice_error?'음성 오류: '+event.voice_error:`첫 ${firstAudio?'음성':'응답'} ${((firstAudio?window.streamMetrics.firstAudioMs:window.streamMetrics.firstTextMs)/1000).toFixed(2)}초 · ${event.gesture||'idle'}`;
    if(event.audio_url){$('speech').src=event.audio_url;$('speech').hidden=false;}
   }
  }
  if(turn===turnId&&!receivedDone)throw Error('응답 연결이 끊어졌어요. 다시 시도해 주세요.');
 }catch(e){if(e.name!=='AbortError'&&turn===turnId){stopPlayback();$('status').textContent='오류: '+e.message;}}
 finally{if(turn===turnId){streamController=null;setBusy(false);}}
}
$('form').onsubmit=e=>{e.preventDefault();send($('text').value);};$('text').onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();send($('text').value);}};
$('reset').onclick=async()=>{const r=await fetch(`/sessions/${session}/reset`,{method:'POST'});if(r.ok){$('messages').replaceChildren();stopPlayback();$('status').textContent='새 대화를 시작합니다.';}};
function wav(samples,rate){const buf=new ArrayBuffer(44+samples.length*2),v=new DataView(buf);const str=(i,s)=>{for(let n=0;n<s.length;n++)v.setUint8(i+n,s.charCodeAt(n));};str(0,'RIFF');v.setUint32(4,36+samples.length*2,true);str(8,'WAVE');str(12,'fmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);v.setUint32(24,rate,true);v.setUint32(28,rate*2,true);v.setUint16(32,2,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,samples.length*2,true);samples.forEach((s,i)=>v.setInt16(44+i*2,Math.max(-1,Math.min(1,s))*32767,true));return new Blob([buf],{type:'audio/wav'});}
async function stopRecording(){
 if(!recording||micTransition)return;
 const sttTurn=++turnId,context=recordContext,captured=frames,rate=context.sampleRate;
 const controller=new AbortController();sttController=controller;
 micTransition=true;recording=false;setBusy(true);clearTimeout(recordTimer);processor.disconnect();source.disconnect();stream.getTracks().forEach(t=>t.stop());
 try{
  await context.close();if(sttTurn!==turnId)return;
  micTransition=false;$('mic').textContent='마이크';setBusy(true);$('status').textContent='음성을 받아쓰고 있어요…';
  const samples=new Float32Array(captured.reduce((s,f)=>s+f.length,0));let o=0;for(const f of captured){samples.set(f,o);o+=f.length;}
  const form=new FormData();form.append('audio',wav(samples,rate),'recording.wav');
  const r=await fetch('/stt',{method:'POST',body:form,signal:controller.signal});const result=await r.json();
  if(sttTurn!==turnId)return;if(!r.ok)throw Error(result.detail);
  sttController=null;setBusy(false);
  if(result.text)await send(result.text);else $('status').textContent='말소리가 감지되지 않았어요.';
 }catch(e){if(e.name!=='AbortError'&&sttTurn===turnId)$('status').textContent='마이크 오류: '+e.message;}
 finally{if(sttTurn===turnId){sttController=null;micTransition=false;setBusy(false);}}
}
$('mic').onclick=async()=>{if(micTransition)return;if(busy){if(streamController||sttController)cancelTurn();else return;}if(recording){await stopRecording();return;}micTransition=true;$('mic').disabled=true;try{stopPlayback();stream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true},video:false});recordContext=new AudioContext();source=recordContext.createMediaStreamSource(stream);processor=recordContext.createScriptProcessor(4096,1,1);frames=[];processor.onaudioprocess=e=>{if(recording)frames.push(new Float32Array(e.inputBuffer.getChannelData(0)));};source.connect(processor);processor.connect(recordContext.destination);recording=true;micTransition=false;$('mic').disabled=false;$('send').disabled=true;$('reset').disabled=true;$('mic').textContent='녹음 끝내기';$('status').textContent='듣고 있어요… (최대 30초)';recordTimer=setTimeout(stopRecording,29500);}catch(e){stream?.getTracks().forEach(t=>t.stop());if(recordContext&&recordContext.state!=='closed')await recordContext.close();micTransition=false;setBusy(false);$('status').textContent='마이크 접근 실패: '+e.message;}};
fetch('/health').then(r=>r.json()).then(h=>{$('status').textContent=`${h.llm} · ${h.device.toUpperCase()} · 음성 ${h.tts_ready?'준비됨':'서버 준비 중'}`;}).catch(e=>{$('status').textContent=e.message;});

fetch('/motions').then(r=>r.json()).then(data=>{motions=Object.fromEntries(data.motions.map(m=>[m.name,m]));window.motionsReady=true;const labels={idle:'기본',nod:'끄덕임',shake_head:'고개 젓기',shy:'수줍음',wave:'손 흔들기',think:'생각',bow:'인사',stretch:'기지개'};for(const m of data.motions){const b=document.createElement('button');b.textContent=labels[m.name]||m.name;b.dataset.motion=m.name;b.onclick=()=>act({gesture:m.name,emotion:m.name==='wave'?'happy':'relaxed'});$('motion-buttons').append(b);}}).catch(e=>console.error(e));
