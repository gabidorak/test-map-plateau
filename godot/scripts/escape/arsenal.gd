extends Node3D
## The local player's weapons and kit in Escape from Plateau (Main/Mode/Arsenal on each player's peer).
## - Weapons (WEAPONS; 1-4 pick one): the crowbar (always there: swings at what is in front), the pistol (always
##   there), the shotgun and the submachine gun (found as supplies, loot.gd). Left mouse fires (held: the submachine gun
##   keeps firing), R reloads (the shotgun a shell at a time), the right mouse (held) aims: a narrower view, tighter
##   rounds. Rounds go where the crosshair is (a ray from the camera, then one from the muzzle to that point), a head
##   hit counts HEADSHOT times; each leaves a tracer, the muzzle flashes and lights up, the view kicks up, and the
##   shot is heard by the zombies round (escape_mode.gd make_noise) and seen by the other players (send_shot). The
##   pistol and the submachine gun share the 9 mm rounds.
## - Carrying a survivor, or knocked down, only the pistol (one hand); rounds scatter more.
## - Kit: bandages (Q: +BANDAGE_HEAL health over BANDAGE_TIME s), medkits (Q when badly hurt, +MEDKIT_HEAL), the
##   flashlight (F) on its battery (BATTERY_LIFE s; spares from supplies; it flickers when nearly flat).
## Hits on zombies go to the host (escape_mode.gd hit_zombie); blood or dust where a round lands, for everyone's shots
## (impact()).

const Layers = preload("res://scripts/physics_layers.gd")
const Zombie = preload("res://scripts/escape/zombie.gd")

## weapon -> its make: damage per round (pellet), rounds a second, magazine, the rounds it takes, reload time (s; the
## shotgun: per shell), scatter (rad), pellets per shot, reach (m), how far zombies hear it (m), view kick (rad)
const WEAPONS := {
	"crowbar": {"name": "Crowbar", "melee": true, "damage": 55.0, "rate": 1.7, "range": 2.3},
	"pistol": {"name": "Pistol", "damage": 34.0, "rate": 5.0, "mag": 12, "ammo": "ammo", "reload": 1.3,
			"spread": 0.012, "pellets": 1, "range": 110.0, "noise": 65.0, "kick": 0.035, "sound": "pistol"},
	"shotgun": {"name": "Shotgun", "damage": 15.0, "rate": 1.15, "mag": 6, "ammo": "shells", "reload": 0.55,
			"spread": 0.065, "pellets": 9, "range": 45.0, "noise": 105.0, "kick": 0.09, "sound": "shotgun",
			"per_shell": true},
	"smg": {"name": "Submachine gun", "damage": 21.0, "rate": 11.0, "mag": 30, "ammo": "ammo", "reload": 2.0,
			"spread": 0.028, "pellets": 1, "range": 90.0, "noise": 85.0, "kick": 0.017, "sound": "smg", "auto": true},
}
const ORDER := ["crowbar", "pistol", "shotgun", "smg"]
const MAX := {"ammo": 180, "shells": 40, "bandage": 5, "medkit": 2, "battery": 3}
const GIVES := {"ammo": 24, "shells": 8}
const HEADSHOT := 2.2
const BANDAGE_HEAL := 30.0
const BANDAGE_TIME := 2.5
const MEDKIT_HEAL := 80.0
const MEDKIT_TIME := 4.5
const BATTERY_LIFE := 300.0                 # s of light per battery
const AIM_FOV := 48.0
const MASK := Layers.SOLID | Layers.VEGETATION | Layers.PROPS | Layers.VEHICLES | Layers.ZOMBIE | Layers.DEBRIS
const TRACER := Color(3.0, 1.9, 0.7)
const LIGHT_COLOR := Color(1.0, 0.95, 0.85)

var mode: Node                              # escape_mode.gd
var player: CharacterBody3D                 # game.player
var owned := {}
var mag := {}
var reserve := {}
var weapon := "pistol"
var bandages := 0
var medkits := 0
var batteries := 0
var battery := 1.0                          # 0 .. 1, the flashlight's
var light_on := false
var trigger := false                        # fire held (semi-automatic: one shot per press)
var aiming := false
var active := false                         # escape_mode.gd: on foot, alive, no menu, the mouse captured
var one_hand := false                       # carrying, or knocked down: the pistol only
var reload_t := 0.0                         # s left of the reload (or of this shell)
var heal_t := 0.0                           # s left of the bandage or medkit
var heal_kind := ""
var shots := 0                              # tests: shots fired, rounds that hit a zombie
var zombie_hits := 0

var _cool := 0.0
var _swing_t := -1.0                        # crowbar: s since the swing started (-1: none)
var _swung := false
var _light: SpotLight3D
var _cone: Node3D
var _tp := {}                               # weapon -> its model in the player's hand (third person)
var _fp := {}                               # weapon -> its model before the camera (first person)
var _flash: OmniLight3D
var _flash_t := 0.0
var _rng := RandomNumberGenerator.new()
var _base_fov := 70.0
var _flicker_t := 0.0

static var _shared := {}


func _ready() -> void:
	_rng.randomize()
	reset(true)
	var pivot: Node3D = player.get_node("Pivot")
	_light = SpotLight3D.new()
	_light.name = "Flashlight"
	_light.light_color = LIGHT_COLOR
	_light.light_energy = 7.0
	_light.spot_range = 40.0
	_light.spot_angle = 24.0
	_light.spot_angle_attenuation = 1.4
	_light.shadow_enabled = true
	_light.position = Vector3(0.18, -0.12, -0.25)
	_light.visible = false
	pivot.add_child(_light)
	_cone = beam_cone(12.0, 2.4, 0.035)
	_cone.position = _light.position
	_cone.visible = false
	pivot.add_child(_cone)
	var body: Node3D = player.get_node("Body")
	var cam: Camera3D = player.camera
	_base_fov = cam.fov
	for w: String in ORDER:
		var tp := gun_model(w)
		tp.position = Vector3(0.3, 1.12, -0.38)
		body.add_child(tp)
		_tp[w] = tp
		var fp := gun_model(w)
		fp.position = Vector3(0.27, -0.26, -0.55)
		fp.scale = Vector3.ONE * 0.8
		for mi: GeometryInstance3D in fp.find_children("*", "GeometryInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cam.add_child(fp)
		_fp[w] = fp
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.35)
	_flash.light_energy = 5.0
	_flash.omni_range = 8.0
	_flash.visible = false
	add_child(_flash)


func _exit_tree() -> void:
	for d: Dictionary in [_tp, _fp]:
		for w: String in d:
			if is_instance_valid(d[w]):
				(d[w] as Node).queue_free()
	if is_instance_valid(_light):
		_light.queue_free()
	if is_instance_valid(_cone):
		_cone.queue_free()
	if player and player.camera:
		player.camera.fov = _base_fov


## The kit at the start of a mission (`fresh`), or after dying: the guns kept, the pistol loaded, a few rounds at least.
func reset(fresh: bool) -> void:
	if fresh:
		owned = {"crowbar": true, "pistol": true}
		mag = {"pistol": 12, "shotgun": 0, "smg": 0}
		reserve = {"ammo": 36, "shells": 0}
		bandages = 1
		medkits = 0
		batteries = 0
		battery = 1.0
		weapon = "pistol"
	else:
		mag["pistol"] = 12
		reserve["ammo"] = maxi(reserve["ammo"], 24)
		battery = maxf(battery, 0.5)
	reload_t = 0.0
	heal_t = 0.0
	trigger = false
	light_on = false


## Takes weapon `w` in hand (if owned, and allowed with one hand).
func select(w: String) -> void:
	if not owned.has(w) or w == weapon or (one_hand and w != "pistol"):
		return
	weapon = w
	reload_t = 0.0
	_cool = maxf(_cool, 0.25)
	if mode.audio:
		mode.audio.play("click", -10.0)


func press_fire() -> void:
	trigger = true


func release_fire() -> void:
	trigger = false


func toggle_light() -> void:
	light_on = not light_on and (battery > 0.0 or batteries > 0)
	if mode.audio:
		mode.audio.play("click", -6.0)


## Starts reloading the weapon in hand, if it is not full and there are rounds for it.
func reload() -> void:
	var w: Dictionary = WEAPONS[weapon]
	if w.get("melee", false) or reload_t > 0.0 or heal_t > 0.0 or mag[weapon] >= w["mag"] or reserve[w["ammo"]] <= 0:
		return
	reload_t = w["reload"]
	if mode.audio:
		mode.audio.play("pump" if weapon == "shotgun" else "reload", -6.0)


## Q: a medkit when badly hurt (or when there is no bandage), else a bandage. False when there is nothing to use.
func heal(health: float, max_health: float) -> bool:
	if heal_t > 0.0 or health >= max_health:
		return false
	if medkits > 0 and (health < 50.0 or bandages == 0):
		heal_kind = "medkit"
		heal_t = MEDKIT_TIME
	elif bandages > 0:
		heal_kind = "bandage"
		heal_t = BANDAGE_TIME
	else:
		return false
	reload_t = 0.0
	if mode.audio:
		mode.audio.play("bandage", -4.0)
	return true


## Uses up a medkit (getting up alone when knocked down). False when there is none.
func use_medkit() -> bool:
	if medkits <= 0:
		return false
	medkits -= 1
	return true


## Whether a supply of `kind` (loot.gd) is any use.
func wants(kind: String) -> bool:
	match kind:
		"ammo":
			return reserve["ammo"] < MAX["ammo"]
		"shells":
			return reserve["shells"] < MAX["shells"]
		"bandage":
			return bandages < MAX["bandage"]
		"medkit":
			return medkits < MAX["medkit"]
		"battery":
			return batteries < MAX["battery"]
		"shotgun":
			return not owned.has("shotgun") or reserve["shells"] < MAX["shells"]
		"smg":
			return not owned.has("smg") or reserve["ammo"] < MAX["ammo"]
	return false


## Takes a supply of `kind`; returns what to tell the player.
func give(kind: String) -> String:
	match kind:
		"ammo", "shells":
			reserve[kind] = mini(reserve[kind] + GIVES[kind], MAX[kind])
			return "+%d %s" % [GIVES[kind], "rounds" if kind == "ammo" else "shells"]
		"bandage":
			bandages += 1
			return "Bandage (%d)" % bandages
		"medkit":
			medkits += 1
			return "Medkit (%d)" % medkits
		"battery":
			batteries += 1
			return "Flashlight battery (%d spare)" % batteries
		"shotgun", "smg":
			var ammo: String = WEAPONS[kind]["ammo"]
			if owned.has(kind):
				reserve[ammo] = mini(reserve[ammo] + WEAPONS[kind]["mag"], MAX[ammo])
				return "+%d %s" % [WEAPONS[kind]["mag"], "rounds" if ammo == "ammo" else "shells"]
			owned[kind] = true
			mag[kind] = WEAPONS[kind]["mag"]
			reserve[ammo] = mini(reserve[ammo] + (8 if kind == "shotgun" else 30), MAX[ammo])
			if not one_hand:
				weapon = kind
			return "%s! (%d)" % [WEAPONS[kind]["name"], ORDER.find(kind) + 1]
	return ""


## For the HUD: the weapon, its rounds, the kit.
func ammo_text() -> String:
	var w: Dictionary = WEAPONS[weapon]
	if w.get("melee", false):
		return w["name"]
	var text: String = "%s   %d / %d" % [w["name"], mag[weapon], reserve[w["ammo"]]]
	if reload_t > 0.0:
		text += "   reloading…"
	return text


func _physics_process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	if one_hand and weapon != "pistol":
		weapon = "pistol"
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			_reloaded()
	if heal_t > 0.0:
		heal_t -= delta
		if heal_t <= 0.0:
			if heal_kind == "medkit" and medkits > 0:
				medkits -= 1
				mode.heal(MEDKIT_HEAL)
			elif heal_kind == "bandage" and bandages > 0:
				bandages -= 1
				mode.heal(BANDAGE_HEAL)
	if light_on:
		battery -= delta / BATTERY_LIFE
		if battery <= 0.0:
			if batteries > 0:
				batteries -= 1
				battery = 1.0
			else:
				battery = 0.0
				light_on = false
	if _swing_t >= 0.0:
		_swing_t += delta
		if not _swung and _swing_t > 0.14:
			_swung = true
			_melee_hit()
		if _swing_t > 0.5:
			_swing_t = -1.0
	if trigger and active and _cool <= 0.0 and heal_t <= 0.0:
		var w: Dictionary = WEAPONS[weapon]
		if w.get("melee", false):
			_swing()
		elif mag[weapon] > 0 and (reload_t <= 0.0 or w.get("per_shell", false)):
			reload_t = 0.0
			_fire(w)
			if not w.get("auto", false):
				trigger = false
		elif mag[weapon] <= 0:
			trigger = false
			if mode.audio:
				mode.audio.play("empty", -4.0)
			reload()


func _reloaded() -> void:
	var w: Dictionary = WEAPONS[weapon]
	if w.get("melee", false):
		return
	var ammo: String = w["ammo"]
	if w.get("per_shell", false):
		if reserve[ammo] > 0 and mag[weapon] < w["mag"]:
			mag[weapon] += 1
			reserve[ammo] -= 1
		if reserve[ammo] > 0 and mag[weapon] < w["mag"]:
			reload_t = w["reload"]          # the next shell
		elif mode.audio:
			mode.audio.play("pump", -6.0)
		return
	var n := mini(int(w["mag"]) - int(mag[weapon]), int(reserve[ammo]))
	mag[weapon] += n
	reserve[ammo] -= n


## One shot of the gun in hand: its pellets traced from the crosshair, checked from the muzzle.
func _fire(w: Dictionary) -> void:
	var cam: Camera3D = player.camera
	if cam == null:
		return
	_cool = 1.0 / float(w["rate"])
	mag[weapon] -= 1
	shots += 1
	var space := get_world_3d().direct_space_state
	var muzzle := _muzzle()
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	var spread: float = w["spread"] * (0.5 if aiming else 1.0) * (1.8 if one_hand else 1.0)
	var ends := PackedVector3Array()
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = MASK
	for k in int(w["pellets"]):
		var dir := (fwd + cam.global_basis.x * _rng.randfn(0.0, spread) + cam.global_basis.y * _rng.randfn(0.0, spread)).normalized()
		q.from = eye
		q.to = eye + dir * float(w["range"])
		var hit := space.intersect_ray(q)
		var end: Vector3 = hit["position"] if hit else q.to
		q.from = muzzle
		q.to = end + (end - muzzle).normalized() * 0.05
		var near := space.intersect_ray(q)              # something between the gun and that point
		if near and muzzle.distance_to(near["position"]) < muzzle.distance_to(end) - 0.1:
			hit = near
			end = near["position"]
		ends.append(end)
		if hit:
			_land(hit, (end - muzzle).normalized(), w)
	tracers(muzzle, ends)
	_flash.global_position = muzzle
	_flash.visible = true
	_flash_t = 0.05
	var kick: float = w["kick"] * (0.6 if aiming else 1.0)
	player.kick(kick * _rng.randf_range(0.8, 1.2), kick * _rng.randf_range(-0.35, 0.35))
	if mode.audio:
		mode.audio.play(w["sound"], -2.0, _rng.randf_range(0.95, 1.05))
	mode.make_noise(muzzle, w["noise"])
	mode.send_shot(weapon, muzzle, ends)


## A round of `w` hit `hit` (a ray result) flying along `dir`.
func _land(hit: Dictionary, dir: Vector3, w: Dictionary) -> void:
	var collider: Object = hit["collider"]
	var p: Vector3 = hit["position"]
	if collider is Zombie:
		var z := collider as Zombie
		var dmg: float = w["damage"]
		if weapon == "shotgun":                 # pellets lose their bite with the distance
			dmg *= clampf(1.25 - player.global_position.distance_to(p) / 30.0, 0.35, 1.0)
		var head := z.is_head(p)
		if head:
			dmg *= HEADSHOT
		zombie_hits += 1
		mode.hit_zombie(z.zid, dmg, dir, false, head)
		impact(p, -dir, "blood")
		if mode.audio:
			mode.audio.play_at("hit_flesh", p, -6.0, _rng.randf_range(0.9, 1.2), 5.0, 40.0)
	else:
		var metal := collider is Node and (collider as Node).is_in_group("vehicles")
		impact(p, hit["normal"], "spark" if metal else "dust")
		if not metal and collider is CollisionObject3D:
			mode.game.breakables.shoot(collider, hit["shape"], dir * 250.0)


func _swing() -> void:
	_cool = 1.0 / float(WEAPONS["crowbar"]["rate"])
	_swing_t = 0.0
	_swung = false
	if mode.audio:
		mode.audio.play("swing", -4.0, _rng.randf_range(0.9, 1.1))


## The crowbar's blow: the zombies in front of the player, within its reach.
func _melee_hit() -> void:
	var space := get_world_3d().direct_space_state
	var fwd: Vector3 = -player.camera.global_basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var shape := SphereShape3D.new()
	shape.radius = 0.95
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = Layers.ZOMBIE
	q.transform = Transform3D(Basis(), player.global_position + Vector3.UP * 1.1 + fwd * 1.15)
	var landed := 0
	for r: Dictionary in space.intersect_shape(q, 6):
		var z := r["collider"] as Zombie
		if z == null or landed >= 3:
			continue
		landed += 1
		zombie_hits += 1
		mode.hit_zombie(z.zid, WEAPONS["crowbar"]["damage"], fwd, true, false)
		impact(z.global_position + Vector3.UP * 1.3, -fwd, "blood")
	if landed > 0 and mode.audio:
		mode.audio.play("hit_flesh", -2.0, _rng.randf_range(0.9, 1.1))
	mode.make_noise(player.global_position, 12.0)


## Where the rounds leave from: the muzzle of the gun in hand (first or third person).
func _muzzle() -> Vector3:
	var m: Node3D = (_fp if player.first_person else _tp)[weapon]
	var tip := m.get_node_or_null("Muzzle") as Node3D
	return tip.global_position if tip else player.camera.global_position


func _process(delta: float) -> void:
	_flash_t -= delta
	_flash.visible = _flash_t > 0.0
	var fp: bool = player.first_person
	for w: String in ORDER:
		var held := w == weapon and player.visible
		(_tp[w] as Node3D).visible = held and not fp
		(_fp[w] as Node3D).visible = held and fp
	# the crowbar's swing, the guns' kick back
	var swing := 0.0
	if _swing_t >= 0.0:
		swing = sin(clampf(_swing_t / 0.35, 0.0, 1.0) * PI) * 1.4
	var kickback := maxf(_cool * float(WEAPONS[weapon].get("rate", 1.0)) - 0.6, 0.0) * 0.25
	for d: Dictionary in [_tp, _fp]:
		var m: Node3D = d[weapon]
		m.rotation = Vector3(-swing + kickback * 2.0, swing * 0.4, 0.0)
	# the flashlight, flickering when nearly flat
	_flicker_t -= delta
	var shine := light_on and player.visible
	if shine and battery < 0.15 and _flicker_t <= 0.0:
		_flicker_t = _rng.randf_range(0.05, 0.4)
		_light.light_energy = 7.0 * (_rng.randf_range(0.1, 1.0) if _rng.randf() < 0.5 else 1.0)
	elif battery >= 0.15:
		_light.light_energy = 7.0
	_light.visible = shine
	_cone.visible = shine and not fp
	var cam: Camera3D = player.camera
	if cam:
		cam.fov = lerpf(cam.fov, AIM_FOV if aiming and active else _base_fov, 1.0 - exp(-12.0 * delta))


# ---------------------------------------------------------------- effects (also for the other players' shots)

## Glowing tracers from `from` to each of `ends`, gone in a moment.
func tracers(from: Vector3, ends: PackedVector3Array) -> void:
	for e in ends:
		var l := from.distance_to(e)
		if l < 0.3:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _tracer_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
		var mid := from.lerp(e, 0.5)
		mi.global_transform = Transform3D(Basis.looking_at(e - from), mid).scaled_local(Vector3(1.0, 1.0, l))
		var tw := mi.create_tween()
		tw.tween_property(mi, "transparency", 1.0, 0.07)
		tw.tween_callback(mi.queue_free)


## Blood ("blood"), sparks ("spark") or a puff of dust ("dust") at `p`, thrown out along `normal`.
func impact(p: Vector3, normal: Vector3, kind: String) -> void:
	var fx := CPUParticles3D.new()
	fx.top_level = true
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 10 if kind != "dust" else 6
	fx.lifetime = 0.5 if kind != "dust" else 0.9
	fx.mesh = _fx_mesh(kind)
	fx.direction = Vector3.UP
	fx.spread = 50.0
	fx.initial_velocity_min = 1.0 if kind == "dust" else 2.0
	fx.initial_velocity_max = 2.5 if kind == "dust" else 5.0
	fx.gravity = Vector3(0.0, -0.6 if kind == "dust" else -9.8, 0.0)
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.3
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fx)
	var n := normal if normal.length_squared() > 0.5 else Vector3.UP
	fx.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, n.normalized())) if n.normalized().dot(Vector3.UP) > -0.99 \
			else Basis.FLIP_Y, p + n.normalized() * 0.05)
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


## A cone of light `length` m long, `radius` m wide at its end, along -Z, `alpha` thick (a flashlight's beam in the fog).
static func beam_cone(length: float, radius: float, alpha: float) -> Node3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = radius
	cone.height = length
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 14
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(LIGHT_COLOR.r, LIGHT_COLOR.g, LIGHT_COLOR.b, alpha)
	mat.disable_receive_shadows = true
	cone.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = PI * 0.5
	mi.position = Vector3(0.0, 0.0, -length * 0.5)
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


## A toy gun (or the crowbar), along -Z, its "Muzzle" at the barrel's end.
static func gun_model(w: String) -> Node3D:
	var root := Node3D.new()
	root.name = w.capitalize()
	var metal := _mat("metal", Color(0.16, 0.17, 0.19), 0.35, 0.6)
	var wood := _mat("wood", Color(0.45, 0.27, 0.14), 0.7)
	var red := _mat("crowbar", Color(0.62, 0.1, 0.08), 0.5, 0.3)
	var muzzle_z := -0.2
	match w:
		"crowbar":
			_box_part(root, Vector3(0.035, 0.035, 0.72), red, Vector3(0.0, 0.0, -0.3))
			var hook := _box_part(root, Vector3(0.035, 0.12, 0.035), red, Vector3(0.0, 0.05, -0.68))
			hook.rotation.x = 0.4
		"pistol":
			_box_part(root, Vector3(0.04, 0.055, 0.2), metal, Vector3(0.0, 0.02, -0.08))
			var grip := _box_part(root, Vector3(0.035, 0.11, 0.05), metal, Vector3(0.0, -0.05, 0.0))
			grip.rotation.x = -0.25
			muzzle_z = -0.19
		"shotgun":
			_box_part(root, Vector3(0.05, 0.06, 0.62), metal, Vector3(0.0, 0.02, -0.28))
			_box_part(root, Vector3(0.06, 0.05, 0.18), wood, Vector3(0.0, -0.02, -0.34))      # the pump
			_box_part(root, Vector3(0.05, 0.09, 0.26), wood, Vector3(0.0, -0.03, 0.14))       # the stock
			muzzle_z = -0.6
		"smg":
			_box_part(root, Vector3(0.05, 0.08, 0.3), metal, Vector3(0.0, 0.0, -0.1))
			_box_part(root, Vector3(0.025, 0.025, 0.14), metal, Vector3(0.0, 0.02, -0.32))
			_box_part(root, Vector3(0.03, 0.15, 0.04), metal, Vector3(0.0, -0.1, -0.12))      # the magazine
			_box_part(root, Vector3(0.035, 0.1, 0.045), metal, Vector3(0.0, -0.07, 0.02))
			muzzle_z = -0.39
	var tip := Marker3D.new()
	tip.name = "Muzzle"
	tip.position = Vector3(0.0, 0.02, muzzle_z)
	root.add_child(tip)
	return root


static func _box_part(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var key := "box%s" % size
	if not _shared.has(key):
		var b := BoxMesh.new()
		b.size = size
		_shared[key] = b
	var mi := MeshInstance3D.new()
	mi.mesh = _shared[key]
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _mat(key: String, c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	if not _shared.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_shared[key] = m
	return _shared[key]


## A unit-long glowing streak along -Z (scaled to each tracer's length).
static func _tracer_mesh() -> Mesh:
	if not _shared.has("tracer"):
		var b := BoxMesh.new()
		b.size = Vector3(0.025, 0.025, 1.0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(TRACER.r, TRACER.g, TRACER.b, 0.9)
		b.material = m
		_shared["tracer"] = b
	return _shared["tracer"]


static func _fx_mesh(kind: String) -> Mesh:
	var key := "fx_" + kind
	if not _shared.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.12) if kind != "dust" else Vector2(0.5, 0.5)
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		match kind:
			"blood":
				m.albedo_color = Color(0.45, 0.02, 0.02, 0.95)
			"spark":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				m.albedo_color = Color(2.5, 1.8, 0.7)
			_:
				m.albedo_color = Color(0.55, 0.52, 0.46, 0.6)
		q.material = m
		_shared[key] = q
	return _shared[key]
