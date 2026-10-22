extends Node3D
## The rescue helicopter of Escape from Plateau and its landing circle (Main/Mode/Evac on every peer): "Dragon 91", a
## red and yellow Sécurité Civile helicopter (toy built here), rotor turning, its searchlight sweeping the fog, a red
## beacon blinking and a column of light over it that shows from afar where it waits. The circle round it (RADIUS m)
## is where survivors are rescued and players climb aboard; take_off() flies it away with them.

const Marks = preload("res://scripts/race_marks.gd")

const RADIUS := 13.0                        # m, the landing circle
const RED := Color(0.85, 0.1, 0.08)
const YELLOW := Color(1.0, 0.8, 0.1)
const RING := Color(1.0, 0.45, 0.2)
const ROTOR_IDLE := 9.0                     # rad/s, waiting
const ROTOR_FLY := 26.0                     # rad/s, flying
const LIFT_TIME := 14.0                     # s from the take-off until it is gone

var flying := false
var audio: Node                             # escape_audio.gd, or null

var _heli: Node3D
var _rotor: Node3D
var _tail_rotor: Node3D
var _beacon: OmniLight3D
var _beacon_mesh: MeshInstance3D
var _search: SpotLight3D
var _search_pivot: Node3D
var _ring: MeshInstance3D
var _column: Node3D
var _rotor_speed := ROTOR_IDLE
var _t := 0.0
var _fly_t := 0.0
var _start := Transform3D.IDENTITY


## At pipeline (`x`, `y`), the helicopter facing `yaw` (radians) on the ground there.
func setup(x: float, y: float, yaw: float) -> void:
	name = "Evac"
	var h := Marks.ground(x, y)
	position = Vector3(x, h, -y)
	_ring = Marks.ring(x, y, RADIUS, 2.0, RING, 0, true)
	_ring.position = Vector3.ZERO
	add_child(_ring)
	_heli = _build()
	_heli.rotation.y = yaw
	_heli.scale = Vector3.ONE * 1.3
	add_child(_heli)
	_start = _heli.transform
	var label := Marks.sign_text(x, y, 7.5, "DRAGON 91 · RESCUE", 72, Color(1.0, 0.85, 0.6))
	label.position = Vector3(0.0, 7.5, 0.0)
	label.visibility_range_end = 120.0
	add_child(label)


func _ready() -> void:
	if audio:
		audio.set_rotor(_heli, true)


func _exit_tree() -> void:
	if audio:
		audio.set_rotor(_heli, false)


## True when `p` (global) is in the landing circle.
func contains(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() < RADIUS \
			and absf(p.y - global_position.y) < 6.0


## Lifts off and flies away (the mission ends).
func take_off() -> void:
	flying = true
	_fly_t = 0.0


## True once it has flown out of sight.
func gone() -> bool:
	return flying and _fly_t > LIFT_TIME


func _process(delta: float) -> void:
	_t += delta
	_rotor_speed = move_toward(_rotor_speed, ROTOR_FLY if flying else ROTOR_IDLE, delta * 6.0)
	_rotor.rotate_y(_rotor_speed * delta)
	_tail_rotor.rotate_x(_rotor_speed * 4.0 * delta)
	var blink := fmod(_t, 1.2) < 0.15
	_beacon.visible = blink
	_beacon_mesh.visible = blink
	_search_pivot.rotation = Vector3(-0.55 + 0.15 * sin(_t * 0.6), 0.9 * sin(_t * 0.35), 0.0)
	Marks.set_strength(_ring, 0.6 + 0.4 * sin(_t * 3.0))
	if flying:
		_fly_t += delta
		var k := _fly_t / LIFT_TIME
		var up := 70.0 * k * k + 6.0 * minf(_fly_t / 3.0, 1.0)
		var away := 260.0 * maxf(k - 0.2, 0.0) * maxf(k - 0.2, 0.0)
		_heli.transform = _start.translated_local(Vector3(0.0, 0.0, -away)).translated(Vector3.UP * up)
		_heli.rotation.x = -0.18 * minf(maxf(_fly_t - 2.5, 0.0) / 3.0, 1.0)
		_column.visible = false
		_ring.visible = false


# ---------------------------------------------------------------- looks

func _build() -> Node3D:
	var root := Node3D.new()
	root.name = "Helicopter"
	var red := _mat(RED, 0.35, 0.2)
	var yellow := _mat(YELLOW, 0.4, 0.1)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.6)
	var blade_mat := _mat(Color(0.42, 0.42, 0.45), 0.5)
	var glass := _mat(Color(0.12, 0.2, 0.3), 0.08, 0.6)
	var body := Node3D.new()
	body.position.y = 1.55
	root.add_child(body)
	var hull := _part(body, _capsule(1.05, 4.6), red, Vector3(0.0, 0.0, 0.2))
	hull.rotation.x = PI * 0.5
	hull.scale = Vector3(1.0, 1.0, 1.08)
	var band := _part(body, _capsule(1.07, 2.2), yellow, Vector3(0.0, -0.15, 0.6))
	band.rotation.x = PI * 0.5
	band.scale = Vector3(1.0, 1.0, 0.55)
	var canopy := _part(body, _sphere(0.95), glass, Vector3(0.0, 0.18, -1.55))
	canopy.scale = Vector3(1.0, 0.85, 1.15)
	_part(body, _box(Vector3(1.2, 0.55, 2.0)), red, Vector3(0.0, 1.05, 0.5))       # engines
	var boom := _part(body, _cylinder(0.22, 0.42, 5.2), red, Vector3(0.0, 0.35, 4.6))
	boom.rotation.x = PI * 0.5
	_part(body, _box(Vector3(0.12, 1.5, 0.9)), yellow, Vector3(0.0, 0.95, 7.1))     # fin
	_part(body, _box(Vector3(1.6, 0.08, 0.5)), red, Vector3(0.0, 0.4, 6.4))         # stabilizer
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.18, 1.1, 7.2)
	body.add_child(_tail_rotor)
	for k in 2:
		var b := _part(_tail_rotor, _box(Vector3(0.05, 1.3, 0.14)), dark, Vector3.ZERO)
		b.rotation.x = k * PI * 0.5
	var mast := _part(body, _cylinder(0.1, 0.12, 0.6), dark, Vector3(0.0, 1.55, 0.3))
	mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_rotor = Node3D.new()
	_rotor.position = Vector3(0.0, 1.88, 0.3)
	body.add_child(_rotor)
	for k in 4:
		var blade := Node3D.new()
		blade.rotation.y = k * PI * 0.5
		_rotor.add_child(blade)
		_part(blade, _box(Vector3(0.32, 0.05, 5.4)), blade_mat, Vector3(0.0, 0.0, 2.75))
	var disc := CylinderMesh.new()                  # the spinning blades' blur
	disc.top_radius = 5.6
	disc.bottom_radius = 5.6
	disc.height = 0.02
	disc.radial_segments = 32
	var blur := StandardMaterial3D.new()
	blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blur.albedo_color = Color(0.5, 0.5, 0.55, 0.16)
	blur.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blur_mi := _part(body, disc, blur, Vector3(0.0, 1.88, 0.3))
	blur_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side: float in [-1.0, 1.0]:                 # skids
		var skid := _part(root, _cylinder(0.07, 0.07, 4.2), dark, Vector3(0.95 * side, 0.12, 0.2))
		skid.rotation.x = PI * 0.5
		for z: float in [-0.9, 1.2]:
			var strut := _part(root, _cylinder(0.05, 0.05, 0.9), dark, Vector3(0.75 * side, 0.55, z))
			strut.rotation.z = 0.35 * side
	for side: float in [-1.0, 1.0]:                 # its name on both sides
		var l := Label3D.new()
		l.text = "DRAGON 91"
		l.font_size = 64
		l.pixel_size = 0.006
		l.outline_size = 0
		l.modulate = Color(1, 1, 1)
		l.position = Vector3(1.08 * side, 0.1, 0.9)
		l.rotation.y = PI * 0.5 * side
		body.add_child(l)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.albedo_color = Color(3.0, 0.2, 0.1)
	_beacon_mesh = _part(body, _sphere(0.11), beacon_mat, Vector3(0.0, 1.4, 1.6))
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.15, 0.1)
	_beacon.light_energy = 6.0
	_beacon.omni_range = 18.0
	_beacon.position = Vector3(0.0, 1.5, 1.6)
	body.add_child(_beacon)
	_search_pivot = Node3D.new()
	_search_pivot.position = Vector3(0.0, -0.75, -1.9)
	body.add_child(_search_pivot)
	_search = SpotLight3D.new()
	_search.light_color = Color(1.0, 0.96, 0.85)
	_search.light_energy = 16.0
	_search.spot_range = 70.0
	_search.spot_angle = 11.0
	_search.shadow_enabled = false
	_search_pivot.add_child(_search)
	_search_pivot.add_child(_beam(70.0, 6.0, Color(1.0, 0.95, 0.8, 0.05)))
	_column = _beam(160.0, 4.0, Color(1.0, 0.55, 0.3, 0.06))
	_column.rotation.x = PI * 0.5               # straight up
	_column.position.y = 2.0
	root.add_child(_column)
	var cabin := OmniLight3D.new()                  # a warm light in the open cabin
	cabin.light_color = Color(1.0, 0.85, 0.6)
	cabin.light_energy = 2.0
	cabin.omni_range = 6.0
	cabin.position = Vector3(0.0, 0.1, 0.4)
	body.add_child(cabin)
	return root


## A cone of light `length` m long, `radius` m wide at its end, pointing -Z: drawn over the fog.
func _beam(length: float, radius: float, c: Color) -> Node3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = radius
	cone.height = length
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = c
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	cone.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = PI * 0.5                        # its narrow top at the lamp, the wide end along -Z
	mi.position = Vector3(0.0, 0.0, -length * 0.5)
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cylinder(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	return m
