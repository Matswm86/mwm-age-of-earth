class_name WorldLook
extends RefCounted

## Lighting recipe for the Rift Lake (DESIGN 7.1), Godot Mobile renderer: Poly Haven
## qwantani_late_afternoon sky (turned so its sun sits at the game sun), sky ambient, one
## shadowed sun at elevation 20 deg / azimuth 258 deg (WSW, shadows fall ENE toward the lake),
## AgX tonemap, warm depth fog, light glow. Static builders, so any scene can share the look.

const SKY_PATH: String = "res://assets/sky/qwantani_late_afternoon_4k.hdr"
const SUN_ELEV_DEG: float = 20.0
## Azimuth from map north (-Z) clockwise toward east (+X).
const SUN_AZ_DEG: float = 258.0
const SUN_COLOUR := Color(1.0, 0.867, 0.706)
const SUN_ENERGY: float = 1.6
## HDRI sun texel at u = 0.600 (found with Blender); this yaw puts it at SUN_AZ_DEG.
const SKY_YAW_DEG: float = 138.0
const HAZE := Color(0.784, 0.722, 0.604)


## Unit vector from the ground toward the sun.
static func sun_dir() -> Vector3:
	var el: float = deg_to_rad(SUN_ELEV_DEG)
	var az: float = deg_to_rad(SUN_AZ_DEG)
	return Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))


static func make_environment() -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load(SKY_PATH)
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0.0, deg_to_rad(SKY_YAW_DEG), 0.0)
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 0.95
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = HAZE
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.3
	env.fog_aerial_perspective = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	return env


## Shadow distance 120 m, 2 splits blended (DESIGN 7.1). `shadows` off for the Low preset.
static func make_sun(shadows: bool = true) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = SUN_COLOUR
	sun.light_energy = SUN_ENERGY
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_split_1 = 0.25
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.0
	sun.basis = Basis.looking_at(-sun_dir(), Vector3.UP)
	return sun
