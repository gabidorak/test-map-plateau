// Grass tufts (milestone M4), drawn with MultiMesh. Per instance: INSTANCE_CUSTOM = (palette colour
// in sRGB, wind phase). Vertex COLOR.r = height along the blade (0 base, 1 tip). Tufts shrink into the
// ground between fade_start and fade_end (LOD fade) and sway with the wind.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toy_noise.gdshaderinc"

uniform float fade_start = 28.0;
uniform float fade_end = 42.0;
uniform float sway = 0.05;
uniform float tone_scale = 1.0;         // same as the ground pattern under it (toy_ground.gdshader)
uniform bool two_tone = true;

varying float tip;
varying vec3 tint;

void vertex() {
	tip = COLOR.r;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = 1.0 - smoothstep(fade_start, fade_end, distance(origin, CAMERA_POSITION_WORLD));
	VERTEX *= vec3(mix(0.5, 1.0, s), s, mix(0.5, 1.0, s));
	float ph = INSTANCE_CUSTOM.a * 6.2831 + dot(origin.xz, vec2(0.21, 0.17));
	float w = sin(TIME * 1.6 + ph) * 0.6 + sin(TIME * 2.7 + ph * 1.7) * 0.4;
	VERTEX.xz += vec2(1.0, 0.5) * w * sway * tip * tip;
	tint = two_tone ? grass_tone(origin.xz * tone_scale, INSTANCE_CUSTOM.rgb) : INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 c = mix(tint * 0.86, tint * 1.12 + vec3(0.02, 0.03, 0.0), tip);
	ALBEDO = srgb_to_linear(clamp(c, 0.0, 1.0));
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.12, 0.16, 0.04);
}
