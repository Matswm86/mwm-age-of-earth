shader_type spatial;
render_mode cull_back;

// Placeholder lake: one opaque plane at the water level, small moving ripples, fog of war.

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float map_size = 512.0;
uniform vec3 deep = vec3(0.07, 0.2, 0.24);
uniform vec3 shallow = vec3(0.18, 0.36, 0.36);

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float f = texture(fog_tex, world_xz / map_size).r;
	float seen = smoothstep(0.15, 0.35, f);
	float vis = smoothstep(0.68, 0.85, f);
	vec2 p = world_xz * 0.35;
	float w = sin(p.x + TIME * 0.9) * 0.5 + sin(p.y * 1.3 - TIME * 0.7) * 0.5;
	vec3 nrm = normalize(vec3(0.06 * cos(p.x + TIME * 0.9), 1.0, 0.06 * cos(p.y * 1.3 - TIME * 0.7)));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	vec3 col = mix(deep, shallow, 0.5 + 0.15 * w);
	ALBEDO = mix(col * 0.4, col, vis) * seen;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6 * vis * seen;
}
