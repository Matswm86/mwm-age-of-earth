extends CanvasLayer

## Phone performance readout (from game-studio/templates/scripts/PerfOverlay.gd, extended as in
## mwm-wayfarer/scripts/PerfOverlay.gd). Spike version: visible from launch; shows fps, p95 frame
## time over the last 300 frames, GPU and render-thread CPU time, draws, primitives, memory and a
## status line written by Main. Buttons are added by Main through add_button(). A three-finger
## tap hides and shows everything.
## GPU time: Android pins the frame rate to the display refresh even with vsync off, so fps alone
## cannot show headroom; the viewport's measured GPU render time can.

const WINDOW := 300
const TEXT_HZ := 4.0
const INK := Color(0.067, 0.082, 0.102, 0.88)
const INK_DOWN := Color(0.078, 0.431, 0.392, 0.95)
const TEXT := Color(0.965, 0.953, 0.925)

## Extra readout line written by Main (units, speed, quality, sim timings).
var status_line: String = ""

var _label: Label
var _result: Label
var _result_box: PanelContainer
var _panel: Control
var _grid: GridContainer
var _buttons: Dictionary = {}
var _touches: Dictionary = {}
var _frames: PackedFloat32Array = PackedFloat32Array()
var _cursor: int = 0
var _filled: int = 0
var _p95_ms: float = 0.0
var _since_sort: int = 0
var _gpu_ms: float = 0.0
var _cpu_ms: float = 0.0
var _vp_rid: RID
var _text_timer: float = 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frames.resize(WINDOW)
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var stats_box := PanelContainer.new()
	stats_box.add_theme_stylebox_override("panel", _box(INK))
	stats_box.position = Vector2(16.0, 16.0)
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(stats_box)
	_label = _make_label(28, Color(1.0, 0.86, 0.45))
	stats_box.add_child(_label)

	_result_box = PanelContainer.new()
	_result_box.add_theme_stylebox_override("panel", _box(INK))
	_result_box.anchor_left = 0.5
	_result_box.anchor_top = 0.5
	_result_box.anchor_right = 0.5
	_result_box.anchor_bottom = 0.5
	_result_box.offset_left = -900.0
	_result_box.offset_top = -200.0
	_result_box.visible = false
	_panel.add_child(_result_box)
	_result = _make_label(26, TEXT)
	_result_box.add_child(_result)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.anchor_left = 1.0
	_grid.anchor_right = 1.0
	_grid.offset_left = -612.0
	_grid.offset_right = -20.0
	_grid.offset_top = 16.0
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_panel.add_child(_grid)


func _make_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func add_button(id: String, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(290.0, 130.0)
	b.add_theme_font_size_override("font_size", 30)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(INK))
	b.add_theme_stylebox_override("hover", _box(INK))
	b.add_theme_stylebox_override("pressed", _box(INK_DOWN))
	b.add_theme_stylebox_override("disabled", _box(Color(0.2, 0.22, 0.25, 0.88)))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.72, 0.75, 0.78))
	b.pressed.connect(cb)
	_grid.add_child(b)
	_buttons[id] = b


func _box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14.0)
	return sb


func set_button_text(id: String, text: String) -> void:
	if _buttons.has(id):
		(_buttons[id] as Button).text = text


func set_buttons_enabled(on: bool) -> void:
	for id: String in _buttons:
		(_buttons[id] as Button).disabled = not on


## True when a screen point is on a visible button or the result box (Main ignores such touches).
func is_over_ui(p: Vector2) -> bool:
	if not _panel.visible:
		return false
	if _result_box.visible and _result_box.get_global_rect().has_point(p):
		return true
	for id: String in _buttons:
		if (_buttons[id] as Button).get_global_rect().has_point(p):
			return true
	return false


func show_result(text: String) -> void:
	_result.text = text
	_result_box.offset_top = -minf(120.0 + 18.0 * text.count("\n"), 500.0)
	_result_box.visible = true


func hide_result() -> void:
	_result_box.visible = false


func set_ui_visible(on: bool) -> void:
	_panel.visible = on


func is_ui_visible() -> bool:
	return _panel.visible


func p95_ms() -> float:
	return _p95_ms


## GPU render time of the last measured frame in ms (0 where the driver gives no timestamps).
func gpu_ms() -> float:
	return _gpu_ms


## Render-thread CPU time of the last frame in ms (culling and command recording).
func cpu_ms() -> float:
	return _cpu_ms


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = true
			if _touches.size() >= 3:
				_panel.visible = not _panel.visible
				_touches.clear()
		else:
			_touches.erase(touch.index)


func _process(delta: float) -> void:
	_frames[_cursor] = delta * 1000.0
	_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	_cpu_ms = (
		RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid)
		+ RenderingServer.get_frame_setup_time_cpu()
	)
	_cursor = (_cursor + 1) % WINDOW
	_filled = mini(_filled + 1, WINDOW)
	_since_sort += 1
	if _since_sort >= 15:
		_since_sort = 0
		var s := _frames.slice(0, _filled)
		s.sort()
		_p95_ms = s[int(floor((_filled - 1) * 0.95))]
	if not _panel.visible:
		return
	_text_timer -= delta
	if _text_timer > 0.0:
		return
	_text_timer = 1.0 / TEXT_HZ
	var fps := Engine.get_frames_per_second()
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var ram := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_label.text = (
		(
			"%d fps   p95 %.1f ms (300 fr)\nGPU %.1f ms   render CPU %.1f ms\n"
			+ "%d draws   %dk prims\nVRAM %.0f MB   RAM %.0f MB\n%s"
		)
		% [fps, _p95_ms, _gpu_ms, _cpu_ms, int(draws), int(tris / 1000.0), vram, ram, status_line]
	)
