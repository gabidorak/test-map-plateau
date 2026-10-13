@tool
extends Resource
## Tree records of the generated world (milestone M5), written by builder/vegetation_builder.gd and
## saved next to the generated meshes. Used at runtime by tree_collision.gd (trunk shapes) and by the
## picker (ray against the crowns). Godot coordinates.

@export var ids := PackedStringArray()
@export var info := PackedStringArray()             # "model|tint|src|osm|height|radius" per tree
@export var base := PackedVector3Array()            # trunk foot on the ground
@export var trunk := PackedVector2Array()           # trunk radius, height of the trunk collider
@export var crown_center := PackedVector3Array()
@export var crown_radii := PackedVector2Array()     # horizontal, vertical half-axes of the crown ellipsoid


func size() -> int:
	return ids.size()


## Picker metadata of tree k.
func describe(k: int) -> Dictionary:
	var f := info[k].split("|")
	return {"type": "tree", "id": ids[k], "model": f[0], "tint": f[1], "src": f[2], "osm": f[3],
			"height": float(f[4]), "radius": float(f[5]), "index": k}


## Nearest crown ellipsoid hit by the ray from `from` along unit `dir` within `max_dist`:
## Vector2(tree index, distance), or Vector2(-1, INF).
func ray_crown(from: Vector3, dir: Vector3, max_dist: float) -> Vector2:
	var best := Vector2(-1, INF)
	for k in crown_center.size():
		var r := crown_radii[k]
		# scale space so the ellipsoid becomes a unit sphere
		var s := Vector3(1.0 / r.x, 1.0 / r.y, 1.0 / r.x)
		var o := (from - crown_center[k]) * s
		var d := dir * s
		var a := d.dot(d)
		var b := o.dot(d)
		var c := o.dot(o) - 1.0
		var disc := b * b - a * c
		if disc < 0.0:
			continue
		var t := (-b - sqrt(disc)) / a
		if t < 0.0:
			t = (-b + sqrt(disc)) / a
		if t >= 0.0 and t < best.y and t <= max_dist:
			best = Vector2(k, t)
	return best
