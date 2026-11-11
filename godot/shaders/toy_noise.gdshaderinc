// Small procedural helpers shared by the toy shaders (ground, grass). World-space inputs in metres.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// three octaves, roughly 0..1
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int k = 0; k < 3; k++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 5.3);
		a *= 0.5;
	}
	return s / 0.875;
}

// Jittered dots on a unit grid: x = distance to the nearest dot centre (grid units), y = its random id,
// zw = offset from that centre (for bumps).
vec4 dots(vec2 p, float jitter) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	vec2 off = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 d = f - (g + 0.5 + (hash22(i + g) - 0.5) * jitter);
			float dd = dot(d, d);
			if (dd < best) {
				best = dd;
				id = hash12(i + g + 7.7);
				off = d;
			}
		}
	}
	return vec4(sqrt(best), id, off);
}

// Two-tone toy grass colour from the palette colour (shared by the ground and the grass tufts so
// the tufts sit on ground of the same shade).
vec3 grass_tone(vec2 p, vec3 base) {
	float t = smoothstep(0.38, 0.62, fbm(p * 0.09 + vec2(3.1, 7.7)));
	vec3 dark = base * vec3(0.84, 0.9, 0.82);
	vec3 light = base * vec3(1.08, 1.07, 0.9) + vec3(0.03, 0.025, 0.0);
	return mix(dark, light, t);
}

// The roads' asphalt (toy_ground.gdshader; the streets drawn by code, street_asphalt.gdshader: they join seamlessly),
// colour c (sRGB) at world point p (xz), fw a pixel's footprint there.
vec3 ground_asphalt(vec3 c, vec2 p, float fw) {
	float fine = 1.0 - smoothstep(0.022, 0.077, fw);          // (the 0.11 m stones resolved)
	float finest = 1.0 - smoothstep(0.0066, 0.0231, fw);      // (the 0.033 m grain)
	vec3 col = c * (0.93 + 0.12 * fbm(p * 0.22));
	col *= 1.0 - 0.07 * smoothstep(0.62, 0.7, fbm(p * 0.06 + 3.0));      // repaired patches
	vec4 d = dots(p * 9.0, 1.0);
	float s = (1.0 - smoothstep(0.12, 0.32, d.x)) * fine;
	col *= 1.0 + (d.y - 0.5) * 0.3 * s;
	col *= 1.0 + (vnoise(p * 30.0) - 0.5) * 0.1 * finest;
	return col;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
