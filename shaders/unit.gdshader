shader_type spatial;
render_mode cull_back;

// Walk cycle for the MultiMesh hominins (scripts/UnitMesh.gd), no skeleton.
// INSTANCE_CUSTOM.rgb = team colour, INSTANCE_CUSTOM.a = walk amount (0..1) + 2 when selected.
// UV2.x = body part id (see UnitMesh.gd). anim_time is game time (scaled by game speed).

uniform float anim_time = 0.0;
// Strides per second at full walk speed (3.2 m/s, about 1.1 m per step).
uniform float stride_hz = 1.45;

const float HIP_Y = 0.72;
const float KNEE_Y = 0.38;
const float SHOULDER_Y = 1.16;

varying vec3 team_col;
varying float selected;

vec3 rot_x(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	selected = step(1.5, cd.a);
	float walk = clamp(cd.a - 2.0 * selected, 0.0, 1.0);
	team_col = cd.rgb;
	float phase = anim_time * stride_hz * 6.2831853 + float(INSTANCE_ID) * 2.399;
	float s = sin(phase);
	int part = int(UV2.x + 0.5);
	float side = (part == 1 || part == 3 || part == 5) ? 1.0 : -1.0;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (part >= 1 && part <= 4) {
		float hip = -0.55 * s * side * walk;
		if (part >= 3) {
			// knee bends while the leg swings forward
			float knee = (0.5 + 0.5 * sin(phase * side + 1.2)) * 0.8 * walk;
			v.y -= KNEE_Y;
			v = rot_x(v, knee);
			v.y += KNEE_Y;
			n = rot_x(n, knee);
		}
		v.y -= HIP_Y;
		v = rot_x(v, hip);
		v.y += HIP_Y;
		n = rot_x(n, hip);
	} else if (part >= 5) {
		float arm = 0.45 * s * side * walk + 0.04 * sin(anim_time * 1.7);
		v.y -= SHOULDER_Y;
		v = rot_x(v, arm);
		v.y += SHOULDER_Y;
		n = rot_x(n, arm);
	}
	// body bob on each step, slow breathing when idle
	v.y += abs(cos(phase)) * 0.045 * walk + 0.008 * sin(anim_time * 2.1 + float(INSTANCE_ID));
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec3 base = mix(COLOR.rgb, team_col, COLOR.a);
	ALBEDO = base;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	EMISSION = team_col * COLOR.a * 0.25 + vec3(0.55, 0.75, 0.35) * selected * 0.18;
}
