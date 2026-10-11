shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Selection ring under each selected unit (and the move marker).

uniform vec3 ring_colour = vec3(0.45, 1.0, 0.45);

void fragment() {
	ALBEDO = ring_colour;
}
