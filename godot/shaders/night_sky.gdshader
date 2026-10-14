// Night sky (scripts/night.gd): a dark blue gradient, stars and the moon, a disc where the moonlight (the
// scene's directional light, LIGHT0) comes from, with a soft halo. The radiance passes (reflections, ambient light)
// leave the stars out. No TIME (no twinkling): it would make Godot redraw the radiance every frame.
shader_type sky;
render_mode use_debanding;

uniform vec4 zenith_color : source_color = vec4(0.012, 0.02, 0.05, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.1, 0.13, 0.22, 1.0);
uniform vec4 glow_color : source_color = vec4(0.2, 0.17, 0.2, 1.0);  // the towns around, low over the horizon
uniform vec4 ground_color : source_color = vec4(0.1, 0.12, 0.19, 1.0);   // under the horizon, past the map's edge
uniform float star_scale = 140.0;           // grid cells across a radian: the smaller, the bigger and fewer the stars
uniform float star_share = 0.07;            // of the cells holding a star
uniform float star_energy = 6.0;
uniform vec4 moon_color : source_color = vec4(0.92, 0.94, 1.0, 1.0);
uniform float moon_radius = 0.035;          // rad, about 4x the real moon: a toy one
uniform float moon_energy = 2.2;
uniform float halo_energy = 0.25;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float stars(vec3 d) {
	vec3 p = d * star_scale;
	vec3 cell = floor(p);
	// a star (radius 0.32 cell) reaches at most the neighbours across the nearest faces: 8 cells
	vec3 side = sign(fract(p) - 0.5);
	float s = 0.0;
	for (int i = 0; i < 8; i++) {
		vec3 c = cell + side * vec3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
		float h = hash13(c);
		if (h > star_share) continue;
		vec3 at = c + hash33(c);
		float r = length(p - at);
		float bright = pow(h / star_share, 3.0);    // a few bright ones, many faint
		s += smoothstep(0.32, 0.0, r) * (0.06 + bright);
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col = mix(horizon_color.rgb, zenith_color.rgb, pow(clamp(up, 0.0, 1.0), 0.45));
	col += glow_color.rgb * exp(-max(up, 0.0) * 14.0);
	col = mix(ground_color.rgb, col, smoothstep(-0.06, 0.0, up));
	if (!AT_CUBEMAP_PASS) {
		col += vec3(0.85, 0.9, 1.0) * stars(d) * star_energy * smoothstep(0.02, 0.3, up);
	}
	if (LIGHT0_ENABLED) {
		float a = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		col += moon_color.rgb * halo_energy * (exp(-a * a / 0.004) + 0.3 * exp(-a * a / 0.06));
		if (a < moon_radius * 1.05) {
			// a lit disc with darker seas
			vec3 side = normalize(cross(LIGHT0_DIRECTION, vec3(0.0, 1.0, 0.0)));
			vec3 top = cross(side, LIGHT0_DIRECTION);
			vec2 q = vec2(dot(d, side), dot(d, top)) / moon_radius;
			float seas = smoothstep(0.35, 0.2, length(q - vec2(-0.25, 0.2))) * 0.25
					+ smoothstep(0.3, 0.15, length(q - vec2(0.3, -0.15))) * 0.2
					+ smoothstep(0.22, 0.1, length(q - vec2(0.05, -0.45))) * 0.15;
			vec3 disc = moon_color.rgb * moon_energy * (1.0 - seas) * (1.0 - 0.25 * dot(q, q));
			col = mix(col, disc, smoothstep(moon_radius * 1.05, moon_radius * 0.97, a));
		}
	}
	COLOR = col;
}
