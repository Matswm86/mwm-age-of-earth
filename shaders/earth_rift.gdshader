shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Intro rift patch: the Lake Turkana area (2.6 x 2.6 deg) as a displaced mesh on the planet
// (Copernicus GLO-30 heights, built by scripts/IntroRift.gd). Albedo is Sentinel-2 cloudless
// 2016 (10 m inside the fine box, ~70 m outside), relief shading from the DEM normal map, lake
// mask from the DEM (flat at 362 m) with a GGX sun glint. Same sun and sky model as the planet.

#include "res://shaders/earth_common.gdshaderinc"

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float sun_power = 1.0;
uniform sampler2D transmittance_lut : filter_linear, repeat_disable;
uniform sampler2D albedo_coarse : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D albedo_fine : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D relief : filter_linear_mipmap_anisotropic, repeat_disable;
// fine box inside the patch, in patch uv (u0, v0, u1, v1)
uniform vec4 fine_box = vec4(0.0, 0.0, 1.0, 1.0);
uniform float relief_gain = 1.0;
uniform float land_gain = 1.0;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform vec2 cloud_shift = vec2(0.0);
uniform float cloud_alt = 6.0;
uniform float cloud_shadow = 0.6;
uniform vec3 clear_hole = vec3(0.0, 0.0, 0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = texture(albedo_coarse, uv).rgb;
	vec2 fuv = (uv - fine_box.xy) / (fine_box.zw - fine_box.xy);
	vec2 fdx = dFdx(fuv);
	vec2 fdy = dFdy(fuv);
	vec2 e = smoothstep(vec2(0.0), vec2(0.06), fuv) * smoothstep(vec2(0.0), vec2(0.06), 1.0 - fuv);
	float wf = e.x * e.y;
	if (wf > 0.0) {
		col = mix(col, textureGrad(albedo_fine, fuv, fdx, fdy).rgb, wf);
	}
	col *= land_gain;
	vec3 rel = texture(relief, uv).rgb;
	float lake = rel.b;

	vec3 up = normalize(wpos);
	vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), up));
	vec3 north = cross(up, east);
	vec2 sxy = (rel.rg * 2.0 - 1.0) * relief_gain;
	vec3 n = normalize(east * sxy.x + north * sxy.y + up * sqrt(max(1.0 - dot(sxy, sxy), 0.05)));
	n = normalize(mix(n, up, lake));

	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float nl = dot(n, sun_dir);
	vec3 tsun = sun_transmittance_lut(transmittance_lut, wpos, sun_dir) * sun_power;
	vec3 sky = vec3(0.05, 0.09, 0.17) * smoothstep(-0.15, 0.35, dot(up, sun_dir)) * sun_power;
	float ao = mix(0.75, 1.0, dot(n, up));
	vec3 sp = normalize(up + sun_dir * (cloud_alt / PLANET_R) / max(dot(up, sun_dir), 0.15));
	float shade = 1.0 - cloud_shadow * cloud_cover(clouds, sp, cloud_shift, clear_hole);
	tsun *= shade;
	vec3 lit = col * (tsun * max(nl, 0.0) + sky * ao);
	float spec = ggx_spec(up, v, sun_dir, 0.09);
	float fv = 0.02 + 0.98 * pow(1.0 - max(dot(up, v), 0.0), 5.0);
	vec3 water = col * (tsun * max(nl, 0.0) * 0.8 + sky) + tsun * spec
		+ fv * vec3(0.2, 0.32, 0.5) * sun_power * 0.6;
	ALBEDO = mix(lit, water, lake);
}
