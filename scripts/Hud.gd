class_name Hud
extends CanvasLayer

## Landscape HUD (GDD 8, DESIGN 2.3-5), light panels, every touch target >= 130 px (48 dp):
## resource bar top-left, age + clock top-centre, menu top-right (Bench lives in the
## PerfOverlay panel it opens), idle-Forager and Home buttons on the right edge, command card
## (2 x 3, 150 px) bottom-right, selection strip bottom-centre with a clear button, discovery
## banner, "+N" drop floaters, onboarding hints (pulsing ring + icon + at most 6 words) and the
## placement tick / cross. Main fills the card and owns the game; this node only shows and emits.

signal card_pressed(id: String)
signal idle_pressed
signal home_pressed
signal clear_pressed
signal menu_pressed
signal place_answer(ok: bool)

const RES_KEYS: Array[String] = ["food", "wood", "stone"]

var cam: Camera3D
var icons: Dictionary = {}
var root: Control
var _theme: Theme
var _res_labels: Dictionary = {}
var _pop_label: Label
var _age_label: Label
var _clock_label: Label
var _card: GridContainer
var _card_buttons: Array[Button] = []
var _card_ids: Array[String] = []
var _card_bars: Array[ColorRect] = []
var _idle_btn: Button
var _idle_label: Label
var _home_btn: Button
var _menu_btn: Button
var _sel_panel: PanelContainer
var _sel_icon: TextureRect
var _sel_label: Label
var _banner: Label
var _hint: HintDraw
var _tick: Button
var _cross: Button
var _floaters: Array[Dictionary] = []
var _banner_t: float = 0.0
var _place_world := Vector3.INF


## Ring + icon + short label for the current onboarding hint (draws on top of the HUD).
class HintDraw:
	extends Control
	var screen := Vector2.INF
	var colour := Color(0.608, 0.878, 0.478)
	var text: String = ""
	var icon: Texture2D
	var t: float = 0.0
	var font_size: int = 36

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if screen == Vector2.INF or text == "":
			return
		var pulse: float = 0.5 + 0.5 * sin(t * 5.0)
		var r: float = 62.0 + 14.0 * pulse
		draw_arc(screen, r + 3.0, 0.0, TAU, 48, Color(0.118, 0.110, 0.102, 0.9), 9.0, true)
		draw_arc(screen, r, 0.0, TAU, 48, Color(colour, 0.6 + 0.4 * pulse), 5.0, true)
		# pointing hand: a finger-tip arrow from the label toward the ring
		var font: Font = get_theme_default_font()
		var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var w: float = ts.x + (96.0 if icon != null else 0.0) + 48.0
		var h: float = 96.0
		var vp: Vector2 = get_viewport_rect().size
		var box := Vector2(screen.x - w * 0.5, screen.y - r - 40.0 - h)
		if box.y < 140.0:
			box.y = screen.y + r + 40.0
		box.x = clampf(box.x, 48.0, vp.x - w - 48.0)
		var rect := Rect2(box, Vector2(w, h))
		draw_rect(rect, Color(0.949, 0.925, 0.878, 0.95), true)
		draw_rect(rect, Color(0.118, 0.110, 0.102, 0.9), false, 3.0)
		var tip: Vector2 = screen + (rect.get_center() - screen).normalized() * (r + 8.0)
		var base: Vector2 = (
			rect.get_center() + (screen - rect.get_center()).normalized() * (h * 0.5)
		)
		draw_line(base, tip, Color(0.118, 0.110, 0.102, 0.9), 6.0, true)
		draw_circle(tip, 9.0, Color(colour, 1.0))
		var x: float = box.x + 24.0
		if icon != null:
			draw_texture_rect(icon, Rect2(Vector2(x, box.y + 8.0), Vector2(80.0, 80.0)), false)
			x += 96.0
		draw_string(
			font,
			Vector2(x, box.y + h * 0.5 + ts.y * 0.32),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.165, 0.149, 0.125)
		)


func _ready() -> void:
	layer = 10
	_theme = _make_theme()
	root = Control.new()
	root.name = "HudRoot"
	root.theme = _theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_resource_bar()
	_build_top()
	_build_right()
	_build_card()
	_build_selection()
	_banner = _label("", 64, GameConfig.TEXT)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-600.0, 190.0)
	_banner.size = Vector2(1200.0, 100.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_color", Color(1, 1, 1))
	_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_banner.add_theme_constant_override("shadow_offset_x", 3)
	_banner.add_theme_constant_override("shadow_offset_y", 3)
	_banner.visible = false
	root.add_child(_banner)
	_hint = HintDraw.new()
	root.add_child(_hint)
	_tick = _plain_button("✓", GameConfig.PRIMARY, Color(1, 1, 1))
	_cross = _plain_button("✕", GameConfig.DANGER, Color(1, 1, 1))
	for b: Button in [_tick, _cross]:
		b.custom_minimum_size = Vector2(130.0, 130.0)
		b.size = Vector2(130.0, 130.0)
		b.visible = false
		b.add_theme_font_size_override("font_size", 64)
		root.add_child(b)
	_tick.pressed.connect(func() -> void: place_answer.emit(true))
	_cross.pressed.connect(func() -> void: place_answer.emit(false))


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = GameConfig.FONT_BODY
	var panel := StyleBoxFlat.new()
	panel.bg_color = GameConfig.PANEL
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(16)
	panel.border_color = Color(0.118, 0.110, 0.102, 0.25)
	panel.set_border_width_all(2)
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := panel.duplicate() as StyleBoxFlat
	normal.set_content_margin_all(8)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = GameConfig.PANEL_ALT
	pressed.set_border_width_all(4)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.85, 0.83, 0.79, 0.85)
	for st: String in ["normal", "hover", "focus"]:
		t.set_stylebox(st, "Button", normal)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", GameConfig.TEXT)
	t.set_color("font_pressed_color", "Button", GameConfig.TEXT)
	t.set_color("font_hover_color", "Button", GameConfig.TEXT)
	t.set_color("font_disabled_color", "Button", GameConfig.TEXT_DIM)
	t.set_color("font_color", "Label", GameConfig.TEXT)
	return t


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _plain_button(text: String, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.118, 0.110, 0.102, 0.8)
	for st: String in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sb)
	for st: String in ["font_color", "font_pressed_color", "font_hover_color"]:
		b.add_theme_color_override(st, fg)
	return b


func _icon_rect(id: String, px: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icons.get(id, null)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_resource_bar() -> void:
	var p := PanelContainer.new()
	p.name = "Resources"
	p.position = Vector2(GameConfig.SAFE_M, GameConfig.SAFE_M * 0.5)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(p)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	p.add_child(hb)
	for k in RES_KEYS:
		hb.add_child(_icon_rect(k, 64.0))
		var l := _label("0", GameConfig.FONT_NUM, GameConfig.TEXT)
		l.custom_minimum_size = Vector2(96.0, 0.0)
		_res_labels[k] = l
		hb.add_child(l)
	hb.add_child(_icon_rect("forager", 64.0))
	_pop_label = _label("0/0", GameConfig.FONT_NUM, GameConfig.TEXT)
	hb.add_child(_pop_label)


func _build_top() -> void:
	var p := PanelContainer.new()
	p.name = "Age"
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.position = Vector2(-40.0, GameConfig.SAFE_M * 0.5)
	p.custom_minimum_size = Vector2(440.0, 0.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	p.add_child(hb)
	_age_label = _label("Age 1 · The Ground", GameConfig.FONT_SMALL, GameConfig.TEXT)
	hb.add_child(_age_label)
	_clock_label = _label("0:00", GameConfig.FONT_SMALL, GameConfig.TEXT_DIM)
	hb.add_child(_clock_label)


func _build_right() -> void:
	_menu_btn = Button.new()
	_menu_btn.text = "Menu"
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_btn.position = Vector2(-GameConfig.SAFE_M - 190.0, GameConfig.SAFE_M * 0.5)
	_menu_btn.size = Vector2(190.0, 130.0)
	_menu_btn.pressed.connect(func() -> void: menu_pressed.emit())
	root.add_child(_menu_btn)
	_idle_btn = _side_button("forager", "Idle")
	_idle_btn.position = Vector2(-GameConfig.SAFE_M - GameConfig.BTN, 300.0)
	_idle_btn.pressed.connect(func() -> void: idle_pressed.emit())
	_idle_label = _idle_btn.get_node("Count") as Label
	_home_btn = _side_button("home", "Home")
	_home_btn.position = Vector2(
		-GameConfig.SAFE_M - GameConfig.BTN, 300.0 - GameConfig.BTN - GameConfig.BTN_GAP
	)
	_home_btn.pressed.connect(func() -> void: home_pressed.emit())


func _side_button(icon_id: String, caption: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.size = Vector2(GameConfig.BTN, GameConfig.BTN)
	b.custom_minimum_size = Vector2(GameConfig.BTN, GameConfig.BTN)
	var ic: TextureRect = _icon_rect(icon_id, 96.0)
	ic.position = Vector2(27.0, 6.0)
	ic.size = Vector2(96.0, 96.0)
	b.add_child(ic)
	var l := _label(caption, 28, GameConfig.TEXT)
	l.name = "Count"
	l.position = Vector2(0.0, 100.0)
	l.size = Vector2(GameConfig.BTN, 40.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(l)
	root.add_child(b)
	return b


func _build_card() -> void:
	_card = GridContainer.new()
	_card.name = "CommandCard"
	_card.columns = 3
	_card.add_theme_constant_override("h_separation", int(GameConfig.BTN_GAP))
	_card.add_theme_constant_override("v_separation", int(GameConfig.BTN_GAP))
	_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var w: float = GameConfig.BTN * 3.0 + GameConfig.BTN_GAP * 2.0
	var h: float = GameConfig.BTN * 2.0 + GameConfig.BTN_GAP
	_card.position = Vector2(-GameConfig.SAFE_M - w, -GameConfig.SAFE_M - h)
	_card.size = Vector2(w, h)
	root.add_child(_card)
	for k in 6:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(GameConfig.BTN, GameConfig.BTN)
		var ic: TextureRect = _icon_rect("", 92.0)
		ic.name = "Icon"
		ic.position = Vector2(29.0, 4.0)
		ic.size = Vector2(92.0, 92.0)
		b.add_child(ic)
		var l := _label("", 28, GameConfig.TEXT)
		l.name = "Caption"
		l.position = Vector2(0.0, 98.0)
		l.size = Vector2(GameConfig.BTN, 44.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(l)
		var bar := ColorRect.new()
		bar.color = Color(GameConfig.PRIMARY, 0.85)
		bar.position = Vector2(8.0, GameConfig.BTN - 12.0)
		bar.size = Vector2(0.0, 6.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)
		var idx: int = k
		b.pressed.connect(func() -> void: _on_card(idx))
		_card.add_child(b)
		_card_buttons.append(b)
		_card_bars.append(bar)
		_card_ids.append("")
	set_card([])


func _on_card(k: int) -> void:
	if _card_ids[k] != "":
		card_pressed.emit(_card_ids[k])


## entries: Array of {id, icon, caption, enabled, progress (0..1, optional), badge (optional)}
func set_card(entries: Array) -> void:
	for k in 6:
		var b: Button = _card_buttons[k]
		if k >= entries.size():
			b.visible = false
			b.disabled = true
			_card_ids[k] = ""
			(b.get_node("Icon") as TextureRect).texture = null
			(b.get_node("Caption") as Label).text = ""
			_card_bars[k].size.x = 0.0
			continue
		var e: Dictionary = entries[k]
		b.visible = true
		_card_ids[k] = str(e.get("id", ""))
		b.disabled = not bool(e.get("enabled", true))
		(b.get_node("Icon") as TextureRect).texture = icons.get(str(e.get("icon", "")), null)
		(b.get_node("Icon") as TextureRect).modulate = Color(
			1, 1, 1, 1.0 if not b.disabled else 0.45
		)
		(b.get_node("Caption") as Label).text = str(e.get("caption", ""))
		var pr: float = float(e.get("progress", 0.0))
		_card_bars[k].size.x = (GameConfig.BTN - 16.0) * clampf(pr, 0.0, 1.0)
	_card.visible = not entries.is_empty()


## Screen centre of command card button k (for hints).
func card_button_centre(id: String) -> Vector2:
	for k in 6:
		if _card_ids[k] == id and _card_buttons[k].visible:
			return _card_buttons[k].get_global_rect().get_center()
	return Vector2.INF


func home_button_centre() -> Vector2:
	return _home_btn.get_global_rect().get_center()


func _build_selection() -> void:
	_sel_panel = PanelContainer.new()
	_sel_panel.name = "Selection"
	_sel_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sel_panel.position = Vector2(-470.0, -GameConfig.SAFE_M - 150.0)
	_sel_panel.custom_minimum_size = Vector2(760.0, 150.0)
	_sel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_sel_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	_sel_panel.add_child(hb)
	_sel_icon = _icon_rect("", 110.0)
	hb.add_child(_sel_icon)
	_sel_label = _label("", GameConfig.FONT_BODY, GameConfig.TEXT)
	_sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(_sel_label)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(118.0, 118.0)
	x.add_theme_font_size_override("font_size", 48)
	x.pressed.connect(func() -> void: clear_pressed.emit())
	hb.add_child(x)
	_sel_panel.visible = false


func set_selection(icon_id: String, text: String) -> void:
	_sel_panel.visible = text != ""
	_sel_icon.texture = icons.get(icon_id, null)
	_sel_label.text = text


func set_resources(res: Dictionary, pop: int, cap: int) -> void:
	for k in RES_KEYS:
		(_res_labels[k] as Label).text = str(int(floor(float(res.get(k, 0.0)))))
	_pop_label.text = "%d/%d" % [pop, cap]
	_pop_label.add_theme_color_override(
		"font_color", GameConfig.DANGER if pop >= cap else GameConfig.TEXT
	)


func set_clock(seconds: float) -> void:
	var s: int = int(seconds)
	_clock_label.text = "%d:%02d" % [s / 60, s % 60]


func set_idle(n: int) -> void:
	_idle_label.text = "Idle %d" % n
	_idle_btn.modulate = Color(1, 1, 1, 1.0 if n > 0 else 0.6)


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_t = 2.0


func float_text(world: Vector3, text: String) -> void:
	var l := _label(text, GameConfig.FONT_SMALL, Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.118, 0.110, 0.102))
	l.add_theme_constant_override("outline_size", 8)
	root.add_child(l)
	_floaters.append({"label": l, "world": world, "t": 0.0})


## Onboarding hint at a world point (or a screen point when `screen` is set). Empty text hides it.
func set_hint(
	text: String, world: Vector3, icon_id: String = "", screen := Vector2.INF, red: bool = false
) -> void:
	_hint.text = text
	_hint.icon = icons.get(icon_id, null)
	_hint.colour = GameConfig.ATTACK if red else GameConfig.SELECT
	_hint.set_meta("world", world)
	_hint.set_meta("screen", screen)


## Shows the tick and cross beside a placement ghost at `world` (INF hides them).
func show_place_confirm(world: Vector3, ok: bool) -> void:
	_place_world = world
	_tick.visible = world != Vector3.INF
	_cross.visible = world != Vector3.INF
	_tick.disabled = not ok


func is_over_ui(p: Vector2) -> bool:
	var ctrls: Array[Control] = [_menu_btn, _idle_btn, _home_btn, _sel_panel, _tick, _cross]
	for c in ctrls:
		if c.visible and c.get_global_rect().grow(6.0).has_point(p):
			return true
	if _card.visible:
		for b in _card_buttons:
			if b.visible and b.get_global_rect().grow(6.0).has_point(p):
				return true
	var res_panel: Control = root.get_node("Resources")
	return res_panel.get_global_rect().has_point(p)


func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t / 0.4, 0.0, 1.0)
		_banner.visible = _banner_t > 0.0
	var k: int = 0
	while k < _floaters.size():
		var f: Dictionary = _floaters[k]
		f["t"] = float(f["t"]) + delta
		var l: Label = f["label"]
		var t: float = float(f["t"]) / 0.6
		if t >= 1.0 or cam == null:
			l.queue_free()
			_floaters.remove_at(k)
			continue
		var w: Vector3 = f["world"]
		if cam.is_position_behind(w):
			l.visible = false
		else:
			var sp: Vector2 = cam.unproject_position(w)
			l.position = sp + Vector2(-l.size.x * 0.5, -40.0 * t)
			l.modulate.a = 1.0 - t * t
		k += 1
	_hint.t += delta
	var screen: Vector2 = _hint.get_meta("screen", Vector2.INF)
	var world: Vector3 = _hint.get_meta("world", Vector3.INF)
	if (
		screen == Vector2.INF
		and world != Vector3.INF
		and cam != null
		and not cam.is_position_behind(world)
	):
		screen = cam.unproject_position(world)
		# a world hint whose spot is off-screen is not shown (no ring pointing at the HUD)
		if not root.get_viewport_rect().grow(-40.0).has_point(screen):
			screen = Vector2.INF
	_hint.screen = screen
	_hint.queue_redraw()
	if _place_world != Vector3.INF and cam != null:
		var sp: Vector2 = cam.unproject_position(_place_world)
		_tick.position = sp + Vector2(70.0, -65.0)
		_cross.position = sp + Vector2(-200.0, -65.0)
