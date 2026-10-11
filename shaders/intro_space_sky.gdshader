shader_type sky;
render_mode use_debanding;

// Intro background in space: black, with the sun as an HDR disc (0.27 deg radius) plus a
// small glare halo; the environment glow turns the over-bright disc into a bloom. Stars are
// geometry (intro_stars.gdshader), not part of the sky.

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float sun_energy = 40.0;
uniform float glare = 0.6;

void sky() {
	float c = dot(EYEDIR, sun_dir);
	float ang = acos(clamp(c, -1.0, 1.0));
	float disc = 1.0 - smoothstep(0.0045, 0.0050, ang);
	vec3 sun_col = vec3(1.0, 0.97, 0.92);
	vec3 col = sun_col * disc * sun_energy;
	col += sun_col * glare * (exp(-ang * 60.0) * 1.2 + exp(-ang * 12.0) * 0.12);
	COLOR = col;
}
