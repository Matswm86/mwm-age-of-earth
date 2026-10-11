shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Intro planet surface (km, planet at the origin). Albedo layers, finest wins where it exists:
// NASA Blue Marble NG global (16k or 8k) -> Blue Marble 500 m East Africa crop -> Sentinel-2
// cloudless 2016 rift mosaic. Lit by the sun through the atmosphere (sunset colours at the
// terminator), cloud shadows, GGX sun glint and sky reflection on the ocean. The atmosphere
// shell (earth_atmosphere.gdshader) adds in-scatter and extinction on top.

#include "res://shaders/earth_common.gdshaderinc"

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float sun_power = 1.0;
uniform sampler2D transmittance_lut : filter_linear, repeat_disable;
uniform sampler2D albedo_global : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ocean_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_region : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 region_box;
uniform sampler2D albedo_s2 : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 s2_box;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
// cloud texture u offsets of the two drifting layers (set by scripts/Intro.gd)
uniform vec2 cloud_shift = vec2(0.0);
uniform float cloud_alt = 6.0;
uniform float cloud_shadow = 0.6;
// lat, lon (radians), radius (radians) of the clear-sky hole over the dive target
uniform vec3 clear_hole = vec3(0.0, 0.0, 0.0);
uniform float land_gain = 1.0;
uniform float ocean_rough = 0.22;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 wrap_grad(vec2 g) {
	return vec2(g.x - round(g.x), g.y);
}

void fragment() {
	vec3 n = normalize(wpos);
	vec2 ll = latlon_of(n);
	vec2 uv = vec2(ll.y / TAU + 0.5, 0.5 - ll.x / PI);
	vec2 dx = wrap_grad(dFdx(uv));
	vec2 dy = wrap_grad(dFdy(uv));
	vec3 col = textureGrad(albedo_global, uv, dx, dy).rgb;
	float water = textureGrad(ocean_mask, uv, dx, dy).r;
	vec2 ruv = box_uv(ll, region_box);
	vec2 rdx = dFdx(ruv);
	vec2 rdy = dFdy(ruv);
	vec2 suv = box_uv(ll, s2_box);
	vec2 sdx = dFdx(suv);
	vec2 sdy = dFdy(suv);
	float wr = box_weight(ll, region_box, 0.08);
	if (wr > 0.0) {
		col = mix(col, textureGrad(albedo_region, ruv, rdx, rdy).rgb, wr);
	}
	float ws = box_weight(ll, s2_box, 0.06);
	if (ws > 0.0) {
		col = mix(col, textureGrad(albedo_s2, suv, sdx, sdy).rgb, ws);
	}
	col *= land_gain;

	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 v = normalize(cam - wpos);
	vec3 p = n * PLANET_R;
	float nl = dot(n, sun_dir);
	vec3 tsun = sun_transmittance_lut(transmittance_lut, p + n * 0.05, sun_dir) * sun_power;

	// cloud shadow: where the sun ray through this point crosses the cloud layer
	vec3 sp = normalize(n + sun_dir * (cloud_alt / PLANET_R) / max(nl, 0.15));
	float shade = 1.0 - cloud_shadow * cloud_cover(clouds, sp, cloud_shift, clear_hole);

	// sky light: weak blue fill on the day side, fades through twilight
	vec3 sky = vec3(0.05, 0.09, 0.17) * smoothstep(-0.15, 0.35, nl) * sun_power;
	vec3 lit = col * (tsun * max(nl, 0.0) * shade + sky);

	// ocean: darker diffuse, GGX glint, Fresnel sky reflection
	float spec = ggx_spec(n, v, sun_dir, ocean_rough);
	float fv = 0.02 + 0.98 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
	vec3 sea = col * (tsun * max(nl, 0.0) * shade * 0.9 + sky)
		+ tsun * spec * shade + fv * vec3(0.12, 0.2, 0.36) * smoothstep(-0.1, 0.3, nl) * sun_power * 0.5;
	ALBEDO = mix(lit, sea, water);
}
