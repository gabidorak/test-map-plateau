// Trees and hedges (milestone M5): soft-toy crowns with baked ambient occlusion, per-lump shading and
// wind sway. Vertex COLOR (baked by blender/trees/treelib.py or vegetation_builder.gd for hedges):
//   r = ambient occlusion, g = lump variation, b = height / tree height, a = part
//   (1 leaves, 0 bark, 0.5 wood stake, 0.25 tie).
// Trees are MultiMesh instances: INSTANCE_CUSTOM = (palette tint in sRGB, wind phase). Hedges are plain
// meshes with use_instance_tint off and their tint as a uniform.
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/toy_noise.gdshaderinc"

uniform bool use_instance_tint = true;
uniform vec3 tint : source_color = vec3(0.33, 0.66, 0.25);
uniform vec3 bark_color : source_color = vec3(0.54, 0.42, 0.31);
uniform vec3 wood_color : source_color = vec3(0.79, 0.64, 0.45);
uniform vec3 tie_color : source_color = vec3(0.29, 0.48, 0.23);
uniform float sway = 0.12;              // metres of model space at the tree top
uniform float flutter = 0.035;          // small leaf ripple along the normal
uniform float ao_strength = 0.6;

varying vec4 data;
varying vec3 leaf_tint;
varying vec3 world_pos;

void vertex() {
	data = COLOR;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = (use_instance_tint ? INSTANCE_CUSTOM.a : 0.0) * 6.2831 + dot(origin.xz, vec2(0.131, 0.071));
	leaf_tint = use_instance_tint ? srgb_to_linear(INSTANCE_CUSTOM.rgb) : tint;
	float h = COLOR.b;
	float w = sin(TIME * 0.9 + phase) * 0.6 + sin(TIME * 2.1 + phase * 1.7) * 0.3;
	VERTEX.xz += vec2(1.0, 0.45) * w * h * h * sway;
	if (COLOR.a > 0.75) {
		vec3 p = VERTEX * 0.9;
		VERTEX += NORMAL * flutter * sin(TIME * 3.1 + phase * 3.0 + p.x + p.y * 1.3 + p.z) * h;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ao = mix(1.0 - ao_strength, 1.0, data.r);
	vec3 c;
	float ao_bark = mix(0.8, 1.0, data.r);
	if (data.a > 0.75) {
		// leaves: each lump a little lighter or darker, sunlit tops warmer, soft speckles
		vec3 base = leaf_tint * (0.86 + 0.28 * data.g);
		base = mix(base * vec3(0.82, 0.88, 0.9), base * vec3(1.08, 1.06, 0.92), smoothstep(0.35, 1.0, data.b));
		float speck = vnoise(world_pos.xz * 2.3 + world_pos.y * 1.7);
		c = base * (0.94 + 0.12 * speck);
		BACKLIGHT = leaf_tint * 0.25;
		ROUGHNESS = 0.82;
		SPECULAR = 0.25;
		RIM = 0.15;
		RIM_TINT = 0.6;
	} else if (data.a > 0.4) {
		c = wood_color * (0.9 + 0.1 * vnoise(world_pos.xy * vec2(3.0, 0.4)));
		ROUGHNESS = 0.9;
	} else if (data.a > 0.1) {
		c = tie_color;
		ROUGHNESS = 0.7;
	} else {
		// bark: soft vertical stripes
		float stripes = vnoise(vec2((world_pos.x + world_pos.z) * 6.0, world_pos.y * 0.7));
		c = bark_color * (0.85 + 0.25 * stripes);
		ROUGHNESS = 0.95;
	}
	ALBEDO = c * (data.a > 0.75 ? ao : ao_bark);
	AO = mix(1.0, data.r, 0.5);
	AO_LIGHT_AFFECT = 0.2;
}
