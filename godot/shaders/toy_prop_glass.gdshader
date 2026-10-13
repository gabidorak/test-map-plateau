// Street furniture (milestone M6): glass panes and water of the props (bus shelters, fountains), a light
// tinted transparent surface with a soft sky reflection. Vertex COLOR.rgb = tint in sRGB.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley;

#include "res://shaders/toy_noise.gdshaderinc"

uniform float opacity = 0.32;

varying vec3 tint;

void vertex() {
	tint = srgb_to_linear(COLOR.rgb);
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tint;
	ALPHA = clamp(opacity + 0.45 * fres, 0.0, 0.9);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
