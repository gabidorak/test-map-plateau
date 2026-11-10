shader_type spatial;
// Villa Luxe's water (scripts/villa/villa_kit.gd): mode 0 a pool or basin's surface (clear, tinted, rippling),
// 1 a falling sheet (the fountain's cascade: white streaks running down), 2 foam (where it falls in).
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform int mode = 0;
uniform vec4 tint : source_color = vec4(0.18, 0.66, 0.74, 1.0);

varying vec3 pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	pos = VERTEX;
}

void fragment() {
	if (mode == 0) {
		vec2 p = pos.xz;
		float t = TIME;
		float a = sin(p.x * 2.3 + t * 1.3) * 0.5 + sin(p.y * 1.9 - t * 1.1) * 0.5;
		float b = noise(p * 1.6 + vec2(t * 0.35, t * 0.2)) - 0.5;
		float c = noise(p * 3.1 - vec2(t * 0.25, -t * 0.3)) - 0.5;
		vec3 n = normalize(vec3(a * 0.06 + b * 0.35, 1.0, c * 0.35 + a * 0.04));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		float caustic = pow(noise(p * 2.5 + vec2(t * 0.4, t * 0.3)), 3.0) * 0.25;
		ALBEDO = tint.rgb + vec3(caustic);
		ROUGHNESS = 0.04;
		METALLIC = 0.0;
		SPECULAR = 0.7;
		ALPHA = 0.72;
	} else if (mode == 1) {
		float across = pos.x * 9.0 + pos.z * 9.0;
		float s = noise(vec2(across, pos.y * 1.5 + TIME * 3.2));
		float s2 = noise(vec2(across * 2.3 + 7.0, pos.y * 3.0 + TIME * 4.5));
		float w = smoothstep(0.35, 0.9, s * 0.6 + s2 * 0.5);
		ALBEDO = mix(vec3(0.62, 0.8, 0.84), vec3(0.97, 0.99, 1.0), w);
		ROUGHNESS = 0.15;
		SPECULAR = 0.6;
		ALPHA = 0.45 + w * 0.45;
	} else {
		float f = noise(pos.xz * 6.0 + vec2(TIME * 1.7, -TIME * 1.3)) * noise(pos.xz * 2.2 - vec2(TIME * 0.6));
		ALBEDO = vec3(0.96, 0.98, 1.0);
		ROUGHNESS = 0.5;
		ALPHA = smoothstep(0.08, 0.4, f) * 0.85;
	}
}
