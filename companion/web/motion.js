// Shared, bounded additive motion timeline. Each track returns to zero.
export function sampleTrack(track,time){
 const k=track.keys;if(time<=k[0].time)return [k[0].x,k[0].y,k[0].z];
 for(let i=1;i<k.length;i++){if(time<=k[i].time){const a=k[i-1],b=k[i];let u=(time-a.time)/(b.time-a.time);u=u*u*(3-2*u);return ['x','y','z'].map(c=>a[c]+(b[c]-a[c])*u);}}
 const last=k[k.length-1];return [last.x,last.y,last.z];
}
export function sampleMotion(motion,time){
 if(!motion||time<0||time>=motion.duration)return {};
 return Object.fromEntries(motion.tracks.map(track=>[track.bone,sampleTrack(track,time)]));
}
