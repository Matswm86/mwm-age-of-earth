shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;

// Intro cloud layer: a shell `cloud_alt` km above the surface with NASA Blue Marble cloud
// imagery. Two copies drift at different speeds so the cover slowly changes shape. Lit by the
// sun through the atmosphere (pink-orange at the terminator), forward-scatter brightening near
// the sun, sky-blue fill. Small-scale fbm erosion fades in when the camera gets close.

#include "res://shaders/earth_common.gdshaderinc"

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float sun_power = 1.0;
uniform sampler2D transmittance_lut : filter_linear, repeat_disable;
uniform sampler2D clouds : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 cloud_shift = vec2(0.0);
uniform vec3 clear_hole = vec3(0.0, 0.0, 0.0);
uniform float detail = 0.0;
uniform float opacity = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(wpos);
	vec2 ll = latlon_of(n);
	vec2 uv = vec2(ll.y / TAU + 0.5, 0.5 - ll.x / PI);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	dx.x -= round(dx.x);
	dy.x -= round(dy.x);
	float a = textureGrad(clouds, uv + vec2(cloud_shift.x, 0.0), dx, dy).r;
	float b = textureGrad(clouds, uv + vec2(cloud_shift.y, 0.004), dx, dy).r;
	float c = mix(a, b, 0.4);
	if (detail > 0.0) {
		float f = fbm(uv * vec2(4096.0, 2048.0) + vec2(TIME * 0.02, 0.0));
		c = mix(c, c * smoothstep(0.25, 0.75, f + c * 0.5), detail);
	}
	float hole_d = distance(ll, clear_hole.xy);
	// thin the cover towards the target (organic edge, no visible ring)
	c -= 0.8 * (1.0 - smoothstep(clear_hole.z * 0.2, clear_hole.z * 2.0, hole_d));
	float alpha = smoothstep(0.1, 0.85, c) * opacity;

	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float nl = dot(n, sun_dir);
	vec3 tsun = sun_transmittance_lut(transmittance_lut, n * (PLANET_R + 6.0), sun_dir) * sun_power;
	// thick cloud: wrap lighting, darker where dense (self-shadow), silver lining towards the sun
	float wrap = clamp(nl * 0.85 + 0.15, 0.0, 1.0) * smoothstep(-0.04, 0.08, nl);
	float dens = smoothstep(0.4, 1.0, c);
	float fwd = phase_mie(dot(-v, sun_dir)) * 0.35;
	vec3 sky = vec3(0.06, 0.1, 0.18) * smoothstep(-0.02, 0.3, nl) * sun_power;
	vec3 col = tsun * (wrap * (0.95 - 0.25 * dens) + fwd * (1.0 - dens)) + sky;
	ALBEDO = col;
	ALPHA = alpha;
}
