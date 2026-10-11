class_name Intro
extends Node3D

## Opening intro (GDD 11.1, Wayfarer GDD 4.3b): one unbroken camera move, no input.
## A pale blue dot beside the sun -> the planet as a crescent that turns to a sunlit disc ->
## the Earth of ~7 million years ago (title card; edited Blue Marble, tools/intro/bake_paleo.py)
## with drifting clouds, a scattering atmosphere and ocean glint -> a dive onto Kanapoi by Lake
## Lonyumun, ~4.2 million years ago (second title card) -> through the cloud deck into a
## golden-hour glide down to the Home Tree, where a hominin wakes and climbs down to its band
## (IntroLocal) -> Main's opening RTS camera pose -> cross-fade into scenes/Main.tscn.
## Title cards: IntroTitles. Every number lives in IntroConfig / IntroLocal.
## Two worlds share this scene: the planet stage (km, planet at the origin) and the local stage
## (m, the RtsTerrain map). The cloud veil hides the switch at IntroConfig.SWITCH_T.
## After the first full viewing (flag in user://intro.cfg) a tap skips. User args `--bench`
## or `--skip-intro` go straight to the game.

signal cue(name: String)
signal finished

const MAIN_SCENE: String = "res://scenes/Main.tscn"

## Seconds into the intro.
var t: float = 0.0
## True while the screenshot bot drives the timeline with seek(); no auto hand-over then.
var capture_mode: bool = false
var low_quality: bool = false
var seen_before: bool = false

var cam: Camera3D
var env_space: Environment
var env_ground: Environment
var world_env: WorldEnvironment
var planet_root: Node3D
var local_root: IntroLocal
var titles: IntroTitles
var music: AudioStreamPlayer

var _surface_mat: ShaderMaterial
var _cloud_mat: ShaderMaterial
var _atmos_mat: ShaderMaterial
var _rift_mat: ShaderMaterial
var _dot_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _stars: IntroStars
var _dot: MeshInstance3D
var _sun_dir: Vector3
var _start_dir: Vector3
var _target_dir: Vector3
var _cues_done: Dictionary = {}
var _handing_over: bool = false
var _stage_local: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--skip-intro" or arg == "--bench" or arg.begins_with("--bench="):
			_handing_over = true
			_go_to_game.call_deferred(0.0)
			return
	low_quality = OS.has_feature("arm32")
	if not _assets_ok():
		_handing_over = true
		_go_to_game.call_deferred(0.0)
		return
	seen_before = _load_seen()
	PerfOverlay.set_ui_visible(false)
	_solve_geometry()
	_make_envs()
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = IntroConfig.FOV
	add_child(cam)
	cam.current = true
	_make_planet()
	_make_local()
	cam.current = true
	_make_veil()
	titles = IntroTitles.new()
	titles.name = "Titles"
	add_child(titles)
	music = AudioStreamPlayer.new()
	music.name = "Music"
	add_child(music)
	apply(0.0)


func _process(delta: float) -> void:
	if capture_mode or _handing_over:
		return
	t += delta
	apply(t)
	if t >= IntroConfig.FADE_START_T:
		_hand_over(IntroConfig.FADE_SECONDS)


func _unhandled_input(event: InputEvent) -> void:
	if capture_mode or _handing_over or not seen_before:
		return
	var st := event as InputEventScreenTouch
	if st != null and st.pressed and t > IntroConfig.SKIP_AFTER:
		_hand_over(IntroConfig.SKIP_FADE_SECONDS)


## Jump the timeline (screenshot bot).
func seek(time_s: float) -> void:
	t = time_s
	apply(t)


# --- setup ---


## Sun from the target's late-afternoon sky; start point on the far side of the planet so the
## first view is a crescent with the sun in frame.
func _solve_geometry() -> void:
	_target_dir = IntroConfig.geo_dir(IntroConfig.TARGET_LAT, IntroConfig.TARGET_LON)
	var east: Vector3 = IntroConfig.east_of(_target_dir)
	var north: Vector3 = _target_dir.cross(east)
	var el: float = deg_to_rad(IntroConfig.SUN_ELEV_DEG)
	var az: float = deg_to_rad(IntroConfig.SUN_AZ_DEG)
	_sun_dir = ((_target_dir * sin(el) + (north * cos(az) + east * sin(az)) * cos(el)).normalized())
	var axis: Vector3 = _sun_dir.cross(_target_dir).normalized()
	_start_dir = _sun_dir.rotated(axis, deg_to_rad(IntroConfig.START_PHASE_DEG))


func _make_envs() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/intro_space_sky.gdshader")
	_sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env_space = Environment.new()
	env_space.background_mode = Environment.BG_SKY
	env_space.sky = sky
	env_space.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env_space.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_tone(env_space)
	world_env = WorldEnvironment.new()
	world_env.environment = env_space
	add_child(world_env)


func _tone(e: Environment) -> void:
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_strength = 1.0
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.set_glow_level(0, 0.0)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(4, 1.0)
	e.set_glow_level(6, 0.6)


## False (and an error in the log) when the intro textures are not imported; the game then
## starts without the intro instead of showing a broken one.
func _assets_ok() -> bool:
	var missing: PackedStringArray = PackedStringArray()
	for f: String in [
		"earth_albedo_8k.jpg", "earth_clouds_8k.jpg", "rift_height.png", "stars_bsc5.png"
	]:
		# load (cached for later), not exists(): a stale .import file passes exists()
		if not ResourceLoader.exists(IntroConfig.TEX_DIR + f) or _tex(f) == null:
			missing.append(f)
	if missing.is_empty():
		return true
	push_error("Intro skipped, textures not imported: %s" % ", ".join(missing))
	return false


func _tex(file: String) -> Texture2D:
	return load(IntroConfig.TEX_DIR + file)


func _make_planet() -> void:
	planet_root = Node3D.new()
	planet_root.name = "Planet"
	add_child(planet_root)
	var r: float = IntroConfig.PLANET_R
	var hole := Vector3(
		deg_to_rad(IntroConfig.TARGET_LAT),
		deg_to_rad(IntroConfig.TARGET_LON),
		deg_to_rad(IntroConfig.CLEAR_HOLE_DEG)
	)
	_surface_mat = ShaderMaterial.new()
	_surface_mat.shader = load("res://shaders/earth_surface.gdshader")
	var albedo: String = "earth_albedo_8k.jpg" if low_quality else "earth_albedo_16k.jpg"
	_surface_mat.set_shader_parameter("albedo_global", _tex(albedo))
	_surface_mat.set_shader_parameter("ocean_mask", _tex("earth_ocean_8k.png"))
	_surface_mat.set_shader_parameter("albedo_region", _tex("rift_bmng_4k.jpg"))
	_surface_mat.set_shader_parameter(
		"region_box", IntroConfig.box_radians(IntroConfig.BMNG_REGION)
	)
	_surface_mat.set_shader_parameter("albedo_s2", _tex("rift_s2_coarse.jpg"))
	_surface_mat.set_shader_parameter("s2_box", IntroConfig.box_radians(IntroConfig.PATCH))
	_surface_mat.set_shader_parameter("clouds", _tex("earth_clouds_8k.jpg"))
	_surface_mat.set_shader_parameter("cloud_alt", IntroConfig.CLOUD_ALT)
	_surface_mat.set_shader_parameter("clear_hole", hole)
	var seg: int = 256 if low_quality else 512
	_sphere("Surface", r, seg, _surface_mat)

	_rift_mat = ShaderMaterial.new()
	_rift_mat.shader = load("res://shaders/earth_rift.gdshader")
	_rift_mat.set_shader_parameter("albedo_coarse", _tex("rift_s2_coarse.jpg"))
	_rift_mat.set_shader_parameter("albedo_fine", _tex("rift_s2_fine.jpg"))
	_rift_mat.set_shader_parameter("relief", _tex("rift_normal.png"))
	var p: Vector4 = IntroConfig.PATCH
	var f: Vector4 = IntroConfig.FINE
	var fine_box := Vector4(
		(f.x - p.x) / (p.z - p.x),
		(p.w - f.w) / (p.w - p.y),
		(f.z - p.x) / (p.z - p.x),
		(p.w - f.y) / (p.w - p.y)
	)
	_rift_mat.set_shader_parameter("fine_box", fine_box)
	_rift_mat.set_shader_parameter("relief_gain", IntroConfig.RELIEF_EXAG)
	_rift_mat.set_shader_parameter("clouds", _tex("earth_clouds_8k.jpg"))
	_rift_mat.set_shader_parameter("cloud_alt", IntroConfig.CLOUD_ALT)
	_rift_mat.set_shader_parameter("clear_hole", hole)
	var rift := IntroRift.new()
	rift.name = "Rift"
	planet_root.add_child(rift)
	rift.build(IntroConfig.PATCH_VERTS_LOW if low_quality else IntroConfig.PATCH_VERTS, _rift_mat)

	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://shaders/earth_clouds.gdshader")
	_cloud_mat.set_shader_parameter("clouds", _tex("earth_clouds_8k.jpg"))
	_cloud_mat.set_shader_parameter("clear_hole", hole)
	_cloud_mat.render_priority = -1
	_sphere("Clouds", r + IntroConfig.CLOUD_ALT, seg / 2, _cloud_mat)

	_atmos_mat = ShaderMaterial.new()
	_atmos_mat.shader = load("res://shaders/earth_atmosphere.gdshader")
	var steps: int = IntroConfig.ATMOS_STEPS_LOW if low_quality else IntroConfig.ATMOS_STEPS_HIGH
	_atmos_mat.set_shader_parameter("view_steps", steps)
	_atmos_mat.render_priority = 1
	_sphere("Atmosphere", IntroConfig.ATMOS_R, 128, _atmos_mat)

	var lut: ImageTexture = IntroAtmosphere.transmittance_lut()
	for m: ShaderMaterial in [_surface_mat, _cloud_mat, _atmos_mat, _rift_mat]:
		m.set_shader_parameter("transmittance_lut", lut)
		m.set_shader_parameter("sun_dir", _sun_dir)
		m.set_shader_parameter("sun_power", IntroConfig.SUN_POWER)

	_stars = IntroStars.new()
	_stars.name = "Stars"
	planet_root.add_child(_stars)
	_stars.build()

	_dot_mat = ShaderMaterial.new()
	_dot_mat.shader = load("res://shaders/intro_dot.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_dot = MeshInstance3D.new()
	_dot.name = "PaleBlueDot"
	_dot.mesh = quad
	_dot.material_override = _dot_mat
	_dot.custom_aabb = AABB(Vector3(-1e9, -1e9, -1e9), Vector3(2e9, 2e9, 2e9))
	planet_root.add_child(_dot)


func _sphere(node_name: String, radius: float, segments: int, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = segments / 2
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet_root.add_child(mi)
	return mi


## Local stage: the game's map, tree and props in golden-hour light, with the hero band
## (IntroLocal). Its environment ends as the game's own (WorldLook), so the cross-fade matches.
func _make_local() -> void:
	local_root = IntroLocal.new()
	local_root.name = "Local"
	local_root.visible = false
	local_root.live = not capture_mode
	add_child(local_root)
	local_root.build(low_quality)
	env_ground = local_root.env


func _make_veil() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = load("res://shaders/intro_veil.gdshader")
	_veil = ColorRect.new()
	_veil.material = _veil_mat
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_veil)


# --- timeline ---


## Cloud veil opacity 0..1 at a time.
func veil_amount(time_s: float) -> float:
	var v: float = smoothstep(IntroConfig.VEIL_IN.x, IntroConfig.VEIL_IN.y, time_s)
	return v * (1.0 - smoothstep(IntroConfig.VEIL_OUT.x, IntroConfig.VEIL_OUT.y, time_s))


## Unit vector towards the sun (planet frame).
func sun_dir() -> Vector3:
	return _sun_dir


func apply(time_s: float) -> void:
	_fire_cues(time_s)
	var veil: float = veil_amount(time_s)
	_veil.visible = veil > 0.001
	_veil_mat.set_shader_parameter("amount", veil)
	_veil_mat.set_shader_parameter("travel", time_s * 0.8)
	titles.update(time_s)
	var local: bool = time_s >= IntroConfig.SWITCH_T
	if local != _stage_local:
		_stage_local = local
		planet_root.visible = not local
		local_root.visible = local
		world_env.environment = env_ground if local else env_space
		if not local:
			cam.attributes = null
	if local:
		local_root.apply(time_s, cam)
	else:
		_apply_planet(time_s)


func _apply_planet(time_s: float) -> void:
	var k: PackedFloat32Array = _sample_keys(time_s)
	var alt: float = k[0]
	var pitch: float = deg_to_rad(-k[1])
	var heading: float = deg_to_rad(k[3])
	var up: Vector3 = _start_dir.slerp(_target_dir, k[2]).normalized()
	var east: Vector3 = IntroConfig.east_of(up)
	var north: Vector3 = up.cross(east)
	var fwd: Vector3 = north * cos(heading) + east * sin(heading)
	var gh: float = IntroConfig.TARGET_H * smoothstep(0.9, 1.0, k[2])
	var ground: Vector3 = up * (IntroConfig.PLANET_R + gh)
	var hd: float = alt * cos(pitch) / maxf(sin(pitch), 1e-4)
	var pos: Vector3 = ground + up * alt - fwd * hd
	var cam_up: Vector3 = fwd * sin(pitch) + up * cos(pitch)
	cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(ground, cam_up)
	cam.fov = IntroConfig.FOV
	var d: float = pos.length()
	var a: float = d - IntroConfig.PLANET_R
	cam.near = clampf(a * 0.3, 0.05, 1.0e8)
	cam.far = d + IntroConfig.ATMOS_R + 10.0
	var vh: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var px_ang: float = 2.0 * tan(deg_to_rad(IntroConfig.FOV * 0.5)) / vh
	var planet_px: float = asin(clampf(IntroConfig.PLANET_R / d, 0.0, 1.0)) / px_ang
	# stars: at the back of the view, gone once the lit planet dominates the exposure
	var star_dist: float = cam.far * 0.97
	var sm: ShaderMaterial = _stars.material
	sm.set_shader_parameter("star_dist", star_dist)
	sm.set_shader_parameter("px_world", star_dist * px_ang)
	var sf: Vector2 = IntroConfig.STAR_FADE_PX
	var sg: float = 1.0 - smoothstep(sf.x, sf.y, planet_px)
	sm.set_shader_parameter("gain", IntroConfig.STAR_GAIN * sg)
	_stars.visible = sg > 0.001
	# pale blue dot: brightness of the lit fraction of the disc
	var lit_frac: float = 0.5 * (1.0 + _sun_dir.dot(pos / d))
	var df: Vector2 = IntroConfig.DOT_FADE_PX
	var dot_a: float = 1.0 - smoothstep(df.x, df.y, planet_px)
	_dot.visible = dot_a > 0.001
	_dot_mat.set_shader_parameter("px_world", px_ang)
	_dot_mat.set_shader_parameter("energy", dot_a * (2.5 + 6.0 * lit_frac))
	var shift: Vector2 = IntroConfig.CLOUD_DRIFT * time_s
	_surface_mat.set_shader_parameter("cloud_shift", shift)
	_cloud_mat.set_shader_parameter("cloud_shift", shift)
	_rift_mat.set_shader_parameter("cloud_shift", shift)
	_cloud_mat.set_shader_parameter("detail", 1.0 - smoothstep(60.0, 600.0, a))


## Monotone cubic (Fritsch-Carlson) through IntroConfig.KEYS. Returns alt (km), pitch, arc,
## heading.
func _sample_keys(time_s: float) -> PackedFloat32Array:
	var keys: Array[Array] = IntroConfig.KEYS
	var out := PackedFloat32Array()
	out.resize(4)
	var n: int = keys.size()
	var tt: float = clampf(time_s, keys[0][0], keys[n - 1][0])
	var seg: int = 0
	while seg < n - 2 and tt > keys[seg + 1][0]:
		seg += 1
	for ch in 4:
		var col: int = ch + 1
		var ys := PackedFloat32Array()
		ys.resize(n)
		for i in n:
			var y: float = keys[i][col]
			ys[i] = log(y) if col == 1 else y
		out[ch] = _monotone(keys, ys, seg, tt)
		if col == 1:
			out[ch] = exp(out[ch])
	return out


func _monotone(keys: Array[Array], ys: PackedFloat32Array, seg: int, tt: float) -> float:
	var n: int = ys.size()
	var x0: float = keys[seg][0]
	var x1: float = keys[seg + 1][0]
	var h: float = x1 - x0
	var m0: float = _tangent(keys, ys, seg, n)
	var m1: float = _tangent(keys, ys, seg + 1, n)
	var s: float = (tt - x0) / h
	var s2: float = s * s
	var s3: float = s2 * s
	return (
		(2.0 * s3 - 3.0 * s2 + 1.0) * ys[seg]
		+ (s3 - 2.0 * s2 + s) * h * m0
		+ (-2.0 * s3 + 3.0 * s2) * ys[seg + 1]
		+ (s3 - s2) * h * m1
	)


func _tangent(keys: Array[Array], ys: PackedFloat32Array, i: int, n: int) -> float:
	if i == 0 or i == n - 1:
		return 0.0
	var d0: float = (ys[i] - ys[i - 1]) / (keys[i][0] - keys[i - 1][0])
	var d1: float = (ys[i + 1] - ys[i]) / (keys[i + 1][0] - keys[i][0])
	if d0 * d1 <= 0.0:
		return 0.0
	# harmonic mean keeps the curve monotone
	return 2.0 * d0 * d1 / (d0 + d1)


func _fire_cues(time_s: float) -> void:
	for cue_name: String in IntroConfig.CUES:
		if _cues_done.has(cue_name) or time_s < IntroConfig.CUES[cue_name]:
			continue
		_cues_done[cue_name] = true
		cue.emit(cue_name)
		var path: String = "res://assets/intro/audio/%s.ogg" % cue_name
		if not capture_mode and ResourceLoader.exists(path):
			music.stream = load(path)
			music.play()


# --- hand-over ---


func _hand_over(fade_s: float) -> void:
	if _handing_over:
		return
	_handing_over = true
	_save_seen()
	finished.emit()
	_go_to_game.call_deferred(fade_s)


## Freeze the last intro frame on top, swap to the game scene, then fade the frozen frame out.
func _go_to_game(fade_s: float) -> void:
	PerfOverlay.set_ui_visible(true)
	# headless (tests): no frames are drawn, so there is nothing to freeze and frame_post_draw
	# never fires
	if fade_s > 0.0 and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		cross_fade(get_tree().root, ImageTexture.create_from_image(img), fade_s)
	get_tree().change_scene_to_file(MAIN_SCENE)


## Full-screen frozen frame that fades out over `seconds`, owned by `parent` (survives a
## scene change when parent is the root).
static func cross_fade(parent: Node, frame: Texture2D, seconds: float) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var rect := TextureRect.new()
	rect.texture = frame
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	parent.add_child(layer)
	var tw: Tween = layer.create_tween()
	# hold one beat so the game scene's first (slow) frame is hidden
	tw.tween_interval(0.15)
	tw.tween_property(rect, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(layer.queue_free)
	return layer


func _load_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(IntroConfig.SAVE_PATH) != OK:
		return false
	return bool(cfg.get_value("intro", "seen", false))


func _save_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("intro", "seen", true)
	cfg.save(IntroConfig.SAVE_PATH)
