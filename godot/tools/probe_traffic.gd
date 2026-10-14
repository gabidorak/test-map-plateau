extends SceneTree
## Long headless run of the bot traffic (scripts/traffic.gd), the lights on the simulated time. Every minute: the buses
## on each direction of each line and the departures so far, the cars driving / stowed and their mean speed. Each bot
## standing still 20 s with somewhere to go is logged with what holds it (the vehicle in its way: model, heading).
## godot --headless --fixed-fps 60 --path godot --script res://tools/probe_traffic.gd -- [minutes] [physics] [cars=n]
## `physics`: the bots never glide (as if a player were everywhere).

var _main: Node
var _minutes := 20.0
var _physics := false


func _initialize() -> void:
	OS.set_environment("PLATEAU_BUSES", "1")
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.is_valid_float():
			_minutes = float(a)
		elif a.begins_with("cars="):
			OS.set_environment("PLATEAU_CARS", a.trim_prefix("cars="))
	_physics = args.has("physics")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _name(b: Object) -> String:
	return "%s#%d" % [b.line["ref"], _main.traffic.bots.find(b)]


func _run() -> void:
	while _main.traffic.bots.is_empty():
		await physics_frame
	var traffic: Node = _main.traffic
	var net: Node = _main.net
	var t := 0.0
	var dt := 1.0 / 60.0
	var still := {}                 # bot -> s stood still with somewhere to go
	var runs := {}                  # route id -> times a bus or car set off on it (from stowed)
	var was_idle := {}
	var worst := 0.0
	var t0: float = net.clock()
	var real0 := Time.get_ticks_msec()
	var ignores := 0
	var ignored := {}
	var was_stowed := {}
	var frame_ms := 0.0
	var frames := 0
	while t < _minutes * 60.0:
		await physics_frame
		t += dt
		net.clock_shift = t0 + t - (net.clock() - net.clock_shift)
		frame_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		frames += 1
		for b: Object in traffic.bots:
			if _physics:
				b.may_glide = false
			var rid: String = b.line["routes"][b.route_index]
			if was_idle.get(b, true) and not b.idle:
				runs[rid] = runs.get(rid, 0) + 1
			was_idle[b] = b.idle
			if b._ignored.size() > ignored.get(b, 0):
				ignores += 1
				print("%7.1f s  %s at (%.0f, %.0f) drives past a %s (deadlock)" % [t, _name(b), b.car.global_position.x,
						-b.car.global_position.z, b.obstacle_car.model_name if b.obstacle_car else "?"])
			ignored[b] = b._ignored.size()
			if b.idle and not was_stowed.get(b, true) and b._blocked_t > b.GIVE_UP:
				print("%7.1f s  %s gave up at (%.0f, %.0f)" % [t, _name(b), b.car.global_position.x, -b.car.global_position.z])
			was_stowed[b] = b.idle
			var v: float = b._speed if b.gliding else b.car.speed()
			if b.state == b.DRIVE and absf(v) < 0.3:
				var before: float = still.get(b, 0.0)
				still[b] = before + dt
				worst = maxf(worst, still[b])
				if floori(still[b] / 20.0) > floori(before / 20.0):
					var why: String = b.reason
					var o: Node3D = b.obstacle_car
					if why == "vehicle ahead" and o != null:
						why += " (%s%s, heading %.2f, %s)" % [o.model_name, " bot" if o.is_bot() else "",
								o.global_basis.z.dot(b.car.global_basis.z), "gliding" if o.pilot and o.pilot.gliding else "physics"]
					print("%7.1f s  %s still %.0f s at (%.0f, %.0f): %s, glide %s" % [t, _name(b), still[b],
							b.car.global_position.x, -b.car.global_position.z, why, b.gliding])
			else:
				still[b] = 0.0
		if floori(t / 60.0) > floori((t - dt) / 60.0):
			var per := {}
			var cars := [0, 0, 0.0]
			for b: Object in traffic.bots:
				if b.line["ref"] == "car":
					if b.idle:
						cars[1] += 1
					else:
						cars[0] += 1
						cars[2] += b._speed if b.gliding else b.car.speed()
				elif not b.idle:
					var rid: String = b.line["routes"][b.route_index]
					per[rid] = per.get(rid, 0) + 1
			print("%7.1f s  buses %s; cars %d driving (mean %.1f m/s), %d stowed; %d bots; %.0f s real, physics %.2f ms/tick" % [
					t, per, cars[0], cars[2] / maxf(cars[0], 1.0), cars[1], traffic.bots.size(),
					(Time.get_ticks_msec() - real0) / 1000.0, frame_ms / maxf(frames, 1)])
			frame_ms = 0.0
			frames = 0
			print("           departed so far: %s" % traffic.departed)

	var bus_runs := {}
	var car_runs := 0
	for rid: String in runs:
		if rid.begins_with("car:"):
			car_runs += runs[rid]
		else:
			bus_runs[rid] = runs[rid]
	print("bus runs per route: ", bus_runs)
	for b: Object in traffic.bots:
		if not b.idle and b.line["ref"] != "car" and b.line["ref"] != "4606":
			print("  %s %s state %d %s, front %.0f / %.0f m at (%.0f, %.0f), obstacle %s" % [_name(b),
					b.line["routes"][b.route_index], b.state, b.reason, b.s + b.nose, b._length, b.car.global_position.x,
					-b.car.global_position.z, b.obstacle_car.model_name if b.obstacle_car else "-"])
	print("car runs: %d; deadlocks settled: %d; longest still: %.0f s" % [car_runs, ignores, worst])
	quit(0)
