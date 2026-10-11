shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_schlick_ggx;

// The lake (Forward+): one plane at the water level that shows the lake bed through the water.
// The scene behind the surface (screen texture + depth) is refracted by the wave normals and
// absorbed by the water column it crosses (red goes first, so shallows are clear and turquoise
// and the deep water is blue), the surface itself only reflects (sky radiance + the shore
// ReflectionProbe, Fresnel from the GGX specular). Two scrolling noise normal maps (wind chop,
// opposite directions) give the glints; shore foam from shore_tex (distance to the waterline,
// 1 = 40 m) breaks along the line and is pushed in and out by a slow wave. Fog of war as on the
// ground. Past the map edge the lake runs on to the horizon as open water.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_buf : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float map_size = 512.0;
// colour the water turns to with depth (in-scattered light), linear
uniform vec3 deep_colour : source_color = vec3(0.05, 0.30, 0.52);
// sky colour added with a Fresnel-like view term (the heightened look: water reads blue from above)
uniform vec3 sky_tint : source_color = vec3(0.45, 0.68, 0.90);
uniform float sky_amount = 0.22;
// extinction per metre of water column (r, g, b)
uniform vec3 absorb = vec3(1.1, 0.42, 0.26);
uniform vec3 foam_colour : source_color = vec3(0.851, 0.831, 0.769);
uniform float wave_strength = 0.35;
uniform float refract_px = 0.018;
uniform float foam_m = 0.55;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float scene_depth(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_buf, suv).r;
	vec4 v = inv_proj * vec4(suv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 uv = (world_xz * 2.0 + 0.5) / 1025.0;
	bool open_water = world_xz.x > map_size || world_xz.y < 0.0 || world_xz.y > map_size;
	// wind chop: two layers, 4 m and 11 m, opposite drift
	vec3 na = texture(wave_a, world_xz / 11.0 + vec2(0.015, 0.006) * TIME).rgb * 2.0 - 1.0;
	vec3 nb = texture(wave_b, world_xz / 4.0 - vec2(0.03, -0.012) * TIME).rgb * 2.0 - 1.0;
	// far water calms down (the chop aliases into vertical streaks of reflected sky at a grazing view)
	float far_k = smoothstep(25.0, 400.0, -VERTEX.z);
	float calm = mix(1.0, 0.05, far_k);
	vec2 s = (na.xy + nb.xy) * wave_strength * calm;
	vec3 wn = normalize(vec3(s.x, 1.0, -s.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// water column behind this pixel (view metres), then refract and re-measure so objects above
	// the water never bleed into the refraction
	float surf = -VERTEX.z;
	float col_m = max(scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - surf, 0.0);
	vec2 ruv = SCREEN_UV + s * refract_px * clamp(col_m, 0.0, 1.0);
	float col_r = scene_depth(ruv, INV_PROJECTION_MATRIX) - surf;
	if (col_r < 0.0) {
		ruv = SCREEN_UV;
		col_r = col_m;
	}
	if (open_water) {
		col_r = 60.0;
	}
	// metres of water the light really crosses: the view ray is slanted, the light comes down
	float path = col_r * 1.4;
	vec3 t = exp(-absorb * path);
	vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 water = bed * t + deep_colour * (1.0 - t);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	water += sky_tint * sky_amount * (0.35 + fres * 2.5) * (1.0 - t * 0.6);
	// shore foam
	float shore_m = open_water ? 40.0 : texture(shore_tex, uv).r * 40.0;
	float push = 0.25 * sin(TIME * 0.7 - shore_m * 2.5);
	float nz = texture(foam_noise, world_xz / 1.6 + vec2(TIME * 0.01, 0.0)).r;
	float foam = (1.0 - smoothstep(0.0, foam_m + push, shore_m)) * smoothstep(0.42, 0.66, nz + 0.2);
	foam *= smoothstep(0.02, 0.15, col_m);
	float f = texture(fog_tex, clamp(world_xz / map_size, vec2(0.0), vec2(1.0))).r;
	float seen = smoothstep(0.15, 0.35, f);
	float vis = mix(0.4, 1.0, smoothstep(0.68, 0.85, f)) * seen;
	// soft edge where the water meets the ground (no hard line on the beach)
	float edge = smoothstep(0.0, 0.08, col_m);
	ALBEDO = foam_colour * foam * vis;
	EMISSION = water * (1.0 - foam) * vis;
	// far water reads rougher: blurs the sky reflection that streaked at a grazing view
	ROUGHNESS = mix(mix(0.03, 0.22, far_k), 0.7, foam);
	METALLIC = 0.0;
	// low specular: the sky radiance is near-white at golden hour and a full Fresnel term bleached
	// the far lake (a reflection probe fixed it but left a hard seam at its box edge, 2026-10-11)
	SPECULAR = mix(mix(0.32, 0.12, far_k), 0.2, foam) * vis;
	ALPHA = edge;
}
