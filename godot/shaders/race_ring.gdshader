shader_type spatial;
// Race circles (scripts/race_marks.gd): a ring draped on the ground (part 0, UV.y across it), a wall of light rising
// from it (part 1, UV.y up it, fading out) and, for the start circles, a faint disc filling it (part 2, UV.y from the
// centre out) swept by a brighter edge going round; UV.x goes once round. Dashes chase each other round the start
// circles, the checkpoint gates are plain, the finish is chequered.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform int part = 0;                       // 0 ground ring, 1 wall, 2 disc
uniform int pattern = 0;                    // 0 chasing dashes, 1 plain, 2 chequered
uniform float segments = 24.0;              // dashes (or squares) round the circle
uniform float spin = 0.08;                  // turns per second the dashes go round
uniform float strength = 1.0;               // the checkpoint after the next is dimmer

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float pulse = 0.8 + 0.2 * sin(TIME * 3.0);
	vec3 c = color.rgb;
	if (pattern == 2) {
		float check = mod(floor(u * segments) + floor(v * (part == 0 ? 2.0 : 6.0)), 2.0);
		c = mix(vec3(0.06), vec3(1.0), check);
	}
	float a;
	if (part == 0) {
		float dash = step(0.4, fract(u * segments - TIME * spin * segments));
		a = (pattern == 0 ? mix(0.35, 1.0, dash) : 0.95) * pulse;
	} else if (part == 1) {
		float fade = 1.0 - v;
		float rise = 0.75 + 0.25 * sin((v * 4.0 - TIME * 1.5) * 6.2832);
		float dash = pattern == 0 ? mix(0.5, 1.0, step(0.4, fract(u * segments - TIME * spin * segments))) : 1.0;
		a = fade * rise * dash * 0.85 * pulse;
	} else {
		float sweep = pow(fract(u - TIME * 0.12), 5.0);
		a = (0.1 + 0.25 * sweep) * smoothstep(0.0, 0.6, v);
	}
	ALBEDO = c;
	ALPHA = clamp(a * strength * color.a, 0.0, 1.0);
}
