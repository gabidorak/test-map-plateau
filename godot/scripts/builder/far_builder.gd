@tool
extends RefCounted
## Chunk streaming (performance): splits the world into CELL-sized cells and gives each one a cheap far
## version, shown by scripts/world_streamer.gd instead of the full-detail nodes once the camera is far away.
## Far version of a cell: the ground on a coarse grid (same shader, one quad per FAR_STEP), its buildings
## merged into one simplified mesh (same material, one draw call) and its trees as low-poly crowns in one
## MultiMesh, plus the railway's light ballast strip (Rail/Far, rail_builder.gd) in place of its track chunks.
## Far away the cost is the triangle count, not the shaders, so the far meshes are kept light.
## Every detailed node belongs to the cell of its centre; the far meshes are built from exactly those nodes,
## so swapping a whole cell never leaves a hole or a double. Props, building kit and labels have no far
## version (they already fade out within ~250 m). Hedges and collision are never streamed.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const WorldStreamer = preload("res://scripts/world_streamer.gd")
const CELL := 192.0                     # m; a multiple of the 96 m tree/kit/prop chunks, which then nest exactly
const FAR_STEP := 8.0                   # m between far ground samples
const BUILDING_SNAP := 1.5              # m grid of the far buildings' vertex clustering
const SKIRT := 3.0                      # m the far ground hangs down at chunk edges (hides cracks at cell seams)
const CROWN_SUBDIV := 0                 # icosphere subdivisions of the far tree crown (20 triangles)

var _cells := {}                        # Vector2i -> {near: Array[Node], ground: [AABB], buildings: [Mesh], box: AABB}


func build(root: Node3D, world: Dictionary, mesh_dir: String) -> Error:
	var map: RefCounted = GroundMap.get_map("res://world/" + String(world["ground_mesh"]["index"]))
	if map == null:
		return ERR_FILE_NOT_FOUND
	for mi: MeshInstance3D in root.get_node("Ground").get_children():
		_add(mi, _mesh_box(mi)).ground.append(mi.mesh.get_aabb())
	for mi: MeshInstance3D in root.get_node("Buildings").get_children().filter(func(n): return n is MeshInstance3D):
		if mi.mesh != null:
			_add(mi, _mesh_box(mi)).buildings.append(mi.mesh)
	for sign: Node3D in root.get_node("Buildings/Signs").get_children():
		_add(sign, _point_box(sign.position))
	for group in ["BuildingKit", "Props", "Vegetation/Trees", "Rail/Track"]:
		if root.get_node_or_null(group) == null:
			continue
		for chunk: Node3D in root.get_node(group).get_children():
			if chunk.name.begins_with("Chunk_"):
				_add(chunk, _chunk_box(chunk))
	for stop: Node3D in root.get_node("Props/BusStops").get_children():
		_add(stop, _point_box(stop.position))

	var far := Node3D.new()
	far.name = "Far"
	root.add_child(far)
	var ground_mat: Material = load(mesh_dir + "ground_material.tres")
	var building_mat: Material = load(mesh_dir + "building_material.tres")
	var crown := _crown_mesh(load(mesh_dir + "foliage_material.tres"))
	MeshUtils.save(crown, mesh_dir + "far_crown.res")
	var trees := _trees_by_cell(root, world)

	var streamer := WorldStreamer.new()
	streamer.name = "Streamer"
	var near_paths: Array = []
	var far_paths := PackedStringArray()
	var boxes: Array[AABB] = []
	var keys := _cells.keys()
	keys.sort()
	for key: Vector2i in keys:
		var c: Dictionary = _cells[key]
		var cell := Node3D.new()
		cell.name = "Cell_%d_%d" % [key.x, key.y]
		cell.visible = false            # the scene shows full detail until the streamer runs
		far.add_child(cell)
		var tag := "%d_%d" % [key.x, key.y]
		if not c.ground.is_empty():
			cell.add_child(_instance("Ground", MeshUtils.save(_far_ground(c.ground, map, ground_mat), mesh_dir + "far_ground_%s.res" % tag)))
		if not c.buildings.is_empty():
			cell.add_child(_instance("Buildings", MeshUtils.save(_merge(c.buildings, building_mat), mesh_dir + "far_buildings_%s.res" % tag)))
		var rail_far := root.get_node_or_null("Rail/Far/Cell_%s" % tag)
		if rail_far:                    # the railway's far ballast strip (rail_builder.gd), cut per cell
			for child: Node in rail_far.get_children():
				child.reparent(cell, false)
		if trees.has(key):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = crown
			mm.instance_count = trees[key].size() / 16
			mm.buffer = trees[key]
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees"
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cell.add_child(mmi)
		var paths := PackedStringArray()
		for n: Node in c.near:
			paths.append(String(root.get_path_to(n)))
		near_paths.append(paths)
		far_paths.append(String(root.get_path_to(cell)))
		boxes.append(c.box)
	streamer.near_paths = near_paths
	streamer.far_paths = far_paths
	streamer.boxes = boxes
	root.add_child(streamer)
	print("streaming: %d cells of %d m" % [keys.size(), CELL])
	return OK


func _add(node: Node3D, box: AABB) -> Dictionary:
	var centre := box.get_center()
	var key := Vector2i(floori(centre.x / CELL), floori(-centre.z / CELL))
	if not _cells.has(key):
		_cells[key] = {"near": [], "ground": [], "buildings": [], "box": box}
	var c: Dictionary = _cells[key]
	c.near.append(node)
	c.box = (c.box as AABB).merge(box)
	return c


func _mesh_box(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb() if mi.is_inside_tree() else mi.transform * mi.mesh.get_aabb()


func _chunk_box(chunk: Node3D) -> AABB:
	var box := AABB(chunk.position, Vector3.ZERO)
	for child in chunk.get_children():
		if child is MultiMeshInstance3D:
			box = box.merge(chunk.transform * (child as MultiMeshInstance3D).custom_aabb)
		elif child is MeshInstance3D and (child as MeshInstance3D).mesh:     # the railway's ballast and rails
			var mi := child as MeshInstance3D
			box = box.merge(chunk.transform * (mi.transform * mi.mesh.get_aabb()))
	return box


func _point_box(p: Vector3) -> AABB:
	return AABB(p - Vector3(2.0, 2.0, 2.0), Vector3(4.0, 4.0, 4.0))


func _instance(name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Ground of the given chunk footprints (Godot AABBs) on a FAR_STEP grid, one flat-coloured quad per
## step with the material under its centre, heights as the detailed mesh draws them, and skirts.
func _far_ground(boxes: Array, map: RefCounted, mat: Material) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var col := PackedColorArray()
	var cust := PackedByteArray()
	var colours := []
	for name: String in map.materials:
		colours.append(Color.html(map.palette["ground"].get(name, "#808080")))
	var grass: int = map.materials.find("grass")
	for box: AABB in boxes:
		var x0 := box.position.x
		var y1 := -box.position.z                   # north edge (pipeline y)
		var nx := maxi(1, ceili(box.size.x / FAR_STEP))
		var ny := maxi(1, ceili(box.size.z / FAR_STEP))
		var dx := box.size.x / nx
		var dy := box.size.z / ny
		var pt := func(i: int, j: int) -> Vector3:
			var x := x0 + i * dx
			var y := y1 - j * dy
			return Vector3(x, map.height(x, y), -y)
		for j in ny:
			for i in nx:
				var a: Vector3 = pt.call(i, j)
				var b: Vector3 = pt.call(i + 1, j)
				var c: Vector3 = pt.call(i + 1, j + 1)
				var d: Vector3 = pt.call(i, j + 1)
				var m: int = map.material_at(x0 + (i + 0.5) * dx, y1 - (j + 0.5) * dy)
				m = grass if m < 0 else m
				var nrm := (d - a).cross(b - a).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				for p: Vector3 in [a, b, c, a, c, d]:
					v.append(p)
					n.append(nrm)
					col.append(colours[m])
					cust.append_array([m, 0, 128, 0])
		# skirts along the footprint edge, hanging down
		var ring := []
		for i in nx:
			ring.append([i, 0])
		for j in ny:
			ring.append([nx, j])
		for i in range(nx, 0, -1):
			ring.append([i, ny])
		for j in range(ny, 0, -1):
			ring.append([0, j])
		for k in ring.size():
			var p: Vector3 = pt.call(ring[k][0], ring[k][1])
			var q: Vector3 = pt.call(ring[(k + 1) % ring.size()][0], ring[(k + 1) % ring.size()][1])
			var pd := p - Vector3(0.0, SKIRT, 0.0)
			var qd := q - Vector3(0.0, SKIRT, 0.0)
			var m: int = map.material_at(p.x, -p.z)
			m = grass if m < 0 else m
			# both windings: the skirt is seen from inside the cell and from the neighbour
			for tri: Array in [[p, q, qd], [p, qd, pd], [p, qd, q], [p, pd, qd]]:
				var t0: Vector3 = tri[0]
				var nrm: Vector3 = ((tri[2] as Vector3) - t0).cross((tri[1] as Vector3) - t0).normalized()
				for t: Vector3 in tri:
					v.append(t)
					n.append(nrm)
					col.append(colours[m])
					cust.append_array([m, 0, 128, 0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_CUSTOM0] = cust
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, mat)
	return mesh


## The building meshes (one non-indexed surface each, world coordinates, building_builder.gd Buf) as one,
## simplified by vertex clustering: positions snap to a BUILDING_SNAP grid and triangles that collapse are
## dropped (rounded corners, bevels and parapets go; walls, roofs and set-backs stay).
func _merge(meshes: Array, mat: Material) -> ArrayMesh:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var fmt := 0
	for mesh: ArrayMesh in meshes:
		var arrays := mesh.surface_get_arrays(0)
		fmt = mesh.surface_get_format(0)
		for k in Mesh.ARRAY_MAX:
			if arrays[k] == null:
				continue
			if out[k] == null:
				out[k] = arrays[k]
			else:
				out[k].append_array(arrays[k])
	var keep := PackedInt32Array()
	var pos: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
	for k in pos.size():
		pos[k] = pos[k].snapped(Vector3.ONE * BUILDING_SNAP)
	for t in range(0, pos.size(), 3):
		if pos[t] != pos[t + 1] and pos[t + 1] != pos[t + 2] and pos[t] != pos[t + 2] \
				and (pos[t + 1] - pos[t]).cross(pos[t + 2] - pos[t]).length_squared() > 1e-6:
			keep.append_array([t, t + 1, t + 2])
	out[Mesh.ARRAY_VERTEX] = pos
	out[Mesh.ARRAY_INDEX] = keep
	var merged := ArrayMesh.new()
	var flags := 0
	for k in 4:
		var shift := Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS
		flags |= fmt & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	merged.surface_set_material(0, mat)
	return merged


## Per cell, MultiMesh buffers (transform + tint/phase) of a unit crown placed over each tree's crown.
func _trees_by_cell(root: Node3D, world: Dictionary) -> Dictionary:
	var data = root.get_node("TreeCollision").data
	var fol: Dictionary = world["palette"]["foliage"]
	var out := {}
	for k in data.size():
		var c: Vector3 = data.crown_center[k]
		var r: Vector2 = data.crown_radii[k]
		var key := Vector2i(floori(c.x / CELL), floori(-c.z / CELL))
		var tint := Color.html(fol[String(data.info[k]).split("|")[1]])
		if not out.has(key):
			out[key] = PackedFloat32Array()
		out[key].append_array([r.x, 0.0, 0.0, c.x, 0.0, r.y, 0.0, c.y, 0.0, 0.0, r.x, c.z,
				tint.r, tint.g, tint.b, fmod(k * 0.618, 1.0)])
	return out


## Unit icosphere with the vertex data toy_foliage.gdshader expects for leaves (darker underneath).
func _crown_mesh(mat: Material) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var pts: Array[Vector3] = []
	for p in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
			[t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
		pts.append(Vector3(p[0], p[1], p[2]).normalized())
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in CROWN_SUBDIV:
		var next := []
		var mid := {}
		var midpoint := func(a: int, b: int) -> int:
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not mid.has(key):
				pts.append(((pts[a] + pts[b]) / 2.0).normalized())
				mid[key] = pts.size() - 1
			return mid[key]
		for f: Array in faces:
			var ab: int = midpoint.call(f[0], f[1])
			var bc: int = midpoint.call(f[1], f[2])
			var ca: int = midpoint.call(f[2], f[0])
			next.append_array([[f[0], ab, ca], [f[1], bc, ab], [f[2], ca, bc], [ab, bc, ca]])
		faces = next
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		for i in [0, 2, 1]:                         # clockwise seen from outside
			var p: Vector3 = pts[f[i]]
			var up := (p.y + 1.0) / 2.0
			st.set_normal(p)
			st.set_color(Color(0.55 + 0.45 * up, 0.5, 0.5 + 0.5 * up, 1.0))
			st.add_vertex(p)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh
