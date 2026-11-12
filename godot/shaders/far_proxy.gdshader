// The buildings' far shapes (scripts/builder/far_proxy.gd: the map's, the railway's, the lots'): their colour
// (COLOR, sRGB) flat by day; at night their walls glow with lit rooms as the near buildings' do (toy_building.gdshader:
// the same share lit, the same power cut), a window every 3 m, a floor every 3 m, faded to their average once a pixel
// covers several.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/toy_noise.gdshaderinc"

uniform vec4 room_light : source_color = vec4(1.0, 0.7, 0.38, 1.0);   // lit rooms at night (toy_building's)
uniform float lit_share = 0.4;          // of the rooms lit at night (toy_building's)
global uniform float night;
global uniform float power;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = srgb_to_linear(clamp(COLOR.rgb, 0.0, 1.0));
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
	if (night > 0.001 && abs(wnrm.y) < 0.5) {
		vec2 q = vec2(dot(wpos.xz, normalize(vec2(-wnrm.z, wnrm.x))), wpos.y) / 3.0;
		vec2 f = fract(q);
		float window = step(0.25, f.x) * step(f.x, 0.75) * step(0.35, f.y) * step(f.y, 0.75);
		float lit = step(1.0 - lit_share * power, hash12(floor(q) + floor(wpos.xz / 97.0)));
		float fw = length(fwidth(q));
		float near = 1.0 - smoothstep(0.15, 0.5, fw);
		float average = lit_share * power * 0.2;
		EMISSION = room_light.rgb * night * 0.85 * mix(average * 0.8, lit * window * 0.7, near);
	}
}
