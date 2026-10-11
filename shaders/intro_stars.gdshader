shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

// Intro star field: one quad per Yale Bright Star Catalogue star (MultiMesh, one draw call).
// INSTANCE_CUSTOM.xyz = direction on the sky (world), .w = relative flux (10^(-0.4 V));
// COLOR = star colour from B-V. Each star is a small Gaussian a few pixels wide, sized and
// brightened by flux, at `star_dist` in front of the camera so the planet hides it.

uniform float star_dist = 1000.0;
// world size of one screen pixel at star_dist
uniform float px_world = 1.0;
uniform float gain = 1.0;

varying vec4 tint;

void vertex() {
	vec3 d = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	float flux = INSTANCE_CUSTOM.w;
	float size_px = 2.2 + 3.5 * sqrt(min(flux, 4.0));
	VERTEX = d * star_dist + vec3(VERTEX.xy * size_px * px_world, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	tint = vec4(COLOR.rgb * min(flux, 6.0) * gain, size_px);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r2 = dot(q, q);
	float core = exp(-r2 * 9.0);
	float halo = exp(-r2 * 2.5) * 0.12;
	ALBEDO = tint.rgb * (core + halo);
}
