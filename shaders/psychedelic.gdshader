shader_type canvas_item;
// Full-screen post-process. `intensity` (0..1) is driven by GameManager's
// psychedelic_intensity and forced to 0 during instant replays.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_seconds = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

vec2 rotate(vec2 uv, float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c)) * uv;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * hash21(floor(p));
		p *= 2.02;
		amp *= 0.5;
	}
	return v;
}

vec3 hue_shift(vec3 color, float shift) {
	const vec3 k = vec3(0.57735);
	float c = cos(shift);
	float s = sin(shift);
	return color * c + cross(k, color) * s + k * dot(k, color) * (1.0 - c);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;

	// Kaleidoscope fold grows in with intensity.
	float segments = mix(1.0, 7.0, intensity);
	float angle = atan(centered.y, centered.x);
	float radius = length(centered);
	float folded_angle = mod(angle, TAU / segments);
	folded_angle = abs(folded_angle - TAU / segments * 0.5);
	vec2 kaleido_uv = vec2(cos(folded_angle), sin(folded_angle)) * radius + 0.5;
	uv = mix(uv, kaleido_uv, intensity * 0.85);

	// Gentle swirl on top of the fold.
	uv = rotate(uv - 0.5, sin(time_seconds * 0.3) * intensity * 0.5) + 0.5;

	// Chromatic aberration.
	float ab = intensity * 0.012;
	vec2 dir = normalize(centered + 0.0001);
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ab).b;

	// Cycling hue rotation.
	col = hue_shift(col, time_seconds * intensity * 1.5);

	// Fractal-ish noise tint, blended in by intensity.
	float n = fbm(uv * 9.0 + time_seconds * 0.6);
	vec3 psychedelic_tint = vec3(
		0.5 + 0.5 * sin(time_seconds * 1.7 + n * 6.28),
		0.5 + 0.5 * sin(time_seconds * 1.3 + n * 6.28 + 2.0),
		0.5 + 0.5 * sin(time_seconds * 2.1 + n * 6.28 + 4.0)
	);
	col = mix(col, col + psychedelic_tint * 0.6, intensity * 0.6);

	// Saturation boost.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 1.0 + intensity * 1.5);

	COLOR = vec4(col, 1.0);
}
