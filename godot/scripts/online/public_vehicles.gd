extends Node
## PTA Online's public vehicles (data/public_vehicles.json; scripts/modes/online_mode.gd makes this node as
## Main/Mode/PublicVehicles): vehicles of nobody's garage that any player may take (online_mode.gd refuse_drive lets
## them): the police helicopter (scripts/helicopter.gd) on Polytechnique's car park by the lake, to try it online; the
## lots' (builder/lots.gd public_vehicles(): the police cars on the commissariat's car park, lot sousPrefecture). The
## host (or solo player, or the official server) parks them when the game starts and tells the players which they are
## (their net ids).

const Garages = preload("res://scripts/online/garages.gd")
const Car = preload("res://scripts/car.gd")
const Lots = preload("res://scripts/builder/lots.gd")
const DATA := "res://data/public_vehicles.json"

var mode: Node                              # online_mode.gd
var spots: Array = []                       # {"id", "model", "name", "xf" (Godot transform of its place)}
var public_ids := {}                        # net id -> its place's name (every peer, from the host)
var _cars := {}                             # host: id -> Car
var _hosting := false


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
	if not parsed is Dictionary:
		push_error("No public vehicles: %s missing" % DATA)
		return
	for v: Dictionary in parsed.get("vehicles", []) + Lots.public_vehicles():
		if not Car.SPECS.has(str(v["model"])):
			continue
		var a := deg_to_rad(float(v["yaw"]))
		spots.append({"id": str(v["id"]), "model": str(v["model"]), "name": str(v["name"]),
				"xf": Transform3D(Basis(Vector3.UP, PI - a), Garages._at(float(v["x"]), float(v["y"])))})


## The game started here: the host parks them.
func begin(hosting: bool) -> void:
	_hosting = hosting
	if not hosting:
		return
	for s: Dictionary in spots:
		_cars[s["id"]] = mode.game.park_vehicle(s["model"], s["xf"], true)
		var car: Car = _cars[s["id"]]
		if car.net_id != "":
			public_ids[car.net_id] = s["name"]
	mode.send_all(self, "_c_ids", [public_ids])


## Whether the vehicle of net id `net_id` is a public one (anyone may drive it).
func is_public(net_id: String) -> bool:
	return public_ids.has(net_id)


## The place of public vehicle `car` (here), "" when it is not one (the prompts).
func public_name(car: Car) -> String:
	if car == null:
		return ""
	if not mode.game.net.active:            # (solo: no net ids)
		for s: Dictionary in spots:
			if _cars.get(s["id"]) == car:
				return s["name"]
		return ""
	return public_ids.get(car.net_id, "")


## Host: player `peer` came in: which vehicles are public.
func player_registered(peer: int) -> void:
	if _hosting:
		mode.send_to(peer, self, "_c_ids", [public_ids])


@rpc("authority", "call_remote", "reliable")
func _c_ids(ids: Dictionary) -> void:
	public_ids = ids
