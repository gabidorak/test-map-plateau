extends Node3D
## The look of the bots far from every player (traffic.gd makes it as Main/Traffic/Proxies; bus_bot.gd far): one
## MultiMesh per vehicle model section (the front, and an articulated bus's rear section) whose instances stand in for
## the bots gliding beyond bus_bot.gd's FAR m. Their own vehicles sleep meanwhile (car.gd set_dormant: hidden, out of
## the physics, not moved): moving a vehicle's node tree (its lamps, wheels, sounds, a bus's dozens of walkable-hull
## shapes) costs far more than writing a transform into a buffer, uploaded once a frame per model.
## Each model's meshes are baked once from a vehicle built for it: every visible surface, merged by material (a few
## draw calls for all the bots of that model), once with the lamps off and once lit (Car.night: the bots drive with
## their headlights on at night; their beams fade out well short of FAR anyway, car.gd BEAM_FADE). The wheels do not
## turn, the indicators do not blink and the doors stay shut, out there. A MultiMesh is drawn whole (no culling nor LOD
## per instance), so the baked meshes are simplified once (to about DETAIL of their triangles: a car is a few dozen
## pixels at FAR) and cast no shadow (the sun's end at 250 m, main.tscn).

const Car = preload("res://scripts/car.gd")
const FLOATS := 12                          # per instance: a Transform3D (MultiMesh buffer layout)
const DETAIL := 0.05                        # share of a model's triangles kept in its stand-in (at least MIN_TRIS)
const MIN_TRIS := 12
const LOD_MERGE_ANGLE := 60.0                # degrees (ImporterMesh.generate_lods): coarser than the import's 25
const LOD_SPLIT_ANGLE := 90.0


class Kind:
	var mmis: Array[MultiMeshInstance3D] = []   # per section
	var meshes: Array = []                  # per section: [lamps off, lamps lit]
	var bots: Array = []                    # the bot of each instance, dense
	var bufs: Array[PackedFloat32Array] = [] # per section
	var dirty := false


var _kinds := {}                            # model -> Kind
var _night := false


## Bot `bot` (bus_bot.gd) shown here from now on, at its far_xf (and far_rear_xf).
func add(bot: Object) -> void:
	var k := _kind(bot.car)
	bot.proxy_index = k.bots.size()
	k.bots.append(bot)
	for buf: PackedFloat32Array in k.bufs:
		buf.resize(k.bots.size() * FLOATS)
	_write(k, bot)


## No longer shown here (its vehicle is back).
func remove(bot: Object) -> void:
	var k: Kind = _kinds.get(bot.car.model_name)
	var i: int = bot.proxy_index
	if k == null or i < 0 or i >= k.bots.size() or k.bots[i] != bot:
		return
	var last: Object = k.bots.pop_back()
	if last != bot:                         # the last instance takes its place
		k.bots[i] = last
		last.proxy_index = i
		_write(k, last)
	for buf: PackedFloat32Array in k.bufs:
		buf.resize(k.bots.size() * FLOATS)
	bot.proxy_index = -1
	k.dirty = true


## The bot moved (its far_xf, far_rear_xf).
func moved(bot: Object) -> void:
	var k: Kind = _kinds.get(bot.car.model_name)
	if k != null and bot.proxy_index >= 0:
		_write(k, bot)


func clear() -> void:
	for k: Kind in _kinds.values():
		for b: Object in k.bots:
			b.proxy_index = -1
		k.bots.clear()
		for buf: PackedFloat32Array in k.bufs:
			buf.resize(0)
		k.dirty = true


func count() -> int:
	var n := 0
	for k: Kind in _kinds.values():
		n += k.bots.size()
	return n


func _write(k: Kind, bot: Object) -> void:
	var o: int = bot.proxy_index * FLOATS
	for sec in k.bufs.size():
		var xf: Transform3D = bot.far_xf if sec == 0 else bot.far_rear_xf
		var buf: PackedFloat32Array = k.bufs[sec]
		var b := xf.basis
		buf[o] = b.x.x
		buf[o + 1] = b.y.x
		buf[o + 2] = b.z.x
		buf[o + 3] = xf.origin.x
		buf[o + 4] = b.x.y
		buf[o + 5] = b.y.y
		buf[o + 6] = b.z.y
		buf[o + 7] = xf.origin.y
		buf[o + 8] = b.x.z
		buf[o + 9] = b.y.z
		buf[o + 10] = b.z.z
		buf[o + 11] = xf.origin.z
		k.bufs[sec] = buf                   # (packed arrays are copied on write)
	k.dirty = true


func _process(_delta: float) -> void:
	var lit: bool = Car.night
	for k: Kind in _kinds.values():
		if lit != _night:
			for sec in k.mmis.size():
				k.mmis[sec].multimesh.mesh = k.meshes[sec][1 if lit else 0]
		if not k.dirty:
			continue
		k.dirty = false
		var n := k.bots.size()
		for sec in k.mmis.size():
			var mm := k.mmis[sec].multimesh
			if mm.instance_count < n or mm.instance_count > maxi(n * 4, 16):
				mm.visible_instance_count = -1
				mm.instance_count = maxi(nextpow2(n), 8)
			var buf: PackedFloat32Array = k.bufs[sec]
			if buf.size() < mm.instance_count * FLOATS:
				var full := buf.duplicate()
				full.resize(mm.instance_count * FLOATS)
				mm.buffer = full
			else:
				mm.buffer = buf
			mm.visible_instance_count = n
			k.mmis[sec].visible = n > 0
	_night = lit


static func nextpow2(n: int) -> int:
	var p := 1
	while p < n:
		p *= 2
	return p


## The model's MultiMeshes, baked from a vehicle built for it on first use.
func _kind(car: Node3D) -> Kind:
	var model: String = car.model_name
	if _kinds.has(model):
		return _kinds[model]
	var k := Kind.new()
	_kinds[model] = k
	if DisplayServer.get_name() == "headless":
		return k                            # nothing to draw (a server, the tests): the bots' poses only
	var template: Car = car.get_script().new()
	template.setup(model)
	var sections: Array = [template]
	if template.trailer:
		sections.append(template.trailer)
	var lit: Array = []
	for on: bool in [false, true]:
		template.set_headlights(on)
		lit.append(sections.map(func(sec: Node3D) -> Mesh: return _bake(sec, template.trailer)))
	for sec in sections.size():
		k.meshes.append([lit[0][sec], lit[1][sec]])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = k.meshes[sec][1 if Car.night else 0]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [model, sec]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		k.mmis.append(mmi)
		k.bufs.append(PackedFloat32Array())
	template.free()
	return k


## One mesh of every visible surface under `section` (in its frame), merged by material; `skip`: a subtree left out
## (the rear section, a child of the front one).
static func _bake(section: Node3D, skip: Node) -> Mesh:
	var tools := {}                         # [material, format] -> SurfaceTool
	var stack: Array = [[section, Transform3D()]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		for c in n.get_children():
			if c == skip or not c is Node3D or not (c as Node3D).visible:
				continue
			var cx: Transform3D = xf * (c as Node3D).transform
			stack.append([c, cx])
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var mat: Material = mi.material_override if mi.material_override \
						else mi.get_surface_override_material(i) if mi.get_surface_override_material(i) \
						else mi.mesh.surface_get_material(i)
				# (surfaces merge when they share the material and the vertex attributes)
				var arrays: Array = mi.mesh.surface_get_arrays(i)
				var attrs := 0
				for j in arrays.size():
					attrs |= (1 << j) if arrays[j] != null else 0
				var key_s := "%d:%d" % [mat.get_instance_id() if mat else 0, attrs]
				if not tools.has(key_s):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[key_s] = [st, mat]
				(tools[key_s][0] as SurfaceTool).append_from(mi.mesh, i, cx)
	# merged (indexed, for the simplifier), then each surface cut down to its LOD nearest DETAIL of its triangles
	var im := ImporterMesh.new()
	for key_s: String in tools:
		var st: SurfaceTool = tools[key_s][0]
		st.index()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, tools[key_s][1])
	im.generate_lods(LOD_MERGE_ANGLE, LOD_SPLIT_ANGLE, [])
	var out := ArrayMesh.new()
	for i in im.get_surface_count():
		var arrays: Array = im.get_surface_arrays(i)
		var want := maxi(int((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() * DETAIL), MIN_TRIS * 3)
		for l in im.get_surface_lod_count(i):
			var idx: PackedInt32Array = im.get_surface_lod_indices(i, l)
			if idx.size() >= want:
				arrays[Mesh.ARRAY_INDEX] = idx     # (the LODs get coarser: the last one still above the target)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, im.get_surface_material(i))
	return out
