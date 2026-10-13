extends Node
## Debug picker: F identifies what is under the crosshair and shows its metadata in an overlay.
## Tree crowns do not collide, so they are tested analytically (ellipsoids from vegetation_data.res).
## The text is also printed and copied to the clipboard, so it can be pasted into a message.

const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const GroundMap = preload("res://scripts/ground_map.gd")
const RANGE := 2000.0

var world_root: Node3D                  # the generated Neighborhood scene
var panel: PanelContainer
var label: Label
var _highlighted: MeshInstance3D
var _highlight_mat: StandardMaterial3D
var _crown_marker: MeshInstance3D


func _ready() -> void:
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.35)
	_highlight_mat.no_depth_test = false
	_crown_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_crown_marker.mesh = sphere
	_crown_marker.material_override = _highlight_mat
	_crown_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crown_marker.visible = false
	add_child(_crown_marker)


## Ray from the centre of `camera`'s view; returns the hit metadata plus "hit"/"distance".
func pick(camera: Camera3D) -> Dictionary:
	var centre := camera.get_viewport().get_visible_rect().size / 2.0
	var from := camera.project_ray_origin(centre)
	var to := from + camera.project_ray_normal(centre) * RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.PICKABLE)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	var dist: float = from.distance_to(hit["position"]) if hit else INF
	var trees := _tree_data()
	if trees:
		var dir := (to - from).normalized()
		var crown: Vector2 = trees.ray_crown(from, dir, minf(dist, RANGE))
		if crown.x >= 0 and crown.y < dist:
			var tinfo: Dictionary = trees.describe(int(crown.x))
			tinfo["part"] = "crown"
			tinfo["hit"] = from + dir * crown.y
			tinfo["distance"] = crown.y
			tinfo["node"] = null
			return tinfo
	if not hit:
		return {}
	var info := WorldQuery.hit_info(hit).duplicate()
	if info.get("type") == "tree":
		info["part"] = "trunk"
	info["hit"] = hit["position"]
	info["distance"] = dist
	info["node"] = WorldQuery.hit_node(hit)
	return info


func _tree_data() -> Resource:
	var n := world_root.get_node_or_null("TreeCollision") if world_root else null
	return n.data if n else null


func pick_and_show(camera: Camera3D) -> void:
	var info := pick(camera)
	_set_highlight(null)
	if info.is_empty():
		show_text("Nothing under the crosshair (within %d m)." % RANGE)
		return
	if info.get("type") == "building" and world_root:
		_set_highlight(world_root.get_node_or_null(NodePath("Buildings/" + String(info["node"].name))))
	elif info.get("type") == "hedge" and world_root:
		_set_highlight(world_root.get_node_or_null(NodePath("Vegetation/Hedges/" + String(info["node"].name))))
	elif info.get("type") in ["prop", "fence"] and world_root:
		var body := world_root.get_node_or_null("PropCollision")
		var box: AABB = body.record_aabb(info["index"]) if body else AABB()
		_crown_marker.transform = Transform3D(Basis.from_scale(box.size * 0.62 + Vector3.ONE * 0.1), box.get_center())
		_crown_marker.visible = true
	elif info.get("type") == "tree":
		var trees := _tree_data()
		var k: int = info["index"]
		var r: Vector2 = trees.crown_radii[k]
		_crown_marker.transform = Transform3D(Basis.from_scale(Vector3(r.x, r.y, r.x) * 1.05), trees.crown_center[k])
		_crown_marker.visible = true
	var text := describe(info)
	show_text(text)
	print(text.replace("\n", " | "))
	DisplayServer.clipboard_set(text)


func show_text(text: String) -> void:
	if label:
		label.text = text
		panel.visible = true


func hide_overlay() -> void:
	if panel:
		panel.visible = false
	_set_highlight(null)


func describe(info: Dictionary) -> String:
	var lines: PackedStringArray = []
	var h: Vector3 = info["hit"]
	var z0: float = 0.0
	if world_root and world_root.has_meta("world"):
		z0 = world_root.get_meta("world")["origin"][2]
	match info.get("type"):
		"building":
			var title: String = info["name"] if info.get("name") else "(no name)"
			lines.append("#%d  %s" % [info["num"], title])
			if info.get("landmark"):
				lines.append("landmark %s (overrides.toml, references/%s/)" % [info["landmark"], info["landmark"]])
			var id_line := "%s · kind %s" % [info["id"], info["kind"]]
			if info.get("parent"):
				id_line += " · part of osm:%s" % info["parent"]
			lines.append(id_line)
			var others: PackedStringArray = []
			for src: String in info["heights"]:
				if src != info["height_src"]:
					others.append("%s %.1f" % [src, info["heights"][src]])
			lines.append("height %.1f m (%s)%s" % [info["height"], info["height_src"],
					("   others: " + ", ".join(others)) if others else ""])
			var walls := "walls yes" if info["walls"] else "no walls: slab from %.1f m, %d pillars" % [
					info["min_height"], info["pillars"]]
			lines.append("base %.2f m · %s · roof %s" % [info["base_z"], walls, info["roof_shape"]])
			if info.has("style"):
				var st: Array = info["style"]
				var tiers: PackedStringArray = []
				for k: String in info["tiers"]:
					tiers.append("%s %d" % [k, info["tiers"][k]])
				lines.append("%s: floors %s · ground %s · %s · top %s%s · %d window floors (g %.1f, f %.1f m)" % [
						info["group"], st[0], st[1], st[2], st[3], (" · windows " + st[4]) if st.size() > 4 else "",
						info["levels"], info["floor_heights"][0], info["floor_heights"][1]])
				lines.append("tiers %s%s" % [", ".join(tiers), (" · %d passages" % info["passages"]) if info["passages"] else ""])
			if info.has("facade"):
				var fa: Dictionary = info["facade"]
				var wall := "wall %s (%s)" % [fa["color"], fa["color_src"]]
				if fa.has("photo"):
					var ph: Dictionary = fa["photo"]
					wall += " · %s from %d photos, confidence %.2f, glazing %d%%, measured %s" % [ph["wall_name"], ph["photos"],
							ph["confidence"], roundi(ph["glazing"] * 100), ph["measured"]]
				lines.append(wall)
			var src: Dictionary = info.get("src", {})
			if src.has("bdtopo") or src.has("rnb"):
				lines.append("BD TOPO %s · RNB %s" % [src.get("bdtopo", "-"), src.get("rnb", "-")])
		"tree":
			var arch := String(info["model"]).get_slice("_", 0)
			lines.append("%s  %s tree (model %s)" % [info["id"], arch, info["model"]])
			lines.append("height %.1f m · crown radius %.1f m · tint %s · %s" % [info["height"], info["radius"],
					info["tint"], info["part"]])
			var src: String = info["src"]
			var where := {"lidar": "LiDAR top", "osm+lidar": "OSM tree matched to a LiDAR top",
					"row+lidar": "OSM tree row, LiDAR top", "osm": "OSM tree, no LiDAR top (sapling)",
					"row": "gap in an OSM tree row (sapling)", "override": "added by overrides.toml"}
			lines.append("source: %s%s%s" % [where.get(src.replace("+override", ""), src),
					" + override" if src.ends_with("+override") else "",
					(" · osm:" + info["osm"]) if info["osm"] else ""])
		"hedge":
			lines.append("%s  hedge" % info["id"])
			lines.append("height %.1f m (%s) · width %.1f m · tint %s" % [info["height"], info["height_src"],
					info["width"], info["tint"]])
			lines.append("source: %s" % info["src"])
		"prop":
			var title: String = info["kind"].replace("_", " ")
			lines.append("%s  %s%s" % [info["id"], title, ("  \"%s\"" % info["name"]) if info["name"] else ""])
			var src: String = info["src"]
			lines.append("model %s · source %s%s · facing %.0f°" % [info["model"], src,
					(" · osm:" + info["osm"]) if info["osm"] else "", fposmod(90.0 - float(info["yaw"]), 360.0)])
			var extra: Dictionary = info["info"]
			if extra.has("stop"):
				var refs: PackedStringArray = []
				for l: Dictionary in extra["lines"]:
					refs.append(l["ref"])
				lines.append("bus stop %s · lines %s · IDFM %s" % [extra["stop"], " ".join(refs) if refs else "none known",
						", ".join(PackedStringArray(extra["idfm"])) if extra["idfm"] else "-"])
			if extra.has("codes"):
				lines.append("signs %s · %d photo detections" % [" ".join(PackedStringArray(extra["codes"])).replace("FR:", ""),
						extra["detections"]])
			if extra.has("phase"):
				lines.append("%s signal, phase %.2f of the 30 s cycle" % ["pedestrian" if extra["ped"] else "car", extra["phase"]])
			var tags: PackedStringArray = []
			for k: String in info["tags"]:
				tags.append("%s=%s" % [k, info["tags"][k]])
			if info["tint"]:
				tags.append("tint " + info["tint"])
			if tags:
				lines.append(" · ".join(tags))
		"fence":
			lines.append("%s  %s %s" % [info["id"], info["style"], "wall" if info["style"] == "wall" else "fence"])
			lines.append("height %.1f m (%s) · osm:%s" % [info["height"], info["height_src"], info["osm"]])
		"terrain", "ground":
			var map := GroundMap.get_map()
			lines.append(map.describe(h.x, -h.z) if map else "Ground")
			lines.append("%s (%s)" % [info["id"], "raised surface" if info["type"] == "ground" else "LiDAR ground"])
		_:
			lines.append(str(info.get("id", "unknown object")))
	lines.append("hit x %.1f  y %.1f  z %.1f (altitude %.1f m) · %.0f m away" % [
			h.x, -h.z, h.y, h.y + z0, info["distance"]])
	return "\n".join(lines)


func _set_highlight(mi: MeshInstance3D) -> void:
	if _highlighted and is_instance_valid(_highlighted):
		_highlighted.material_overlay = null
	_highlighted = mi
	if mi:
		mi.material_overlay = _highlight_mat
	_crown_marker.visible = false
