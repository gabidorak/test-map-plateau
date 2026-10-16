// Toy ground (milestone M4): one shader for every ground surface, kerb and marking.
// Per vertex: COLOR = palette colour (sRGB, from pipeline/palette.toml), CUSTOM0 = (material id, flags,
// per-piece variation, 0) as bytes. Patterns are procedural and in world space (metres), so they tile
// across chunks; they fade to their average colour when a pixel covers several features.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/toy_noise.gdshaderinc"

// Material ids: index in world.json ground_mesh.materials (ground_builder.gd checks the order).
const int ASPHALT = 0;
const int CONCRETE = 1;
const int PAVING = 2;
const int SETT = 3;
const int GRAVEL = 4;
const int DIRT = 5;
const int SAND = 6;
const int GRASS = 7;
const int TALL_GRASS = 8;
const int FOREST_FLOOR = 9;
const int CONSTRUCTION = 10;
const int WATER = 11;
const int CLAY = 12;
const int TARTAN = 13;
const int ARTIFICIAL_TURF = 14;
const int COURT = 15;
const int WOOD = 16;
const int BUILDING = 17;
const int KERB = 18;
const int PAINT = 19;
const int BALLAST = 20;     // the railway's trackbed (tools/rail/patch_world.py)

uniform float bump_strength = 1.0;

varying vec3 wpos;
varying flat int mat;
varying flat float variation;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mat = int(round(CUSTOM0.r * 255.0));
	variation = CUSTOM0.b;
	if (mat == PAINT) {
		// decals: pulled a little towards the camera so they never z-fight with the road
		VERTEX += normalize(CAMERA_POSITION_WORLD - wpos) * 0.03;
	}
}

// 1 while features `size` metres wide are well resolved, 0 once a pixel covers most of one
float detail(float size, float fw) {
	return 1.0 - smoothstep(size * 0.2, size * 0.7, fw);
}

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Rounded tiles in rows (row offset `shift` of a tile). Returns (signed distance to the tile edge,
// negative inside; tile id) and the outward edge direction in `dir`.
// `bump` everywhere is the world xz gradient of a fake height field (raised tiles, pebbles...).
vec2 tiles(vec2 p, vec2 size, float gap, float radius, float shift, out vec2 dir) {
	float row = floor(p.y / size.y);
	float sx = p.x + row * shift * size.x;
	vec2 id = vec2(floor(sx / size.x), row);
	vec2 local = (vec2(fract(sx / size.x), fract(p.y / size.y)) - 0.5) * size;
	vec2 half_size = size * 0.5 - gap * 0.5;
	float d = rbox(local, half_size, radius);
	vec2 q = max(abs(local) - (half_size - radius), 0.0) * sign(local);
	dir = length(q) > 1e-5 ? normalize(q) : vec2(0.0);
	return vec2(d, hash12(id + 0.37));
}

// Shared tile look: joint colour, per-tile tint, rounded bevel (bump gradient towards the joints).
vec3 tiled(vec3 c, vec2 p, vec2 size, float gap, float radius, float shift, float tint, float joint,
		float bevel, float fw, inout vec2 bump, inout float ao) {
	vec2 dir;
	vec2 t = tiles(p, size, gap, radius, shift, dir);
	float k = detail(min(size.x, size.y), fw);
	float inside = smoothstep(0.0, -0.004 - fw * 0.5, t.x);
	float rim = 1.0 - smoothstep(0.0, bevel, -t.x);
	vec3 tile = c * (1.0 + (t.y - 0.5) * tint);
	vec3 col = mix(c * joint, tile, inside);
	bump -= dir * rim * inside * 0.8 * k;
	ao *= mix(1.0, mix(0.55, 1.0, inside), k);
	return mix(c * mix(1.0, joint, 0.25), col, k);
}

vec3 asphalt(vec3 c, vec2 p, float fw, inout vec2 bump) {
	vec3 col = c * (0.93 + 0.12 * fbm(p * 0.22));
	col *= 1.0 - 0.07 * smoothstep(0.62, 0.7, fbm(p * 0.06 + 3.0));      // repaired patches
	vec4 d = dots(p * 9.0, 1.0);
	float s = (1.0 - smoothstep(0.12, 0.32, d.x)) * detail(0.11, fw);
	col *= 1.0 + (d.y - 0.5) * 0.3 * s;
	col *= 1.0 + (vnoise(p * 30.0) - 0.5) * 0.1 * detail(0.033, fw);
	return col;
}

vec3 grass(vec3 c, vec2 p, float fw, inout vec2 bump) {
	vec3 col = grass_tone(p, c);
	col *= 1.0 + (fbm(p * 2.5) - 0.5) * 0.12 * detail(0.4, fw);
	vec4 d = dots(p * 2.4, 0.85);
	float k = detail(0.4, fw);
	float clover = (1.0 - smoothstep(0.13, 0.2, d.x)) * step(d.y, 0.22) * k;
	col = mix(col, col * vec3(0.8, 0.96, 0.8), clover);
	bump -= d.zw * clover * 2.0;
	float flower = (1.0 - smoothstep(0.05, 0.085, d.x)) * step(0.965, d.y) * detail(0.08, fw);
	col = mix(col, d.y > 0.985 ? vec3(0.98, 0.86, 0.3) : vec3(0.97, 0.97, 0.94), flower);
	return col;
}

vec3 tall_grass(vec3 c, vec2 p, float fw, inout vec2 bump) {
	vec3 col = grass_tone(p * 1.3, c);
	vec2 q = vec2(p.x * 0.8 + p.y * 0.6, -p.x * 0.6 + p.y * 0.8);
	float streak = vnoise(vec2(q.x * 0.7, q.y * 5.0));
	col *= 1.0 + (streak - 0.5) * 0.22 * detail(0.25, fw);
	vec4 d = dots(p * 1.2, 1.0);
	col *= 1.0 - 0.12 * (1.0 - smoothstep(0.2, 0.45, d.x)) * detail(0.8, fw);
	return col;
}

vec3 forest_floor(vec3 c, vec2 p, float fw, inout vec2 bump) {
	vec3 col = c * (0.88 + 0.2 * fbm(p * 0.4));
	vec4 d = dots(p * 5.0, 1.0);
	float leaf = (1.0 - smoothstep(0.18, 0.26, d.x)) * detail(0.2, fw);
	vec3 leaf_col = mix(vec3(0.55, 0.38, 0.2), vec3(0.62, 0.55, 0.22), d.y);
	col = mix(col, mix(col, leaf_col, 0.55), leaf * step(0.45, d.y));
	return col;
}

vec3 pebbles(vec3 c, vec2 p, float scale, float radius, float amount, float fw, inout vec2 bump) {
	vec4 d = dots(p * scale, 1.0);
	float k = detail(1.0 / scale, fw);
	float pebble = (1.0 - smoothstep(radius * 0.7, radius, d.x)) * step(1.0 - amount, d.y) * k;
	vec3 stone = mix(vec3(0.72, 0.7, 0.66), c * 1.25, fract(d.y * 7.3));
	bump -= d.zw * pebble * 3.0;
	return mix(c, stone, pebble);
}

vec3 dirt(vec3 c, vec2 p, float fw, inout vec2 bump) {
	vec3 col = c * (0.9 + 0.2 * fbm(p * 0.5));
	col *= 1.0 + (vnoise(p * 8.0) - 0.5) * 0.12 * detail(0.12, fw);
	return pebbles(col, p, 3.5, 0.16, 0.45, fw, bump);
}

vec3 tyre_tracks(vec3 c, vec2 p, float fw) {
	vec2 cell = floor(p / 30.0);
	float a = hash12(cell) * 3.1416;
	vec2 q = vec2(cos(a) * p.x + sin(a) * p.y, -sin(a) * p.x + cos(a) * p.y);
	float w = mod(q.x + hash12(cell + 2.0) * 7.0, 7.0);
	float band = smoothstep(0.98, 1.02, w) * (1.0 - smoothstep(1.38, 1.42, w))
			+ smoothstep(2.78, 2.82, w) * (1.0 - smoothstep(3.18, 3.22, w));
	float tread = mix(0.6, 1.0, step(0.5, fract(q.y * 4.0)) * detail(0.25, fw));
	float here = smoothstep(0.35, 0.45, fbm(p * 0.04 + 9.0));
	return c * (1.0 - 0.2 * band * tread * here);
}

// crushed stone: angular grey pebbles of a few tones, packed, with dark gaps
vec3 ballast(vec3 c, vec2 p, float fw, inout vec2 bump, inout float ao) {
	vec4 d = dots(p * 16.0, 1.0);
	float k = detail(0.06, fw);
	float stone = 1.0 - smoothstep(0.28, 0.5, d.x);
	vec3 col = c * (0.82 + 0.3 * d.y) * mix(1.0, 0.72 + 0.28 * stone, k);
	col *= 0.93 + 0.12 * fbm(p * 0.7);
	bump -= d.zw * stone * 2.5 * k;
	ao *= mix(1.0, mix(0.7, 1.0, stone), k);
	return col;
}

vec3 water(vec3 c, vec2 p, float fw, inout vec2 bump) {
	vec2 flow = vec2(TIME * 0.06, TIME * 0.035);
	float n = fbm(p * 0.5 + flow);
	float e = 0.15;
	float nx = fbm((p + vec2(e, 0.0)) * 0.5 + flow);
	float nz = fbm((p + vec2(0.0, e)) * 0.5 + flow);
	bump += vec2(nx - n, nz - n) / e * 0.25;
	float glint = smoothstep(0.72, 0.8, fbm(p * 1.3 - flow * 2.0)) * detail(0.6, fw);
	return c * (0.88 + 0.2 * n) + vec3(0.12) * glint;
}

vec3 wood(vec3 c, vec2 p, float fw, inout vec2 bump, inout float ao) {
	float plank = floor(p.y / 0.14);
	float x = p.x + hash12(vec2(plank, 1.0)) * 2.0;
	float grain = vnoise(vec2(x * 0.9 + plank * 13.0, p.y * 25.0));
	vec3 col = c * (0.88 + 0.22 * hash12(vec2(plank, floor(x / 2.0)))) * (0.93 + 0.12 * grain * detail(0.05, fw));
	float edge = min((0.5 - abs(fract(p.y / 0.14) - 0.5)) * 0.14, (0.5 - abs(fract(x / 2.0) - 0.5)) * 2.0);
	float joint = 1.0 - smoothstep(0.004, 0.008, edge);
	ao *= mix(1.0, 0.6, joint * detail(0.14, fw));
	return col;
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec2 p = wpos.xz;
	float fw = length(fwidth(p));
	vec2 bump = vec2(0.0);              // world xz gradient of a fake height: tilts the normal
	float ao = 1.0;
	float rough = 0.9;
	float spec = 0.3;
	vec3 col = c;

	if (mat == ASPHALT) {
		col = asphalt(c, p, fw, bump);
	} else if (mat == CONCRETE) {
		col = tiled(c, p, vec2(1.6, 1.6), 0.02, 0.01, 0.0, 0.07, 0.78, 0.02, fw, bump, ao);
		col *= 1.0 + (fbm(p * 1.2) - 0.5) * 0.08;
		rough = 0.85;
	} else if (mat == PAVING) {
		col = tiled(c, p, vec2(0.4, 0.2), 0.016, 0.025, 0.5, 0.16, 0.7, 0.03, fw, bump, ao);
		rough = 0.8;
	} else if (mat == SETT) {
		col = tiled(c, p, vec2(0.21, 0.17), 0.022, 0.04, 0.43, 0.18, 0.7, 0.035, fw, bump, ao);
		rough = 0.75;
	} else if (mat == GRAVEL) {
		col = c * (0.92 + 0.12 * fbm(p * 0.6));
		col = pebbles(col, p, 13.0, 0.42, 0.75, fw, bump);
	} else if (mat == DIRT) {
		col = dirt(c, p, fw, bump);
	} else if (mat == SAND) {
		col = c * (0.95 + 0.08 * fbm(p * 0.5));
		float r = sin(dot(p, vec2(0.8, 0.6)) * 9.0 + fbm(p * 0.7) * 6.0);
		col *= 1.0 + r * 0.035 * detail(0.7, fw);
		rough = 0.95;
	} else if (mat == GRASS) {
		col = grass(c, p, fw, bump);
		rough = 0.95;
		spec = 0.2;
	} else if (mat == TALL_GRASS) {
		col = tall_grass(c, p, fw, bump);
		rough = 0.95;
		spec = 0.2;
	} else if (mat == FOREST_FLOOR) {
		col = forest_floor(c, p, fw, bump);
		rough = 0.95;
	} else if (mat == CONSTRUCTION) {
		col = tyre_tracks(dirt(c, p, fw, bump), p, fw);
	} else if (mat == WATER) {
		col = water(c, p, fw, bump);
		rough = 0.08;
		spec = 0.6;
	} else if (mat == CLAY) {
		col = c * (1.0 + (vnoise(p * 20.0) - 0.5) * 0.1 * detail(0.05, fw));
	} else if (mat == TARTAN) {
		col = c * (1.0 + (vnoise(p * 28.0) - 0.5) * 0.14 * detail(0.035, fw));
		rough = 0.8;
	} else if (mat == ARTIFICIAL_TURF) {
		col = c * (1.0 + (step(0.5, fract(p.x / 5.0)) - 0.5) * 0.08);
		col *= 1.0 + (vnoise(p * 12.0) - 0.5) * 0.08 * detail(0.08, fw);
	} else if (mat == COURT) {
		col = c * (0.97 + 0.06 * fbm(p * 0.8));
		rough = 0.7;
	} else if (mat == WOOD) {
		col = wood(c, p, fw, bump, ao);
	} else if (mat == KERB) {
		col = c * (1.0 + (vnoise(p * 14.0) - 0.5) * 0.1 * detail(0.07, fw));
		rough = 0.8;
	} else if (mat == BALLAST) {
		col = ballast(c, p, fw, bump, ao);
		rough = 0.95;
	} else if (mat == PAINT) {
		col = c * (0.93 + 0.07 * vnoise(p * 2.5));
		rough = 0.6;
	}

	ALBEDO = srgb_to_linear(clamp(col, 0.0, 1.0));
	ROUGHNESS = rough;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
	if (bump != vec2(0.0)) {
		vec3 n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		n = normalize(n - vec3(bump.x, 0.0, bump.y) * 0.35 * bump_strength);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
}
