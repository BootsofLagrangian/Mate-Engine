import json,math,re
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[2];logs=root/'logs/windows-objects-premium';report=json.loads((logs/'report.json').read_text());measure=json.loads((root/'diagnostics/desktop_objects/premium-seat-raycast.json').read_text());meta=json.loads((root/'native/assets/desktop_objects/premium/objects.json').read_text())
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',12)
def vec(s):return [float(v) for v in re.findall(r'-?[0-9]+(?:\.[0-9]+)?',s)]
for kind in ['chair','sofa']:
 file=kind+'-composite-assumed-pet-front.png';im=Image.open(logs/file).convert('RGB');d=ImageDraw.Draw(im)
 cap=next(c for c in report['captures'] if c['file']==file);contact=next(c for c in report['contacts'] if c['label']==kind);origin=vec(cap['composite_origin']);sp=vec(contact['socket_px']);sp=[sp[i]-origin[i] for i in range(2)];seat=meta[kind]['sockets']['seat']
 w,h=Image.open(logs/(kind+'-prop.png')).size;lo,hi=measure[kind]['transformed_local_aabb_union'];size=[hi[i]-lo[i] for i in range(3)];cos=3/math.sqrt(9+.55**2);sin=.55/math.sqrt(9+.55**2);camera_size=max(size[1]*cos+size[2]*sin,size[0]/(w/h))*1.14;ppm=h/camera_size
 def project(x,y,z):return (sp[0]+ppm*(x-seat[0]),sp[1]-ppm*(cos*(y-seat[1])-sin*(z-seat[2])))
 d.rectangle((14,16,im.width-14,128),fill='white',outline='#777777');d.text((23,23),f'{kind.upper()} — geometric contact audit, assumed pet-over-prop composite',fill='black',font=font)
 texts=[f'Magenta: authored seat socket ({seat[0]}, {seat[1]}, {seat[2]})',f'Green: actual cushion top at x=+/-0.06m, same seat depth',f'Cyan: cushion surface at front depth z=0.22m; NOT contact target',f'Projection: {ppm:.2f} px/m, tilt {math.degrees(math.atan(.55/3)):.2f} deg; markers from imported GLB rays']
 for j,t in enumerate(texts):d.text((23,45+j*18),t,fill='black',font=font)
 # authored socket cross
 x,y=sp;d.line((x-12,y,x+12,y),fill='#de007e',width=2);d.line((x,y-12,x,y+12),fill='#de007e',width=2)
 for ray in measure[kind]['rays']:
  if ray['y'] is None or ray['x']==0:continue
  if abs(ray['z']-seat[2])<.001:color='#00a032'
  elif ray['z']==.22:color='#008bb5'
  else:continue
  px,py=project(ray['x'],ray['y'],ray['z']);d.ellipse((px-4,py-4,px+4,py+4),outline=color,width=2)
  if ray['x']>0:d.line((px+7,py,px+95,py),fill=color,width=1)
 # external label lower corner
 top=next(r['y'] for r in measure[kind]['rays'] if r['x']==.06 and abs(r['z']-seat[2])<.001);delta=(top-seat[1])*cos*ppm
 d.text((23,146),f'Socket is {1000*(top-seat[1]):.2f} mm / {delta:.2f} px BELOW bilateral cushion top.',fill='black',font=font)
 im.save(root/'diagnostics/desktop_objects/premium-previews'/(kind+'-native-seat-overlay.png'))
 measure[kind].update({'projection_ppm':ppm,'socket_composite_px':sp,'socket_below_bilateral_top_px':delta})
(root/'diagnostics/desktop_objects/premium-seat-raycast.json').write_text(json.dumps(measure,indent=2))
