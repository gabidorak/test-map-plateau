extends SceneTree
## Headless check of LAN games (scripts/net.gd): run it twice at once, as the host and as a client on this machine:
##   godot --headless --path godot --script res://tools/test_lan.gd -- --host --name=Host
##   godot --headless --path godot --script res://tools/test_lan.gd -- --join=127.0.0.1 --name=Guest
## (tools/test_lan.sh does both, on port 7790). The host knocks a pole down before the client joins: the client sees
## it lying. The host jumps a few times: the client draws each takeoff soon after the host does (the wall clock is
## shared on this machine).
## The host parks a bus on Nouvelle Voie; the client sees it, steps into its aisle and stays standing inside while the
## host drives it ~5 s; the host sees the client's player inside the bus all along (the bus passing through it), at
## the same place in it as the bus speeds up (as drawn: after the frame's physics and processing). A
## tree the host bends bends on the client. The client then takes over one of the host's cars (it simulates it, the
## host shows a frozen copy with a driver), drives it a little and leaves; the host gets its car back. Last, on the
## host, a car rolled at a remote player's look-alike stops against it (and passes through with its collision off).
## Chat: the client opens it with Enter and says hello, the host answers; holding Tab shows both players and pings.
## Damage: rounds of the host's hit the client's taxi (net.gd hit_vehicle): it breaks on the client, which simulates it,
## and smokes black on both; then the host's fire truck water hoses it (net.gd water_vehicle): its fire goes out on the
## client, and on both it runs again.
## Passenger seat: after the bus, the client sits in the passenger seat of the host's fire truck (E from its right side);
## the host sees its look-alike seated there (the player itself hidden) while it drives the truck a little, the client
## rides along in it, gets out with Space, and the seat is empty again on the host.
## Exit code 1 on failure. No --fixed-fps: the states are stamped with the real clock.

const Layers = preload("res://scripts/physics_layers.gd")
const WorldQuery = preload("res://scripts/world_query.gd")
const Breakables = preload("res://scripts/breakables.gd")
const RemotePlayer = preload("res://scripts/remote_player.gd")
const MeshUtils = preload("res://scripts/builder/mesh_utils.gd")
const BUS_ROAD := Vector2(165.0, -215.0)    # the straight stretch of Nouvelle Voie test_cars.gd drives the bus on
const BUS_ROAD_DIR := Vector2(120.0, -59.0)
const JUMPS_FILE := "/tmp/test_lan_jumps.txt"    # the host's takeoff times, for the client
const JUMP_TIME := 12.0                     # s the host jumps for, every even second
const RISE := 0.05                          # m up from the ground: a takeoff
const MAX_JUMP_LAG := 0.08                  # s (~30 ms headless on a laptop; it was 120 with a fixed 100 ms delay)

var _main: Node
var _failures: PackedStringArray = []
var _hosting := false


## Calls `fn` each frame after every other node's _process: what is drawn.
class LateProbe extends Node:
	var fn: Callable

	func _init(f: Callable) -> void:
		fn = f
		process_priority = 1000

	func _process(_delta: float) -> void:
		fn.call()


func _initialize() -> void:
	_hosting = "--host" in OS.get_cmdline_user_args()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.debug_cars = _hosting             # the host's 4 cars at start; the bus comes on top
	root.add_child(_main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + ("[host] " if _hosting else "[client] ") + what)
	if not ok:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Waits until `cond` holds, at most `timeout` seconds; returns whether it held.
func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await physics_frame
	return true


func _press(code: Key) -> void:
	_key(code, true)
	_key(code, false)


## True when `chat` (chat.gd) shows `text` from `who`.
func _said(chat: Node, who: String, text: String) -> bool:
	return chat._lines.any(func(l: Array) -> bool: return l[0] == who and l[2] == text)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## The test bus: the 12 m bus nearest Nouvelle Voie (the host's cars at start include another one).
func _bus() -> Node:
	var best: Node = null
	for car: Node in _main.cars:
		if car.model_name == "bus-idfm" and (best == null or _off_road(car) < _off_road(best)):
			best = car
	return best


func _off_road(car: Node) -> float:
	return Vector2(car.global_position.x, -car.global_position.z).distance_to(BUS_ROAD)


## The same tree on both sides: the first one that bends.
func _test_tree() -> int:
	var trees: Node = _main.world_root.get_node_or_null("TreeCollision/Bendable")
	for k in trees.data.base.size():
		if Breakables.bends(trees.data, k):
			return k
	return -1


## The same prop on both sides: the breakable one nearest the spawn point.
func _test_prop() -> int:
	var props: Node = _main.world_root.get_node_or_null("PropCollision/Breakable")
	var spawn: Vector3 = MeshUtils.to_godot(_main.spawn_xy.x, _main.spawn_xy.y, 0.0)
	var best := -1
	var best_d := INF
	for k: int in props._owners_of_record:
		var o: Vector3 = (props.record_shapes(k)[0][1] as Transform3D).origin
		var d := Vector2(o.x - spawn.x, o.z - spawn.z).length()
		if d < best_d:
			best = k
			best_d = d
	return best


func _debris_of(k: int) -> Variant:
	for d: Dictionary in _main.breakables.debris:
		if d["record"] == k:
			return d
	return null


func _run() -> void:
	if _hosting:
		await _run_host()
	else:
		await _run_client()
	print("%d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)


func _run_host() -> void:
	var net: Node = _main.net
	_check(await _until(func() -> bool: return _main.mode == "host" and _main.cars.size() == 4, 60.0),
			"hosting, the 4 cars parked")
	var pole := _test_prop()
	_check(_main.breakables.break_prop(pole, Vector3(3.0, 0.0, 0.0)), "knocked down prop %d before the client joins" % pole)
	var bus: Node = _main.spawn_car_near_player("bus-idfm")
	var g := WorldQuery.ground_y(bus.get_world_3d(), BUS_ROAD.x, -BUS_ROAD.y, Layers.SOLID)
	bus.place(Transform3D(Basis(Vector3.UP, atan2(BUS_ROAD_DIR.x, -BUS_ROAD_DIR.y)), Vector3(BUS_ROAD.x, g + 0.3, -BUS_ROAD.y)))
	_check(bus.net_id != "", "the bus has a network id (%s)" % bus.net_id)
	_check(_main.spawn_car_near_player("bus-idfm-artic") != null, "an articulated bus parked too")
	var truck: Node = _main.spawn_car_near_player("fire-truck")
	_check(truck != null, "a fire truck parked too")
	_check(await _until(func() -> bool: return net.players.size() == 2, 90.0), "the client joined")
	await _jump_for_client()
	var guest: int = net.players.keys().filter(func(id: int) -> bool: return id != 1)[0]
	_check(await _until(func() -> bool: return _said(_main.chat, "Guest", "hello from the guest"), 30.0),
			"the client's chat message is here")
	net.say("hi guest")
	_check(net.ping(guest) >= 0 and net.ping(1) == 0, "pings known here (guest %d ms)" % net.ping(guest))
	_check(await _until(func() -> bool: return net.cars.size() == 8, 30.0), "the client's taxi is here (%d vehicles)" % net.cars.size())
	var taxi: Node = null
	for id: String in net.cars:
		if net.cars[id].model_name == "taxi":
			taxi = net.cars[id]
			_check(net.owner_of[id] == guest and net.cars[id].remote, "the client simulates its taxi")
	if taxi:
		for i in 2:
			net.hit_vehicle(taxi, 50.0)
		_check(not taxi.broken, "hits on the client's taxi do not count here")
		_check(await _until(func() -> bool: return taxi.broken and taxi.smoking_black(), 10.0),
				"the client's taxi breaks and smokes black here too (from its states)")
		net.water_vehicle(taxi, taxi, Vector3(0.0, -50.0, 0.0), taxi.global_position, 0.5)
		_check(taxi.broken, "water on the client's taxi does not put it out here")
		for i in 5:                         # 3 s of the jet in all, a batch every ~0.13 s
			await _frames(8)
			net.water_vehicle(taxi, taxi, Vector3(0.0, -50.0, 0.0), taxi.global_position, 0.5)
		_check(await _until(func() -> bool: return not taxi.broken and not taxi.smoking_black(), 10.0),
				"the host's water puts the client's taxi out (from its states)")
	_check(net.lan_label().contains(":%d" % net.port), "top right label: " + net.lan_label())
	var remote: Node3D = net._remotes[guest]
	_check(await _until(func() -> bool: return remote.visible and bus.carries(remote.global_position, 0.3), 40.0),
			"the client's player is shown in the bus aisle")
	await _frames(30)

	net.request_drive(bus)
	_check(_main.driving == bus, "the host drives the bus")
	var start: Vector3 = bus.global_position
	var inside := 0
	var frames := 0
	var ignored := 0
	# where the client's player is drawn in the bus: should not slip back as it speeds up
	var at_rest: Vector3 = bus.global_transform.affine_inverse() * remote.global_position
	var slip := [0.0, 0.0]                  # largest drift from at_rest (m), bus speed then (m/s)
	var probe := LateProbe.new(func() -> void:
		var d: float = (bus.global_transform.affine_inverse() * remote.global_position).distance_to(at_rest)
		if d > slip[0]:
			slip[0] = d
			slip[1] = absf(bus.speed()))
	root.add_child(probe)
	_key(KEY_W, true)
	_key(KEY_G, true)                       # a honk as it pulls away, for the client to hear
	var honked := false
	for i in 300:
		await physics_frame
		frames += 1
		honked = honked or bus.audio.horn
		if i == 60:
			_key(KEY_G, false)
		if i == 90 or i == 100:                 # ding-ding
			_key(KEY_B, true)
			_key(KEY_B, false)
		inside += int(remote.visible and bus.carries(remote.global_position, 0.4))
		ignored += int(remote.ignores(bus))
	_key(KEY_W, false)
	probe.queue_free()
	_check(honked and not bus.audio.horn, "G sounded the horn while held")
	_check(bus.bells == 2, "B rang the bell twice (%d)" % bus.bells)
	_check(slip[0] < 0.05, "they stay put in the bus as it speeds up (drifted %.2f m at most, at %.1f m/s)" % slip)
	_key(KEY_S, true)
	await _until(func() -> bool: return absf(bus.speed()) < 0.5, 10.0)
	_key(KEY_S, false)
	var moved: float = bus.global_position.distance_to(start)
	_check(moved > 15.0, "the bus drove %.0f m" % moved)
	_check(inside == frames, "the client's player is shown inside the moving bus (%d/%d frames)" % [inside, frames])
	_check(ignored == frames, "the bus does not collide with them (%d/%d frames)" % [ignored, frames])
	_main.exit_car()
	_check(net.driver_of[bus.net_id] == 0 and net.owner_of[bus.net_id] == 1, "out of the seat: nobody drives the bus")

	var k := _test_tree()
	_main.breakables.bend_tree(k, Vector3(3.0, 0.0, 0.0))
	net.broke("bend", k, Vector3(3.0, 0.0, 0.0))
	print("bent tree %d for the client" % k)

	# the client sits in the fire truck's passenger seat while we drive it a little
	var seated := func() -> bool: return truck._passenger.visible and not remote.visible
	_check(await _until(seated, 40.0), "the client sits in the fire truck's passenger seat (its look-alike there, the player hidden)")
	_check(truck._passenger_skin.albedo_color.is_equal_approx(net.player_color(guest)), "in the client's colour")
	net.request_drive(truck)
	_check(_main.driving == truck, "the host drives the fire truck")
	var t_start: Vector3 = truck.global_position
	var seated_frames := 0
	_key(KEY_W, true)
	for i in 70:
		await physics_frame
		seated_frames += int(seated.call())
	_key(KEY_W, false)
	_key(KEY_S, true)
	await _until(func() -> bool: return absf(truck.speed()) < 0.3, 10.0)
	_key(KEY_S, false)
	_check(seated_frames == 70 and truck.global_position.distance_to(t_start) > 2.0,
			"they stay seated as it drives %.1f m (%d/70 frames)" % [truck.global_position.distance_to(t_start), seated_frames])
	_main.exit_car()
	_check(await _until(func() -> bool: return not truck._passenger.visible and remote.visible, 30.0),
			"the client got out: the seat is empty, the player shown again")

	# the client takes one of our cars
	var taken := func() -> Node:
		for id: String in net.cars:
			if net.driver_of[id] == guest:
				return net.cars[id]
		return null
	_check(await _until(func() -> bool: return taken.call() != null, 40.0), "the client drives one of the host's cars")
	var car: Node = taken.call()
	if car:
		_check(car.remote and car.freeze, "the host shows it as a frozen copy")
		_check(car._driver_dummy == null or car._driver_dummy.visible, "with the client's driver in it")
		var p0: Vector3 = car.global_position
		await _until(func() -> bool: return car.global_position.distance_to(p0) > 2.0, 10.0)
		_check(car.global_position.distance_to(p0) > 2.0, "and it moves as the client drives it (%.1f m)" % car.global_position.distance_to(p0))
	_check(await _until(func() -> bool: return net.players.size() == 1, 40.0), "the client left")
	if car:
		_check(net.owner_of[car.net_id] == 1 and not car.remote, "its car is the host's again")
		await _check_run_into_player(car)


## Rolls `car` at 8 m/s at a remote player's look-alike standing on Nouvelle Voie (behind where the bus started):
## it stops against it, and passes through it with the collision off.
func _check_run_into_player(car: Node) -> void:
	var dummy := RemotePlayer.new()
	dummy.setup("Dummy", Color.RED)
	_main.add_child(dummy)
	var dir := Vector3(BUS_ROAD_DIR.x, 0.0, -BUS_ROAD_DIR.y).normalized()
	var road := Vector3(BUS_ROAD.x, 0.0, -BUS_ROAD.y)
	var at := road - dir * 14.0
	at.y = WorldQuery.ground_y(car.get_world_3d(), at.x, at.z, Layers.SOLID)
	for collide in [true, false]:
		dummy.show_at(Transform3D(Basis.IDENTITY, at), 0.0)
		dummy.update_collision(collide, null, _main.cars)
		var from := road - dir * 24.0
		from.y = WorldQuery.ground_y(car.get_world_3d(), from.x, from.z, Layers.SOLID) + 0.3
		car.place(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), from))
		await _frames(30)
		car.linear_velocity = car.global_basis.z * 8.0
		await _frames(120)
		# how far the car's front is past the look-alike's centre
		var past: float = car.to_local(at).z * -1.0 + car.half_extents.z + car.extents_center.z
		if collide:
			_check(past < 0.0, "a car rolled at a remote player stops against it (front %.1f m from them)" % -past)
		else:
			_check(past > 2.0, "and drives through with its collision off (%.1f m past)" % past)
	dummy.queue_free()


## Jumps at each even second of the wall clock for JUMP_TIME s, writing in JUMPS_FILE when each takeoff is drawn
## here: the client measures how much later it draws it (_watch_host_jumps; both run on this machine).
func _jump_for_client() -> void:
	var player: CharacterBody3D = _main.player
	var file := FileAccess.open(JUMPS_FILE, FileAccess.WRITE)
	var state := [player.global_position.y, false]   # ground height, rising
	var probe := LateProbe.new(func() -> void:
		var up: bool = player.global_position.y > state[0] + RISE
		if up and not state[1]:
			file.store_line("%.6f" % Time.get_unix_time_from_system())
			file.flush()
		elif not up and player.is_on_floor():
			state[0] = player.global_position.y
		state[1] = up)
	root.add_child(probe)
	player.scripted_input = Vector2.ZERO
	var end := Time.get_unix_time_from_system() + JUMP_TIME
	var last := 0
	while Time.get_unix_time_from_system() < end:
		await physics_frame
		var sec := int(Time.get_unix_time_from_system())
		player.scripted_jump = sec % 2 == 0 and sec != last
		if player.scripted_jump:
			last = sec
	player.scripted_jump = false
	player.scripted_input = null
	await _frames(60)
	probe.queue_free()
	file.close()


## Watches the host jump (_jump_for_client): how long after it is drawn there each takeoff is drawn here.
func _watch_host_jumps() -> void:
	var net: Node = _main.net
	var host: Node3D = net._remotes[1]
	_check(await _until(func() -> bool: return host.visible, 10.0), "the host's player is shown")
	var state := [host.global_position.y, false]     # ground height, rising
	var rises: Array[float] = []
	var probe := LateProbe.new(func() -> void:
		var y := host.global_position.y
		state[0] = minf(state[0], y)
		var up: bool = y > state[0] + RISE
		if up and not state[1]:
			rises.append(Time.get_unix_time_from_system())
		state[1] = up)
	root.add_child(probe)
	await _until(func() -> bool: return false, JUMP_TIME - 3.0)
	probe.queue_free()
	var takeoffs: Array[float] = []
	for line in FileAccess.get_file_as_string(JUMPS_FILE).split("\n", false):
		takeoffs.append(line.to_float())
	var lags: Array[float] = []
	for r in rises:
		var before := takeoffs.filter(func(t: float) -> bool: return t <= r and r - t < 1.0)
		if not before.is_empty():
			lags.append(r - before.max())
	print("jump lags (ms): ", lags.map(func(l: float) -> int: return roundi(l * 1000.0)))
	lags.sort()
	var median := lags[lags.size() / 2] if not lags.is_empty() else INF
	_check(lags.size() >= 3 and median < MAX_JUMP_LAG, "the host's jumps are drawn here %.0f ms after there (median of %d)"
			% [median * 1000.0, lags.size()])


func _run_client() -> void:
	var net: Node = _main.net
	_check(await _until(func() -> bool: return _main.mode == "client", 90.0), "joined the host")
	_check(net.players.size() == 2, "2 players known")
	var pole := _test_prop()
	var d: Variant = _debris_of(pole)
	_check(d != null, "the prop %d the host knocked down before we joined is down here too" % pole)
	if d:
		var up: Vector3 = (d["body"] as Node3D).global_basis.y
		_check(up.dot(Vector3.UP) < 0.7, "lying where it fell there (tilted %.0f°)" % rad_to_deg(up.angle_to(Vector3.UP)))
	var chat: Node = _main.chat
	_press(KEY_ENTER)
	await _frames(2)
	_check(chat.is_open() and not _main.player.active, "Enter opens the chat, the player stands still")
	chat._line.text = "hello from the guest"
	chat._line.text_submitted.emit(chat._line.text)
	await _frames(2)
	_check(not chat.is_open() and _main.player.active, "Enter sends and closes it")
	_check(await _until(func() -> bool: return _said(chat, "Guest", "hello from the guest"), 10.0),
			"our message comes back through the host")
	_check(await _until(func() -> bool: return net.ping(1) >= 0 and net.ping(net.me()) >= 0, 10.0),
			"pings known here (host %d ms, us %d ms)" % [net.ping(1), net.ping(net.me())])
	_key(KEY_TAB, true)
	await process_frame                     # the list follows Tab in game.gd _process: physics frames may come first
	await process_frame
	var list: Control = _main._player_list
	_check(list.visible and list._grid.get_child_count() == 6, "Tab held shows the 2 players and their ping")
	_key(KEY_TAB, false)
	await process_frame
	await process_frame
	_check(not list.visible, "and hides them once released")
	_check(await _until(func() -> bool: return _main.cars.size() == 7 and _off_road(_bus()) < 3.0, 30.0),
			"the host's 7 vehicles are here (%d), its bus on Nouvelle Voie" % _main.cars.size())
	for c: Node in _main.cars:
		if c.model_name == "bus-idfm-artic":
			_check(c.remote and c.freeze and c.trailer.freeze, "the articulated bus is a frozen copy, both sections")
			_check(c.trailer.global_position.distance_to(c.to_global(c.rear_offset)) < 0.5, "its rear section is behind it")
	_check(_main.spawn_car_near_player("taxi") != null and _main.cars[-1].net_id.begins_with("%d:" % net.me()),
			"parked a taxi of ours")
	await _watch_host_jumps()
	_check(await _until(func() -> bool: return _said(chat, "Host", "hi guest"), 30.0), "the host's answer is here")
	var taxi: Node = _main.cars.filter(func(c: Node) -> bool: return c.model_name == "taxi")[0]
	_check(await _until(func() -> bool: return taxi.broken and taxi.smoking_black(), 10.0),
			"the host's hits broke our taxi here, which simulates it")
	_check(await _until(func() -> bool: return not taxi.broken and not taxi.smoking_black(), 10.0),
			"the host's water put our taxi's fire out here")
	var bus: Node = _bus()
	_check(bus.remote and bus.freeze, "the bus is a frozen copy")
	await _frames(30)
	# step into the aisle, behind the driver
	var player: CharacterBody3D = _main.player
	player.teleport(bus.to_global(bus.driver_exit + Vector3(0.0, 0.05, -2.5)))
	_check(await _until(func() -> bool: return player.carrier == bus, 5.0), "standing in the bus")
	var start: Vector3 = bus.global_position
	var inside := 0
	var frames := 0
	# while the host drives it, until it has gone some way and stopped again
	var k := _test_tree()
	var tree_bent := false                  # it springs back up within a couple of seconds
	var honk := 0                           # frames its horn sounded here
	var bells0: int = bus.bells
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await physics_frame
		frames += 1
		honk += int(bus.audio.horn)
		inside += int(bus.carries(player.global_position, 0.1) and player.carrier == bus)
		tree_bent = tree_bent or _main.breakables.bent.has(k)
		if bus.global_position.distance_to(start) > 15.0 and absf(bus.speed()) < 0.3 and net.driver_of[bus.net_id] == 0:
			break
	var moved: float = bus.global_position.distance_to(start)
	_check(moved > 15.0, "the host's bus drove %.0f m here" % moved)
	_check(honk > 30 and honk < 90 and not bus.audio.horn, "its horn sounded here as long as the host held it (%d frames)" % honk)
	_check(bus.bells - bells0 == 2, "its bell rang here as often as the host rang it (%d)" % (bus.bells - bells0))
	_check(inside == frames, "stood inside it all the way (%d/%d frames, fell %.1f m below its floor)" % [inside, frames,
			maxf(0.0, bus.global_position.y - player.global_position.y)])
	t0 = Time.get_ticks_msec()
	while not tree_bent and Time.get_ticks_msec() - t0 < 10000:
		await physics_frame
		tree_bent = _main.breakables.bent.has(k)
	_check(tree_bent, "the tree the host bent bends here")

	# ride in the passenger seat of the host's fire truck while the host drives it
	var truck: Node = _main.cars.filter(func(c: Node) -> bool: return c.model_name == "fire-truck")[0]
	player.teleport(truck.to_global(Vector3(-truck.half_extents.x - 1.0, 0.3, 1.0)))
	await _frames(10)
	_press(KEY_E)
	await _frames(2)
	_check(_main.riding == truck and truck.riding and not player.visible, "E from its right side: in the fire truck's passenger seat")
	var r_start: Vector3 = truck.global_position
	var with_it := true                     # our view stays in the truck
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await physics_frame
		var cam := root.get_camera_3d()
		with_it = with_it and (cam == truck.camera or cam == truck._cab_camera)
		if truck.global_position.distance_to(r_start) > 2.0 and absf(truck.speed()) < 0.3 \
				and net.driver_of[truck.net_id] == 0:
			break
	_check(truck.global_position.distance_to(r_start) > 2.0 and with_it,
			"rode %.1f m in it as the host drove, seen from the truck" % truck.global_position.distance_to(r_start))
	_press(KEY_SPACE)
	await _frames(3)
	_check(_main.riding == null and player.visible and truck.to_local(player.global_position).x < 0.0,
			"Space: out on its right side")
	await _frames(60)

	# out of the bus, then take one of the host's cars
	_main.spawn_at(Vector2(-34, 55.0))
	await _frames(10)
	var car: Node = null
	for c: Node in _main.cars:
		if c.model_name in ["kaykit-hatchback", "sedan"] and net.owner_of[c.net_id] == 1:
			car = c
	net.request_drive(car)
	_check(await _until(func() -> bool: return _main.driving == car, 5.0), "the host let us drive its %s" % car.model_name)
	_check(not car.remote and not car.freeze, "we simulate it now")
	var p0: Vector3 = car.global_position
	_key(KEY_W, true)
	await _frames(90)
	_key(KEY_W, false)
	_check(car.global_position.distance_to(p0) > 2.0, "it drives (%.1f m)" % car.global_position.distance_to(p0))
	await _frames(60)
	net.leave()
	await _frames(30)
