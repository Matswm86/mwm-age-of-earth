extends Node

## Audio autoload (GDD 11.1 opening, GDD 12 feel). Buses Master > Ambience, SFX, Voices, UI.
## Finds the Intro and Main scenes when they enter the tree (no scene has to call it):
## - Intro: the cue(name) signal and the intro clock drive a soundscape (space hum, rising tone,
##   dive wind, cloud whoosh, dawn chorus, the climber's wake call, bark scrapes, landing thud,
##   footsteps, band calls); the game ambience starts under the ground stage, so the hand-over
##   to Main is a cross-fade with no gap.
## - Main: ambience layers follow the camera (lake near water, wind with zoom, insects over land,
##   frogs on the shore), wildlife calls come from the animals' real positions, Foragers answer
##   selection and orders, gather / build / drop / train / discovery / age-up sounds, UI taps.
## 3D sounds use a pool of SfxConfig.POOL_SIZE AudioStreamPlayer3D; the listener sits above the
## camera focus. Short clips are WAV samples, loops are OGG streams. Volumes and mute are saved to
## user://audio.cfg and set from the Menu (Sound / Volume buttons). All numbers: SfxConfig.

var volumes: Dictionary = SfxConfig.DEFAULT_VOLUME.duplicate()
var muted: bool = false
## Events played since start (tests read it).
var played: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_next: int = 0
var _flat: Array[AudioStreamPlayer] = []
var _flat_next: int = 0
var _amb: Dictionary = {}
var _amb_gain: Dictionary = {}
var _amb_target: Dictionary = {}
var _amb_on: bool = false
var _amb_timer: float = 0.0
var _listener: AudioListener3D
var _main: Main
var _intro: Intro
var _intro_beds: Dictionary = {}
var _intro_pending: Array[Array] = []
var _intro_climb_done: bool = false
var _voice_t: float = 0.0
var _work_timer: float = 0.0
var _work_next: Dictionary = {}
var _alarm_t: float = 0.0
var _wild_t: float = 6.0
var _thunder_t: float = 200.0
var _sel_sig: int = 0
var _sel_timer: float = 0.0
var _panel: PanelContainer
var _menu_added: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_make_buses()
	_load_settings()
	_apply_volumes()
	for k in SfxConfig.POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = SfxConfig.UNIT_SIZE
		p.max_distance = SfxConfig.MAX_DISTANCE
		p.panning_strength = SfxConfig.PANNING
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_pool.append(p)
	for k in SfxConfig.FLAT_PLAYERS:
		var f := AudioStreamPlayer.new()
		add_child(f)
		_flat.append(f)
	for layer: String in SfxConfig.AMB_LAYERS:
		var a := AudioStreamPlayer.new()
		a.bus = "Ambience"
		a.volume_db = -80.0
		add_child(a)
		_amb[layer] = a
		_amb_gain[layer] = 0.0
		_amb_target[layer] = 0.0
	_listener = AudioListener3D.new()
	add_child(_listener)
	get_tree().node_added.connect(_on_node_added)


# --- buses and settings ---


func _make_buses() -> void:
	for bus: String in SfxConfig.BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func set_volume(bus: String, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func set_muted(on: bool) -> void:
	muted = on
	_apply_volumes()
	_save_settings()
	PerfOverlay.set_button_text("sound", "Sound: off" if muted else "Sound: on")


func _apply_volumes() -> void:
	for bus: String in volumes:
		var i: int = AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v: float = float(volumes[bus])
		# squared slider for a perceptual taper
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v * v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001 or (bus == "Master" and muted))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SfxConfig.SAVE_PATH) != OK:
		return
	for bus: String in volumes:
		volumes[bus] = float(cf.get_value("volume", bus, volumes[bus]))
	muted = bool(cf.get_value("volume", "muted", false))


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for bus: String in volumes:
		cf.set_value("volume", bus, volumes[bus])
	cf.set_value("volume", "muted", muted)
	cf.save(SfxConfig.SAVE_PATH)


# --- playback ---


func stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream
	return _streams[path]


## [stream, volume dB, pitch spread, bus] of a random file of the event.
func _pick(event: String) -> Array:
	var e: Array = SfxConfig.EVENTS[event]
	var files: Array = e[0]
	var path: String = SfxConfig.path_of(files[_rng.randi() % files.size()])
	return [stream(path), float(e[1]), float(e[2]), str(e[3])]


## Positional one-shot at a world point; null when the event has no file.
func play_at(
	event: String, at: Vector3, pitch: float = 1.0, gain_db: float = 0.0
) -> AudioStreamPlayer3D:
	var p: Array = _pick(event)
	if p[0] == null:
		return null
	played[event] = int(played.get(event, 0)) + 1
	var pl: AudioStreamPlayer3D = _free_3d()
	pl.stream = p[0]
	pl.bus = p[3]
	pl.volume_db = float(p[1]) + gain_db
	var spread: float = p[2]
	pl.pitch_scale = pitch * (1.0 + _rng.randf_range(-spread, spread))
	pl.global_position = at
	pl.play()
	return pl


## Non-positional one-shot (UI, stings, intro foley).
func play(event: String, gain_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var p: Array = _pick(event)
	if p[0] == null:
		return null
	played[event] = int(played.get(event, 0)) + 1
	var spread: float = p[2]
	return _play_flat(
		p[0], p[3], float(p[1]) + gain_db, pitch * (1.0 + _rng.randf_range(-spread, spread))
	)


func _play_flat(s: AudioStream, bus: String, db: float, pitch: float) -> AudioStreamPlayer:
	var pl: AudioStreamPlayer = _flat[_flat_next]
	for k in _flat.size():
		var c: AudioStreamPlayer = _flat[(_flat_next + k) % _flat.size()]
		if not c.playing:
			pl = c
			_flat_next = (_flat_next + k) % _flat.size()
			break
	_flat_next = (_flat_next + 1) % _flat.size()
	pl.stream = s
	pl.bus = bus
	pl.volume_db = db
	pl.pitch_scale = pitch
	pl.play()
	return pl


func _free_3d() -> AudioStreamPlayer3D:
	for k in _pool.size():
		var p: AudioStreamPlayer3D = _pool[(_pool_next + k) % _pool.size()]
		if not p.playing:
			_pool_next = (_pool_next + k + 1) % _pool.size()
			return p
	# all busy: cut the next in turn (the oldest started)
	var q: AudioStreamPlayer3D = _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	q.stop()
	return q


func busy_voices() -> int:
	var n: int = 0
	for p in _pool:
		if p.playing:
			n += 1
	return n


# --- scene hook-up ---


func _on_node_added(n: Node) -> void:
	if n is Intro:
		_intro = n as Intro
		_intro.cue.connect(_on_intro_cue)
		_intro.finished.connect(_on_intro_finished)
		_intro_pending.clear()
		_intro_climb_done = false
	elif n is Main:
		n.ready.connect(_on_main_ready.bind(n), CONNECT_ONE_SHOT)


func _on_main_ready(m: Main) -> void:
	_main = m
	_listener.make_current()
	if m.game != null:
		m.game.dropped.connect(_on_dropped)
		m.game.building_placed.connect(_on_building_placed)
		m.game.building_finished.connect(_on_building_finished)
		m.game.unit_trained.connect(_on_unit_trained)
		m.game.tech_finished.connect(_on_tech_finished)
		m.game.ordered.connect(_on_ordered)
	_sel_sig = 0
	if m.hud != null:
		m.hud.card_pressed.connect(func(_id: String) -> void: play("ui_tap"))
		m.hud.idle_pressed.connect(func() -> void: play("ui_tap"))
		m.hud.home_pressed.connect(func() -> void: play("ui_tap"))
		m.hud.clear_pressed.connect(func() -> void: play("ui_tap"))
		m.hud.menu_pressed.connect(_on_menu)
		m.hud.place_answer.connect(
			func(ok: bool) -> void: play("ui_confirm" if ok else "ui_cancel")
		)
	_add_menu()
	start_ambience(SfxConfig.AMB_FADE_IN_S)
	m.tree_exiting.connect(func() -> void: _main = null)


# --- game events ---


func _unit_world(i: int) -> Vector3:
	return Vector3(_main.units.pos[i].x, _main.units.hgt[i] + 1.0, _main.units.pos[i].y)


## Every Forager keeps its own voice pitch.
func _unit_pitch(i: int) -> float:
	var h: float = float((i * 7919) % 97) / 96.0
	return 1.0 + (h - 0.5) * 2.0 * SfxConfig.UNIT_PITCH_SPREAD


func _voice(event: String, i: int, chance: float) -> void:
	if _main == null or i < 0 or i >= _main.units.count:
		return
	if _voice_t > 0.0 or _rng.randf() > chance:
		return
	_voice_t = SfxConfig.VOICE_GAP_S
	play_at(event, _unit_world(i), _unit_pitch(i))


## Selection poll: a new unit selection gets a contact call, a building selection a tap.
func _tick_selection(delta: float) -> void:
	_sel_timer -= delta
	if _sel_timer > 0.0:
		return
	_sel_timer = SfxConfig.SELECT_POLL_S
	var ids: PackedInt32Array = _main.units.selected_ids()
	var sig: int = hash([ids, _main.sel_building])
	if sig == _sel_sig:
		return
	_sel_sig = sig
	if not ids.is_empty():
		_voice("contact", ids[_rng.randi() % ids.size()], SfxConfig.SELECT_CHANCE)
	elif _main.sel_building >= 0:
		play("ui_tap")


func _on_ordered(_kind: String, ids: PackedInt32Array) -> void:
	if not ids.is_empty():
		_voice("ack", ids[_rng.randi() % ids.size()], SfxConfig.ORDER_CHANCE)


func _on_dropped(world: Vector3, text: String) -> void:
	var ev: String = "drop_" + text.get_slice(" ", 1)
	if SfxConfig.EVENTS.has(ev):
		play_at(ev, world - Vector3(0.0, 1.8, 0.0))


func _bld_world(k: int) -> Vector3:
	return _main.game.buildings[k].node.global_position + Vector3(0.0, 0.5, 0.0)


func _on_building_placed(k: int) -> void:
	play_at("build_place", _bld_world(k))


func _on_building_finished(k: int) -> void:
	play_at("building_done", _bld_world(k))
	play_at("chorus", _bld_world(k) + Vector3(0.0, 0.5, 0.0), 1.0, -4.0)


func _on_unit_trained(u: int) -> void:
	_voice_t = 0.0
	_voice("contact", u, 1.0)


func _on_tech_finished(id: String) -> void:
	if SfxConfig.AGE_UP_TECHS.has(id):
		play("age_up")
		play("chorus", -6.0)
		return
	for b in _main.game.buildings:
		if b.type == "knapping_floor":
			play_at("knap", b.node.global_position + Vector3(0.0, 0.4, 0.0))
			break
	play("research_done")


func _on_menu() -> void:
	play("ui_tap")
	if _panel != null and not PerfOverlay.is_ui_visible():
		_panel.visible = false


# --- per frame ---


func _process(delta: float) -> void:
	_voice_t = maxf(_voice_t - delta, 0.0)
	if _intro != null and is_instance_valid(_intro):
		_tick_intro()
	else:
		_intro = null
	if _main != null and is_instance_valid(_main) and _main.is_inside_tree():
		_place_listener()
		_tick_selection(delta)
		_tick_work(delta)
		_tick_wildlife(delta)
	_tick_ambience(delta)


func _place_listener() -> void:
	var cam: RtsCamera = _main.cam
	if cam == null:
		return
	var g := Vector3(cam.focus.x, _main.terrain.height_at(cam.focus.x, cam.focus.y), cam.focus.y)
	_listener.global_transform = Transform3D(
		cam.global_basis, g.lerp(cam.global_position, SfxConfig.LISTENER_LIFT)
	)


## Gather and build sounds from working Foragers near the listener, and the predator alarm.
func _tick_work(delta: float) -> void:
	_alarm_t = maxf(_alarm_t - delta, 0.0)
	_work_timer -= delta
	if _main.bench_mode or _main.game == null or _work_timer > 0.0:
		return
	_work_timer = SfxConfig.WORK_POLL_S
	var g: Game = _main.game
	var u: Units = _main.units
	var lp := Vector2(_listener.global_position.x, _listener.global_position.z)
	var n: int = 0
	for i in mini(u.count, g.job.size()):
		if u.team[i] != Game.PLAYER:
			continue
		var j: int = g.job[i]
		if j != Game.Job.GATHER and j != Game.Job.BUILD:
			continue
		if (
			float(_work_next.get(i, 0.0)) > g.time
			or u.pos[i].distance_to(lp) > SfxConfig.WORK_RANGE_M
		):
			continue
		var ev: String = "build_knock"
		var every: Vector2 = SfxConfig.BUILD_EVERY
		if j == Game.Job.GATHER:
			ev = str(SfxConfig.GATHER_EVENT.get(g.nodes[g.target[i]].kind, "gather_food"))
			every = SfxConfig.GATHER_EVERY
		_work_next[i] = g.time + _rng.randf_range(every.x, every.y)
		if n < SfxConfig.WORK_MAX_PER_POLL:
			play_at(ev, _unit_world(i) - Vector3(0.0, 0.6, 0.0))
			n += 1
	_check_alarm()


## GDD 12: a hyena near the band -> the nearest Forager barks, the hyena giggles.
func _check_alarm() -> void:
	if _alarm_t > 0.0:
		return
	var hy: Vector2 = _main.animals.hyena_pos()
	if hy == Vector2.INF:
		return
	var u: Units = _main.units
	for i in u.count:
		if u.team[i] == Game.PLAYER and u.pos[i].distance_to(hy) < SfxConfig.ALARM_RANGE_M:
			_alarm_t = SfxConfig.ALARM_COOLDOWN_S
			play_at("alarm", _unit_world(i), _unit_pitch(i))
			play_at("hyena_giggle", _ground(hy, 0.8))
			return


func _ground(p: Vector2, up: float) -> Vector3:
	return Vector3(p.x, maxf(_main.terrain.height_at(p.x, p.y), SpikeConfig.WATER_LEVEL) + up, p.y)


func _tick_wildlife(delta: float) -> void:
	_thunder_t -= delta
	if _thunder_t <= 0.0:
		_thunder_t = _rng.randf_range(SfxConfig.THUNDER_EVERY.x, SfxConfig.THUNDER_EVERY.y)
		play("thunder")
	_wild_t -= delta
	if _wild_t > 0.0:
		return
	_wild_t = _rng.randf_range(SfxConfig.WILDLIFE_EVERY.x, SfxConfig.WILDLIFE_EVERY.y)
	var total: float = 0.0
	for k: String in SfxConfig.WILDLIFE_WEIGHTS:
		total += float(SfxConfig.WILDLIFE_WEIGHTS[k])
	var r: float = _rng.randf() * total
	for k: String in SfxConfig.WILDLIFE_WEIGHTS:
		r -= float(SfxConfig.WILDLIFE_WEIGHTS[k])
		if r <= 0.0:
			play_wildlife(k)
			return


func _rand_of(pts: Array) -> Vector2:
	return pts[_rng.randi() % pts.size()]


## One wildlife call of a kind ("bird_wood", "bird_eagle", "bird_shore", "gazelle", "hyena",
## "bigcat", "croc") from where such an animal is. False when there is none.
func play_wildlife(kind: String) -> bool:
	if _main == null:
		return false
	var ev: String = kind
	var pts: Array = []
	var up: float = 0.6
	match kind:
		"bird_wood":
			var c: Vector2 = GameConfig.WOODLAND if _rng.randf() < 0.6 else GameConfig.HOME
			var off := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
			pts = [c + off * SfxConfig.BIRD_SPREAD_M]
			up = SfxConfig.BIRD_HEIGHT_M
		"bird_eagle", "bird_shore":
			pts = GameConfig.CROCODILES
			up = 18.0 if kind == "bird_eagle" else 2.0
		"gazelle":
			pts = Array(_main.animals.positions_of(0))
			up = 0.8
		"hyena":
			pts = Array(_main.animals.positions_of(2))
			ev = "hyena_whoop" if _rng.randf() < 0.55 else "hyena_giggle"
		"bigcat":
			pts = Array(_main.animals.positions_of(1))
		"croc":
			pts = GameConfig.CROCODILES
			ev = "croc_hiss" if _rng.randf() < 0.5 else "croc_splash"
			up = 0.3
	if pts.is_empty() or not SfxConfig.EVENTS.has(ev):
		return false
	var p: Vector2 = _rand_of(pts)
	if kind == "gazelle" and _rng.randf() < SfxConfig.HOOVES_CHANCE:
		play_at("hooves", _ground(p, 0.2))
	return play_at(ev, _ground(p, up)) != null


# --- ambience ---


## Start the looped ambience layers (fade in over about fade_s). Safe to call again.
func start_ambience(fade_s: float) -> void:
	if _amb_on:
		return
	_amb_on = true
	for layer: String in SfxConfig.AMB_LAYERS:
		var a: AudioStreamPlayer = _amb[layer]
		var s: AudioStream = stream(SfxConfig.path_of(SfxConfig.AMB_LAYERS[layer]))
		if s == null:
			continue
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		a.stream = s
		a.volume_db = -80.0
		a.play(_rng.randf() * maxf(s.get_length() - 1.0, 0.0))
		_amb_gain[layer] = 0.0
	_amb_timer = 0.0
	_mix_targets(SfxConfig.INTRO_AMB_ZOOM, SfxConfig.INTRO_AMB_WATER)
	if fade_s <= 0.0:
		for layer: String in _amb_gain:
			_amb_gain[layer] = _amb_target[layer]


func _mix_targets(zoom: float, water: float) -> void:
	var shore: float = clampf(4.0 * water * (1.0 - water), 0.0, 1.0)
	_amb_target["wind_grass"] = SfxConfig.MIX_WIND_GRASS.x + SfxConfig.MIX_WIND_GRASS.y * zoom
	_amb_target["wind_high"] = (
		SfxConfig.MIX_WIND_HIGH.x + SfxConfig.MIX_WIND_HIGH.y * pow(zoom, 1.5)
	)
	_amb_target["lake"] = (
		SfxConfig.MIX_LAKE.x + SfxConfig.MIX_LAKE.y * clampf(water * 2.0, 0.0, 1.0)
	)
	_amb_target["insects"] = maxf(
		0.0, (SfxConfig.MIX_INSECTS.x + SfxConfig.MIX_INSECTS.y * zoom) * (1.0 - water)
	)
	_amb_target["frogs"] = SfxConfig.MIX_FROGS.x + SfxConfig.MIX_FROGS.y * shore


func _tick_ambience(delta: float) -> void:
	if not _amb_on:
		return
	_amb_timer -= delta
	if _amb_timer <= 0.0 and _main != null and is_instance_valid(_main) and _main.cam != null:
		_amb_timer = SfxConfig.AMB_UPDATE_S
		var cam: RtsCamera = _main.cam
		var zoom: float = clampf(
			inverse_lerp(SpikeConfig.CAM_MIN_H, SpikeConfig.CAM_MAX_H, cam.height), 0.0, 1.0
		)
		_mix_targets(zoom, water_near(cam.focus))
	var k: float = minf(1.0, delta * SfxConfig.AMB_SMOOTH)
	for layer: String in _amb:
		var g: float = lerpf(float(_amb_gain[layer]), float(_amb_target[layer]), k)
		_amb_gain[layer] = g
		(_amb[layer] as AudioStreamPlayer).volume_db = linear_to_db(maxf(g, 0.0001))


## Fraction of probe points round p that are under the lake (0..1).
func water_near(p: Vector2) -> float:
	if _main == null or _main.terrain == null:
		return 0.0
	var wet: int = 0
	var n: int = 0
	for r: float in SfxConfig.WATER_RINGS:
		for k in SfxConfig.WATER_POINTS:
			var a: float = TAU * float(k) / float(SfxConfig.WATER_POINTS)
			var q: Vector2 = p + Vector2(cos(a), sin(a)) * r
			n += 1
			if _main.terrain.height_at(q.x, q.y) < SpikeConfig.WATER_LEVEL:
				wet += 1
	return float(wet) / float(maxi(n, 1))


## Current linear gain of an ambience layer (tests read it).
func ambience_gain(layer: String) -> float:
	return float(_amb_gain.get(layer, 0.0))


# --- intro ---


func _on_intro_cue(cue_name: String) -> void:
	if _intro == null or _intro.capture_mode:
		return
	var at: float = float(IntroConfig.CUES.get(cue_name, _intro.t))
	for ev: Array in SfxConfig.INTRO_EVENTS:
		if ev[0] == cue_name:
			_intro_pending.append([at + float(ev[1]), ev[2], ev[3], float(ev[4])])
	if cue_name == "climb" and not _intro_climb_done:
		_intro_climb_done = true
		_queue_climb()


## Bark scrapes and rustles down the trunk, the landing thud, footsteps to the band, band calls.
func _queue_climb() -> void:
	if _intro.local_root == null:
		return
	var ct: Vector4 = _intro.local_root.climber_times()
	var t: float = ct.x
	var k: int = 0
	while t < ct.y:
		_intro_pending.append([t, "sfx", "bark_scrape", -8.0])
		if k % 3 == 1:
			_intro_pending.append([t + 0.12, "sfx", "rustle", -12.0])
		t += SfxConfig.CLIMB_STEP_S
		k += 1
	_intro_pending.append([ct.z - 0.05, "sfx", "land_thud", -4.0])
	_intro_pending.append([ct.z, "sfx", "rustle", -10.0])
	t = ct.z + 0.4
	while t < ct.w:
		_intro_pending.append([t, "sfx", "footstep", -10.0])
		t += SfxConfig.WALK_STEP_S
	# the band answers when the climber arrives, at the latest before the hand-over fade
	var calls_at: float = minf(ct.w, IntroConfig.FADE_START_T - SfxConfig.BAND_CALL_LEAD_S)
	for c: Vector2 in SfxConfig.BAND_CALLS:
		_intro_pending.append([calls_at + c.x, "voice", str(c.y), -6.0])
	print_verbose("Sfx climber times ", ct)


func _tick_intro() -> void:
	if _intro.capture_mode:
		return
	var now: float = _intro.t
	var keep: Array[Array] = []
	for ev: Array in _intro_pending:
		if float(ev[0]) > now:
			keep.append(ev)
		else:
			_fire_intro(str(ev[1]), str(ev[2]), float(ev[3]))
	_intro_pending = keep
	# the space hum dies away as the dive reaches the air
	if _intro_beds.has("space_hum"):
		var h: AudioStreamPlayer = _intro_beds["space_hum"]
		var f: float = clampf(
			inverse_lerp(SfxConfig.HUM_FADE.x, SfxConfig.HUM_FADE.y, now), 0.0, 1.0
		)
		h.volume_db = SfxConfig.HUM_DB + linear_to_db(maxf(1.0 - f, 0.0001))


func _fire_intro(kind: String, sound: String, db: float) -> void:
	match kind:
		"bed", "one":
			var s: AudioStream = stream(SfxConfig.intro_path(sound))
			if s == null:
				return
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = sound == "space_hum"
			var p := AudioStreamPlayer.new()
			p.bus = "Ambience" if kind == "bed" else "SFX"
			p.stream = s
			p.volume_db = db
			add_child(p)
			p.play()
			played["intro:" + sound] = 1
			if kind == "bed":
				_intro_beds[sound] = p
			else:
				p.finished.connect(p.queue_free)
		"amb":
			start_ambience(3.0)
		"fade":
			_fade_intro(IntroConfig.FADE_SECONDS + 1.0)
		"sfx":
			played["intro:" + sound] = 1
			play(sound, db)
		"voice":
			played["intro:band_call"] = 1
			play("contact", db, float(sound))


func _on_intro_finished() -> void:
	_intro_pending.clear()
	start_ambience(1.0)
	var skipped: bool = _intro.t < IntroConfig.FADE_START_T - 0.5
	_fade_intro(IntroConfig.SKIP_FADE_SECONDS if skipped else IntroConfig.FADE_SECONDS + 1.0)


func _fade_intro(seconds: float) -> void:
	for k: String in _intro_beds:
		var p: AudioStreamPlayer = _intro_beds[k]
		if not is_instance_valid(p):
			continue
		var tw: Tween = create_tween()
		tw.tween_property(p, "volume_db", -60.0, seconds)
		tw.tween_callback(p.queue_free)
	_intro_beds.clear()


# --- menu: Sound on/off + Volume panel (GDD 8: hit areas at least 130 px) ---


func _add_menu() -> void:
	if _menu_added:
		return
	_menu_added = true
	PerfOverlay.add_button(
		"sound", "Sound: off" if muted else "Sound: on", func() -> void: set_muted(not muted)
	)
	PerfOverlay.add_button("volume", "Volume", _toggle_panel)
	_panel = PanelContainer.new()
	_panel.name = "VolumePanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.067, 0.082, 0.102, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18.0)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = SfxConfig.PANEL_POS
	_panel.custom_minimum_size = Vector2(SfxConfig.PANEL_WIDTH, 0.0)
	_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_panel.add_child(box)
	for bus: String in ["Master"] + SfxConfig.BUSES:
		box.add_child(_slider_row(bus))
	PerfOverlay.add_panel(_panel)


func _slider_row(bus: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, SfxConfig.ROW_PX)
	var l := Label.new()
	l.text = str(SfxConfig.SLIDER_NAMES[bus])
	l.custom_minimum_size = Vector2(250.0, 0.0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.965, 0.953, 0.925))
	row.add_child(l)
	var s := HSlider.new()
	s.name = bus
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(volumes[bus])
	s.custom_minimum_size = Vector2(SfxConfig.PANEL_WIDTH - 290.0, SfxConfig.ROW_PX)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.35, 0.37, 0.4)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.078, 0.6, 0.53)
	fill.content_margin_top = 6.0
	fill.content_margin_bottom = 6.0
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.value_changed.connect(func(v: float) -> void: set_volume(bus, v))
	row.add_child(s)
	return row


func _toggle_panel() -> void:
	play("ui_tap")
	if _panel != null:
		_panel.visible = not _panel.visible
