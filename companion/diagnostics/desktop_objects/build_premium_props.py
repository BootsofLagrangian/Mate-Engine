"""Reference-informed original furniture meshes. Run using Blender 5 bpy Python.
Product reference photos remain /tmp/mate-prop-references, never in game assets.
"""
import bpy, math, json, os, random
import numpy as np
from mathutils import Vector
from pathlib import Path
from PIL import Image
BASE=Path(__file__).resolve().parents[2]
OUT=BASE/'native/assets/desktop_objects/premium'
PRE=BASE/'diagnostics/desktop_objects/premium-previews'
OUT.mkdir(parents=True,exist_ok=True); PRE.mkdir(parents=True,exist_ok=True)
random.seed(39)
def xyz(p): return (p[0],-p[2],p[1])
def clean():
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(name,color,rough=.6,metal=0,tex=None):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
 if tex:
  n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(tex));n.image.pack();m.node_tree.links.new(n.outputs['Color'],bs.inputs['Base Color'])
 return m
# Deterministic woven-color texture and long-grain oak; original pixels.
rng=np.random.default_rng(39)
y,x=np.mgrid[0:256,0:256];noise=rng.normal(0,1,(256,256));weave=2*np.sin(x*np.pi)+2*np.sin(y*np.pi)+noise*2
fabric=np.clip(np.array([139,157,147])[None,None,:]+weave[:,:,None],0,255).astype('uint8')
Image.fromarray(fabric).save(PRE/'fabric.png')
y,x=np.mgrid[0:512,0:512];grain=np.sin(y*.16+np.sin(x*.009)*1.6)+.38*np.sin(y*.75+np.sin(x*.014)*2)+rng.normal(0,.25,(512,512))
oak=np.clip(np.array([198,164,118])[None,None,:]+grain[:,:,None]*np.array([5,5,4]),0,255).astype('uint8');Image.fromarray(oak).save(PRE/'oak.png')
fab=mat('Sage woven upholstery',(0.32,.4,.34),.92,tex=PRE/'fabric.png')
seam=mat('Tailored sage piping',(.23,.30,.255),.9)
cream=mat('Warm ivory satin frame',(.76,.77,.72),.32)
graph=mat('Graphite powder coated metal',(.052,.065,.066),.38,.38)
chrome=mat('Satin aluminum',(.45,.50,.51),.24,.8)
rubber=mat('Soft black wheel rubber',(.018,.023,.024),.82)
wood=mat('Natural oak',(.61,.42,.23),.53,tex=PRE/'oak.png')
pad=mat('Warm grey desk mat',(.28,.32,.31),.92)
white=mat('Porcelain keycaps',(.82,.84,.80),.38)
accent=mat('Muted sage keycaps',(.32,.45,.39),.5)
pillow=mat('Oat boucle cushion',(.70,.64,.52),.98)

def finish(o,name,material):
 o.name=name;o.data.materials.append(material)
 for p in o.data.polygons:p.use_smooth=True
 return o

def box(name,loc,size,bevel,material):
 bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(loc));o=bpy.context.object;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  m=o.modifiers.new('Crafted soft edge','BEVEL');m.width=bevel;m.segments=4;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=m.name)
 m=o.modifiers.new('Weighted flat normals','WEIGHTED_NORMAL');m.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=m.name)
 return finish(o,name,material)
def rod(name,a,b,r,material,r2=None,vertices=20):
 a,b=Vector(xyz(a)),Vector(xyz(b));d=b-a
 bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r if r2 is None else r2,depth=d.length,location=(a+b)/2)
 o=bpy.context.object;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();return finish(o,name,material)
def curve(name,pts,r,material,cyclic=False):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=12;cu.bevel_depth=r;cu.bevel_resolution=2
 sp=cu.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
 for p,v in zip(sp.bezier_points,pts):p.co=xyz(v);p.handle_left_type='AUTO';p.handle_right_type='AUTO'
 sp.use_cyclic_u=cyclic;o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);o.data.materials.append(material)
 bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False);return o

def cushion(name,loc,size,material,exponent=.34,deform=None):
 # superellipsoid: broad soft faces and real rounded corners, no cube silhouette
 verts=[];faces=[];n=48;m=24
 def sp(v):return math.copysign(abs(v)**exponent,v)
 for j in range(m+1):
  v=-math.pi/2+math.pi*j/m
  for i in range(n):
   u=2*math.pi*i/n;p=[size[0]/2*sp(math.cos(v))*sp(math.cos(u)),size[1]/2*sp(math.sin(v)),size[2]/2*sp(math.cos(v))*sp(math.sin(u))]
   if deform:p=deform(p)
   verts.append(xyz([p[k]+loc[k] for k in range(3)]))
 for j in range(m):
  for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o)
 # mesh face order outward check and UVs via smart projection
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.uv.smart_project(island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
 return finish(o,name,material)
def rounded_loop(cx,y,cz,w,d,r,material,name):
 pts=[]
 for xc,zc,ang in [(cx+w/2-r,cz+d/2-r,0),(cx-w/2+r,cz+d/2-r,90),(cx-w/2+r,cz-d/2+r,180),(cx+w/2-r,cz-d/2+r,270)]:
  for k in range(5):
   a=math.radians(ang+k*22.5);pts.append((xc+r*math.cos(a),y,zc+r*math.sin(a)))
 # angle ordering easier generic superellipse perimeter
 pts=[(cx+w/2*math.copysign(abs(math.cos(a))**.25,math.cos(a)),y,cz+d/2*math.copysign(abs(math.sin(a))**.25,math.sin(a))) for a in np.linspace(0,2*math.pi,48,endpoint=False)]
 return curve(name,pts,.0019,material,True)

def chair():
 # five molded spokes and twin castors; seat .48m, tapering upholstered back
 rod('Gas lift',(0,.115,0),(0,.395,0),.021,chrome)
 rod('Lift cover',(0,.12,0),(0,.265,0),.033,cream)
 for i in range(5):
  a=2*math.pi*i/5+.2;x,z=math.sin(a)*.29,math.cos(a)*.29
  curve('Sculpted five star base',[(0,.17,0),(x*.55,.125,z*.55),(x,.09,z)],.018,cream)
  rod('Caster stem',(x,.047,z),(x,.098,z),.011,chrome)
  # twin wheels, axis tangent to radius
  dx,dz=math.cos(a)*.018,-math.sin(a)*.018
  for sign in [-1,1]:
   xx,zz=x+dx*sign,z+dz*sign
   rod('Twin rubber caster',(xx-dx*.33,.035,zz-dz*.33),(xx+dx*.33,.035,zz+dz*.33),.035,rubber,vertices=24)
 box('Tilt mechanism',(0,.37,-.035),(.22,.067,.22),.022,cream)
 cushion('Molded seat shell',(0,.412,.005),(.50,.055,.465),cream,.36)
 cushion('Waterfall upholstered seat',(0,.455,.015),(.505,.075,.465),fab,.34,lambda p:[p[0],p[1]-.025*(p[2]/.232)**2,p[2]])
 rounded_loop(0,.438,.016,.494,.455,.05,seam,'Seat perimeter welt')
 def backshape(p):
  t=(p[1]+.267)/.534
  return [p[0]*(1-.31*t),p[1],p[2]-.066*t+.045*(p[0]/.25)**2]
 cushion('Upholstered tapered ergonomic back',(0,.757,-.208),(.49,.534,.09),fab,.29,backshape)
 # visible supporting ivory spine and bent arms
 curve('Back support spine',[(0,.385,-.18),(0,.52,-.28),(0,.73,-.30)],.024,cream)
 for s in [-1,1]:
  curve('Sculpted arm upright',[(s*.205,.395,-.085),(s*.283,.44,-.07),(s*.286,.638,-.04)],.019,cream)
  cushion('Soft arm cap',(s*.281,.650,-.006),(.087,.03,.23),pad,.33)
 rod('Tilt control lever',(.12,.379,.03),(.246,.38,.08),.008,graph)
 box('Adjustment paddle',(.25,.38,.09),(.046,.016,.05),.006,graph)
 return {'asset':'chair.glb','sockets':{'seat':[0,.48,.08],'inspect':[0,.76,-.17]},'seat_width':.43}

def sofa():
 for x in [-.79,.79]:
  for z in [-.31,.31]:
   rod('Slim recessed aluminum leg',(x,.014,z),(x,.235,z),.0115,graph,r2=.016)
   rod('Felt glide',(x,.005,z),(x,.017,z),.014,rubber)
 box('Slender floating rail',(0,.222,0),(1.69,.043,.72),.016,graph)
 cushion('Upholstered lower deck',(0,.277,0),(1.79,.095,.825),fab,.23)
 for s in [-1,1]:
  cushion('Soft narrow wrap arm',(s*.833,.487,-.003),(.155,.465,.83),fab,.29)
 # full external back then two separately padded inside backs/seat pads
 cushion('Continuous outer back',(0,.51,-.354),(1.66,.505,.13),fab,.26)
 for s in [-1,1]:
  x=s*.385
  cushion('Deep seat cushion',(x,.375,.042),(.763,.13,.69),fab,.30,lambda p:[p[0],p[1]-.013*(p[2]/.345)**2,p[2]])
  rounded_loop(x,.365,.042,.752,.680,.035,seam,'Seat sewn welt')
  cushion('Soft separate back cushion',(x,.588,-.245),(.765,.359,.17),fab,.31,lambda p:[p[0],p[1],p[2]-.052*p[1]/.179])
  # clean stitch tracing outside edges, no decorative clutter
  curve('Back cushion top seam',[(x-.353,.755,-.27),(x,.766,-.285),(x+.353,.755,-.27)],.0016,seam)
 return {'asset':'sofa.glb','sockets':{'seat':[0,.428,.12],'inspect':[0,.58,-.19]},'seat_width':1.46}

def workstation():
 # 130 x 65 x 73cm Workshop proportions; top nesting in slim oak rail
 box('Solid oak edge tabletop',(0,.714,0),(1.30,.034,.65),.012,wood)
 box('Inset warm grey linoleum',(0,.732,0),(1.277,.006,.627),.008,pillow)
 for x in [-.61,.61]:
  for z in [-.28,.28]:
   box('Oak square leg',(x,.353,z),(.045,.706,.045),.005,wood)
   box('Leg end glide',(x,.005,z),(.036,.010,.036),.004,rubber)
 for z in [-.28,.28]:box('Recessed long apron',(0,.671,z),(1.19,.065,.027),.004,wood)
 for x in [-.61,.61]:box('Side oak apron',(x,.671,0),(.027,.065,.52),.004,wood)
 box('Wool desk pad',(.08,.739,.14),(.77,.006,.30),.035,pad)
 box('Monitor aluminum foot',(0,.747,-.17),(.23,.018,.17),.012,chrome)
 box('Monitor tapered stand',(0,.837,-.244),(.055,.18,.035),.008,chrome)
 box('Slim aluminum monitor',(0,1.016,-.218),(.58,.347,.028),.012,chrome)
 box('Dark glass bezel',(0,1.019,-.2),(.562,.324,.008),.008,graph)
 # original abstract sage wallpaper + quiet window panels, real texture only within screen
 W,H=768,432;yy,xx=np.mgrid[0:H,0:W];t=yy/H
 arr=np.zeros((H,W,3),dtype=np.uint8)
 for c,(a,b) in enumerate(zip([192,208,202],[99,141,135])):arr[:,:,c]=a+(b-a)*t
 for cy,cx,rad,col in [(410,560,310,[146,174,158]),(470,180,340,[70,119,114]),(520,590,315,[47,90,91])]:arr[(xx-cx)**2+(yy-cy)**2<rad**2]=col
 from PIL import ImageDraw
 im=Image.fromarray(arr);d=ImageDraw.Draw(im);d.rounded_rectangle((45,37,340,302),radius=12,fill=(231,234,222));d.rounded_rectangle((61,57,323,82),radius=5,fill=(197,210,199))
 for k in range(6):d.rounded_rectangle((67,107+k*24,270-(k%3)*37,113+k*24),radius=3,fill=(153,177,164))
 d.rounded_rectangle((208,387,558,414),radius=12,fill=(210,223,210))
 for k in range(8):d.rounded_rectangle((229+k*40,393,246+k*40,409),radius=4,fill=[(113,145,134),(199,173,132),(174,153,142)][k%3])
 im.save(PRE/'screen.png');screenmat=mat('Original calm desktop wallpaper',(1,1,1),.42,tex=PRE/'screen.png')
 # explicitly oriented UV quad facing +Z in exported coordinates
 me=bpy.data.meshes.new('Display pixels');me.from_pydata([xyz(p) for p in [(-.273,.867,-.194),(.273,.867,-.194),(.273,1.17,-.194),(-.273,1.17,-.194)]],[],[(0,1,2,3)]);me.uv_layers.new()
 for i,uv in enumerate([(0,0),(1,0),(1,1),(0,1)]):me.uv_layers.active.data[i].uv=uv
 o=bpy.data.objects.new('Inset LCD image',me);bpy.context.collection.objects.link(o);finish(o,'Inset LCD image',screenmat)
 bs=screenmat.node_tree.nodes.get('Principled BSDF');bs.inputs['Emission Strength'].default_value=.22;screenmat.node_tree.links.new(screenmat.node_tree.nodes.get('Image Texture').outputs['Color'],bs.inputs['Emission Color'])
 box('Keyboard aluminum tray',(-.055,.751,.175),(.405,.019,.137),.008,chrome)
 for row in range(5):
  for col in range(14):
   if row==4 and 3<=col<=8:continue
   x=-.243+col*.0277;z=.122+row*.0237
   box('Sculpted keycap',(x,.764,z),(.023,.010,.019),.0035,accent if (row==0 and col==0) or col==13 else white)
 box('Spacebar',(-.084,.764,.217),(.154,.010,.019),.0035,white)
 cushion('Wireless mouse',(.256,.765,.165),(.064,.042,.102),cream,.65)
 curve('Mouse wheel',[(.256,.787,.146),(.256,.788,.160)],.0038,graph)
 return {'asset':'workstation.glb','sockets':{'use':[-.055,.77,.185],'keyboard_left':[-.16,.77,.185],'keyboard_right':[.08,.77,.185],'inspect':[0,1.017,-.194]},'seat_width':0}

def render(kind):
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
 scene.render.resolution_x=840;scene.render.resolution_y=700;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
 scene.world.color=(.30,.30,.30);scene.view_settings.view_transform='AgX'
 for loc,power,size in [((2,4,3),400,4),((-3,2,2),250,3),((0,3,-3),330,3)]:
  bpy.ops.object.light_add(type='AREA',location=xyz(loc));o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector(xyz((0,.45,0)))-o.location).to_track_quat('-Z','Y').to_euler()
 h={'chair':.53,'sofa':.40,'computer':.62}[kind];scale={'chair':1.53,'sofa':2.12,'computer':1.66}[kind]
 bpy.ops.object.camera_add(location=xyz((1.8,h+1.05,3.5)));camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=scale;camera.rotation_euler=(Vector(xyz((0,h,0)))-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
 scene.render.filepath=str(PRE/(kind+'-threequarter.png'));bpy.ops.render.render(write_still=True)
 camera.location=xyz((0,h+.55,3));camera.rotation_euler=(Vector(xyz((0,h,0)))-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(PRE/(kind+'-front.png'));bpy.ops.render.render(write_still=True)

metadata={}
for kind,fn in [('chair',chair),('sofa',sofa),('computer',workstation)]:
 clean();m=fn()
 # Join by material; inexpensive draw calls and self-contained GLB
 bpy.ops.object.select_all(action='DESELECT')
 groups={}
 for o in list(bpy.context.scene.objects):
  if o.type=='MESH':groups.setdefault(o.data.materials[0].name,[]).append(o)
 for group in groups.values():
  bpy.ops.object.select_all(action='DESELECT')
  for o in group:o.select_set(True)
  bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join()
 bpy.context.view_layer.update();verts=[o.matrix_world@v.co for o in bpy.context.scene.objects if o.type=='MESH' for v in o.data.vertices]
 points=[(v.x,v.z,-v.y) for v in verts];lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
 m['bounds']={'min':lo,'max':hi};m['ground_y']=lo[1];m['triangles']=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH');m['material_count']=len(groups)
 bpy.ops.object.select_all(action='SELECT');bpy.ops.export_scene.gltf(filepath=str(OUT/m['asset']),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
 m['bytes']=(OUT/m['asset']).stat().st_size;metadata[kind]=m
 (OUT/'objects.json').write_text(json.dumps(metadata,indent=2)+'\n')
 render(kind)
print('PREMIUM_ASSETS',json.dumps(metadata))
