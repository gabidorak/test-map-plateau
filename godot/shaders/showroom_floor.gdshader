// Showroom floor (scripts/builder/interior_builder.gd): polished marble tiles in world space, cream with faint grey
// veins, every other tile a shade warmer, thin dark grout lines and a gold inlay line every `band` tiles.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/toy_noise.gdshaderinc"

uniform float tile = 1.2;                   // m
uniform int band = 6;                       // tiles between gold lines
uniform vec3 cream = vec3(0.95, 0.91, 0.83);
uniform vec3 warm = vec3(0.86, 0.79, 0.66);
uniform vec3 vein = vec3(0.6, 0.6, 0.62);
uniform vec3 grout = vec3(0.45, 0.43, 0.4);
uniform vec3 gold = vec3(0.85, 0.62, 0.22);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz / tile;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 c = mix(cream, warm, checker * 0.75);
	float n = fbm(world.xz * 0.9 + cell * 3.7);
	float v = smoothstep(0.035, 0.0, abs(n - 0.5));
	c = mix(c, vein, v * 0.35);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * tile;
	float g = smoothstep(0.004, 0.0, edge - 0.002);
	c = mix(c, grout, g * 0.7);
	vec2 b = mod(cell, float(band));
	float on_band = (b.x == 0.0 && f.x < 0.06) || (b.y == 0.0 && f.y < 0.06) ? 1.0 : 0.0;
	ALBEDO = mix(c, gold, on_band);
	ROUGHNESS = mix(0.24, 0.35, on_band) + g * 0.4;
	SPECULAR = 0.45;
}
