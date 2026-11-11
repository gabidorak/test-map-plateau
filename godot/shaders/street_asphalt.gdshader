// The streets' asphalt drawn by code (scripts/build_kit.gd "street_asphalt": the supermarket's block, Losplatos
// Custom's site): the map's road asphalt (toy_ground.gdshader), its pattern in world space, so they join seamlessly.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toy_noise.gdshaderinc"

uniform vec3 colour = vec3(0.388, 0.4, 0.42);      // sRGB: the palette's asphalt (pipeline/palette.toml, #63666b)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	ALBEDO = srgb_to_linear(clamp(ground_asphalt(colour, p, length(fwidth(p))), 0.0, 1.0));
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
}
