shader_type canvas_item;

// Cloud veil for the descent through the cloud deck. Five sheets of fbm cloud at increasing
// depth; each sheet grows from the screen centre as the camera flies into it and fades out as
// it passes the lens, so puffs stream outwards like a real fly-through. Lit from the sun side
// (upper left), grey-blue in the shadowed folds. `amount` 0..1 is driven by scripts/Intro.gd;
// at 1 the screen is solid cloud, which hides the switch from planet scale to the local map.

uniform float amount = 0.0;
uniform float travel = 0.0;
uniform vec2 sun_screen = vec2(-0.6, -0.5);

const int SHEETS = 4;

// integer lattice hash (no precision streaks at large coordinates)
float hash12(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 5.3);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 q = (SCREEN_UV - 0.5) * aspect;
	vec3 acc = vec3(0.0);
	float a_acc = 0.0;
	// back to front
	for (int k = SHEETS - 1; k >= 0; k--) {
		float ph = fract(travel * 0.35 + float(k) / float(SHEETS));
		float z = mix(4.0, 0.25, ph);
		float seed = mod(floor(travel * 0.35 + float(k) / float(SHEETS)), 16.0) * 7.31 + float(k) * 3.7;
		vec2 p = q * z * 2.2 + vec2(seed, seed * 0.61);
		float n = fbm(p);
		float d = smoothstep(0.42, 0.78, n + (amount - 0.5) * 0.6);
		// fade in from the distance, out as the sheet reaches the lens
		float life = smoothstep(0.0, 0.25, ph) * (1.0 - smoothstep(0.75, 1.0, ph));
		float a = d * life * smoothstep(0.0, 0.3, amount);
		// light: sun-side edges brighter (one extra noise tap, not a second fbm)
		float side = vnoise(p * 2.0 + sun_screen * 0.6);
		float lit = clamp(0.35 + 0.7 * n + 0.25 * (side - 0.5) + 0.2 * dot(q, -sun_screen), 0.0, 1.0);
		vec3 col = mix(vec3(0.6, 0.65, 0.73), vec3(1.0, 0.98, 0.94), lit);
		acc = col * a + acc * (1.0 - a);
		a_acc = a + a_acc * (1.0 - a);
	}
	// solid white-out at the peak
	float solid = smoothstep(0.82, 1.0, amount);
	acc = mix(acc, vec3(0.9, 0.92, 0.95), solid * (1.0 - a_acc));
	a_acc = mix(a_acc, 1.0, solid);
	COLOR = vec4(acc / max(a_acc, 1e-3), a_acc);
}
