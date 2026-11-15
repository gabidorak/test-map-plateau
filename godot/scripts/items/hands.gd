extends Node3D
## Our player's hands (Main/Items/Hands, not on a dedicated server): the item in hand shown (third person: in the body's
## right hand; first person: before the camera), the fire key held (items.gd fires: try_fire), the aim (the right mouse
## held: a narrower view), a weapon's kick and muzzle flash. A weapon in hand turns the body with the view (player.gd
## face_aim). The models are made once per kind and kept; nothing runs while the hands are empty.

const ItemDb = preload("res://scripts/items/item_db.gd")
const Weapon = preload("res://scripts/items/weapons/weapon.gd")

const HAND := Vector3(0.3, 1.12, -0.38)     # third person: the item in the body's right hand
const VIEW := Vector3(0.27, -0.26, -0.55)   # first person: before the camera
const AIM_FOV := 50.0

var items: Node                             # items.gd
var people: Node                            # people.gd
var audio: Node                             # items_audio.gd
var player: CharacterBody3D                 # game.player
var kind := ""                              # the item in hand, "" none
var trigger := false                        # the fire key held
var aiming := false
var cool := 0.0                             # s before the next shot

var _models := {}                           # kind -> [third person model, first person model]
var _flash: OmniLight3D
var _flash_t := 0.0
var _base_fov := 70.0
var _kick := 0.0                            # the gun's kick back, easing to 0


func _ready() -> void:
	_base_fov = player.camera.fov
	_flash = OmniLight3D.new()
	_flash.light_energy = 3.0
	_flash.omni_range = 5.0
	_flash.visible = false
	_flash.top_level = true
	add_child(_flash)


func _exit_tree() -> void:
	for k: String in _models:
		for m: Node in _models[k]:
			if is_instance_valid(m):
				m.queue_free()
	if player and player.camera:
		player.camera.fov = _base_fov


## Takes `item_kind` in hand ("" empty hands).
func show_kind(item_kind: String) -> void:
	kind = item_kind
	trigger = false
	if kind != "" and not _models.has(kind):
		_make_models(kind)
	_show_models()
	player.face_aim = kind != "" and ItemDb.is_weapon(kind)


func _make_models(k: String) -> void:
	var b: Weapon = items.behaviour(k)
	if b == null:
		_models[k] = []
		return
	var tp := b.model()
	tp.position = HAND
	(player.get_node("Body") as Node3D).add_child(tp)
	var fp := b.model()
	fp.position = VIEW
	fp.scale = Vector3.ONE * 0.85
	for mi: GeometryInstance3D in fp.find_children("*", "GeometryInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.camera.add_child(fp)
	_models[k] = [tp, fp]


func _show_models() -> void:
	var fp: bool = player.first_person
	var shown: bool = player.visible and not player.held and not player.person_carried()
	for k: String in _models:
		var pair: Array = _models[k]
		if pair.size() == 2:
			(pair[0] as Node3D).visible = k == kind and shown and not fp
			(pair[1] as Node3D).visible = k == kind and shown and fp


## The muzzle of the model in view (first or third person), or the camera when none.
func muzzle_node() -> Node3D:
	var pair: Array = _models.get(kind, [])
	if pair.size() == 2:
		var m: Node3D = pair[1] if player.first_person else pair[0]
		var tip := m.get_node_or_null("Muzzle") as Node3D
		if tip:
			return tip
	return player.camera


## Where the crosshair points: the first thing (or person standing, not us) on the camera's line, `reach` m out from
## the player at most.
func aim_point(reach: float) -> Vector3:
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var to := from + dir * (reach + from.distance_to(player.global_position + Vector3.UP * 1.5))
	return Weapon.trace(get_world_3d().direct_space_state, people.up_people(), from, to, people.my_id())["point"]


## A flash of `color` at the muzzle, the gun kicking back.
func flash(color: Color) -> void:
	_flash.light_color = color
	_flash.global_position = muzzle_node().global_position
	_flash.visible = true
	_flash_t = 0.06


## The view kicked up (`pitch` rad) and the gun back.
func recoil(pitch: float) -> void:
	player.kick(pitch * randf_range(0.8, 1.2), pitch * randf_range(-0.3, 0.3))
	_kick = 1.0


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = _flash_t > 0.0
	var cam: Camera3D = player.camera
	if kind == "" and absf(cam.fov - _base_fov) < 0.05:
		return
	_show_models()
	_kick = maxf(_kick - delta * 6.0, 0.0)
	var pair: Array = _models.get(kind, [])
	for m: Node3D in pair:
		m.rotation.x = _kick * 0.35
	var want := AIM_FOV if aiming and kind != "" else _base_fov
	cam.fov = lerpf(cam.fov, want, 1.0 - exp(-12.0 * delta))
	if absf(cam.fov - want) < 0.05:
		cam.fov = want


func _physics_process(delta: float) -> void:
	cool = maxf(cool - delta, 0.0)
	if trigger and cool <= 0.0:
		trigger = false                     # one shot per press
		items.try_fire()
