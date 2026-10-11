shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// Grass blades (scripts/GrassField.gd): a MultiMesh of 2 x 2 m blade patches on a grid that
// follows the camera. In world space each blade is dropped onto the terrain (height_tex), thinned
// by the biome (biome.gdshaderinc: none on paths, camp floors, the waterline; sparse under forest),
// faded out with distance, coloured sun-cured gold to green by lushness, and bent by wind gusts.
// COLOR per vertex: r = blade random (density cut), g = blade random (hue, height), b = 0 root ..
// 1 tip. `spread` stretches the grid at high zoom so one field covers the screen.

#include "res://shaders/biome.gdshaderinc"

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D biome_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform sampler2D splat_a : filter_linear, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float map_size = 512.0;
uniform float water_level = 0.0;
// reed mode (GrassField.make_reeds): density from biome A, grows from the bed up to 0.6 m deep
uniform bool reeds = false;
uniform vec2 centre = vec2(256.0);
uniform float spread = 1.0;
uniform float density = 1.0;
uniform float fade_start = 40.0;
uniform float fade_end = 60.0;
uniform float height_scale = 1.0;
uniform vec3 dry : source_color = vec3(0.70, 0.64, 0.33);
uniform vec3 green : source_color = vec3(0.38, 0.50, 0.17);
uniform vec3 fresh : source_color = vec3(0.52, 0.68, 0.20);
uniform vec3 root_tint : source_color = vec3(0.45, 0.42, 0.25);
uniform vec2 wind_dir = vec2(0.8, -0.6);
uniform float wind_strength = 0.35;

varying float tip;
varying vec3 col;
varying vec2 wxz;

vec2 map_uv(vec2 xz) {
	return (xz * 2.0 + 0.5) / 1025.0;
}

void vertex() {
	vec3 w = VERTEX;
	w.xz = centre + (w.xz - centre) * spread;
	vec2 base = w.xz;
	vec2 uv = map_uv(base);
	vec4 bio = textureLod(biome_tex, base / map_size, 0.0);
	float trample = textureLod(ground_tex, base / map_size, 0.0).g;
	float shore_m = textureLod(shore_tex, uv, 0.0).r * 40.0;
	float rock = textureLod(splat_a, uv, 0.0).b;
	float dens = grass_density(bio, trample, shore_m, rock, base) * density;
	// meadow-scale variation: thinner, shorter swards and denser stands, 3-10 m across
	float meadow = bnoise(base * 0.18) * 0.65 + bnoise(base * 0.55) * 0.35;
	dens *= mix(0.75, 1.15, meadow);
	float dist = length(CAMERA_POSITION_WORLD - w);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	bool outside = base.x < 0.0 || base.y < 0.0 || base.x > map_size || base.y > map_size;
	float ground = textureLod(height_tex, uv, 0.0).r;
	if (reeds) {
		dens = smoothstep(0.1, 0.55, bio.a) * density * smoothstep(water_level - 0.6, water_level - 0.3, ground);
		dens *= 1.0 - smoothstep(water_level + 0.6, water_level + 1.2, ground);
	} else {
		// shore_m is the distance to the waterline on both sides: nothing grows below the water
		dens *= smoothstep(water_level + 0.05, water_level + 0.25, ground);
	}
	// strict: blades whose random is 0 must not survive a density of 0 (stray blades on floors)
	float keep = step(COLOR.r + 0.004, dens * fade) * (outside ? 0.0 : 1.0);

	tip = COLOR.b;
	// lush grass grows taller; blades thin out toward the fade edge by shrinking, not popping
	float hs = height_scale * mix(0.75, 1.2, bio.g) * mix(0.6, 1.2, meadow) * mix(0.85, 1.1, COLOR.g);
	hs *= 0.35 + 0.65 * smoothstep(0.0, 0.15, dens * fade - COLOR.r);
	float y = (VERTEX.y) * hs * keep;
	// wind: a travelling gust over a slow sway, bending the upper blade
	float ph = dot(base, wind_dir) * 0.11 - TIME * 1.6;
	float gust = 0.55 + 0.45 * sin(ph) * sin(ph * 0.37 + 1.3);
	float bend = wind_strength * tip * tip * gust * (0.6 + 0.4 * sin(TIME * 2.3 + COLOR.g * 30.0));
	w.xz += wind_dir * bend * hs;
	w.y = ground + y - 0.02 - bend * 0.25 * hs;
	VERTEX = w;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));
	col = reeds ? mix(green, fresh, bnoise(base * 0.3) * 0.5) * vec3(0.78, 0.86, 0.62) : grass_colour(base, bio.g, dry, green, fresh);
	wxz = base;
}

void fragment() {
	float g = COLOR.g;
	vec3 c = col * mix(0.9, 1.12, g);
	// dark, cool roots and sunlit dry tips
	c = mix(c * root_tint * 1.6, c, smoothstep(0.0, 0.55, tip));
	c = mix(c, c * vec3(1.15, 1.08, 0.85), smoothstep(0.7, 1.0, tip) * 0.5);
	float f = texture(fog_tex, wxz / map_size).r;
	float seen = smoothstep(0.15, 0.35, f);
	float vis = smoothstep(0.68, 0.85, f);
	vec3 grey = vec3(dot(c, vec3(0.3, 0.59, 0.11)));
	vec3 dim = mix(grey, c, 0.4) * 0.42;
	ALBEDO = mix(dim, c, vis) * seen;
	AO = mix(0.35, 1.0, smoothstep(0.0, 0.7, tip));
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.35, 0.33, 0.12) * tip;
}
