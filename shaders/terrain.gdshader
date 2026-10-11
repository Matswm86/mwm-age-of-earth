shader_type spatial;
render_mode cull_back;

// Placeholder terrain: vertex colours from scripts/RtsTerrain.gd, darkened by the fog of war.
// fog_tex R: 0 = unexplored (black), 0.5 = explored (dim, grey), 1 = visible.

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float map_size = 512.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float f = texture(fog_tex, world_xz / map_size).r;
	float seen = smoothstep(0.15, 0.35, f);
	float vis = smoothstep(0.68, 0.85, f);
	vec3 col = COLOR.rgb;
	vec3 grey = vec3(dot(col, vec3(0.3, 0.59, 0.11)));
	vec3 dim = mix(grey, col, 0.4) * 0.42;
	ALBEDO = mix(dim, col, vis) * seen;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2 * vis;
}
