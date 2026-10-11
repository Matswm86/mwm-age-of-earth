// Shared by terrain.gdshader and grass.gdshader: where grass grows, so the ground under the blades
// and the blades agree. biome (tools/game/bake_biome.py): R forest, G lush, B path, A reeds.
// ground_tex G = trampled camp floor; shore_m = metres to the waterline; rock = splat_a B.

// 0..1 value noise from a hash, for patchy colour (no texture fetch)
// (hash12 without sin: sin() of large world coordinates loses fp32 precision and turned the
// noise into flat boxes with straight edges, seen 2026-10-11)
float bhash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = bhash(i);
	float b = bhash(i + vec2(1.0, 0.0));
	float c = bhash(i + vec2(0.0, 1.0));
	float d = bhash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// camp floors fray at the edge (patchy grass, not a clean disc)
float frayed(float trample, vec2 xz) {
	// noise only on the rim (0..0.7): inside a floor nothing may fray (stray blades, 2026-10-11)
	float rim = smoothstep(0.0, 0.3, trample) * (1.0 - smoothstep(0.55, 0.8, trample));
	return clamp(trample + (bnoise(xz * 0.45) - 0.5) * 0.7 * rim, 0.0, 1.0);
}

float grass_density(vec4 biome, float trample, float shore_m, float rock, vec2 xz) {
	float d = 1.0;
	trample = frayed(trample, xz);
	// grass is fully gone before the dirt (terrain.gdshader) shows: no blades on paths or floors
	d *= 1.0 - smoothstep(0.04, 0.22, biome.b);
	d *= 1.0 - 0.55 * smoothstep(0.45, 0.95, biome.r);
	d *= 1.0 - smoothstep(0.06, 0.3, trample);
	d *= smoothstep(1.2, 3.5, shore_m);
	d *= 1.0 - 0.35 * smoothstep(0.6, 1.0, rock);
	return clamp(d, 0.0, 1.0);
}

// grass colour at a world point: sun-cured gold to fresh green by lushness, broken into patches
vec3 grass_colour(vec2 xz, float lush, vec3 dry, vec3 green, vec3 fresh) {
	float n = bnoise(xz * 0.09) * 0.6 + bnoise(xz * 0.33) * 0.4;
	float g = clamp(lush * 1.25 - 0.2 + (n - 0.5) * 0.7, 0.0, 1.0);
	vec3 c = mix(dry, green, smoothstep(0.15, 0.85, g));
	c = mix(c, fresh, smoothstep(0.75, 1.0, g) * 0.6);
	// value variation: lush stands are darker, dry stands lighter (patches 5-15 m, plus fine mottling)
	float v = mix(1.12, 0.78, smoothstep(0.3, 0.9, g)) * mix(0.82, 1.12, bnoise(xz * 0.7));
	return c * v;
}
