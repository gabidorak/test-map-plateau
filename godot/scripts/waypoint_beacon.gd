extends Node3D
## The waypoint in the world (game.gd set_waypoint, put on the full-screen map: scripts/world_map.gd): a tall gold
## beam of light standing on the ground there, wider the further it is so it stays a line on the horizon, and on the
## screen a gold diamond with the distance over it, held at the screen's edge when it is out of view. Reaching it
## (REACHED m) takes it away.

const GroundMap = preload("res://scripts/ground_map.gd")
const Minimap = preload("res://scripts/minimap.gd")
const HEIGHT := 400.0                       # m
const RADIUS := 1.5                         # m, near
const WIDE_FROM := 70.0                     # m away: wider from there on, by distance
const REACHED := 12.0                       # m (flat)
const EDGE := 40.0                          # px kept from the screen's edges

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 colour : source_color;
varying float height;
void vertex() { height = VERTEX.y; }
void fragment() {
	float edge = abs(dot(NORMAL, VIEW));    // solid in the middle of the beam, soft at its sides
	float fade = 1.0 - smoothstep(0.35, 1.0, (height + 0.5 * %f) / %f);   // and fading out up high
	ALBEDO = colour.rgb;
	ALPHA = colour.a * sqrt(edge) * fade;
}
""" % [HEIGHT, HEIGHT]

var game: Node                              # game.gd
var _beam: MeshInstance3D
var _marker: Control                        # in the HUD
var _at := Vector3.ZERO                     # the beam's foot
var _distance := 0.0


func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = HEIGHT
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = SHADER
	mat.set_shader_parameter("colour", Color(Minimap.WAYPOINT, 0.8))
	mesh.material = mat
	_beam = MeshInstance3D.new()
	_beam.mesh = mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = 16384.0       # (the shader fades it, the culling must not cut it)
	add_child(_beam)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.draw.connect(_draw_marker)
	game.hud.add_child(_marker)
	game.hud.move_child(_marker, 0)         # under the rest of the HUD
	visible = false


## Stands the beam at pipeline (x, y), or hides it (null).
func place(xy: Variant) -> void:
	visible = xy != null
	_marker.visible = visible
	if xy == null:
		return
	var map: RefCounted = GroundMap.get_map()
	var y: float = map.height(xy.x, xy.y) if map else 0.0
	_at = Vector3(xy.x, y, -xy.y)
	_beam.global_position = _at + Vector3.UP * HEIGHT * 0.5


func _process(_delta: float) -> void:
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye: Vector3 = game.map_eye()
	_distance = Vector2(eye.x - _at.x, eye.z - _at.z).length()
	if _distance < REACHED:
		game.set_waypoint(null)
		game.toast("Waypoint reached")
		return
	var k := maxf(1.0, cam.global_position.distance_to(_at) / WIDE_FROM)
	_beam.scale = Vector3(k, 1.0, k)
	_marker.queue_redraw()


func _draw_marker() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not visible:
		return
	var view := _marker.size
	var mid := view * 0.5
	var target := _at + Vector3.UP * 3.0
	var p := cam.unproject_position(target)
	var inside := Rect2(Vector2.ONE * EDGE, view - Vector2.ONE * EDGE * 2.0)
	if cam.is_position_behind(target):
		p = mid + (mid - p) * 1000.0        # behind: towards the side it is on, off the screen
	if not inside.has_point(p):             # held at the edge, on the line from the middle
		var d := p - mid
		var t := minf(absf((inside.size.x * 0.5) / d.x) if d.x != 0.0 else INF,
				absf((inside.size.y * 0.5) / d.y) if d.y != 0.0 else INF)
		p = mid + d * minf(t, 1.0)
	Minimap.draw_waypoint(_marker, p, 9.0)
	var font := _marker.get_theme_default_font()
	var text := "%d m" % roundi(_distance) if _distance < 1000.0 else "%.1f km" % (_distance / 1000.0)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var at := p + Vector2(-w * 0.5, -18.0)
	_marker.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Minimap.INK)
	_marker.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Minimap.WAYPOINT)
