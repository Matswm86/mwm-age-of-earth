shader_type spatial;
render_mode cull_back;

// Vertex-animation-texture bodies (hominins, animals) on a MultiMesh (scripts/VatModel.gd).
// vat: float16 RGBA, 2048 texels wide: per vertex [position, normal], rows_per_frame rows per frame.
// INSTANCE_CUSTOM: r = clip first frame, g = frames + 1000 x loop, b = clip start (anim_time
// seconds), a = team index (0-3) + 4 when selected. Frames blend linearly (15 fps bake).
// Team identity (DESIGN 7.6): body paint bands by rest height (chest 70-79 %, hip 47-53 %),
// ragged by noise, never the whole body; plus a warm rim term so units read at RTS zoom.

uniform sampler2D vat : filter_nearest, repeat_disable;
uniform int vcount = 1;
uniform int rows_per_frame = 1;
uniform float fps = 15.0;
uniform float anim_time = 0.0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float paint = 1.0;
uniform vec3 team_cols[4];
uniform vec3 albedo_mul : source_color = vec3(1.0);
uniform vec3 rim_colour : source_color = vec3(1.0, 0.82, 0.62);
uniform float rim_strength = 0.35;
uniform float roughness = 0.8;

varying float rest_h;
varying flat int team;

vec3 fetch(int vid, int frame, int slot) {
	ivec2 c = ivec2((vid % 1024) * 2 + slot, frame * rows_per_frame + vid / 1024);
	return texelFetch(vat, c, 0).xyz;
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float loop = step(999.5, cd.g);
	float frames = max(cd.g - 1000.0 * loop, 1.0);
	float t = max(anim_time - cd.b, 0.0) * fps;
	t = loop > 0.5 ? mod(t, frames) : min(t, frames - 1.0);
	float f0 = floor(t);
	float fr = t - f0;
	float f1 = loop > 0.5 ? mod(f0 + 1.0, frames) : min(f0 + 1.0, frames - 1.0);
	int a = int(cd.r + f0);
	int b = int(cd.r + f1);
	int vid = clamp(int(UV2.x * float(vcount)), 0, vcount - 1);
	VERTEX = mix(fetch(vid, a, 0), fetch(vid, b, 0), fr);
	NORMAL = normalize(mix(fetch(vid, a, 1), fetch(vid, b, 1), fr));
	// glTF stores V flipped: UV2.y = 1 - rest height (seen 2026-10-11: bands landed on the knees)
	rest_h = 1.0 - UV2.y;
	team = int(mod(cd.a, 4.0));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb * albedo_mul;
	if (paint > 0.5) {
		float n = vnoise(UV * 90.0);
		float edge = 0.025 * (n - 0.5);
		float h = rest_h + edge;
		float chest = smoothstep(0.695, 0.71, h) * (1.0 - smoothstep(0.785, 0.80, h));
		float hip = smoothstep(0.465, 0.48, h) * (1.0 - smoothstep(0.525, 0.54, h));
		float m = (chest + hip) * mix(0.55, 0.95, smoothstep(0.2, 0.8, n));
		alb = mix(alb, team_cols[team], m);
	}
	ALBEDO = alb;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_colour * rim * rim_strength * (0.35 + alb);
}
