extends "res://scripts/car.gd"
## Police nationale patrol car (Car.SPECS "police-hatchback"): the realistic compact hatchback in the force's grey livery
## of 2021 on, built by blender/vehicles/build_car.py, driven like the other realistic cars (cab view, passenger seat),
## with a blue LED light bar on its roof and two blue flashers in its grille (its cab file's "beacons") and the French
## police two-tone siren, la-ré (scripts/vehicle_audio.gd). The bell action (B) switches the siren and the lights on
## and off: the bar's left half and the left flasher flash three times, then the right ones (FLASH s), each side lighting
## the street around it in blue.
## LAN games: net_state carries the switch (flag 512, as for the fire truck's siren); a remote copy flashes and sounds
## from it.

const FLASH := 0.6                          # s, a cycle of the blue lights: three quick flashes on each side in turn
const FLAGS_SIREN := 512                    # above car.gd's net_state flags

var siren := false                          # siren sounding, lights flashing

var _beacons := {"left": [], "right": []}   # per side: the bar's half and the grille flasher
var _lit_beacon: StandardMaterial3D         # unlit, they show the model's own blue
var _beacon_lights: Array[OmniLight3D] = [] # left, right, over the bar
var _lit_sides := [false, false]
var _flash_t := 0.0


func setup(model: String) -> void:
	super(model)
	name = "PoliceCar"
	audio.siren_tone = "police"
	_lit_beacon = StandardMaterial3D.new()
	_lit_beacon.albedo_color = Color(0.12, 0.3, 1.0)
	_lit_beacon.emission_enabled = true
	_lit_beacon.emission = _lit_beacon.albedo_color
	_lit_beacon.emission_energy_multiplier = 10.0
	for side: String in ["left", "right"]:
		for n: String in _cab_file["beacons"][side]:
			_beacons[side].append(find_child(n, true, false) as MeshInstance3D)
		var light := OmniLight3D.new()
		light.name = "Beacon_" + side
		light.light_color = Color(0.2, 0.4, 1.0)
		light.omni_range = 10.0
		light.light_energy = 3.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = BEAM_FADE * 0.5
		light.distance_fade_length = 20.0
		light.visible = false
		var bar: MeshInstance3D = _beacons[side][0]
		light.position = _in_car(bar) * bar.get_aabb().get_center() + Vector3.UP * 0.25
		add_child(light)
		_beacon_lights.append(light)


func _unhandled_input(event: InputEvent) -> void:
	if driving and controls and event.is_action_pressed("bell"):
		siren = not siren
		get_viewport().set_input_as_handled()
		return
	super(event)


func _physics_process(delta: float) -> void:
	super(delta)
	if not remote:
		audio.siren = siren


func _process(delta: float) -> void:
	super(delta)
	_update_beacons(delta)


## Three quick flashes of the left lights, then of the right ones, every FLASH s; all dark with the siren off.
func _update_beacons(delta: float) -> void:
	_flash_t = fmod(_flash_t + delta, FLASH) if siren else 0.0
	var phase := _flash_t / FLASH
	for k in 2:
		var t := phase * 2.0 - k                # 0..1 during this side's half
		var lit := siren and t >= 0.0 and t < 1.0 and fmod(t * 3.0, 1.0) < 0.55
		if lit == _lit_sides[k]:
			continue
		_lit_sides[k] = lit
		for mi: MeshInstance3D in _beacons["left" if k == 0 else "right"]:
			mi.material_override = _lit_beacon if lit else null
		_beacon_lights[k].visible = lit


## LAN games: the car's state with the siren switch in the flags.
func net_state() -> Array:
	var s := super()
	s[4] = s[4] | (FLAGS_SIREN if siren else 0)
	return s


func apply_net_state(a: Array, b: Array, w: float) -> void:
	super(a, b, w)
	siren = b[4] & FLAGS_SIREN != 0
	audio.siren = siren


func dash_line() -> String:
	return "SIREN" if siren else ""
