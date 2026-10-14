// Street furniture (milestone M6): soft-toy props with baked colours and ambient occlusion.
// Vertex COLOR (blender/toylib.py) = (toy colour in sRGB, ambient occlusion). One material per slot, told
// apart by `mode`: 0 toy, 1 tint (colour x INSTANCE_CUSTOM.rgb), 2 glow (lamp diffusers, ad panels),
// 3 car signal lenses, 4 pedestrian signal lenses. MultiMesh INSTANCE_CUSTOM = (tint in sRGB, phase):
// signals run a 30 s cycle offset by the phase (car: green, amber, red; pedestrians green while cars are red), on
// the game's shared clock: the global `signal_clock` (scripts/traffic.gd, which runs the same cycle for the bot buses).
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://shaders/toy_noise.gdshaderinc"

uniform int mode = 0;
uniform float glow_energy = 1.2;
uniform float signal_energy = 4.0;
uniform float cycle = 30.0;
global uniform float signal_clock;
uniform float ao_strength = 0.55;

varying vec4 data;
varying flat vec4 inst;

void vertex() {
	data = COLOR;
	inst = INSTANCE_CUSTOM;
}

// which lamp a lens is (0 red, 1 amber, 2 green) and whether it is lit at cycle time t
bool lit(vec3 c, float t, bool ped) {
	int lamp = c.g > c.r ? 2 : (c.g > 0.5 ? 1 : 0);
	if (ped) {
		bool walk = t > 0.6 && t < 0.92;
		return lamp == 2 ? walk : !walk;
	}
	if (lamp == 2) return t < 0.45;
	if (lamp == 1) return t >= 0.45 && t < 0.55;
	return t >= 0.55;
}

void fragment() {
	vec3 c = srgb_to_linear(data.rgb);
	float ao = data.a;
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	if (mode == 1) {
		c *= srgb_to_linear(inst.rgb);
	}
	if (mode == 2) {
		ALBEDO = c;
		EMISSION = c * glow_energy;
	} else if (mode >= 3) {
		bool on = lit(data.rgb, fract(signal_clock / cycle + inst.a), mode == 4);
		ALBEDO = on ? c : c * 0.18;
		EMISSION = on ? c * signal_energy : vec3(0.0);
		ROUGHNESS = 0.2;
	} else {
		ALBEDO = c * mix(1.0 - ao_strength, 1.0, ao);
		AO = mix(1.0, ao, 0.5);
		AO_LIGHT_AFFECT = 0.2;
		RIM = 0.08;
	}
}
