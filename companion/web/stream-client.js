export async function* readEvents(response){
 if(!response.ok)throw Error((await response.text())||response.statusText);
 const reader=response.body.getReader(),decoder=new TextDecoder();let buffer='';
 try{while(true){const {done,value}=await reader.read();if(done){buffer+=decoder.decode();break;}buffer+=decoder.decode(value,{stream:true});let index;while((index=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,index);buffer=buffer.slice(index+1);if(line.trim())yield JSON.parse(line);}}if(buffer.trim())yield JSON.parse(buffer);}
 finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
}

export class PCMPlayer{
 constructor(context,destination){this.context=context;this.destination=destination;this.nodes=new Set();this.playhead=0;this.frames=0;this.gaps=[];}
 get playing(){return this.context.currentTime<this.playhead&&this.nodes.size>0;}
 enqueue(base64,rate){
  const binary=atob(base64),bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
  if(bytes.length%2)throw Error('Invalid PCM frame');
  const view=new DataView(bytes.buffer),buffer=this.context.createBuffer(1,bytes.length/2,rate),out=buffer.getChannelData(0);
  for(let i=0;i<out.length;i++)out[i]=view.getInt16(i*2,true)/32768;
  const node=this.context.createBufferSource();node.buffer=buffer;node.connect(this.destination);this.nodes.add(node);node.onended=()=>{node.disconnect();this.nodes.delete(node);};
  const now=this.context.currentTime;
  const start=Math.max(now+(this.frames===0?.035:.003),this.playhead);
  if(this.frames>0&&start>this.playhead)this.gaps.push((start-this.playhead)*1000);node.start(start);this.playhead=start+buffer.duration;this.frames++;
  return start;
 }
 stop(){for(const node of this.nodes){try{node.stop();}catch{}node.disconnect();}this.nodes.clear();this.playhead=0;this.frames=0;this.gaps=[];}
}
