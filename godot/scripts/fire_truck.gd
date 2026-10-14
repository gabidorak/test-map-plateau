extends "res://scripts/car.gd"
## Airport fire truck (Car.SPECS "fire-truck"): a 6x6 crash tender built by blender/vehicles/build_fire_truck.py, driven
## like the other vehicles (all six wheels drive, the front two steer), with a working roof water cannon
## (scripts/water_cannon.gd), blue beacons and a two-tone siren.
## The cannon aims where the driver looks: the point under the middle of the screen (the chase camera's line of sight,
## up to AIM_RANGE) is where the turret turns (YAW_RATE) and the barrel rises (PITCH_RATE) to drop the jet, allowing for
## gravity and air drag (or at its longest reach); the fire action (left mouse button, held) sprays. game.gd draws a ring
## where the jet as aimed would land (sight_point). The bell action (B) switches the siren and the beacons on and off.
## LAN games: net_state also carries the turret aim and the spray and siren switches (flags 32, 64); a remote copy
## turns its turret and sprays from them for show, the hits counting on the peer simulating the truck.

const WaterCannon = preload("res://scripts/water_cannon.gd")
const YAW_RATE := 1.4                       # rad/s, turret
const PITCH_RATE := 0.9                     # rad/s, barrel
const YAW_LIMIT := 2.9                      # rad either way from straight ahead
const PITCH_LIMITS := Vector2(-0.15, 1.0)   # rad, barrel down / up
const LONGEST := 0.66                       # rad of barrel elevation that throws the jet furthest (with the drag)
const AIM_RANGE := 150.0                    # m, how far the driver's line of sight is followed
const AIM_MASK := Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.DEBRIS
const FLASH := 0.7                          # s, the blue beacons' cycle: two quick flashes on each side in turn
const FLAGS_SPRAY := 32
const FLAGS_SIREN := 64

var cannon: WaterCannon
var aim := Vector2.ZERO                     # turret yaw (+ to the left), barrel pitch (+ up), rad
var siren := false                          # siren sounding, beacons flashing
var aim_target := Vector3.INF               # global, the point the driver looks at (INF: none)

var _fittings := {}                         # assets/cars/fire_truck.json
var _monitor: Node3D                        # turning head of the cannon
var _barrel: Node3D
var _monitor_rest := Transform3D.IDENTITY
var _barrel_rest := Transform3D.IDENTITY
var _pivot := Vector3.ZERO                  # barrel pivot, car frame
var _want := Vector2.ZERO                   # aim the turret turns to
var _beacons := {"left": [], "right": [], "amber": []}
var _beacon_mats := {}                      # "blue" / "amber" -> [off, on]
var _beacon_lights: Array[OmniLight3D] = [] # left, right
var _flash_t := 0.0
var _sight := Vector3.INF                   # where the jet as aimed lands (global), INF: nowhere in reach
var _solved := Vector3.INF                  # target the barrel pitch was last solved for (car frame)
var _aim_query := PhysicsRayQueryParameters3D.new()


func setup(model: String) -> void:
	_fittings = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cars/" + SPECS[model]["fittings"]))
	super(model)
	name = "FireTruck"
	_monitor = find_child(_fittings["monitor"], true, false) as Node3D
	_barrel = _monitor.find_child(_fittings["barrel"], true, false) as Node3D
	_monitor_rest = _monitor.transform
	_barrel_rest = _barrel.transform
	var m: Node3D = _monitor
	while m.get_parent() != self:
		m = m.get_parent()
	var tip := Vector3(_fittings["nozzle"][0], _fittings["nozzle"][1], _fittings["nozzle"][2]) * m.scale + m.position
	_pivot = _in_car(_barrel).origin
	var nozzle := Node3D.new()
	nozzle.name = "Nozzle"
	nozzle.transform = _in_car(_barrel).affine_inverse() * Transform3D(Basis.IDENTITY, tip)
	_barrel.add_child(nozzle)
	cannon = WaterCannon.new()
	cannon.nozzle = nozzle
	add_child(cannon)
	# beacons: the model's meshes, lit by swapping materials; a blue light over each roof beacon
	for k: String in ["blue", "amber"]:
		var c := Color(0.15, 0.35, 1.0) if k == "blue" else Color(1.0, 0.6, 0.05)
		var off := StandardMaterial3D.new()
		off.albedo_color = c.darkened(0.5)
		off.roughness = 0.2
		var on := StandardMaterial3D.new()
		on.albedo_color = c
		on.emission_enabled = true
		on.emission = c
		on.emission_energy_multiplier = 8.0
		_beacon_mats[k] = [off, on]
	for side: String in _beacons:
		for n: String in _fittings["beacons"][side]:
			var mi := find_child(n, true, false) as MeshInstance3D
			mi.material_override = _beacon_mats["amber" if side == "amber" else "blue"][0]
			_beacons[side].append(mi)
	for side: String in ["left", "right"]:
		var light := OmniLight3D.new()
		light.name = "Beacon_" + side
		light.light_color = Color(0.2, 0.4, 1.0)
		light.omni_range = 9.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		var lamp: MeshInstance3D = _beacons[side][0]
		light.position = _in_car(lamp) * lamp.get_aabb().get_center() + Vector3.UP * 0.4
		add_child(light)
		_beacon_lights.append(light)


## Lamps from the truck's fittings file (no walkable layout).
func _build_lamps(m: Node3D, box: AABB, _layout: Dictionary) -> void:
	super(m, box, _fittings)


func _ready() -> void:
	super()
	_aim_query.collision_mask = AIM_MASK
	_aim_query.exclude = [get_rid()]


func set_driving(on: bool) -> void:
	super(on)
	if not on:
		cannon.firing = false


func _unhandled_input(event: InputEvent) -> void:
	if driving and controls and event.is_action_pressed("bell"):
		siren = not siren
		get_viewport().set_input_as_handled()
		return
	super(event)


func _physics_process(delta: float) -> void:
	super(delta)
	if remote:
		return
	if driving and controls:
		_take_aim()
		cannon.firing = Input.is_action_pressed("fire")
	else:
		cannon.firing = false
	aim.x = move_toward(aim.x, _want.x, YAW_RATE * delta)
	aim.y = move_toward(aim.y, _want.y, PITCH_RATE * delta)
	_pose_turret()
	audio.siren = siren
	if driving:
		_sight = _predict_landing()


## The point the driver looks at, and the turret aim that drops the jet there.
func _take_aim() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var to := from - cam.global_basis.z * AIM_RANGE
	_aim_query.from = from
	_aim_query.to = to
	var h := get_world_3d().direct_space_state.intersect_ray(_aim_query)
	aim_target = h["position"] if h else to
	var d := to_local(aim_target) - _pivot
	_want.x = clampf(atan2(d.x, d.z), -YAW_LIMIT, YAW_LIMIT)
	if _solved == Vector3.INF or _solved.distance_to(d) > 0.2:
		_solved = d
		_want.y = solve_pitch(Vector2(d.x, d.z).length(), d.y)


## Barrel elevation (rad) whose jet, leaving the nozzle at WaterCannon.SPEED, passes `dist` m away horizontally at
## `rise` m above the pivot: the low shot, found by bisection on the flight with drag; LONGEST when out of reach,
## the lowest elevation when even that passes over it.
func solve_pitch(dist: float, rise: float) -> float:
	if _height_at(PITCH_LIMITS.x, dist) > rise:
		return PITCH_LIMITS.x
	if _height_at(LONGEST, dist) < rise:
		return LONGEST
	var lo := PITCH_LIMITS.x
	var hi := LONGEST
	for i in 14:
		var mid := (lo + hi) * 0.5
		if _height_at(mid, dist) < rise:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Height above the pivot of a jet at elevation `pitch` when it is `dist` m away horizontally (-INF: falls short).
func _height_at(pitch: float, dist: float) -> float:
	var barrel := cannon.nozzle.position.length()
	var p := Vector2(cos(pitch), sin(pitch)) * barrel
	var v := Vector2(cos(pitch), sin(pitch)) * WaterCannon.SPEED
	var dt := 0.05
	for i in int(WaterCannon.LIFE / dt):
		if p.x >= dist:
			return p.y
		var q := p + v * dt
		if q.x >= dist:
			return lerpf(p.y, q.y, (dist - p.x) / (q.x - p.x))
		v.y -= WaterCannon.G * dt
		v -= v * WaterCannon.DRAG * dt
		p = q
	return -INF


## Where a jet out of the nozzle as it points now first hits something (global), INF if nowhere.
func _predict_landing() -> Vector3:
	var xf := cannon.nozzle.global_transform
	var p := xf.origin
	var v := xf.basis.z.normalized() * WaterCannon.SPEED + linear_velocity
	var dt := 0.08
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = WaterCannon.MASK
	q.exclude = [get_rid()]
	for i in int(WaterCannon.LIFE / dt):
		q.from = p
		q.to = p + v * dt
		var h := space.intersect_ray(q)
		if h:
			return h["position"]
		p = q.to
		v.y -= WaterCannon.G * dt
		v -= v * WaterCannon.DRAG * dt
	return Vector3.INF


## Where the jet as aimed would land (global), or null; for the ring on the screen.
func sight_point() -> Variant:
	return _sight if _sight != Vector3.INF else null


func _pose_turret() -> void:
	_monitor.transform = _monitor_rest * Transform3D(Basis(Vector3.UP, aim.x), Vector3.ZERO)
	_barrel.transform = _barrel_rest * Transform3D(Basis(Vector3.RIGHT, -aim.y), Vector3.ZERO)


func _process(delta: float) -> void:
	super(delta)
	_update_beacons(delta)


## Blue beacons: two quick flashes on the left, then on the right (FLASH s); the amber one pulses like a rotating
## lamp. All dark with the siren off.
func _update_beacons(delta: float) -> void:
	_flash_t = fmod(_flash_t + delta, FLASH) if siren else 0.0
	var phase := _flash_t / FLASH
	for k in 2:
		var side := "left" if k == 0 else "right"
		var t := phase * 2.0 - k                # 0..1 during this side's half
		var lit := siren and t >= 0.0 and t < 1.0 and (t < 0.18 or (t > 0.3 and t < 0.48))
		for mi: MeshInstance3D in _beacons[side]:
			mi.material_override = _beacon_mats["blue"][1 if lit else 0]
		_beacon_lights[k].visible = lit
		_beacon_lights[k].light_energy = 3.0 if lit else 0.0
	var amber := siren and fmod(phase * 3.0, 1.0) < 0.35
	for mi: MeshInstance3D in _beacons["amber"]:
		mi.material_override = _beacon_mats["amber"][1 if amber else 0]


## LAN games: the car's state with the spray and siren switches in the flags and the turret aim after it.
func net_state() -> Array:
	var s := super()
	s[4] = s[4] | (FLAGS_SPRAY if cannon.firing else 0) | (FLAGS_SIREN if siren else 0)
	s.append(aim)
	return s


func apply_net_state(a: Array, b: Array, w: float) -> void:
	super(a, b, w)
	var flags: int = b[4]
	cannon.firing = flags & FLAGS_SPRAY != 0
	siren = flags & FLAGS_SIREN != 0
	audio.siren = siren
	if b.size() > 7:
		aim = a[7].lerp(b[7], minf(w, 1.0)) if a.size() > 7 else b[7]
		_want = aim
		_pose_turret()


## A remote copy's cannon sprays for show only: the hits count on the peer simulating the truck.
func set_remote(on: bool) -> void:
	super(on)
	cannon.live = not on
	cannon.firing = false


func dash_line() -> String:
	var parts := PackedStringArray()
	if cannon.firing:
		parts.append("WATER")
	if siren:
		parts.append("SIREN")
	return " · ".join(parts)
