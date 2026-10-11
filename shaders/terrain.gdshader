shader_type spatial;
render_mode cull_back;

// Rift Lake ground (DESIGN 7.2). The flat grid is lifted from height_tex (game metres, x3 relief).
// Seven Poly Haven layers in three Texture2DArrays; per pixel only the top 2 splat weights are
// sampled (2 x albedo, normal, material), then height-blended: w = (splat * (0.35 + h)^4)^2.
// Macro noise (~25 m) breaks tiling; sky_ao (relief occlusion) and ground_tex.r (contact
// occlusion under trees, rocks and buildings) stand in for the baked lightmap; ground_tex.g
// tramples camp floors toward red earth. fog_tex R: 0 unexplored, 0.5 explored, 1 visible.

#include "res://shaders/biome.gdshaderinc"

uniform sampler2D biome_tex : filter_linear, repeat_disable;
uniform vec3 grass_dry : source_color = vec3(0.70, 0.64, 0.33);
uniform vec3 grass_green : source_color = vec3(0.38, 0.50, 0.17);
uniform vec3 grass_fresh : source_color = vec3(0.52, 0.68, 0.20);
uniform vec3 litter : source_color = vec3(0.24, 0.20, 0.13);
uniform vec3 dirt : source_color = vec3(0.58, 0.50, 0.40);
uniform float sward = 0.9;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D sky_ao_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D splat_a : filter_linear, repeat_disable;
uniform sampler2D splat_b : filter_linear, repeat_disable;
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray mat_arr : filter_linear_mipmap, repeat_enable;
uniform float inv_tile[7];
uniform vec3 tints[7];
uniform float map_size = 512.0;
uniform float detail_normal = 0.9;
uniform float macro_lo = 0.82;
uniform float macro_hi = 1.12;
uniform float wet_band_m = 2.5;

varying vec2 world_xz;
varying float ground_h;

vec2 map_uv(vec2 xz) {
	// 1025 samples 0.5 m apart cover 0..512 m inclusive
	return (xz * 2.0 + 0.5) / 1025.0;
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	VERTEX.y = textureLod(height_tex, map_uv(world_xz), 0.0).r;
	ground_h = VERTEX.y;
	vec3 n = textureLod(normal_tex, map_uv(world_xz), 0.0).rgb * 2.0 - 1.0;
	NORMAL = normalize(n);
}

vec2 layer_uv(vec2 xz, int i) {
	float a = 0.6 * float(i);
	mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	return (r * xz) * inv_tile[i];
}

// tangent-space normal of layer i, turned back into the map frame (x east, y south)
vec2 layer_slope(vec3 tn, int i) {
	float a = 0.6 * float(i);
	vec2 d = vec2(tn.x, -tn.y);
	return vec2(cos(a) * d.x + sin(a) * d.y, -sin(a) * d.x + cos(a) * d.y);
}

void fragment() {
	vec2 uv = map_uv(world_xz);
	vec4 sa = texture(splat_a, uv);
	vec3 sb = texture(splat_b, uv).rgb;
	vec2 gm = texture(ground_tex, world_xz / map_size).rg;
	float w[7] = float[7](sa.r, sa.g, sa.b, sa.a, sb.r, sb.g, sb.b);
	// trampled camp floor: grass gives way to red earth; elsewhere the laterite only shows in
	// small patches (the 4.2 Mya woodland floor is grass and litter, not open red soil)
	w[1] *= 0.3;
	w[0] *= 1.0 - 0.55 * gm.g;
	int i1 = 0;
	int i2 = 1;
	if (w[1] > w[0]) { i1 = 1; i2 = 0; }
	for (int k = 2; k < 7; k++) {
		if (w[k] > w[i1]) { i2 = i1; i1 = k; }
		else if (w[k] > w[i2]) { i2 = k; }
	}
	vec3 uv1 = vec3(layer_uv(world_xz, i1), float(i1));
	vec3 uv2 = vec3(layer_uv(world_xz, i2), float(i2));
	vec3 m1 = texture(mat_arr, uv1).rgb;
	vec3 m2 = texture(mat_arr, uv2).rgb;
	float b1 = pow(max(w[i1], 0.0) * pow(0.35 + m1.b, 4.0), 2.0);
	float b2 = pow(max(w[i2], 0.0) * pow(0.35 + m2.b, 4.0), 2.0);
	float t = b2 / max(b1 + b2, 1e-5);
	vec3 a1 = texture(albedo_arr, uv1).rgb * tints[i1];
	vec3 a2 = texture(albedo_arr, uv2).rgb * tints[i2];
	vec3 n1 = texture(normal_arr, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_arr, uv2).rgb * 2.0 - 1.0;
	vec3 alb = mix(a1, a2, t);
	vec3 mat = mix(m1, m2, t);
	vec2 slope = mix(layer_slope(n1, i1), layer_slope(n2, i2), t) * detail_normal;
	// macro variation kills tiling at RTS height
	float macro = texture(macro_tex, world_xz / 64.0).r;
	alb *= mix(macro_lo, macro_hi, macro);
	float shore_m = texture(shore_tex, uv).r * 40.0;
	// biome (bake_biome.py): grass sward, forest litter, trampled trails
	vec4 bio = texture(biome_tex, world_xz / map_size);
	float lum = dot(alb, vec3(0.3, 0.59, 0.11));
	float gd = grass_density(bio, gm.g, shore_m, sa.b, world_xz) * smoothstep(0.05, 0.25, ground_h);
	vec3 gc = grass_colour(world_xz, bio.g, grass_dry, grass_green, grass_fresh);
	alb = mix(alb, gc * clamp(lum * 1.5, 0.25, 1.1) * 0.55, gd * sward);
	alb = mix(alb, litter * (0.6 + lum * 1.2), smoothstep(0.3, 0.9, bio.r) * 0.75 * step(0.0, ground_h));
	float trail = max(smoothstep(0.1, 0.7, bio.b), smoothstep(0.1, 0.9, frayed(gm.g, world_xz)) * 0.85);
	// trails stop at the waterline (the shore trail showed as a sand strip on the lake bed)
	trail *= smoothstep(0.0, 0.3, ground_h);
	alb = mix(alb, dirt * (0.42 + lum * 1.35), trail);
	// wet band at the waterline
	float wet = 1.0 - smoothstep(0.0, wet_band_m, shore_m);
	alb *= mix(1.0, 0.62, wet);
	float contact = gm.r;
	alb *= mix(0.55, 1.0, contact);
	// world normal: macro relief + layer detail (whiteout-style)
	vec3 mn = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	vec3 wn = normalize(vec3(mn.x + slope.x * mn.y, mn.y, mn.z + slope.y * mn.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float sky = texture(sky_ao_tex, uv).r;
	AO = mat.r * sky * mix(0.4, 1.0, contact);
	AO_LIGHT_AFFECT = 0.25;
	ROUGHNESS = mix(clamp(mat.g, 0.55, 1.0), 0.45, wet);
	SPECULAR = 0.35;
	// fog of war
	float f = texture(fog_tex, world_xz / map_size).r;
	float seen = smoothstep(0.15, 0.35, f);
	float vis = smoothstep(0.68, 0.85, f);
	vec3 grey = vec3(dot(alb, vec3(0.3, 0.59, 0.11)));
	vec3 dim = mix(grey, alb, 0.4) * 0.42;
	ALBEDO = mix(dim, alb, vis) * seen;
}
