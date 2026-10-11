// Shared physics for the opening intro (planet, clouds, rift patch, atmosphere).
// Units: kilometres, planet centre at the world origin. Earth-fixed frame:
// dir(lat, lon) = (cos lat cos lon, sin lat, -cos lat sin lon); +Y = north pole.
// Single-scattering constants after Bruneton & Neyret 2008 / Hillaire 2020 (sea-level values).

const float PLANET_R = 6371.0;
const float ATMOS_R = 6471.0;
const vec3 BETA_R = vec3(5.802e-3, 13.558e-3, 33.1e-3);
const float BETA_M = 3.996e-3;
const float BETA_M_EXT = 4.44e-3;
const vec3 BETA_O = vec3(0.650e-3, 1.881e-3, 0.085e-3);
const float H_R = 8.0;
const float H_M = 1.2;
const float MIE_G = 0.8;

// t of the near and far hit of a ray with a sphere at the origin; x > y means no hit.
vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float d = b * b - c;
	if (d < 0.0) {
		return vec2(1e9, -1e9);
	}
	float s = sqrt(d);
	return vec2(-b - s, -b + s);
}

// Density of Rayleigh, Mie and ozone at height h (km) above sea level.
vec3 atmos_density(float h) {
	float o = max(0.0, 1.0 - abs(h - 25.0) / 15.0);
	return vec3(exp(-h / H_R), exp(-h / H_M), o);
}

vec3 extinction_of(vec3 od) {
	return exp(-(BETA_R * od.x + BETA_M_EXT * od.y + BETA_O * od.z));
}

// Optical depth from p towards the sun, to the top of the atmosphere. Zero light when the
// planet is in the way (soft over 2 km so the terminator does not alias).
vec3 sun_optical_depth(vec3 p, vec3 s, int steps) {
	vec2 hit = ray_sphere(p, s, ATMOS_R);
	float len = max(hit.y, 0.0);
	float dt = len / float(steps);
	vec3 od = vec3(0.0);
	for (int i = 0; i < steps; i++) {
		vec3 q = p + s * (dt * (float(i) + 0.5));
		od += atmos_density(length(q) - PLANET_R) * dt;
	}
	return od;
}

// Transmittance of sunlight arriving at p (km, world), including planet shadow.
vec3 sun_transmittance(vec3 p, vec3 s, int steps) {
	float r = length(p);
	float mu = dot(p / r, s);
	// cosine of the horizon angle at this height
	float mu_h = -sqrt(max(0.0, 1.0 - (PLANET_R * PLANET_R) / (r * r)));
	float lit = smoothstep(mu_h - 0.004, mu_h + 0.004, mu);
	return extinction_of(sun_optical_depth(p, s, steps)) * lit;
}

// Same as sun_transmittance, read from the precomputed table (scripts/IntroAtmosphere.gd):
// u = cos of the sun zenith angle mapped -1..1 -> 0..1, v = sqrt(height / 100 km).
vec3 sun_transmittance_lut(sampler2D lut, vec3 p, vec3 s) {
	float r = length(p);
	float mu = dot(p / r, s);
	float mu_h = -sqrt(max(0.0, 1.0 - (PLANET_R * PLANET_R) / (r * r)));
	float lit = smoothstep(mu_h - 0.004, mu_h + 0.004, mu);
	float h = clamp((r - PLANET_R) / (ATMOS_R - PLANET_R), 0.0, 1.0);
	vec2 uv = vec2(mu * 0.5 + 0.5, sqrt(h));
	return textureLod(lut, uv, 0.0).rgb * lit;
}

float phase_rayleigh(float c) {
	return 3.0 / (16.0 * PI) * (1.0 + c * c);
}

float phase_mie(float c) {
	float g = MIE_G;
	float gg = g * g;
	return 3.0 / (8.0 * PI) * ((1.0 - gg) * (1.0 + c * c))
		/ ((2.0 + gg) * pow(max(1.0 + gg - 2.0 * g * c, 1e-4), 1.5));
}

// Earth-fixed lat/lon (radians) of a unit vector.
vec2 latlon_of(vec3 n) {
	return vec2(asin(clamp(n.y, -1.0, 1.0)), atan(-n.z, n.x));
}

// Weight 1 inside a lat/lon box (radians: lon0, lat0, lon1, lat1), fading over `feather`
// (fraction of the box size) at the edges.
float box_weight(vec2 ll, vec4 box, float feather) {
	vec2 uv = vec2((ll.y - box.x) / (box.z - box.x), (ll.x - box.y) / (box.w - box.y));
	vec2 e = smoothstep(vec2(0.0), vec2(feather), uv) * smoothstep(vec2(0.0), vec2(feather), 1.0 - uv);
	return e.x * e.y;
}

vec2 box_uv(vec2 ll, vec4 box) {
	return vec2((ll.y - box.x) / (box.z - box.x), (box.w - ll.x) / (box.w - box.y));
}

// Cloud cover 0..1 at a point (Blue Marble cloud map, two drifting copies, thinned round the
// dive target). `hole` = lat, lon, radius (radians). Used for cloud shadows on the ground.
float cloud_cover(sampler2D tex, vec3 n, vec2 shift, vec3 hole) {
	vec2 ll = latlon_of(n);
	vec2 uv = vec2(ll.y / TAU + 0.5, 0.5 - ll.x / PI);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	float a = textureGrad(tex, uv + vec2(shift.x, 0.0), dx, dy).r;
	float b = textureGrad(tex, uv + vec2(shift.y, 0.004), dx, dy).r;
	float c = mix(a, b, 0.4);
	c -= 0.8 * (1.0 - smoothstep(hole.z * 0.2, hole.z * 2.0, distance(ll, hole.xy)));
	return smoothstep(0.1, 0.85, c);
}

// Cheap value noise + fbm for small-scale cloud detail.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s;
}

// GGX specular for water (sun glint), returns the reflected fraction of sun irradiance.
float ggx_spec(vec3 n, vec3 v, vec3 l, float rough) {
	vec3 h = normalize(v + l);
	float nh = max(dot(n, h), 0.0);
	float nl = max(dot(n, l), 0.0);
	float nv = max(dot(n, v), 1e-3);
	float a2 = rough * rough * rough * rough;
	float d = a2 / (PI * pow(nh * nh * (a2 - 1.0) + 1.0, 2.0));
	float k = rough * rough * 0.5;
	float g = nl / (nl * (1.0 - k) + k) * nv / (nv * (1.0 - k) + k);
	float f = 0.02 + 0.98 * pow(1.0 - max(dot(v, h), 0.0), 5.0);
	return d * g * f / max(4.0 * nv, 1e-3);
}
