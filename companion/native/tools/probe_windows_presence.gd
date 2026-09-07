extends "probe_windows_continuity.gd"
## Owned viewport crops retained in memory; disk writes happen after motion ends.
## Crops follow the actor. Desktop travel is measured separately in report frames.
var pictures:Array=[]
var picture_next:=0
func sample()->void:
	super.sample()
	if app==null or not app.avatar.has_model() or elapsed()<picture_next or pictures.size()>=800:return
	picture_next=elapsed()+100
	var source:Image=root.get_texture().get_image()
	var center:Vector2=app.pet_rect.get_center()
	if app.objects.contact_scene_active():center=app.pet_rect.merge(app.objects.contact_bounds()).get_center()
	var size:=Vector2i(mini(512,source.get_width()),mini(512,source.get_height()))
	var origin:=Vector2i(center)-size/2
	origin.x=clampi(origin.x,0,source.get_width()-size.x)
	origin.y=clampi(origin.y,0,source.get_height()-size.y)
	pictures.append({"ms":elapsed(),"origin":origin,"image":source.get_region(Rect2i(origin,size))})
func finish()->void:
	if closing:return
	DirAccess.make_dir_recursive_absolute(output.path_join("motion"))
	var timing:Array=[]
	for i in pictures.size():
		var item:Dictionary=pictures[i]
		var file:="motion/frame-%04d.png" % i
		item.image.save_png(output.path_join(file))
		timing.append({"file":file,"ms":item.ms,"crop_origin":str(item.origin)})
	report["motion_crops"]=timing
	pictures.clear()
	await super.finish()
