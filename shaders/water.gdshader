shader_type spatial;
render_mode cull_back;

// Lake Turkana (DESIGN 7.4): one opaque plane at the water level. Colour from depth_tex
// (water.png, 1 = 4 m real depth): silt -> jade shallow -> jade deep. Two scrolling noise normal
// maps (wind chop, opposite directions) give the sun glints and the sky Fresnel reflection;
// shore foam from shore_tex (distance to the waterline, 1 = 40 m) where it is under ~0.9 m,
// broken by noise and pushed in and out by a slow wave. Fog of war as on the ground.

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float map_size = 512.0;
uniform vec3 silt_shallow : source_color = vec3(0.490, 0.478, 0.353);
uniform vec3 jade_shallow : source_color = vec3(0.369, 0.549, 0.431);
uniform vec3 jade_deep : source_color = vec3(0.184, 0.431, 0.384);
uniform vec3 foam_colour : source_color = vec3(0.851, 0.831, 0.769);
uniform float wave_strength = 0.35;
uniform float foam_m = 0.9;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = (world_xz * 2.0 + 0.5) / 1025.0;
	float depth = texture(depth_tex, uv).r / 0.46; // water.png peaks at 117/255 on this map
	// past the map edge the lake is open water
	if (world_xz.x > map_size || world_xz.y < 0.0 || world_xz.y > map_size) {
		depth = 1.0;
	}
	vec3 col = mix(silt_shallow, jade_shallow, smoothstep(0.0, 0.18, depth));
	col = mix(col, jade_deep, smoothstep(0.18, 0.55, depth));
	// wind chop: two layers, 4 m and 11 m, opposite drift
	vec3 na = texture(wave_a, world_xz / 11.0 + vec2(0.015, 0.006) * TIME).rgb * 2.0 - 1.0;
	vec3 nb = texture(wave_b, world_xz / 4.0 - vec2(0.03, -0.012) * TIME).rgb * 2.0 - 1.0;
	vec2 s = (na.xy + nb.xy) * wave_strength;
	vec3 wn = normalize(vec3(s.x, 1.0, -s.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// shore foam
	float shore_m = texture(shore_tex, uv).r * 40.0;
	if (world_xz.x > map_size || world_xz.y < 0.0 || world_xz.y > map_size) {
		shore_m = 40.0;
	}
	float push = 0.25 * sin(TIME * 0.7 - shore_m * 2.5);
	float nz = texture(foam_noise, world_xz / 1.6 + vec2(TIME * 0.01, 0.0)).r;
	float foam = (1.0 - smoothstep(0.0, foam_m + push, shore_m)) * smoothstep(0.38, 0.62, nz + 0.25);
	foam = max(foam, (1.0 - smoothstep(0.0, 0.18, shore_m)) * 0.8);
	col = mix(col, foam_colour, foam);
	float f = texture(fog_tex, clamp(world_xz / map_size, vec2(0.0), vec2(1.0))).r;
	float seen = smoothstep(0.15, 0.35, f);
	float vis = smoothstep(0.68, 0.85, f);
	ALBEDO = mix(col * 0.4, col, vis) * seen;
	ROUGHNESS = mix(0.035, 0.7, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.2, foam) * vis * seen;
}
