extends Node
## Night mode (N, or the settings page: Settings "night"; game.gd adds it to Main and switches it). The scene's sun
## turns into moonlight (pale blue, low in the south-east, still casting shadows), the sky into a night one
## (shaders/night_sky.gdshader: stars and the moon, where the moonlight comes from), with a dark blue ambient light and
## haze. About half the buildings' rooms are lit (global shader uniform `night`, shaders/toy_building.gdshader), the
## street lamp diffusers and ad panels glow, and each street and path lamp lights the ground under it (not while
## knocked over, breakables.gd), as do the RER B platform lamps (the station's lights glow too). Bot vehicles drive with their headlights on (car.gd `night`); game.gd switches the
## player's on as they get in. Day puts the scene's own settings back, also when the scene goes (the environment and
## the prop materials are shared resources that a reloaded scene gets again). Each player's own: LAN games do not
## share it.

const Car = preload("res://scripts/car.gd")
const Train = preload("res://scripts/train.gd")
const MOON := Vector3(-30.0, 35.0, 0.0)     # moonlight rotation, degrees: from 30° up in the south-east
const MOON_COLOR := Color(0.6, 0.7, 1.0)
const MOON_ENERGY := 0.55
const AMBIENT := Color(0.3, 0.38, 0.6)
const AMBIENT_ENERGY := 0.55
const FOG := Color(0.03, 0.045, 0.08)
const FOG_DENSITY := 0.0018
const SATURATION := 0.9
const GLOW_ENERGY := 6.0                    # lamp diffusers and ad panels (toy_prop.gdshader "glow" slot)
const LAMP_COLOR := Color(1.0, 0.85, 0.62)
const LAMP_FADE := 150.0                    # m from the camera beyond which the lamps' lights fade out (not their glow)
## lamp model -> [energy, range (m), spot angle (degrees; 0: an omni light)]
const LAMPS := {"lamp_street": [5.0, 18.0, 70.0], "lamp_path": [1.6, 9.0, 0.0]}
const RAIL_LAMP := [4.0, 14.0, 80.0]        # the RER B platform lamps (rail_builder.gd), as the street lamps
const LAMP_CHECK := 0.3                     # s between looks for knocked-over lamps

var on := false
var game: Node                              # game.gd: its cars and breakables
var env: Environment
var sun: DirectionalLight3D
var world_root: Node3D

var _day := {}                              # the scene's own settings
var _sky: ShaderMaterial
var _lamps: Array = []                      # [Light3D, MultiMesh, instance]
var _lamps_built := false
var _glow: Array[ShaderMaterial] = []
var _glow_day: Array = []                   # their glow_energy by day
var _check_t := 0.0


func _exit_tree() -> void:
	set_night(false)


func set_night(n: bool) -> void:
	if n == on:
		return
	on = n
	if _day.is_empty():
		_day = {"sky": env.sky.sky_material, "ambient": env.ambient_light_color,
				"ambient_energy": env.ambient_light_energy, "sky_share": env.ambient_light_sky_contribution,
				"fog": env.fog_enabled, "saturation": env.adjustment_saturation, "sun": sun.rotation,
				"sun_color": sun.light_color, "sun_energy": sun.light_energy}
	if n:
		if _sky == null:
			_sky = ShaderMaterial.new()
			_sky.shader = load("res://shaders/night_sky.gdshader")
		env.sky.sky_material = _sky
		env.ambient_light_color = AMBIENT
		env.ambient_light_energy = AMBIENT_ENERGY
		env.ambient_light_sky_contribution = 0.15
		env.fog_enabled = true
		env.fog_light_color = FOG
		env.fog_density = FOG_DENSITY
		env.fog_sky_affect = 0.0
		env.adjustment_saturation = SATURATION
		sun.rotation_degrees = MOON
		sun.light_color = MOON_COLOR
		sun.light_energy = MOON_ENERGY
	else:
		env.sky.sky_material = _day["sky"]
		env.ambient_light_color = _day["ambient"]
		env.ambient_light_energy = _day["ambient_energy"]
		env.ambient_light_sky_contribution = _day["sky_share"]
		env.fog_enabled = _day["fog"]
		env.adjustment_saturation = _day["saturation"]
		sun.rotation = _day["sun"]
		sun.light_color = _day["sun_color"]
		sun.light_energy = _day["sun_energy"]
	RenderingServer.global_shader_parameter_set("night", 1.0 if n else 0.0)
	Car.night = n
	Train.night = n
	if game:
		for car: Car in game.cars:
			if is_instance_valid(car) and car.is_bot():
				car.set_headlights(n)
	if n and not _lamps_built:
		_build_lamps()
	for k in _glow.size():
		_glow[k].set_shader_parameter("glow_energy", GLOW_ENERGY if n else _glow_day[k])
	for l: Array in _lamps:
		(l[0] as Light3D).visible = n
	_check_t = LAMP_CHECK


## A light under each street and path lamp, child of its MultiMesh (so it streams with it, world_streamer.gd), and the
## glow material of their diffusers.
func _build_lamps() -> void:
	_lamps_built = true
	_build_rail_lamps()
	var props := world_root.get_node_or_null("Props") if world_root else null
	if props == null:
		return
	for mmi: MultiMeshInstance3D in props.find_children("*", "MultiMeshInstance3D", true, false):
		var spec: Array = LAMPS.get(String(mmi.name), [])
		var mm := mmi.multimesh
		if spec.is_empty() or mm == null:
			continue
		var head := _glow_box(mm.mesh)
		if head.size == Vector3.ZERO:
			continue
		for i in mm.instance_count:
			var light: Light3D
			if spec[2] > 0.0:
				var spot := SpotLight3D.new()
				spot.spot_range = spec[1]
				spot.spot_angle = spec[2]
				spot.spot_angle_attenuation = 0.5
				spot.rotation = Vector3(-PI * 0.5, 0.0, 0.0)    # its -Z down
				light = spot
			else:
				var omni := OmniLight3D.new()
				omni.omni_range = spec[1]
				light = omni
			light.light_color = LAMP_COLOR
			light.light_energy = spec[0]
			light.light_specular = 0.3
			light.distance_fade_enabled = true
			light.distance_fade_begin = LAMP_FADE
			light.distance_fade_length = 30.0
			# just under the diffuser: a spot does not light its own lamp head from inside
			light.position = _instance(mm, i) * Vector3(head.get_center().x, head.position.y - 0.05, head.get_center().z)
			mmi.add_child(light)
			_lamps.append([light, mm, i])


## The RER B station's platform lamps (rail_builder.gd: Rail/Station, their lights' positions in its "lamp_lights"
## meta) light the platforms; their diffusers, the screens and the underpass and tunnel lights glow.
func _build_rail_lamps() -> void:
	var station := world_root.get_node_or_null("Rail/Station") if world_root else null
	if station == null:
		return
	for mi: MeshInstance3D in world_root.get_node("Rail").find_children("*", "MeshInstance3D", true, false):
		if mi.mesh:
			_glow_box(mi.mesh)
	for p: Vector3 in station.get_meta("lamp_lights", PackedVector3Array()):
		var spot := SpotLight3D.new()
		spot.spot_range = RAIL_LAMP[1]
		spot.spot_angle = RAIL_LAMP[2]
		spot.spot_angle_attenuation = 0.5
		spot.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		spot.light_color = LAMP_COLOR
		spot.light_energy = RAIL_LAMP[0]
		spot.light_specular = 0.3
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = LAMP_FADE
		spot.distance_fade_length = 30.0
		spot.position = p
		station.add_child(spot)
		_lamps.append([spot, null, 0])


## Box of `mesh`'s glowing surface (toy_prop.gdshader mode 2), in the mesh frame; its material goes into _glow.
func _glow_box(mesh: Mesh) -> AABB:
	for k in mesh.get_surface_count():
		var mat := mesh.surface_get_material(k) as ShaderMaterial
		if mat == null or mat.get_shader_parameter("mode") != 2:
			continue
		if mat not in _glow:
			_glow.append(mat)
			var day: Variant = mat.get_shader_parameter("glow_energy")
			_glow_day.append(day if day != null \
					else RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), "glow_energy"))
		var box := AABB()
		var first := true
		for v: Vector3 in mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
		return box
	return AABB()


## Instance i of `mm` as drawn now: through breakables.gd's copy of the buffer (it scales knocked-over ones to nothing).
func _instance(mm: MultiMesh, i: int) -> Transform3D:
	return game.breakables.instance_transform(mm, i) if game and game.breakables else mm.get_instance_transform(i)


func _process(delta: float) -> void:
	if not on or _lamps.is_empty():
		return
	_check_t += delta
	if _check_t < LAMP_CHECK:
		return
	_check_t = 0.0
	for l: Array in _lamps:
		if l[1] != null:                    # the railway's lamps do not break
			(l[0] as Light3D).visible = _instance(l[1], l[2]).basis.x.length_squared() > 1e-4
