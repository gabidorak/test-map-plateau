extends Node
## PTA Online's properties (ONLINE_MILESTONES.md O9 step 1, data/properties.json), Main/Mode/Properties under
## scripts/modes/online_mode.gd: flats behind real windows of real buildings.
## - Each property's front door is its building's entrance (the Logements de l'X: the porch beside the plot's number,
##   scripts/builder/logements_x_builder.gd porch), with a sign saying what is for sale there (or that it is yours).
##   E there: its panel (scripts/online/property_panel.gd): buy it (with or without its garage option), add the garage
##   option later, go in once it is yours, open or lock its door to visitors, visit the flats other owners opened.
## - Going in builds its interior (scripts/online/studio_builder.gd) where the flat really is, behind its windows
##   (logements_x_builder.gd: slot_windows, floor_levels), and puts the player in its hall: through the windows one sees
##   the residence. E by the flat's front door: back out at the building's entrance; the interior goes. It also goes
##   when the player is taken elsewhere (the in-game menu's garage, a respawn). An interior exists only on the machine
##   of a player inside it (never on the server, nor for the others).
## - Instances: every owner has their own flat behind the same door (an address is not exclusive), all of them at the
##   same place in the building. The host keeps where each player is (`where`: peer -> "<property>|<owner>", "" out)
##   and tells everyone; each peer shows only the players in the same flat as itself (net.gd hidden_peers): outside,
##   no one sees those inside; inside, one sees only who is in the same flat.
## - Visits: an owner opens their flat's door to visitors (the panel); while they are in the game, any player may go
##   in from the entrance's panel ("Visit X's flat") and they see each other. Locked (the default), only the owner.
## - The residence's car park (rail.json logements_x car_park) has a residents' terminal (a PTA Online garage of kind
##   "residence", scripts/online/garages.gd, beside the path from the residence): its owners get their vehicles out
##   there, on its purple bays.
## - The garage option (garage_price more): a private lift in the flat's hall (a hidden garage of kind "private" whose
##   terminal is the lift and whose bays are the residents'): E by it lists the owner's vehicles; the one picked comes
##   out on a residents' bay with the player at the wheel.
## - Villa de charme (a property whose site is "villa", scripts/villaEnPierreCoteaux/): a whole estate. Its "front door" is the plaque by
##   its gate (the panel there); going in lets the player through the gate (villaEnPierreCoteaux.gd `allowed`: its owners and those
##   let in), its rooms are where they stand; its owners are let in by themselves as they come to the gate, and are
##   out once they leave its grounds. Its garage (the terminal by the utility room, a hidden garage of kind "private")
##   gets their vehicles out on its three bays. Players not let in are put back outside the gate.
## Who owns what: solo (the PTA Online test, --online-test), `owned`, bought with the test wallet. Online, buying comes
## with step 2 (the accounts server keeps them); until then the host reads its owners from PLATEAU_ONLINE_HOMES
## ("name=property[+garage];...", for tests) and tells each player theirs.

const LogX = preload("res://scripts/builder/logements_x_builder.gd")
const StudioBuilder = preload("res://scripts/online/studio_builder.gd")
const PropertyPanel = preload("res://scripts/online/property_panel.gd")
const Garages = preload("res://scripts/online/garages.gd")
const Car = preload("res://scripts/car.gd")
const Economy = preload("res://scripts/economy.gd")
const Marks = preload("res://scripts/race_marks.gd")
const VillaEnPierreCoteaux = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_data.gd")
const VillaEnPierreCoteauxHouse = preload("res://scripts/villaEnPierreCoteaux/villaEnPierreCoteaux_house.gd")
const DATA := "res://data/properties.json"
const RAIL := "res://world/rail.json"
const REACH := 2.6                          # m from a front door for E
const EXIT_REACH := 1.2                     # m from the flat's own front door (or its lift), inside, for E
const STAND := 1.3                          # m out of the entrance where the player is put back
const GARAGE_PRICE := 10000                 # € the garage option, when the data doesn't say
const VILLA_REACH := 16.0                   # m from the villa's gate within which its owners are let in
const VILLA_OUT := 24.0                     # m from it, outside its wall, beyond which they are out
## The Logements de l'X's residents' car park, in its car park's (a, b) (tools/rail/logements_x.py: a north along it,
## b east across it): the terminal at the mouth of the path from the residence (the planted island across the east
## row), facing north; two of its real bays either side of the path in the east row (drawn 0.6 m longer, into the
## aisle, for the long cars), their cars facing the aisle.
const RESIDENTS_ID := "logx-residents"
const RESIDENTS_TERMINAL := Vector2(6.9, 31.0)
const RESIDENTS_BAYS := [0.0, 2.5, 7.5, 10.0]  # a of each bay's south line
const RESIDENTS_BAY_B := 29.8               # b of their middles
const BAY := Vector2(2.5, 5.6)              # m, a bay's width and length
const BAY_MARGIN := 0.05                    # m a vehicle keeps from their lines (garages.gd fits: real bays, narrow)

var mode: Node                              # scripts/modes/online_mode.gd
var list: Array = []                        # {"id", "name", "short", "tier", "price", "garage_price", "about", "floor",
											# "site", "door2" (map), "door" (Godot), "out" (Godot, unit), "stand2" (map),
											# "frame" (Transform3D), "windows" ([x0, x1, y0, y1] in the flat's frame)}
var owned := {}                             # id -> {"garage": bool}: what the local player owns (solo: bought here;
											# online: from the host, _c_homes)
var inside := ""                            # the property the local player is in, "" none
var inside_owner := ""                      # whose flat there (the local player's, or the one they visit)
var where := {}                             # peer -> the flat they are in (instance), from the host; "" / none: out
var open := {}                              # instance -> true: flats open to visitors (their owner in the game)
var homes := {}                             # host, online: username -> {id: {"garage": bool}} (_read_homes)
var _names := {}                            # host: peer -> username, of those logged in
var interior: Node3D                        # its interior while they are
var _panel: PropertyPanel
var _mouse := Input.MOUSE_MODE_VISIBLE
var _signs := {}                            # id -> Label3D
var _lift := false                          # the lift's garage panel is open: a vehicle out is driven off
var _drive_t := 0.0                         # s left to wait for that vehicle to show up
var _villa_ask_t := 0.0                     # s before asking again to be let into the villa


func _ready() -> void:
	_load()
	_read_homes()
	if mode:
		mode.answered.connect(_on_answered)


func _load() -> void:
	if not FileAccess.file_exists(DATA) or not FileAccess.file_exists(RAIL):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var rail: Variant = JSON.parse_string(FileAccess.get_file_as_string(RAIL))
	if not data is Dictionary or not rail is Dictionary or not (rail as Dictionary).has("logements_x"):
		return
	var lx: Dictionary = rail["logements_x"]
	var ids := {}
	for e: Dictionary in data["properties"]:
		if ids.has(e["id"]):                    # (ids are permanent keys of the owners' saves: one each)
			push_error("properties.json: id %s twice, the second left out" % e["id"])
			continue
		ids[e["id"]] = true
		var b: Dictionary = e["building"]
		if str(b.get("site", "")) == "villa":
			_load_villa(e)
			continue
		if str(b.get("site", "")) != "logements_x":
			continue
		var pl := {}
		for q: Dictionary in lx["plots"]:
			if str(q["num"]) == str(b["plot"]):
				pl = q
		if pl.is_empty():
			push_error("Property %s: no plot %s" % [e["id"], b["plot"]])
			continue
		var i := int(b["face"])
		var k := int(b["floor"])
		var j := int(b["slot"])
		var f := LogX.face(pl, i)
		var corner: Vector2 = f[0]
		var along: Vector2 = f[1]
		var out: Vector2 = f[2]
		var lv := LogX.floor_levels(pl, lx["dims"], k)
		var u_left: float = float(LogX.slot(pl, i, k, j)[0]) + StudioBuilder.WINDOW_X
		var o := corner + along * u_left
		var frame := Transform3D(Basis(_gd(-along), Vector3.UP, _gd(-out)), Vector3(o.x, float(lv[0]), -o.y))
		var windows := []
		for w: Array in LogX.slot_windows(pl, i, k, j):
			windows.append([u_left - float(w[1]), u_left - float(w[0]), float(lv[1]) - float(lv[0]),
					float(lv[2]) - float(lv[0])])
		var po := LogX.porch(pl)
		var door2: Vector2 = po[0]
		var dout: Vector2 = po[1]
		list.append({"id": str(e["id"]), "name": str(e["name"]), "short": str(e.get("short", "Flat")),
				"tier": str(e.get("tier", "standard")), "price": int(e["price"]),
				"garage_price": int(e.get("garage_price", GARAGE_PRICE)), "about": str(e.get("about", "")),
				"floor": k, "site": "logements_x", "door2": door2, "door": Vector3(door2.x, float(po[2]), -door2.y),
				"out": _gd(dout), "stand2": door2 + dout * STAND, "frame": frame, "windows": windows})
	if lx.has("car_park") and list.any(func(p: Dictionary) -> bool: return p["site"] == "logements_x"):
		_garages(lx["car_park"])
	_villa_garage()


## The villa (its node: game.gd villa): its entry in the list, its plaque by the gate as its front door.
func _load_villa(e: Dictionary) -> void:
	var v: Node = _villa()
	if v == null:
		return
	var door: Vector3 = v.plaque_point()
	var out: Vector3 = v.road_out()
	var door2 := Vector2(door.x, -door.z)
	list.append({"id": str(e["id"]), "name": str(e["name"]), "short": str(e.get("short", "Villa")),
			"tier": str(e.get("tier", "luxury")), "price": int(e["price"]), "garage_price": int(e.get("garage_price", 0)),
			"about": str(e.get("about", "")), "floor": 0, "site": "villa", "door2": door2, "door": door, "out": out,
			"stand2": door2 + Vector2(out.x, -out.z) * STAND, "frame": v.frame, "windows": []})


func _villa() -> Node:
	return mode.game.get("villaEnPierreCoteaux") if mode and mode.game else null


## The villa's garage: a hidden garage of kind "private" (its owners: their vehicles out on its three bays).
func _villa_garage() -> void:
	var v: Node = _villa()
	if v == null or mode == null or mode.garages == null:
		return
	for p: Dictionary in list:
		if p["site"] != "villa":
			continue
		var bays := []
		for xf: Transform3D in v.garage_bays():
			bays.append({"xf": xf, "w": 3.0, "l": 5.6, "margin": 0.1})
		var t: Vector3 = v.frame * (VillaEnPierreCoteauxHouse.GARAGE_TERMINAL + Vector3(0.8, 0.0, 0.0))
		_add_garage({"id": garage_id(p["id"]), "name": "Your garage · %s" % p["name"], "kind": "private", "hidden": true,
				"property": p["id"], "site": "villa", "xy": Vector2(t.x, -t.z), "terminal": t, "facing": Vector3.RIGHT,
				"bays": bays, "about": "Your vehicles come out on the garage's three bays: pick one, then drive out."})


## The residents' terminal and bays at the Logements de l'X's car park `cp` (rail.json), and each flat's private lift
## (its garage option): PTA Online garages (mode.garages), built with the others.
func _garages(cp: Dictionary) -> void:
	if mode == null or mode.garages == null:
		return
	var o := Vector2(cp["o"][0], cp["o"][1])
	var d := Vector2(cp["d"][0], cp["d"][1]).normalized()
	var n := Vector2(d.y, -d.x)
	var at := func(a: float, b: float) -> Vector2: return o + d * a + n * b
	var bays := []
	var nose := _gd(-n)                     # the cars face the aisle
	for a0: float in RESIDENTS_BAYS:
		var c: Vector2 = at.call(a0 + BAY.x * 0.5, RESIDENTS_BAY_B)
		bays.append({"xf": Transform3D(Basis(Vector3.UP.cross(nose), Vector3.UP, nose), Garages._at(c.x, c.y)),
				"w": BAY.x, "l": BAY.y, "margin": BAY_MARGIN})
	var t: Vector2 = at.call(RESIDENTS_TERMINAL.x, RESIDENTS_TERMINAL.y)
	_add_garage({"id": RESIDENTS_ID, "name": "Logements de l'X", "kind": "residence", "site": "logements_x", "xy": t,
			"terminal": Garages._at(t.x, t.y), "facing": _gd(d), "bays": bays})
	for p: Dictionary in list:
		if p["site"] != "logements_x":
			continue
		_add_garage({"id": garage_id(p["id"]), "name": "Your garage · %s" % p["name"], "kind": "private",
				"hidden": true, "property": p["id"], "site": p["site"], "xy": p["door2"],
				"terminal": (p["frame"] as Transform3D) * StudioBuilder.LIFT, "facing": Vector3.FORWARD, "bays": bays})


func _add_garage(g: Dictionary) -> void:
	mode.garages.list.append(g)
	mode.garages.by_id[g["id"]] = g


## The private garage (the lift) of property `id`.
static func garage_id(id: String) -> String:
	return id + ":garage"


## The flat of `owner` at property `id` (an instance: where[peer]).
static func instance(id: String, owner: String) -> String:
	return "%s|%s" % [id, owner]


## Map vector -> Godot vector.
static func _gd(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, -v.y)


## The villa's entry, {} none.
func get_villa() -> Dictionary:
	return get_property(VillaEnPierreCoteaux.ID)


## The property `id` (its list entry), {} none.
func get_property(id: String) -> Dictionary:
	for p: Dictionary in list:
		if p["id"] == id:
			return p
	return {}


## Whether the local player owns property `id`.
func is_owned(id: String) -> bool:
	return owned.has(id)


## Whether the local player owns property `id` with its garage option.
func has_garage(id: String) -> bool:
	return owned.has(id) and bool(owned[id].get("garage", false))


## The local player's name (their account's online, their nickname solo).
func my_name() -> String:
	return str(mode.game.economy.username) if mode.game.net.active else str(mode.game.nickname)


## Host: what player `username` owns ({id: {"garage"}}): solo, the local player's.
func homes_of(username: String) -> Dictionary:
	if not mode.game.net.active:
		return owned
	return homes.get(username, {})


## Why the player of account `acc` (online_mode.gd account; {} the local player, for the prompts) may not get a vehicle
## out at garage `g` ("" they may): the residents' terminal is for those who own a flat in the residence, a flat's
## lift for its owner with the garage option.
func refusal(g: Dictionary, acc := {}) -> String:
	var kind := str(g.get("kind", ""))
	if kind not in ["residence", "private"]:
		return ""
	var theirs: Dictionary = owned if acc.is_empty() else homes_of(str(acc.get("username", "")))
	if kind == "private":
		return "" if bool(theirs.get(str(g["property"]), {}).get("garage", false)) \
				else "Comes with the flat's garage option."
	for id: String in theirs:
		if get_property(id).get("site", "") == str(g.get("site", "")):
			return ""
	return "Residents only: buy a flat in the residence (on the map)."


func _exit_tree() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()


## After the world is in (not on the dedicated server, which draws nothing): the signs and the panel.
func begin() -> void:
	for p: Dictionary in list:
		if p["site"] == "villa":
			_update_sign(p["id"])
		else:
			_sign(p)
	var v: Node = _villa()
	if v and not get_villa().is_empty():
		v.allowed = func() -> bool: return is_owned(VillaEnPierreCoteaux.ID) or inside == VillaEnPierreCoteaux.ID
	_panel = PropertyPanel.new()
	mode.game.hud.add_child(_panel)
	_panel.buy.connect(buy)
	_panel.enter.connect(func(id: String) -> void: enter(id))
	_panel.visit.connect(func(id: String, owner: String) -> void: enter(id, owner))
	_panel.door.connect(set_door)
	_panel.closed.connect(close_panel)


## The board by the entrance (on the other side of the door from the plot's number): what is for sale there, or that
## it is the player's.
func _sign(p: Dictionary) -> void:
	var out: Vector3 = p["out"]
	var x := Vector3.UP.cross(out).normalized()
	var at: Vector3 = p["door"] + x * 1.45 + out * 0.035 + Vector3(0, 1.45, 0)
	var basis := Basis(x, Vector3.UP, out)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.78, 0.5, 0.03)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#1c1d20")
	mat.roughness = 0.5
	board.material_override = mat
	board.transform = Transform3D(basis, at)
	add_child(board)
	var label := Label3D.new()
	label.transform = Transform3D(basis, at + out * 0.017)
	label.pixel_size = 0.0021
	label.font_size = 30
	label.outline_size = 0
	label.modulate = Color(0.96, 0.95, 0.92)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	_signs[p["id"]] = label
	_update_sign(p["id"])


func _update_sign(id: String) -> void:
	var p := get_property(id)
	if not p.is_empty() and p["site"] == "villa" and _villa():
		_villa().set_plaque("%s\n%s" % [str(p["name"]).to_upper(), "YOUR HOME" if is_owned(id)
				else "FOR SALE · %s" % Economy.money(int(p["price"]))])
		return
	if p.is_empty() or not _signs.has(id):
		return
	var label: Label3D = _signs[id]
	var k: int = p["floor"]
	var nth := "%d%s" % [k, "st" if k == 1 else "nd" if k == 2 else "rd" if k == 3 else "th"]
	label.text = "%s · %s FLOOR\n%s" % [str(p["short"]).to_upper(), nth.to_upper(), "YOUR HOME" if is_owned(id)
			else "FOR SALE\n%s" % Economy.money(int(p["price"]))]


# ---------------------------------------------------------------- the local player

func _player_pos() -> Vector3:
	return mode.game.player.global_position


## The property whose front door the player stands by (on foot, outside), {} none.
func door_at_hand() -> Dictionary:
	if inside != "" or mode.game.driving or mode.game.riding or mode.game.flying:
		return {}
	var here := _player_pos()
	for p: Dictionary in list:
		var d: Vector3 = p["door"]
		if Vector2(here.x - d.x, here.z - d.z).length() < REACH and absf(here.y - d.y) < 2.0:
			return p
	return {}


## How far the player, in a flat, stands from its point `meta` ("exit": the front door, "lift"), INF when not there.
func _inside_to(meta: String) -> float:
	if inside == "" or interior == null or not interior.has_meta(meta):
		return INF
	var e: Vector3 = interior.transform * (interior.get_meta(meta) as Vector3)
	var here := _player_pos()
	if absf(here.y - e.y) > 1.5:
		return INF
	return Vector2(here.x - e.x, here.z - e.z).length()


## Whether the player, in a flat, stands by its front door (nearer it than the lift).
func exit_at_hand() -> bool:
	var d := _inside_to("exit")
	return d < EXIT_REACH and d <= _inside_to("lift")


## Whether the player, in their own flat with the garage option, stands by its lift (nearer it than the front door).
func lift_at_hand() -> bool:
	if inside_owner != my_name() or not has_garage(inside):
		return false
	var d := _inside_to("lift")
	return d < EXIT_REACH and d < _inside_to("exit")


## E: in a flat by its door, out; by its lift, the vehicles to leave with; by a property's front door, its panel.
## Whether E was used.
func interact() -> bool:
	if lift_at_hand():
		take_lift()
		return true
	if villa_garage_at_hand():
		mode.open_garage(garage_id(VillaEnPierreCoteaux.ID))
		return true
	if exit_at_hand():
		leave()
		return true
	var p := door_at_hand()
	if p.is_empty():
		return false
	open_panel(p["id"])
	return true


## Whether the player, in their own villa on foot, stands by its garage's terminal.
func villa_garage_at_hand() -> bool:
	if not has_garage(VillaEnPierreCoteaux.ID) or mode.game.driving or mode.game.flying:
		return false
	var g: Dictionary = mode.garages.get_garage(garage_id(VillaEnPierreCoteaux.ID)) if mode.garages else {}
	if g.is_empty():
		return false
	var t: Vector3 = g["terminal"]
	var here := _player_pos()
	return Vector2(here.x - t.x, here.z - t.z).length() < 1.6 and absf(here.y - t.y) < 1.5


## The line over the bottom of the screen ("" none).
func prompt() -> String:
	var k := Settings.key_text("interact")
	if lift_at_hand():
		return "%s  Garage lift: leave by car" % k
	if villa_garage_at_hand():
		return "%s  Your garage: get a vehicle out" % k
	if exit_at_hand():
		return "%s  Leave the flat" % k
	var p := door_at_hand()
	if p.is_empty():
		return ""
	if is_owned(p["id"]):
		return "%s  %s · your home%s" % [k, p["short"], ": the gate opens for you" if p["site"] == "villa" else ": go in"]
	var guests := visits(p["id"]).size()
	return "%s  %s for sale · %s%s" % [k, p["short"], Economy.money(int(p["price"])),
			" · %d open to visits" % guests if guests > 0 else ""]


## The owners (other than the local player) whose flat at property `id` is open to visitors now.
func visits(id: String) -> Array:
	var out := []
	for key: String in open:
		var parts := key.split("|")
		if parts[0] == id and parts[1] != my_name():
			out.append(parts[1])
	out.sort()
	return out


## Whether the local player's flat at property `id` is open to visitors.
func door_open(id: String) -> bool:
	return open.has(instance(id, my_name()))


func open_panel(id: String) -> void:
	var p := get_property(id)
	if p.is_empty() or _panel == null:
		return
	if not _panel.visible:
		_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_panel(p)
	mode.game.update_controls()


func _show_panel(p: Dictionary) -> void:
	_panel.open(p, is_owned(p["id"]), has_garage(p["id"]), Settings.key_text("interact"), visits(p["id"]),
			door_open(p["id"]))


func ui_open() -> bool:
	return _panel != null and _panel.visible


func close_panel() -> void:
	if not ui_open():
		return
	_panel.close()
	Input.mouse_mode = _mouse
	mode.game.update_controls()


## Buys property `id` (solo: the test wallet), `garage` with its garage option; for a property already owned, adds
## the garage option.
func buy(id: String, garage := false) -> void:
	var p := get_property(id)
	if p.is_empty() or has_garage(id) or (is_owned(id) and not garage):
		return
	if mode.game.net.active:
		_panel.set_status("Homes can be bought in the offline test for now: online, they come with the next update.")
		return
	if p["site"] == "villa":
		garage = true                       # (its garage comes with it)
	var price := int(p["garage_price"]) if is_owned(id) else int(p["price"]) + (int(p["garage_price"]) if garage else 0)
	if mode.test_money < price:
		_panel.set_status("Not enough money: %s needed, you have %s." % [Economy.money(price),
				Economy.money(mode.test_money)])
		return
	mode.test_money -= price
	mode.game.economy.balance = mode.test_money
	mode.game.economy.wallet_changed.emit()
	var added := is_owned(id)
	owned[id] = {"garage": garage}
	_update_sign(id)
	_show_panel(p)
	if p["site"] == "villa":
		_panel.set_status("Félicitations! %s is yours (−%s): its gate opens for you, your vehicles come out in its garage." %
				[p["name"], Economy.money(price)])
	elif added:
		_panel.set_status("The garage is yours (−%s): the lift in your hall takes you to your car." % Economy.money(price))
	else:
		_panel.set_status("Félicitations! The %s is yours (−%s).%s" % [str(p["short"]).to_lower(), Economy.money(price),
				" Its lift takes you to your car." if garage else " Your car waits at the residents' car park."])


## Opens (`on`) the local player's flat at property `id` to visitors, or locks it.
func set_door(id: String, on: bool) -> void:
	if is_owned(id):
		mode.to_host(self, "_h_door", [id, on])


## Into property `id`: the local player's own flat (`owner` ""; they must own it), or `owner`'s, open to visitors.
## The host lets them in (_c_enter: the interior built where it is, the player in its hall). Whether they are in now
## (solo: at once; online: when the host answers).
func enter(id: String, owner := "") -> bool:
	var p := get_property(id)
	if owner == "":
		owner = my_name()
		if not is_owned(id):
			return false
	if p.is_empty():
		return false
	close_panel()
	mode.to_host(self, "_h_enter", [id, owner])
	return inside == id and inside_owner == owner


## The host let us into `owner`'s flat at property `id` (`garage`: theirs has the lift).
func _go_in(id: String, owner: String, garage: bool) -> void:
	var p := get_property(id)
	if p.is_empty():
		return
	if p["site"] == "villa":
		_free_interior()
		inside = id
		inside_owner = owner
		mode.game.toast("Welcome home: the gate opens" if owner == my_name() else "%s lets you in: the gate opens" % owner)
		return
	_free_interior()
	interior = StudioBuilder.new().build(p["windows"], garage)
	interior.name = "Interior_" + id
	interior.transform = p["frame"]
	add_child(interior)
	inside = id
	inside_owner = owner
	_daylight()
	var spawn: Array = interior.get_meta("spawn")
	var pos: Vector3 = interior.transform * (spawn[0] as Vector3)
	var facing: Vector3 = interior.transform.basis * (spawn[1] as Vector3)
	_off_everything()
	mode.game.player.teleport(pos + Vector3(0, 0.05, 0), atan2(-facing.x, -facing.z))
	mode.game.toast("Welcome home" if owner == my_name() else "Welcome to %s's flat" % owner)


## Out of the flat, at its building's entrance.
func leave() -> void:
	var p := get_property(inside)
	_drop_interior()
	if not p.is_empty():
		_to_entrance(p)


## E by the flat's lift: its garage's panel (online_mode.gd open_garage); the vehicle picked comes out at the
## residents' car park and the player drives it off (_on_answered).
func take_lift() -> void:
	if inside == "" or inside_owner != my_name() or not has_garage(inside):
		return
	_lift = true
	mode.open_garage(garage_id(inside))


## The host's answer to a garage request: from the lift, the vehicle is out: wait for it and take the wheel.
func _on_answered(ok: bool, _text: String) -> void:
	if _lift and ok and inside != "":
		_drive_t = 8.0
	_lift = false


func _drive_off(car: Car) -> void:
	_drop_interior()
	var g: Node = mode.game
	g.player.set_carrier(null)
	var p := car.to_global(car.extents_center + Vector3(car.half_extents.x + 1.0, 0.0, 0.0))
	p.y = Marks.ground(p.x, -p.z) + 0.1
	g.player.teleport(p)
	if g.net.active:
		g.net.request_drive(car)            # game.drive_granted seats us
	else:
		g.enter_car(car)
	g.toast("Down the lift: your %s, ready to go" % Car.common_name(car.model_name))


## Puts the player at property `id`'s entrance, facing its door (the in-game menu's test trip).
func go_to(id: String) -> void:
	var p := get_property(id)
	if p.is_empty():
		return
	_drop_interior()
	_off_everything()
	_to_entrance(p)


func _to_entrance(p: Dictionary) -> void:
	var s: Vector2 = p["stand2"]
	var face: Vector3 = -(p["out"] as Vector3)
	mode.game.player.set_carrier(null)
	mode.game.player.teleport(Vector3(s.x, Marks.ground(s.x, s.y) + 0.1, -s.y), atan2(-face.x, -face.z))


func _off_everything() -> void:
	var g: Node = mode.game
	if g.driving:
		g.exit_car()
	if g.riding:
		g.leave_ride()
	if g.flying:
		g.set_flying(false)
	g.player.set_carrier(null)


## Out of the flat (the host told: the others stop seeing us there).
func _drop_interior() -> void:
	var was := inside
	_free_interior()
	if was != "":
		mode.to_host(self, "_h_leave", [])


func _free_interior() -> void:
	if interior and is_instance_valid(interior):
		interior.queue_free()
	interior = null
	inside = ""
	inside_owner = ""


## The windows' daylight, by day only.
func _daylight() -> void:
	if interior == null:
		return
	var day := interior.get_node_or_null("Daylight") as Node3D
	if day:
		day.visible = not (mode.game.night != null and mode.game.night.on)


func _process(delta: float) -> void:
	if mode == null or mode.game.mode == "server":
		return
	_hide_others()
	if _drive_t > 0.0:
		_drive_t -= delta
		var car: Car = mode.car_of(mode.mine)
		if car and inside != "":
			_drive_t = 0.0
			_drive_off(car)
			return
	_villa_process(delta)
	if inside == "" or interior == null:
		return
	# taken out some other way (a garage, a respawn, the fly camera): the interior goes
	var local: Vector3 = interior.transform.affine_inverse() * _player_pos()
	var box: AABB = interior.get_meta("bounds")
	if mode.game.flying or not box.has_point(local):
		_drop_interior()
		return
	_daylight()


## The villa: its owners let in as they come to its gate (or are in its grounds); out once they have left them.
func _villa_process(delta: float) -> void:
	var v: Node = _villa()
	if v == null or get_villa().is_empty():
		return
	var me: Node3D = mode.game.driving if mode.game.driving else mode.game.player
	var at: Vector3 = me.global_position
	var near_gate := at.distance_to(v.gate_point()) < VILLA_REACH
	if inside == VillaEnPierreCoteaux.ID:
		if not v.in_grounds(at) and at.distance_to(v.gate_point()) > VILLA_OUT:
			_drop_interior()
		return
	_villa_ask_t -= delta
	if is_owned(VillaEnPierreCoteaux.ID) and inside == "" and _villa_ask_t <= 0.0 and (near_gate or v.in_grounds(at)) and not mode.game.flying:
		_villa_ask_t = 2.0
		mode.to_host(self, "_h_enter", [VillaEnPierreCoteaux.ID, my_name()])


## Shows only the players in the same flat as us (or, out of every flat, those out too): net.gd hidden_peers.
func _hide_others() -> void:
	var net: Node = mode.game.net
	if not net.active:
		return
	var mine := instance(inside, inside_owner) if inside != "" else ""
	var hidden := {}
	for peer: int in net.players:
		if peer != mode.me() and str(where.get(peer, "")) != mine:
			hidden[peer] = true
	net.hidden_peers = hidden


## The maps' badges: each property's entrance (the residents' car park is with the garages).
func map_places() -> Array:
	var out := []
	for p: Dictionary in list:
		if p["site"] != "villa":
			out.append([p["name"], "home", p["door2"]])
	return out


# ---------------------------------------------------------------- host

## The owners PLATEAU_ONLINE_HOMES gives ("name=property[+garage];..."): until step 2's accounts server keeps them.
func _read_homes() -> void:
	for entry in OS.get_environment("PLATEAU_ONLINE_HOMES").split(";", false):
		var kv := entry.split("=")
		if kv.size() != 2:
			continue
		var name := kv[0].strip_edges()
		for item in kv[1].split(",", false):
			var id := item.strip_edges().trim_suffix("+garage")
			if not get_property(id).is_empty():
				if not homes.has(name):
					homes[name] = {}
				homes[name][id] = {"garage": item.strip_edges().ends_with("+garage")}


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else mode.me()


func _name_of(peer: int) -> String:
	if not mode.game.net.active:
		return my_name()
	return str(_names.get(peer, mode.account(peer).get("username", "")))


## Host: tells everyone (and ourselves) where each player is and which doors are open.
func _share() -> void:
	mode.send_all(self, "_c_state", [where, open])


## Host: a player was let in: where everyone is.
func player_registered(peer: int) -> void:
	if mode.hosting and mode.game.net.active:
		mode.send_to(peer, self, "_c_state", [where, open])


## Host: a player's login was checked: what they own.
func player_logged_in(peer: int) -> void:
	var acc: Dictionary = mode.account(peer)
	if acc.is_empty():
		return
	_names[peer] = str(acc["username"])
	mode.send_to(peer, self, "_c_homes", [homes_of(str(acc["username"]))])


## Host: player `peer` left: out of every flat, their door locked.
func player_left(peer: int) -> void:
	var name := str(_names.get(peer, ""))
	_names.erase(peer)
	where.erase(peer)
	if name != "":
		for key: String in open.keys():
			if key.ends_with("|" + name):
				open.erase(key)
	_share()


@rpc("any_peer", "call_remote", "reliable")
func _h_enter(id: String, owner: String) -> void:
	if not mode.hosting:
		return
	var peer := _sender()
	var key := instance(id, owner)
	var homes_there := homes_of(owner)
	var why := ""
	if get_property(id).is_empty() or not homes_there.has(id):
		why = "No such flat."
	elif owner != _name_of(peer) and not open.has(key):
		why = "%s's door is locked." % owner
	if why != "":
		mode.send_to(peer, self, "_c_refused", [why])
		return
	where[peer] = key
	_share()
	mode.send_to(peer, self, "_c_enter", [id, owner, bool(homes_there[id].get("garage", false))])


@rpc("any_peer", "call_remote", "reliable")
func _h_leave() -> void:
	if not mode.hosting:
		return
	if where.erase(_sender()):
		_share()


@rpc("any_peer", "call_remote", "reliable")
func _h_door(id: String, on: bool) -> void:
	if not mode.hosting:
		return
	var peer := _sender()
	var name := _name_of(peer)
	if not homes_of(name).has(id):
		return
	if on:
		open[instance(id, name)] = true
	else:
		open.erase(instance(id, name))
	_share()
	if not mode.game.net.active:
		_c_state(where, open)                # solo: the panel shows it


@rpc("authority", "call_remote", "reliable")
func _c_enter(id: String, owner: String, garage: bool) -> void:
	_go_in(id, owner, garage)


@rpc("authority", "call_remote", "reliable")
func _c_refused(text: String) -> void:
	if ui_open():
		_panel.set_status(text)
	else:
		mode.game.toast(text)


@rpc("authority", "call_remote", "reliable")
func _c_state(now_where: Dictionary, now_open: Dictionary) -> void:
	where = now_where
	open = now_open
	if ui_open():
		var p := get_property(_panel.property_id)
		if not p.is_empty():
			var status: String = _panel.status_text()
			_show_panel(p)
			_panel.set_status(status)


@rpc("authority", "call_remote", "reliable")
func _c_homes(mine: Dictionary) -> void:
	owned = mine
	for p: Dictionary in list:
		_update_sign(p["id"])
