shader_type spatial;
render_mode unshaded, cull_front, blend_premul_alpha, depth_draw_never, depth_test_disabled;

// Intro atmosphere: physically based single scattering (Rayleigh + Mie + ozone absorption),
// ray-marched per pixel through a 100 km shell. Drawn on the back faces of the shell so it
// works from space and from inside. The march stops at the scene depth (ground, rift patch),
// so it gives both the blue limb seen from orbit and the aerial haze over the rift.
// Output is premultiplied: in-scattered light + (1 - alpha) x what is behind, with alpha =
// 1 - mean transmittance (grey extinction).

#include "res://shaders/earth_common.gdshaderinc"

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float sun_power = 1.0;
uniform sampler2D transmittance_lut : filter_linear, repeat_disable;
// in-scatter brightness relative to the lit ground (artistic exposure match)
uniform float scatter_gain = 1.0;
uniform int view_steps = 16;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(wpos - ro);
	vec2 ha = ray_sphere(ro, rd, ATMOS_R);
	if (ha.x > ha.y || ha.y < 0.0) {
		discard;
	}
	float t0 = max(ha.x, 0.0);
	float t1 = ha.y;
	vec2 hp = ray_sphere(ro, rd, PLANET_R);
	if (hp.x < hp.y && hp.x > 0.0) {
		t1 = min(t1, hp.x);
	}
	// scene depth (reverse Z: 0 = nothing drawn)
	float z = texture(depth_tex, SCREEN_UV).r;
	if (z > 0.0) {
		vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
		vp.xyz /= vp.w;
		t1 = min(t1, length(vp.xyz));
	}
	if (t1 <= t0) {
		discard;
	}
	float dt = (t1 - t0) / float(view_steps);
	// interleaved gradient noise jitters the samples (no banding from the few steps)
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	vec3 od = vec3(0.0);
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	for (int i = 0; i < view_steps; i++) {
		vec3 p = ro + rd * (t0 + dt * (float(i) + 0.5 + (jit - 0.5) * 0.35));
		float h = length(p) - PLANET_R;
		vec3 d = atmos_density(h) * dt;
		od += d * 0.5;
		vec3 ts = sun_transmittance_lut(transmittance_lut, p, sun_dir);
		vec3 tv = extinction_of(od);
		od += d * 0.5;
		vec3 att = ts * tv;
		sum_r += att * d.x;
		sum_m += att * d.y;
	}
	float c = dot(rd, sun_dir);
	vec3 inscatter = (sum_r * BETA_R * phase_rayleigh(c) + sum_m * BETA_M * phase_mie(c));
	inscatter *= sun_power * scatter_gain * PI;
	vec3 trans = extinction_of(od);
	ALBEDO = inscatter;
	ALPHA = clamp(1.0 - dot(trans, vec3(0.3333)), 0.0, 1.0);
}
