// Water surface of the lakes and ponds (scripts/water.gd): flat at the body's level, see-through to the dug-out bed.
// Looks: rippling normals from scrolled noise (two wind directions, small and large ripples), the bed refracted
// through them and fading into the water colour with the depth of water in front of it (from the depth buffer),
// shallow water clear and turquoise, deep water dark green-blue, a foam line where the water meets the shore or
// anything standing in it, and the sky's reflection growing towards grazing angles (fresnel, from the scene's sky).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;

#include "res://shaders/toy_noise.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.32, 0.7, 0.66);
uniform vec3 deep_color : source_color = vec3(0.04, 0.2, 0.24);
uniform float clarity = 0.9;            // 1/m: how fast the bed fades into the water colour
uniform float ripple = 0.16;            // normal tilt of the ripples
uniform float refraction = 0.03;        // screen uv shift per unit of ripple tilt
uniform float foam_width = 0.25;        // m of water depth the shore foam covers
uniform vec2 wind = vec2(0.45, 0.25);   // m/s, ripple drift

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// height of the ripples at world xz `p`: four wind-driven wave trains of different lengths and directions, their
// height varied over the lake (so no grid of noise cells shows), and a little noise chop on top
float waves(vec2 p) {
	float t = TIME;
	float h = sin(dot(p, vec2(0.8, 0.6)) * 1.3 + t * 1.4) * 0.3
			+ sin(dot(p, vec2(-0.5, 0.86)) * 2.1 + t * 1.9) * 0.18
			+ sin(dot(p, vec2(0.95, -0.31)) * 3.7 + t * 2.6) * 0.1
			+ sin(dot(p, vec2(-0.21, -0.98)) * 5.3 + t * 3.1) * 0.06;
	h *= 0.5 + fbm(p * 0.07 + wind * t * 0.04);
	return h + fbm(vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) * 0.5 + wind * t * 0.3) * 0.3;
}

// view-space distance along the view ray to the scene's depth at `uv`
float scene_dist(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	return length(v.xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float fw = length(fwidth(p));
	float e = 0.12;
	float h = waves(p);
	vec2 g = vec2(waves(p + vec2(e, 0.0)) - h, waves(p + vec2(0.0, e)) - h) / e;
	g *= 1.0 - smoothstep(0.4, 3.0, fw);              // far away the ripples average out
	vec3 n = normalize(vec3(-g.x * ripple, 1.0, -g.y * ripple));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float surface = length(VERTEX);
	// the bed behind the surface, refracted by the ripples (not where that would show something in front of the water)
	vec2 shift = g * refraction / max(surface * 0.08, 1.0);
	vec2 ruv = clamp(SCREEN_UV + shift, vec2(0.002), vec2(0.998));
	float thick = scene_dist(ruv, INV_PROJECTION_MATRIX) - surface;
	if (thick < 0.0) {
		ruv = SCREEN_UV;
		thick = scene_dist(ruv, INV_PROJECTION_MATRIX) - surface;
	}
	thick = max(thick, 0.0);
	// a ray's path through the water is longer than the water is deep at grazing angles: what fades is the path
	vec3 view = normalize(-VERTEX);
	float facing = abs(dot(view, NORMAL));
	float through = exp(-thick * clarity);
	vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;
	float fresnel = pow(1.0 - clamp(facing, 0.0, 1.0), 5.0) * 0.9 + 0.04;
	vec3 water = mix(deep_color, shallow_color, exp(-thick * 0.45));

	// foam along the shore and around whatever stands in the water, broken up by noise
	float foam_n = fbm(p * 1.7 + wind * TIME * 0.5);
	float foam = (1.0 - smoothstep(0.0, foam_width * (0.5 + foam_n), thick * facing)) * step(0.001, thick);
	foam *= smoothstep(0.35, 0.6, foam_n + 0.25) * (1.0 - smoothstep(30.0, 80.0, surface));

	ALBEDO = mix(water * (1.0 - through), vec3(0.95), foam);
	EMISSION = bed * through * (1.0 - fresnel) * (1.0 - foam) * vec3(0.85, 0.95, 0.95);
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = 1.0;
}
