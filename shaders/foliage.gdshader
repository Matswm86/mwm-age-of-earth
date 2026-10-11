shader_type spatial;
render_mode cull_disabled;

// Leaf cards of the trees (ModelLib._foliage). Alpha scissor, never blended. Three tricks make
// a crown read as a volume instead of a flat sheet of cards from RTS height:
// - crown normals: the card normal is bent toward the direction out of the crown ellipsoid, so the
//   sunny side of the crown is bright and the far side falls into shade;
// - crown occlusion: leaves deep inside the crown are darker (fake self-shadow, AO);
// - translucency: back-lit leaves glow a little (BACKLIGHT).
// Wind: a slow sway of the whole crown growing with height, plus a fast per-leaf flutter.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float alpha_cut = 0.3;
uniform vec3 crown_centre = vec3(0.0, 4.0, 0.0);
uniform vec3 crown_radius = vec3(4.0, 3.0, 4.0);
uniform float bend = 0.8;
uniform float inner_dark = 0.6;
uniform float wind = 0.12;
uniform vec3 translucency : source_color = vec3(0.45, 0.5, 0.2);
// canopy fade (DESIGN 7.5): xyz = a player unit's chest, w = 1 when used. Leaves on the line of
// sight from the camera to a unit dither out to ~25 %, so units under a crown stay readable.
uniform vec4 reveal[16];
uniform float reveal_r = 1.6;

varying float inner;
varying float crown_y;
varying vec3 leaf_w;

void vertex() {
	vec3 d = (VERTEX - crown_centre) / crown_radius;
	inner = clamp(length(d), 0.0, 1.4);
	crown_y = d.y;
	leaf_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mix(NORMAL, normalize(d * crown_radius), bend));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float top = crown_centre.y + crown_radius.y;
	float h = clamp(VERTEX.y / max(top, 0.1), 0.0, 1.0);
	float s = sin(TIME * 1.1 + wp.x * 0.13 + wp.z * 0.09) + 0.45 * sin(TIME * 2.7 + wp.z * 0.6);
	VERTEX.xz += vec2(0.7, -0.5) * s * wind * h * h;
	VERTEX += NORMAL * sin(TIME * 7.0 + dot(wp, vec3(3.1, 1.7, 2.3))) * 0.02 * h;
}

void fragment() {
	if (!FRONT_FACING) {
		// Godot flips the normal of back faces; the bent crown normal must not flip
		NORMAL = -NORMAL;
	}
	vec4 t = texture(albedo_tex, UV) * albedo_col;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = CAMERA_POSITION_WORLD;
	float hide = 0.0;
	for (int i = 0; i < 16; i++) {
		if (reveal[i].w < 0.5) {
			continue;
		}
		vec3 seg = reveal[i].xyz - cam;
		float k = clamp(dot(wp - cam, seg) / dot(seg, seg), 0.0, 1.0);
		float d = length(wp - (cam + seg * k));
		hide = max(hide, (1.0 - smoothstep(reveal_r * 0.6, reveal_r, d)) * step(k, 0.985));
	}
	// ordered 4x4 dither keeps ~25 % of the leaves where hidden
	ivec2 q = ivec2(FRAGCOORD.xy) % 4;
	float bayer = float((q.x * 4 + q.y * 7) % 16) / 16.0;
	if (hide * 0.75 > bayer) {
		discard;
	}
	float shade = mix(1.0 - inner_dark, 1.0, smoothstep(0.25, 1.0, inner));
	// underside of the crown in its own shade, top catches the sky
	shade *= mix(0.55, 1.08, smoothstep(-1.0, 0.7, crown_y));
	// clump-scale light and dark (~1.5 m lumps) so the crown breaks into masses, not a sheet
	vec3 cp = leaf_w * 0.65;
	float clump = fract(sin(dot(floor(cp), vec3(12.99, 78.23, 37.71))) * 43758.55);
	vec3 fp = fract(cp);
	float edge = smoothstep(0.0, 0.35, min(min(fp.x, fp.y), fp.z));
	shade *= mix(0.78, 1.1, clump) * mix(0.85, 1.0, edge);
	ALBEDO = t.rgb * shade;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.6;
	}
	AO = shade;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	BACKLIGHT = translucency * t.rgb * 1.6;
}
