// Shared body of ground_mark.gdshader and ground_mark_overlay.gdshader (see there).

uniform vec3 outline : source_color = vec3(0.118, 0.110, 0.102);

varying vec4 col;
varying float mode;

void vertex() {
	col = COLOR;
	mode = INSTANCE_CUSTOM.x;
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float aa = fwidth(r) * 1.5;
	vec3 c = col.rgb;
	float a = 0.0;
	if (mode < 0.5) {
		// unit foot mark (owner feedback 2026-10-11): a soft dark contact shadow, plus a thin
		// team-coloured ring instead of a solid plate
		float blob = (1.0 - smoothstep(0.0, 0.75, r)) * 0.5;
		float ring = smoothstep(0.74 - aa, 0.76, r) * (1.0 - smoothstep(0.86, 0.86 + aa, r));
		float ring_a = clamp(col.a * 2.4, 0.0, 0.9) * ring;
		c = mix(vec3(0.02, 0.02, 0.015), col.rgb, step(0.001, ring_a) * ring);
		a = max(blob * (1.0 - ring), ring_a);
	} else if (mode < 1.5) {
		float band = smoothstep(0.80 - aa, 0.80, r) * (1.0 - smoothstep(0.92, 0.92 + aa, r));
		float o = smoothstep(0.75 - aa, 0.77, r) * (1.0 - smoothstep(0.96, 0.96 + aa, r));
		c = mix(outline, col.rgb, band);
		a = max(band, o * 0.85) * col.a;
	} else {
		float fill = (1.0 - smoothstep(0.96, 0.96 + aa, r)) * 0.22;
		float band = smoothstep(0.90 - aa, 0.90, r) * (1.0 - smoothstep(0.98, 0.98 + aa, r));
		a = max(fill, band) * col.a;
	}
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
