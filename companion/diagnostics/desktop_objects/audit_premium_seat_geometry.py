import bpy,json
from mathutils import Vector
from pathlib import Path
root=Path(__file__).resolve().parents[2]
meta=json.loads((root/'native/assets/desktop_objects/premium/objects.json').read_text())
results={}
for kind in ['chair','sofa']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=str(root/'native/assets/desktop_objects/premium'/meta[kind]['asset']))
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();out=[]
 for x,z in [(0,.08 if kind=='chair' else .12),(.06,.08 if kind=='chair' else .12),(-.06,.08 if kind=='chair' else .12),(.06,-.12),(.06,.22),(.06,.31)]:
  ok,loc,n,ix,ob,m=bpy.context.scene.ray_cast(dg,Vector((x,-z,.51)),Vector((0,0,-1)))
  out.append({'x':x,'z':z,'y':loc.z if ok else None,'object':ob.name if ok else None})
 corners=[o.matrix_world@Vector(c) for o in bpy.context.scene.objects if o.type=='MESH' for c in o.bound_box]
 bounds=[[min((v.x,v.z,-v.y)[k] for v in corners) for k in range(3)],[max((v.x,v.z,-v.y)[k] for v in corners) for k in range(3)]]
 results[kind]={'rays':out,'transformed_local_aabb_union':bounds}
 print(kind,json.dumps(out))
(root/'diagnostics/desktop_objects/premium-seat-raycast.json').write_text(json.dumps(results,indent=2))
