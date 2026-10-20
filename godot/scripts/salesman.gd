extends Node3D
## The car salesman of a showroom (scripts/dealership.gd): a toy figure in a navy suit with a gold tie, who waits by the
## reception, greets the local player coming in, walks after them around the showroom (A* on a 0.5 m grid of the floor,
## around the podiums, columns and furniture) and talks in a speech bubble: the car on the podium they stand by (its
## name, price and pitch), small talk, a word when they take a display car for a test drive, and a cry when they drive
## off with it. Back to his post once they have left. Nothing collides with him. Built at runtime, local to each peer.

const KEEP := 2.2                           # m he stays from the player on foot
const KEEP_DRIVING := 5.5                   # m from a car the player drives in the showroom
const WALK := 1.5                           # m/s
const HURRY := 3.6                          # m/s, when the player is far
const LINE_GAP := 2.5                       # s of silence between lines
const IDLE_EVERY := 11.0                    # s between small-talk lines
const GRID := 0.5                           # m, path grid cell
const TALK_RANGE := 9.0                     # m: he greets and pitches once this close to the player
const NAME := "Jean-Claude"
const SKIN := Color(0.95, 0.76, 0.62)
const SUIT := Color(0.07, 0.08, 0.15)
const GOLD := Color(1.0, 0.78, 0.36)
const HAIR := Color(0.1, 0.07, 0.05)

const GREET := [
	"Bonjour, bonjour! Welcome to %s. I am %s, at your service.",
	"Ah, a connoisseur! Welcome to %s. %s, for anything you need.",
	"Welcome back to %s! %s here. Champagne? The bar is in the lounge.",
]
const SMALL_TALK := [
	"Take your time, everything you see is for sale. Except me.",
	"Every car comes with a full tank and its own red carpet.",
	"Our finance desk can arrange anything. Anything.",
	"The Mercedes on the turntable? Not for sale... unless you insist.",
	"Mind the golden R8. Solid gold. Well... plated.",
	"Test drives are free. The keys are in every car, just hop in.",
	"This building used to be a school, you know. Now it teaches people about luxury.",
	"Sit in one, you will see. The leather alone is worth the price.",
]
const TEST_DRIVE := [
	"Excellent choice! The keys are in it. Gently on the marble, please.",
	"A test drive? Of course! The big doors are wide open.",
	"Feel that? That is quality. Bring it back in one piece!",
]
const DRIVE_OFF := [
	"Wait! The paperwork!",
	"Monsieur?! That is not how a test drive works!",
	"I will put it on your account then... Bonne route!",
]
const NOT_THERE := "That one is out on a test drive. It will be back... I hope."

var showroom: Node3D                        # dealership.gd
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _bubble: Label3D
var _astar: AStarGrid2D
var _grid_origin := Vector2.ZERO            # Godot (x, z) of cell (0, 0)'s corner
var _path := PackedVector2Array()
var _path_t := 0.0
var _path_goal := Vector2i(-1, -1)
var _speed := 0.0
var _phase := 0.0
var _t := 0.0
var _line_t := 0.0                          # s the current line stays up
var _quiet_t := 0.0                         # s until the next line may come
var _idle_t := 4.0
var _away_t := 1e6                          # s since the player was last in the showroom
var _greet := 0
var _greet_due := false                     # the player came in: greet them once near
var _small := 0
var _pitched := -1                          # the spot last pitched
var _drove := false                         # the player drove a car in the showroom
var _talking := false


func _ready() -> void:
	_build_body()
	_build_grid()
	_small = randi() % SMALL_TALK.size()


func _process(delta: float) -> void:
	_t += delta
	_line_t -= delta
	_quiet_t -= delta
	if _line_t <= 0.0 and _bubble.visible:
		_bubble.visible = false
		_quiet_t = LINE_GAP
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(global_position) > 250.0:
		return
	var game: Node = showroom.game
	var target := Vector3.INF
	var keep := KEEP
	if game != null and game.mode in ["solo", "host", "client"] and not game.flying:
		var driving: Node3D = game.driving
		var p: Vector3 = driving.global_position if driving else (game.riding.global_position if game.riding \
				else game.player.global_position)
		if showroom.is_inside(p):
			if _away_t > 40.0:
				_greet_due = true
				_pitched = -1
			_away_t = 0.0
			if _greet_due and global_position.distance_to(p) < TALK_RANGE + 6.0:
				_greet_due = false
				_say(GREET[_greet % GREET.size()] % [showroom.dealer, NAME], true)
				_greet += 1
			target = p
			keep = KEEP_DRIVING if driving else KEEP
			if driving and not _drove:
				_drove = true
				_say(TEST_DRIVE[randi() % TEST_DRIVE.size()], true)
			elif not driving:
				_drove = false
				if not _greet_due and global_position.distance_to(p) < TALK_RANGE:
					_chat(p, delta)
		else:
			if _away_t < 10.0 and _drove and driving and p.distance_to(global_position) < 80.0:
				_say(DRIVE_OFF[randi() % DRIVE_OFF.size()], true)
				_drove = false
			_away_t += delta
			if _away_t < 6.0:
				target = global_position                # waits by the door a little
	if target == Vector3.INF:
		target = showroom.salesman_xf.origin
		keep = 0.2
	_walk(delta, target, keep)
	_animate(delta, target)


## Says the car spot the player stands by, or a little small talk now and then.
func _chat(p: Vector3, delta: float) -> void:
	var k: int = showroom.spot_near(p, 5.2)
	if k >= 0 and k != _pitched:
		_pitched = k
		var c: Dictionary = showroom.cars[k]
		if showroom.car_on_spot(k) == null:
			_say(NOT_THERE, true)
		else:
			_say("The %s, %s. %s" % [c["label"], c["price"], c["pitch"]], true)
		_idle_t = IDLE_EVERY
		return
	if k < 0:
		_pitched = -1
	_idle_t -= delta
	if _idle_t <= 0.0:
		_idle_t = IDLE_EVERY
		_say(SMALL_TALK[_small % SMALL_TALK.size()])
		_small += 1


## Shows `text` in the bubble (`urgent`: even over the line he is saying).
func _say(text: String, urgent := false) -> void:
	if not urgent and (_bubble.visible or _quiet_t > 0.0):
		return
	_bubble.text = text
	_bubble.visible = true
	_line_t = clampf(text.length() * 0.065, 3.0, 9.0)


# ---------------------------------------------------------------- walking

func _build_grid() -> void:
	var poly := PackedVector2Array()            # the outline in Godot (x, z), 0.35 m in
	for p: Vector2 in showroom.outline:
		poly.append(Vector2(p.x, -p.y))
	var shrunk := Geometry2D.offset_polygon(poly, -0.35)
	if not shrunk.is_empty():
		poly = shrunk[0]
		for s: PackedVector2Array in shrunk:
			if s.size() > poly.size():
				poly = s
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	_grid_origin = lo
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, ceili((hi.x - lo.x) / GRID) + 1, ceili((hi.y - lo.y) / GRID) + 1)
	_astar.cell_size = Vector2.ONE * GRID
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for i in _astar.region.size.x:
		for j in _astar.region.size.y:
			_astar.set_point_solid(Vector2i(i, j), not Geometry2D.is_point_in_polygon(_cell_centre(Vector2i(i, j)), poly))
	for o: Vector3 in showroom.obstacles:
		if o.z <= 0.0:
			continue
		var r := o.z + 0.3
		var a := _cell_of(Vector2(o.x - r, o.y - r))
		var b := _cell_of(Vector2(o.x + r, o.y + r))
		for i in range(maxi(a.x, 0), mini(b.x + 1, _astar.region.size.x)):
			for j in range(maxi(a.y, 0), mini(b.y + 1, _astar.region.size.y)):
				if _cell_centre(Vector2i(i, j)).distance_to(Vector2(o.x, o.y)) < r:
					_astar.set_point_solid(Vector2i(i, j))


func _cell_centre(c: Vector2i) -> Vector2:
	return _grid_origin + (Vector2(c) + Vector2(0.5, 0.5)) * GRID


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - _grid_origin.x) / GRID), floori((p.y - _grid_origin.y) / GRID))


## The free cell nearest to `p` (Godot x, z) within a few metres, or (-1, -1).
func _free_cell(p: Vector2) -> Vector2i:
	var c := _cell_of(p)
	for r in 12:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for i in range(c.x - r, c.x + r + 1):
			for j in range(c.y - r, c.y + r + 1):
				var k := Vector2i(i, j)
				if _astar.is_in_boundsv(k) and not _astar.is_point_solid(k):
					var d := _cell_centre(k).distance_to(p)
					if d < best_d:
						best_d = d
						best = k
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _walk(delta: float, target: Vector3, keep: float) -> void:
	var here := Vector2(global_position.x, global_position.z)
	var goal := Vector2(target.x, target.z)
	_speed = 0.0
	if here.distance_to(goal) <= keep:
		_path.clear()
		return
	_path_t -= delta
	var goal_cell := _free_cell(goal)
	if goal_cell.x < 0:
		return
	if _path.is_empty() or (_path_t <= 0.0 and goal_cell != _path_goal):
		_path_t = 0.5
		_path_goal = goal_cell
		var from := _free_cell(here)
		_path.clear()
		if from.x >= 0:
			for p in _astar.get_id_path(from, goal_cell):
				_path.append(_cell_centre(p))
			if not _path.is_empty():
				_path[_path.size() - 1] = goal if _astar.is_in_boundsv(_cell_of(goal)) and \
						not _astar.is_point_solid(_cell_of(goal)) else _path[_path.size() - 1]
	while _path.size() > 1 and here.distance_to(_path[0]) < 0.6:
		_path.remove_at(0)
	if _path.is_empty():
		return
	var speed := HURRY if here.distance_to(goal) > 10.0 else WALK
	var to := _path[0] - here
	var step := minf(speed * delta, to.length())
	if _path.size() == 1:
		step = minf(step, here.distance_to(goal) - keep)
	if step <= 0.0:
		return
	here += to.normalized() * step
	_speed = speed
	global_position = Vector3(here.x, showroom.floor_y, here.y)


# ---------------------------------------------------------------- body

func _animate(delta: float, target: Vector3) -> void:
	var face := target - global_position
	if _speed > 0.0 and not _path.is_empty():
		face = Vector3(_path[0].x - global_position.x, 0.0, _path[0].y - global_position.z)
	face.y = 0.0
	if face.length() > 0.05:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(face.x, face.z), minf(6.0 * delta, 1.0))
	var swing := clampf(_speed / WALK, 0.0, 1.6)
	_phase += delta * (2.0 + 2.5 * swing) if swing > 0.0 else 0.0
	var s := sin(_phase) * 0.45 * minf(swing, 1.0)
	_legs[0].rotation.x = s
	_legs[1].rotation.x = -s
	_arms[0].rotation.x = -s * 0.8
	_body.position.y = absf(cos(_phase)) * 0.03 * minf(swing, 1.0) + sin(_t * 1.7) * 0.004
	if _bubble.visible and swing == 0.0:
		# talking with his hands
		_arms[1].rotation.x = lerpf(_arms[1].rotation.x, -0.9 + sin(_t * 3.1) * 0.3, minf(8.0 * delta, 1.0))
		_arms[1].rotation.z = lerpf(_arms[1].rotation.z, -0.25 + sin(_t * 2.3) * 0.12, minf(8.0 * delta, 1.0))
	else:
		_arms[1].rotation.x = lerpf(_arms[1].rotation.x, s * 0.8, minf(10.0 * delta, 1.0))
		_arms[1].rotation.z = lerpf(_arms[1].rotation.z, 0.0, minf(10.0 * delta, 1.0))


func _mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale_ := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 4
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _cylinder(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Front +Z, his left +X, feet on y = 0, 1.85 m tall.
func _build_body() -> void:
	var skin := _mat(SKIN, 0.55)
	var suit := _mat(SUIT, 0.45)
	var shirt := _mat(Color(0.97, 0.97, 0.97), 0.5)
	var gold := _mat(GOLD, 0.2, 1.0)
	var black := _mat(Color(0.02, 0.02, 0.02), 0.15)
	var hair := _mat(HAIR, 0.35)
	_body = Node3D.new()
	add_child(_body)
	for side: float in [1.0, -1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.1, 0.95, 0.0)
		_body.add_child(hip)
		_part(hip, _cylinder(0.075, 0.095, 0.86), suit, Vector3(0.0, -0.45, 0.0))
		_part(hip, _box(Vector3(0.115, 0.07, 0.27)), black, Vector3(0.0, -0.9, 0.05))
		_legs.append(hip)
	# jacket: a tapered body, its hem over the hips, round shoulders; shirt, gold tie and pocket square in front
	_part(_body, _cylinder(0.235, 0.19, 0.6), suit, Vector3(0.0, 1.27, 0.0), Vector3(1.0, 1.0, 0.62))
	_part(_body, _cylinder(0.2, 0.215, 0.2), suit, Vector3(0.0, 0.9, 0.0), Vector3(1.0, 1.0, 0.66))
	for side: float in [1.0, -1.0]:
		_part(_body, _sphere(0.085), suit, Vector3(side * 0.225, 1.53, 0.0), Vector3(1.0, 0.8, 1.0))
	_part(_body, _cylinder(0.12, 0.15, 0.07), suit, Vector3(0.0, 1.6, 0.0), Vector3(1.0, 1.0, 0.7))
	_part(_body, _box(Vector3(0.12, 0.26, 0.02)), shirt, Vector3(0.0, 1.45, 0.137))
	_part(_body, _box(Vector3(0.05, 0.3, 0.015)), gold, Vector3(0.0, 1.38, 0.147))
	_part(_body, _box(Vector3(0.065, 0.045, 0.03)), gold, Vector3(0.0, 1.555, 0.142))
	_part(_body, _box(Vector3(0.06, 0.035, 0.012)), gold, Vector3(0.12, 1.42, 0.13))
	for k in 2:                         # jacket buttons
		_part(_body, _sphere(0.012), gold, Vector3(0.0, 1.06 + 0.1 * k, 0.122))
	for side: float in [1.0, -1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.265, 1.56, 0.0)
		_body.add_child(shoulder)
		_part(shoulder, _capsule(0.062, 0.64), suit, Vector3(0.0, -0.29, 0.0))
		_part(shoulder, _box(Vector3(0.13, 0.05, 0.13)), shirt, Vector3(0.0, -0.58, 0.0))
		_part(shoulder, _sphere(0.058), skin, Vector3(0.0, -0.65, 0.0))
		if side > 0.0:
			_part(shoulder, _box(Vector3(0.135, 0.035, 0.135)), gold, Vector3(0.0, -0.545, 0.0))     # the watch
		_arms.append(shoulder)
	_part(_body, _capsule(0.055, 0.16), skin, Vector3(0.0, 1.68, 0.0))
	_part(_body, _sphere(0.14), skin, Vector3(0.0, 1.81, 0.0), Vector3(1.0, 1.08, 1.0))
	_part(_body, _sphere(0.148), hair, Vector3(0.0, 1.875, -0.02), Vector3(1.0, 0.62, 1.04))
	for side: float in [1.0, -1.0]:
		_part(_body, _sphere(0.016), black, Vector3(side * 0.048, 1.83, 0.128))
	_part(_body, _sphere(0.022), skin, Vector3(0.0, 1.8, 0.145))
	for side: float in [1.0, -1.0]:
		_part(_body, _sphere(0.03), skin, Vector3(side * 0.142, 1.8, 0.0), Vector3(0.6, 1.0, 1.0))     # ears
	_part(_body, _box(Vector3(0.1, 0.018, 0.02)), hair, Vector3(0.0, 1.765, 0.132))         # the moustache
	_bubble = Label3D.new()
	_bubble.position = Vector3(0.0, 2.35, 0.0)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 34
	_bubble.pixel_size = 0.0042
	_bubble.outline_size = 12
	_bubble.outline_modulate = Color(0.05, 0.03, 0.0)
	_bubble.modulate = Color(1.0, 0.95, 0.82)
	_bubble.width = 560.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)
	set_meta("plateau", {"type": "npc", "id": "salesman %s (%s)" % [NAME, showroom.dealer]})
