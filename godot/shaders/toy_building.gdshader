// Toy buildings (milestone M7): one material for every building surface. Per-vertex data written by
// scripts/builder/building_builder.gd:
//   COLOR wall/roof colour (sRGB)       UV (u along the facade, h above the building base), m
//   UV2 (facade length, h of the last window floor's ceiling)
//   CUSTOM0 (ground floor height, floor height, door u or -1, bay width)
//   CUSTOM1 (part, floor style, ground style, material)
//   CUSTOM2 (accent colour sRGB, top style + 4 * window variant)
//   CUSTOM3 (seed, window floors, tier top h, parapet height)
// Style indices follow pipeline/plateau/facades.py. Windows are recessed with a parallax trick (the reveal
// shows on the side away from the viewer), glass mixes a sky reflection with a dark room; walls get their
// material pattern; everything fades to its average colour when a pixel covers several windows.
// Landmarks (M9) add the podium ground floor, panel and shingle materials and window variants (thick frames,
// pairs, staggered from floor to floor).
// At night (global `night`, scripts/night.gd) the glass reflects a dark sky and about half the rooms are lit (fewer
// in a power cut: global `power`).
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/toy_noise.gdshaderinc"

const int WALL = 0;
const int ROOF = 1;
const int COPING = 2;
const int PARAPET = 3;
const int SOFFIT = 4;
const int FASCIA = 5;
const int PLANT = 6;
const int PITCHED = 7;
const int EAVE = 8;         // house roofs: soffit, fascia, chimney (plain vertex colour)
const int TILES = 9;        // house roofs: UV = (along the eave, world height)
const int GREEN = 10;       // planted (sedum) roof of a landmark: UV = world (x, y), COLOR = the sedum green

const int F_BLIND = 0;
const int F_PUNCHED = 1;
const int F_RIBBON = 2;
const int F_CURTAIN = 3;
const int F_SLATS = 4;
const int F_BALCONIES = 5;
const int F_LOGGIAS = 6;
const int F_HIGH_BAND = 7;
const int F_GRID = 8;
const int F_HOUSE = 9;      // houses: punched windows with shutters, white frames, one front door

const int G_PLAIN = 0;
const int G_SHOPFRONT = 1;
const int G_LOBBY = 2;
const int G_PLINTH = 3;
const int G_PODIUM = 4;

const int M_RENDER = 0;
const int M_BRICK = 1;
const int M_WOOD = 2;
const int M_METAL = 3;
const int M_CONCRETE = 4;
const int M_PANELS = 5;
const int M_SHINGLES = 6;

const int W_PLAIN = 0;
const int W_FRAMED = 1;
const int W_PAIRS = 2;
const int W_FRAMED_STAGGERED = 3;

const int T_PLAIN = 0;
const int T_BAND = 1;

uniform vec4 coping_color : source_color = vec4(0.83, 0.84, 0.85, 1.0);
uniform vec4 soffit_color : source_color = vec4(0.94, 0.92, 0.88, 1.0);
uniform vec4 glass_sky_color : source_color = vec4(0.61, 0.79, 0.93, 1.0);
uniform vec4 glass_deep_color : source_color = vec4(0.18, 0.29, 0.39, 1.0);
uniform vec4 door_color : source_color = vec4(0.23, 0.27, 0.32, 1.0);
uniform vec4 plant_color : source_color = vec4(0.73, 0.75, 0.77, 1.0);
uniform float min_run = 2.2;            // facades shorter than this get no windows (corners)
uniform float frame = 0.06;             // window frame width (m)
uniform float recess = 0.14;            // window recess depth (m)
uniform vec4 room_light : source_color = vec4(1.0, 0.7, 0.38, 1.0);   // lit rooms at night
uniform float lit_share = 0.4;          // of the rooms lit at night
global uniform float night;
global uniform float power;             // share of the rooms still lit (scripts/night.gd: a power cut leaves a few)

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 base_col;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;
varying flat vec4 c3;
varying flat vec2 run;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_col = vec4(srgb_to_linear(COLOR.rgb), 1.0);
	c0 = CUSTOM0;
	c1 = CUSTOM1;
	c2 = vec4(srgb_to_linear(CUSTOM2.rgb), CUSTOM2.a);
	c3 = CUSTOM3;
	run = UV2;
}

// 1 while features `size` metres wide are resolved, 0 once a pixel covers most of one
float detail(float size, float fw) {
	return 1.0 - smoothstep(size * 0.15, size * 0.6, fw);
}

// thin line of width w (m) at the integer multiples of `period` along coordinate t, antialiased
float lines(float t, float period, float w, float fw) {
	float d = abs(fract(t / period + 0.5) - 0.5) * period;
	return (1.0 - smoothstep(w * 0.5, w * 0.5 + fw, d)) * detail(period, fw);
}

// grid = (bay width, ground floor height, floor height): panel joints follow the facade's rhythm
vec3 material_color(int m, vec2 p, vec3 col, float seed, float fw, vec3 grid, out float rough) {
	rough = 0.88;
	float n = fbm(p * 0.35 + seed);
	if (m == M_PANELS) {
		// precast panels one bay wide and one floor tall, each a touch lighter or darker
		float fy = p.y < grid.y ? 0.0 : 1.0 + floor((p.y - grid.y) / max(grid.z, 0.5));
		float y0 = fy == 0.0 ? 0.0 : grid.y + (fy - 1.0) * grid.z;
		float id = hash12(vec2(floor(p.x / max(grid.x, 0.5)), fy) + seed);
		float joint = max(lines(p.x, max(grid.x, 0.5), 0.025, fw), 1.0 - smoothstep(0.012, 0.012 + fw, abs(p.y - y0)));
		return col * (0.95 + 0.07 * id + 0.03 * n) * (1.0 - 0.3 * joint * detail(0.5, fw));
	}
	if (m == M_SHINGLES) {
		// slate-like shingles in horizontal courses, joints staggered, a shadow under each overlap
		float row = floor(p.y / 0.22);
		float bx = (p.x + mod(row, 2.0) * 0.2) / 0.4;
		float id = hash12(vec2(floor(bx), row) + seed);
		float t = fract(p.y / 0.22);
		vec3 c = col * (0.93 + 0.12 * id) * mix(0.84, 1.0, smoothstep(0.0, 0.35, t));
		float joint = 1.0 - smoothstep(0.01, 0.01 + fw * 2.5, abs(fract(bx + 0.5) - 0.5) * 0.4);
		return c * (1.0 - 0.25 * joint * detail(0.4, fw));
	}
	if (m == M_BRICK) {
		float row = floor(p.y / 0.08);
		float bx = (p.x + mod(row, 2.0) * 0.12) / 0.24;
		float id = hash12(vec2(floor(bx), row) + seed);
		vec3 c = col * (0.92 + 0.16 * id);
		float mortar = max(lines(p.y, 0.08, 0.012, fw), lines(p.x + mod(row, 2.0) * 0.12, 0.24, 0.012, fw));
		return mix(c, vec3(0.86, 0.83, 0.78) * 0.9, mortar * 0.8);
	}
	if (m == M_WOOD) {
		float board = floor(p.x / 0.15);
		float id = hash12(vec2(board, seed));
		vec3 c = col * (0.9 + 0.18 * id) * (0.96 + 0.08 * vnoise(vec2(p.x * 9.0, p.y * 0.6)));
		return c * (1.0 - 0.45 * lines(p.x, 0.15, 0.012, fw));
	}
	if (m == M_METAL) {
		rough = 0.45;
		float seam = max(lines(p.y, 0.6, 0.015, fw), lines(p.x, 3.0, 0.02, fw));
		float id = hash12(vec2(floor(p.x / 3.0), floor(p.y / 0.6)) + seed);
		return col * (0.96 + 0.06 * id) * (1.0 - 0.3 * seam);
	}
	if (m == M_CONCRETE) {
		float joint = max(lines(p.x, 2.4, 0.02, fw), lines(p.y, 1.2, 0.02, fw));
		vec2 q = vec2(p.x / 0.6, p.y / 0.6);
		vec2 f = fract(q) - 0.5;
		float tie = (1.0 - smoothstep(0.035, 0.06, length(f * 0.6))) * detail(0.6, fw);
		return col * (0.95 + 0.08 * n) * (1.0 - 0.28 * joint) * (1.0 - 0.3 * tie);
	}
	return col * (0.96 + 0.07 * n);
}

// window of a floor: (half width, sill, head, kind) in bay coordinates; kind 0 none, 1 window, 2 loggia
vec4 window_rect(int fs, float bw, float fh) {
	if (fs == F_PUNCHED) return vec4(clamp(bw * 0.27, 0.45, 0.8), 0.9, fh - 0.55, 1.0);
	if (fs == F_RIBBON) return vec4(bw * 0.5, 1.0, fh - 0.5, 1.0);
	if (fs == F_CURTAIN) return vec4(bw * 0.5, 0.0, fh, 1.0);
	if (fs == F_SLATS) return vec4(bw * 0.5, 0.85, fh - 0.4, 1.0);
	if (fs == F_BALCONIES) return vec4(clamp(bw * 0.3, 0.55, 1.1), 0.05, fh - 0.45, 1.0);
	if (fs == F_LOGGIAS) return vec4(bw * 0.4, 0.0, fh - 0.3, 2.0);
	if (fs == F_GRID) return vec4(bw * 0.36, 0.75, fh - 0.55, 1.0);
	if (fs == F_HOUSE) return vec4(clamp(bw * 0.19, 0.42, 0.62), 0.95, fh - 0.5, 1.0);
	return vec4(0.0);
}

vec3 sky_reflection(vec3 v, vec3 n) {
	vec3 r = reflect(-v, n);
	vec3 sky = mix(glass_sky_color.rgb * 1.15, glass_sky_color.rgb * vec3(0.7, 0.85, 1.05), clamp(r.y * 1.6, 0.0, 1.0));
	vec3 below = mix(glass_deep_color.rgb * 1.6, vec3(0.45, 0.5, 0.45), 0.4);
	return mix(below, sky, smoothstep(-0.08, 0.05, r.y)) * (1.0 - 0.88 * night);
}

void fragment() {
	int part = int(round(c1.x));
	int fs = int(round(c1.y));
	int gs = int(round(c1.z));
	int mat = int(round(c1.w));
	vec3 col = base_col.rgb;
	vec3 accent = c2.rgb;
	float seed = c3.x;
	float rough = 0.88;
	float spec = 0.35;
	vec3 emis = vec3(0.0);
	float u = UV.x;
	float h = UV.y;
	float fw = max(fwidth(u) + fwidth(h), 1e-4);
	vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);

	if (part == ROOF) {
		vec2 p = UV;
		float grit = hash12(floor(p * 9.0) + seed);
		float seam = lines(p.x + 0.3 * p.y, 1.1, 0.03, fwidth(p.x));
		col *= (0.94 + 0.1 * grit * detail(0.11, fwidth(p.x))) * (1.0 - 0.12 * seam) * (0.96 + 0.08 * fbm(p * 0.2));
	} else if (part == GREEN) {
		// sedum mats: green with drifts of olive, ochre and rust (they turn red in the sun), tufts and the rows of
		// the planting trays
		vec2 p = UV;
		float fwp = fwidth(p.x) + fwidth(p.y);
		float drift = fbm(p * 0.09 + seed * 0.37);
		float rust = smoothstep(0.55, 0.72, fbm(p * 0.05 + vec2(seed * 0.11, 3.7)));
		vec3 olive = vec3(0.5, 0.56, 0.2);
		vec3 ochre = vec3(0.68, 0.46, 0.2);
		vec3 red = vec3(0.62, 0.27, 0.17);
		col = mix(col, olive, smoothstep(0.45, 0.7, drift) * 0.45);
		col = mix(col, mix(ochre, red, smoothstep(0.5, 0.75, drift)), rust * 0.9);
		float tuft = hash12(floor(p * 4.0) + seed);
		col *= mix(1.0, 0.86 + 0.24 * tuft, detail(0.25, fwp));
		float tray = max(lines(p.x, 1.2, 0.025, fwidth(p.x)), lines(p.y, 1.2, 0.025, fwidth(p.y)));
		col *= 1.0 - 0.1 * tray * detail(1.2, fwp);
		rough = 0.97;
		spec = 0.15;
	} else if (part == PITCHED) {
		float row = lines(wpos.y, 0.32, 0.03, fwidth(wpos.y));
		col *= (1.0 - 0.25 * row) * (0.95 + 0.08 * hash12(vec2(floor(wpos.y / 0.32), floor(UV.x * 2.0)) + seed));
	} else if (part == TILES) {
		// courses of tiles (curved terracotta when reddish, flat slates or tiles otherwise), joints staggered
		float row = floor(UV.y / 0.21);
		float bx = (UV.x + mod(row, 2.0) * 0.14) / 0.28;
		float id = hash12(vec2(floor(bx), row) + seed);
		float t = fract(UV.y / 0.21);
		float fwr = fwidth(UV.y) + fwidth(UV.x);
		float shade = mix(0.8, 1.0, smoothstep(0.0, 0.4, t));
		float joint = 1.0 - smoothstep(0.01, 0.01 + fwr * 2.0, abs(fract(bx + 0.5) - 0.5) * 0.28);
		float terracotta = smoothstep(0.05, 0.15, col.r - col.b);
		float ripple = 0.9 + 0.1 * sin(fract(bx) * 6.2832);
		col *= (0.92 + 0.14 * id) * mix(1.0, shade * mix(1.0 - 0.2 * joint, ripple, terracotta), detail(0.3, fwr));
		col *= 0.97 + 0.06 * fbm(UV * 0.3 + seed);
	} else if (part == EAVE) {
		rough = 0.8;
	} else if (part == COPING) {
		col = coping_color.rgb;
		rough = 0.5;
		spec = 0.5;
	} else if (part == PARAPET) {
		col = material_color(M_RENDER, UV, col, seed, fw, vec3(3.0, 4.0, 3.0), rough) * 0.92;
	} else if (part == SOFFIT) {
		vec2 p = UV;
		col = soffit_color.rgb;
		float grid = max(lines(p.x, 1.2, 0.02, fwidth(p.x)), lines(p.y, 1.2, 0.02, fwidth(p.y)));
		col *= 1.0 - 0.18 * grid;
		vec2 f = fract(p / 2.4) - 0.5;
		float lamp = 1.0 - smoothstep(0.04, 0.06, length(f * 2.4));
		emis = vec3(1.0, 0.95, 0.85) * lamp * 1.4 * detail(2.4, fwidth(p.x));
		col = mix(col, vec3(1.0, 0.97, 0.9), lamp);
	} else if (part == FASCIA) {
		col = mix(accent, coping_color.rgb, lines(h - c3.z, 10.0, 0.08, fw));
		rough = 0.5;
	} else if (part == PLANT) {
		col = plant_color.rgb * (1.0 - 0.35 * lines(h, 0.14, 0.035, fw)) * (1.0 - 0.3 * lines(u, 2.0, 0.03, fw));
		rough = 0.5;
	} else {
		// ---------------------------------------------------------------- facades
		float L = run.x;
		float win_top = run.y;
		float g = c0.x;
		float f = c0.y;
		float door = c0.z;
		float bay = max(c0.w, 0.5);
		int top_style = int(round(c2.a)) % 4;
		int win = int(round(c2.a)) / 4;
		vec3 wall = material_color(mat, vec2(u, h), col, seed, fw, vec3(L / max(1.0, floor(L / bay)), g, f), rough);
		vec3 outc = wall;
		// floor of this pixel
		int k = h < g ? 0 : 1 + int(floor((h - g) / max(f, 0.5)));
		float zb = k == 0 ? 0.0 : g + float(k - 1) * f;
		float fh = k == 0 ? g : f;
		float y = h - zb;
		bool top_zone = h > win_top + 0.02 || (zb + fh > win_top + 0.3 && k > 0);
		float nb = max(1.0, floor(L / bay));
		float bw = L / nb;
		float bi = floor(u / bw);
		float x = u - (bi + 0.5) * bw;
		vec4 rect = vec4(0.0);
		bool has_windows = L >= min_run && h >= 0.0 && fs != F_BLIND;
		if (has_windows && !top_zone) {
			if (k == 0) {
				if (gs == G_SHOPFRONT) rect = vec4(bw * 0.46, 0.12, g - 0.9, 1.0);
				else if (gs == G_PODIUM) rect = vec4(bw * 0.4, 0.12, min(g - 1.6, 3.6), 1.0);
				else if (gs == G_LOBBY) rect = vec4(bw * 0.48, 0.05, g - 0.35, 1.0);
				else if (fs == F_HIGH_BAND) rect = vec4(bw * 0.5, max(g - 2.0, 1.2), g - 0.5, 1.0);
				else rect = window_rect(fs == F_CURTAIN ? F_RIBBON : (fs == F_LOGGIAS || fs == F_BALCONIES ? F_PUNCHED : fs), bw, fh);
			} else if (fs != F_HIGH_BAND) {
				rect = window_rect(fs, bw, fh);
			}
		}
		if (fs == F_HOUSE && k == 0 && door >= 0.0 && abs((bi + 0.5) * bw - door) < bw * 0.5 + 0.6) {
			rect = vec4(0.0);
		}
		// window variants (M9): pairs get wider openings split by a pier, framed ones a thick frame; staggered
		// windows move along their bay from floor to floor
		if (k > 0 && rect.w > 0.0 && rect.w < 1.5) {
			if (win == W_PAIRS) {
				rect.x = clamp(bw * 0.34, 0.8, 1.6);
			}
			if (win == W_FRAMED_STAGGERED) {
				float room = max(bw * 0.5 - rect.x - 0.25, 0.0);
				x -= (hash12(vec2(bi, float(k)) + seed * 1.7) * 2.0 - 1.0) * room;
			}
		}
		// ground floor bands
		if (k == 0 && gs == G_SHOPFRONT && y > g - 0.8 && y < g - 0.2) {
			outc = accent;
			rough = 0.5;
		}
		if (k == 0 && gs == G_PLINTH && y < 0.6 && h >= -2.0) {
			outc = wall * 0.78;
		}
		// curtain wall spandrels and the floor lines of ribbon / slat / grid facades
		if (!top_zone && has_windows && k > 0 && (fs == F_CURTAIN)) {
			rect = vec4(bw * 0.5, 0.0, fh, 1.0);
		}
		if (!top_zone && has_windows && k > 0 && (fs == F_RIBBON || fs == F_SLATS || fs == F_GRID)) {
			float band = 1.0 - smoothstep(0.12, 0.12 + fw, abs(y - fh + 0.25));
			outc = mix(outc, accent, band * 0.85 * detail(0.25, fw));
		}
		// top zone: band of the accent colour
		if (top_zone && top_style == T_BAND && h < c3.z + 0.01) {
			outc = mix(accent, accent * 0.85, lines(h, 0.5, 0.02, fw));
			rough = 0.5;
		}
		// shingles: a dark joint along each floor line
		if (mat == M_SHINGLES && k > 0 && y < 0.05 && h >= 0.0) {
			outc = mix(wall, accent * 0.7, 0.8);
		}
		// house shutters: one each side of the window, the width of half the window, horizontal louvres
		bool house = fs == F_HOUSE;
		vec3 house_frame = vec3(0.93, 0.93, 0.9);
		if (house && rect.w == 1.0 && rect.z > rect.y) {
			float sx = abs(x) - rect.x - 0.04;
			float sy = abs(y - (rect.y + rect.z) * 0.5) - (rect.z - rect.y) * 0.5;
			if (sx > 0.0 && sx < rect.x && sy < 0.0) {
				outc = accent * (1.0 - 0.28 * lines(y, 0.075, 0.025, fw)) * (sx < 0.03 || sx > rect.x - 0.03 ? 0.8 : 1.0);
				rough = 0.6;
			}
		}
		// windows
		float coverage = 0.0;
		bool framed = k > 0 && (win == W_FRAMED || win == W_FRAMED_STAGGERED);
		if (framed && rect.w > 0.0 && rect.w < 1.5) {
			rect.x += 0.1;
			rect.y -= 0.1;
			rect.z += 0.1;
		}
		if (rect.w > 0.0 && rect.z > rect.y) {
			float hw = rect.x;
			float cy = (rect.y + rect.z) * 0.5;
			float hh = (rect.z - rect.y) * 0.5;
			coverage = clamp(2.0 * hw * 2.0 * hh / (bw * fh), 0.0, 1.0);
			vec2 q = vec2(x, y - cy);
			vec2 inside = hw - abs(q.x) > 0.0 && hh - abs(q.y) > 0.0 ? vec2(1.0) : vec2(0.0);
			if (inside.x > 0.0) {
				float wid = hash12(vec2(bi, float(k)) + seed * 3.1);
				vec3 tng = normalize(cross(vec3(0.0, 1.0, 0.0), wnrm));
				vec3 vt = vec3(dot(v_world, tng), v_world.y, max(dot(v_world, wnrm), 0.08));
				bool curtain = fs == F_CURTAIN && k > 0;
				float depth = rect.w > 1.5 ? 0.9 : (curtain ? 0.03 : recess);
				vec2 gq = q - vt.xy / vt.z * depth;       // where the view ray reaches the glass plane
				float fr = curtain ? 0.035 : (framed ? 0.17 : frame);
				bool on_glass = abs(gq.x) < hw - fr && abs(gq.y) < hh - fr;
				if (rect.w > 1.5) {
					// loggia: dark recess with a french window at its back
					vec3 back = wall * 0.62;
					if (abs(gq.x) < hw * 0.55 && gq.y < hh - 0.25 && gq.y > -hh + 0.05) {
						back = mix(glass_deep_color.rgb, sky_reflection(v_world, wnrm), 0.25);
					}
					outc = (abs(gq.x) < hw && abs(gq.y) < hh) ? back : wall * (gq.y > 0.0 ? 0.55 : 0.75);
				} else if (win == W_PAIRS && k > 0 && abs(q.x) < 0.17) {
					outc = wall;                 // the pier between the two windows of a pair
					coverage *= 0.8;
				} else if (on_glass) {
					float fres = 0.15 + 0.6 * pow(1.0 - vt.z, 3.0);
					vec3 room = glass_deep_color.rgb * (0.8 + 0.4 * wid);
					// blinds half down in some windows
					float blind = step(0.86, wid) * step(gq.y, hh - fr) * step(hh - (0.3 + 0.6 * fract(wid * 7.0)) * hh * 2.0, gq.y);
					room = mix(room, vec3(0.86, 0.82, 0.72), blind * 0.85);
					float lit = night * step(1.0 - lit_share * power, fract(wid * 13.7 + 0.3));
					vec3 lamp = room_light.rgb * (0.55 + 0.6 * fract(wid * 31.3)) * mix(1.0, 0.6, blind);
					room = mix(room, lamp * 0.6, lit);
					emis = lamp * lit * (1.0 - fres) * 1.1;
					outc = mix(room, sky_reflection(v_world, wnrm), fres);
					// mullion and transom
					float mull = curtain || fs == F_RIBBON || gs == G_LOBBY || house ? 1.0 - smoothstep(0.02, 0.02 + fw, abs(gq.x)) : 0.0;
					float tran = (fs == F_PUNCHED || fs == F_GRID) && k > 0 ? 1.0 - smoothstep(0.02, 0.02 + fw, abs(gq.y - hh * 0.45)) : 0.0;
					outc = mix(outc, house ? house_frame : accent, max(mull, tran) * detail(0.08, fw));
					if (curtain) {
						float slab = 1.0 - smoothstep(0.3, 0.3 + fw, abs(y - fh + 0.2));
						outc = mix(outc, mix(glass_deep_color.rgb, accent, 0.35), slab);
					}
					rough = 0.08;
					spec = 0.6;
				} else if (abs(q.x) > hw - fr || abs(q.y) > hh - fr) {
					outc = house ? house_frame : accent;   // the frame
					rough = 0.5;
				} else {
					outc = wall * (gq.y > 0.0 ? 0.58 : 0.82);   // reveal: lintel soffit darker than the sill
				}
			}
		}
		// door: a house has one panelled leaf in its shutter colour, in a white frame
		if (house && door >= 0.0 && k == 0 && abs(u - door) < 0.6 && y < 2.25 && h > -1.0) {
			float dx = abs(u - door);
			if (dx > 0.5 || y > 2.15) {
				outc = house_frame;
			} else {
				float panel = max(1.0 - smoothstep(0.02, 0.02 + fw, abs(dx - 0.3)), 1.0 - smoothstep(0.02, 0.02 + fw, abs(y - 1.0)));
				outc = accent * 0.82 * (1.0 - 0.25 * panel * step(dx, 0.3) * step(0.25, y) * step(y, 1.9));
				rough = 0.45;
			}
			coverage = 0.0;
		} else if (door >= 0.0 && k == 0 && abs(u - door) < 1.0 && y < 2.55 && h > -1.0) {
			float dx = u - door;
			if (abs(dx) > 0.9 || y > 2.45) {
				outc = accent;
			} else {
				vec3 leaf = mix(door_color.rgb, sky_reflection(v_world, wnrm), 0.35);
				float split = 1.0 - smoothstep(0.015, 0.015 + fw, abs(dx));
				float bar = 1.0 - smoothstep(0.03, 0.03 + fw, abs(y - 1.05));
				outc = mix(leaf, accent, max(split, bar * step(abs(dx), 0.75)));
				rough = 0.15;
				spec = 0.55;
			}
			coverage = 0.0;
		}
		// far away: the average of wall and glass instead of shimmering windows
		float far = 1.0 - detail(min(bw, max(rect.z - rect.y, 0.4)), fw);
		vec3 avg = mix(wall, mix(glass_deep_color.rgb, glass_sky_color.rgb, 0.45), coverage * 0.8);
		outc = mix(outc, avg, far * step(0.001, rect.w));
		emis = mix(emis, room_light.rgb * lit_share * power * coverage * 0.8 * night * 0.85, far * step(0.001, rect.w));
		col = outc;
		// contact shadow at the foot of the walls
		col *= mix(0.72, 1.0, smoothstep(-0.2, 0.6, h + 0.0 * c3.w));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
}
