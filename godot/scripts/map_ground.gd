extends RefCounted
## The ground as the maps draw it (scripts/minimap.gd, scripts/world_map.gd), straight from the ground map the loader
## has already read (scripts/ground_map.gd): its piece ids one texel a metre (an RG8 texture: id = r + 256 g) and a
## texture of a colour per piece, from the game's own palette, so the maps show the ground as the game draws it
## (roads, paths, buildings, lawns, water) with no picture to build or ship. The id texture is cut down on a worker
## thread the first time a map asks (ready()), and kept for the session: both maps share it.
## A map is a ColorRect with material(); view() points it: the pipeline point under its middle, the way up on it, and
## how many metres it spans; `round` cuts it to a disc (the minimap).

const GroundMap = preload("res://scripts/ground_map.gd")
const STEP := 2                             # ground samples (0.5 m) per texel: 1 m (~48 MB of texture)
const PALETTE_W := 4096                     # pieces per row of the colour texture
const BACKGROUND := Color(0.12, 0.13, 0.16)
const PATHS := ["sidewalk", "footway", "path", "pedestrian", "cycleway", "steps", "track"]

const SHADER := """
shader_type canvas_item;
uniform sampler2D ids : filter_nearest;
uniform sampler2D colours : filter_nearest;
uniform vec2 centre;                        // texels (x east, y south) under the middle of the map
uniform vec2 forward;                       // unit, in texels: up on the map
uniform vec2 half_span;                     // texels from the middle to the right edge and to the top edge
uniform bool round_map;
uniform vec4 background : source_color;

vec3 piece(ivec2 t) {
	ivec2 n = textureSize(ids, 0);
	if (t.x < 0 || t.y < 0 || t.x >= n.x || t.y >= n.y) return background.rgb;
	vec2 v = texelFetch(ids, t, 0).rg;
	int id = int(round(v.r * 255.0)) + int(round(v.g * 255.0)) * 256;
	if (id == 0) return background.rgb;
	return texelFetch(colours, ivec2((id - 1) % 4096, (id - 1) / 4096), 0).rgb;
}

void fragment() {
	vec2 o = (UV - 0.5) * 2.0;              // -1..1, y down
	vec2 right = vec2(-forward.y, forward.x);
	vec2 q = centre + o.x * half_span.x * right - o.y * half_span.y * forward - 0.5;
	vec2 fw = fwidth(q);
	vec3 c;
	if (max(fw.x, fw.y) < 1.5) {            // zoomed in: blend the 4 texels round the point
		ivec2 i = ivec2(floor(q));
		vec2 f = fract(q);
		c = mix(mix(piece(i), piece(i + ivec2(1, 0)), f.x),
				mix(piece(i + ivec2(0, 1)), piece(i + ivec2(1, 1)), f.x), f.y);
	} else {                                // zoomed out: 4 texels spread over the pixel (no shimmer)
		vec2 d = fw * 0.25;
		c = (piece(ivec2(q + vec2(-d.x, -d.y))) + piece(ivec2(q + vec2(d.x, -d.y)))
				+ piece(ivec2(q + vec2(-d.x, d.y))) + piece(ivec2(q + vec2(d.x, d.y)))) * 0.25;
	}
	float a = 1.0;
	if (round_map) {
		float r = length(o);
		c *= 1.0 - 0.25 * smoothstep(0.6, 1.0, r);   // darker towards the rim
		a = 0.92 * (1.0 - smoothstep(1.0 - fwidth(r), 1.0, r));
	}
	COLOR = vec4(c, a);
}
"""

static var origin := Vector2.ZERO           # pipeline (x, y) of texel (0, 0)'s corner
static var texel := 1.0                     # m
static var extent := Rect2()                # pipeline (x, y) the ground map covers (y north: position is its SW corner)
static var _ids_tex: ImageTexture
static var _colours_tex: ImageTexture
static var _shader: Shader
static var _task := -1
static var _ids: Image                      # written by the task
static var _colours: Image
static var _failed := false


## True once the textures are made; starts making them (and keeps asking: call it every frame until then).
static func ready() -> bool:
	if _ids_tex:
		return true
	if _failed:
		return false
	if _task < 0:
		var map: RefCounted = GroundMap.get_map()   # (read by the loader already: at once)
		if map == null:
			_failed = true
			return false
		_task = WorkerThreadPool.add_task(_cut.bind(map), false, "Map textures")
		return false
	if not WorkerThreadPool.is_task_completed(_task):
		return false
	wait()
	_ids_tex = ImageTexture.create_from_image(_ids)
	_colours_tex = ImageTexture.create_from_image(_colours)
	_ids = null
	_colours = null
	_shader = Shader.new()
	_shader.code = SHADER
	return true


## Waits for the worker, if it runs (a game quitting while it does: a task left running aborts the engine at exit).
static func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## A material drawing the ground (once ready()).
static func material(round_map: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("ids", _ids_tex)
	mat.set_shader_parameter("colours", _colours_tex)
	mat.set_shader_parameter("background", BACKGROUND)
	mat.set_shader_parameter("round_map", round_map)
	return mat


## Points `mat` at pipeline point `centre`, `up` (a unit pipeline vector) up, `half_m` metres from the middle to the
## right edge and to the top edge.
static func view(mat: ShaderMaterial, centre: Vector2, up: Vector2, half_m: Vector2) -> void:
	mat.set_shader_parameter("centre", Vector2(centre.x - origin.x, origin.y - centre.y) / texel)
	mat.set_shader_parameter("forward", Vector2(up.x, -up.y))
	mat.set_shader_parameter("half_span", half_m / texel)


## Worker thread: the ground's piece ids one every STEP samples, and the colour of each piece.
static func _cut(map: RefCounted) -> void:
	var w: int = map._w
	var h: int = map._h
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RG8, map._ids)   # (shares the bytes)
	img.resize(maxi(1, w / STEP), maxi(1, h / STEP), Image.INTERPOLATE_NEAREST)
	texel = map._cell * float(w) / float(img.get_width())
	origin = Vector2(map._ox - map._cell * 0.5, map._oy + map._cell * 0.5)
	extent = Rect2(origin.x, origin.y - map._cell * h, map._cell * w, map._cell * h)
	_ids = img
	var ground: Dictionary = map.palette.get("ground", {})
	var road := Color(str(ground.get("asphalt", "#63666b")))
	var n: int = map.pieces.size()
	var colours := Image.create_empty(PALETTE_W, maxi(1, ceili(n / float(PALETTE_W))), false, Image.FORMAT_RGBA8)
	for k in n:
		var piece: Array = map.pieces[k]
		var c := Color(str(ground.get(piece[1], ground.get("concrete", "#c9c4b8"))))
		if piece[0] == "building":
			c = Color("#b3a6cf")            # a touch darker than the walls' ground colour: stands out from paving
		elif piece[1] == "asphalt" and piece[0] in PATHS:
			c = road.lerp(Color.WHITE, 0.35)    # paths and sidewalks lighter than the roads
		colours.set_pixel(k % PALETTE_W, k / PALETTE_W, c)
	_colours = colours
