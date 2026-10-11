class_name WorldLook
extends RefCounted

## Lighting recipe for the Rift Lake, Mobile renderer (Forward+ only in the A/B APK) (owner
## 2026-10-11: graphics first, the visual target is a bright, high-key, saturated realistic RTS
## look). Poly Haven qwantani_late_afternoon sky for ambient and reflections, one warm golden-hour
## sun at 30 deg (SW, so the faces the camera sees are lit and shadows fall away up the screen),
## cool sky fill, ACES tonemap with a grade (contrast up, saturation up), glow on highlights; on
## Forward+ also SSAO + SSIL, SSR and volumetric haze. set_quality() turns the expensive effects
## off for the Low preset. Static builders, so any scene can share the look.

const SKY_PATH: String = "res://assets/sky/qwantani_late_afternoon_4k.hdr"
const SUN_ELEV_DEG: float = 30.0
## Azimuth from map north (-Z) clockwise toward east (+X).
const SUN_AZ_DEG: float = 228.0
const SUN_COLOUR := Color(1.0, 0.9, 0.78)
const SUN_ENERGY: float = 3.0
## HDRI sun texel at u = 0.600 (found with Blender); this yaw put it at azimuth 258 deg, so
## turn it by the same amount the sun moved.
const SKY_YAW_DEG: float = 138.0 - (258.0 - SUN_AZ_DEG)
const HAZE := Color(0.80, 0.78, 0.70)
## Mobile renderer stand-in for the volumetric haze: depth fog a little denser, more sun scatter.
const MOBILE_FOG_DENSITY: float = 0.0006
const MOBILE_SUN_SCATTER: float = 0.4
## The Mobile renderer lands ~15 % darker than Forward+ with the same settings (no SSIL bounce,
## its own colour pipeline; look_stats lum 0.50 -> 0.42 on the camp): exposure and a little more
## sky ambient bring it back.
const AMBIENT: float = 0.42
const MOBILE_AMBIENT: float = 0.5
const MOBILE_EXPOSURE: float = 1.25


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
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0.0, deg_to_rad(SKY_YAW_DEG), 0.0)
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 3.5
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.38
	env.adjustment_saturation = 1.04
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = HAZE
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.00025
	env.fog_sky_affect = 0.1
	env.fog_aerial_perspective = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.0
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.15
	env.ssao_ao_channel_affect = 0.5
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.ssil_sharpness = 0.98
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.volumetric_fog_density = 0.0015
	env.volumetric_fog_albedo = Color(0.92, 0.88, 0.80)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0
	set_quality(env, true)
	return env


## True on the Forward+ build (the side-by-side A/B APK); the main APK runs the Mobile renderer.
static func is_forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## High on Forward+: every screen-space effect on. High on Mobile (no SSAO, SSIL, SSR or
## volumetric fog there): contact darkening comes from the terrain's sky_ao and contact mask, the
## crown occlusion in foliage.gdshader and the unit discs; the haze is depth fog with sun scatter,
## a little denser to stand in for the volumetric haze. Low: only the cheap ones.
static func set_quality(env: Environment, high: bool) -> void:
	var fplus: bool = is_forward_plus()
	env.ssao_enabled = high and fplus
	env.ssil_enabled = high and fplus
	env.ssr_enabled = high and fplus
	env.volumetric_fog_enabled = high and fplus
	env.fog_enabled = true
	env.fog_density = 0.00025 if fplus else MOBILE_FOG_DENSITY
	env.fog_sun_scatter = 0.25 if fplus else MOBILE_SUN_SCATTER
	env.glow_enabled = high
	env.ambient_light_energy = AMBIENT if fplus else MOBILE_AMBIENT
	env.tonemap_exposure = 1.0 if fplus else MOBILE_EXPOSURE


## Shadow distance 90 m (fit_shadows scales it), 2 splits blended, soft-filtered edges.
## `shadows` off for the Low preset.
static func make_sun(shadows: bool = true) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = SUN_COLOUR
	sun.light_energy = SUN_ENERGY
	# no PCSS (angular size 0): it was the costliest part of the 36 % the sun shadow took
	# (2026-10-11); the soft filter keeps the edges soft
	sun.light_angular_distance = 0.0
	sun.light_volumetric_fog_energy = 1.4
	sun.shadow_enabled = shadows
	# 2 splits (Godot has 2 or 4; 4 re-drew every caster twice more for ~1.5 ms); Main scales
	# the distance with the camera height
	# (fit_shadows) so the far zoom keeps its tree shadows and the default view stays sharp
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if not is_forward_plus():
		# Mobile: one orthogonal map draws every caster once instead of twice; at the RTS pitch the
		# units sit in the far split anyway, so the sharpness there is the same
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_blur = 0.8
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 2.2
	sun.basis = Basis.looking_at(-sun_dir(), Vector3.UP)
	return sun


## Tilt-shift: a camera-attribute depth of field that blurs the top (far) and bottom (near) screen
## edges around the focus distance `focus_m`. Off on Low.
static func make_camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_near_enabled = true
	ca.dof_blur_amount = 0.05
	return ca


static func update_tilt_shift(ca: CameraAttributesPractical, focus_m: float, on: bool) -> void:
	ca.dof_blur_far_enabled = on
	ca.dof_blur_near_enabled = on
	ca.dof_blur_far_distance = focus_m * 1.35
	ca.dof_blur_far_transition = focus_m * 0.9
	# near blur only on what is much closer than the ground (tall crowns right under the camera
	# turned into paint smears at 0.62)
	ca.dof_blur_near_distance = focus_m * 0.45
	ca.dof_blur_near_transition = focus_m * 0.2


## Shadow reach for an RTS camera `dist_m` from its focus: covers the far screen edge.
static func fit_shadows(sun: DirectionalLight3D, dist_m: float) -> void:
	sun.directional_shadow_max_distance = clampf(dist_m * 2.1, 55.0, 170.0)


## Per-frame look upkeep for the match: shadow reach follows the camera, tree crowns fade over the
## player's units (canopy fade, foliage.gdshader).
static func per_frame(sun: DirectionalLight3D, cam: RtsCamera, units: Units) -> void:
	fit_shadows(sun, cam.height / sin(deg_to_rad(cam.tilt_deg())))
	ModelLib.set_reveal(units.reveal_points(0, 16))
