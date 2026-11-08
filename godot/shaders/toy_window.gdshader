// Window panes drawn as geometry (builder/logements_x_builder.gd): the sky-reflecting glass of toy_building.gdshader
// over a dark room by day, about 40 % of the rooms lit at night (fewer in a power cut: global `power`).
// Vertex COLOR.rgb = a tint over the reflection (dark grey glass; white curtains show lighter), COLOR.a = the pane's
// random draw
// (lit when below lit_share * power).
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/toy_noise.gdshaderinc"

uniform vec4 glass_sky_color : source_color = vec4(0.61, 0.79, 0.93, 1.0);
uniform vec4 glass_deep_color : source_color = vec4(0.18, 0.29, 0.39, 1.0);
uniform vec4 room_light : source_color = vec4(1.0, 0.7, 0.38, 1.0);
uniform float lit_share = 0.4;
uniform float lit_energy = 1.4;
global uniform float night;
global uniform float power;

varying vec4 data;
varying vec3 wpos;

void vertex() {
	data = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	// the sky's reflection brighter towards the top of the pane and at grazing angles
	float up = clamp(0.35 + 0.5 * fres + 0.08 * sin(wpos.y * 0.9 + wpos.x * 0.3), 0.0, 1.0);
	vec3 refl = mix(srgb_to_linear(glass_deep_color.rgb), srgb_to_linear(glass_sky_color.rgb), up);
	vec3 tint = srgb_to_linear(data.rgb);
	vec3 day = refl * tint;
	vec3 dark = refl * 0.12;
	bool lit = data.a < lit_share * power;
	ALBEDO = mix(day, dark, night);
	ROUGHNESS = 0.08;
	SPECULAR = 0.65;
	METALLIC = 0.0;
	if (lit) {
		EMISSION = srgb_to_linear(room_light.rgb) * mix(vec3(1.0), tint, 0.25) * lit_energy * night;
	}
}
