shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, fog_disabled;

// The pale blue dot: the planet seen from so far away that it is smaller than a pixel. Drawn
// as a point-spread spot at the planet centre with the brightness of the lit disc; faded out
// by scripts/Intro.gd once the real sphere is a few pixels wide.

uniform vec3 centre = vec3(0.0);
uniform float px_world = 1.0;
uniform float size_px = 4.5;
uniform vec3 colour : source_color = vec3(0.55, 0.68, 0.95);
uniform float energy = 1.0;

void vertex() {
	vec3 c = (VIEW_MATRIX * vec4(centre, 1.0)).xyz;
	VERTEX = c + vec3(VERTEX.xy * size_px * px_world * (-c.z), 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r2 = dot(q, q);
	ALBEDO = colour * energy * (exp(-r2 * 7.0) + 0.08 * exp(-r2 * 1.5));
}
