class_name IntroTitles
extends CanvasLayer

## The two title cards of the opening intro (owner 2026-10-11): "About 7 million years ago" over
## the globe, then "About 4.2 million years ago" with the place line during the dive. White
## Cinzel (SIL OFL 1.1) with a soft shadow, the place line in EB Garamond Italic (SIL OFL 1.1),
## fading in and out on IntroConfig.TITLE_* windows. update(t) is a pure function of the
## timeline, so the screenshot bot can seek.

const FONT_TITLE: String = "res://assets/fonts/Cinzel-Variable.ttf"
const FONT_SUB: String = "res://assets/fonts/EBGaramond-Italic-Variable.ttf"
## Sizes at the 1920 x 1080 base (canvas_items stretch scales them with the screen).
const SIZE_TITLE: int = 78
const SIZE_SUB: int = 44
const TITLE_WEIGHT: int = 500
const SUB_WEIGHT: int = 450
const TRACKING_PX: int = 5
## Card centre as a fraction of the screen height.
const CARD_Y: float = 0.70
## Rise over the card's life (px) for a little motion.
const DRIFT_PX: float = 14.0
const SHADOW := Color(0.0, 0.0, 0.0, 0.5)

var _globe: Control
var _dive: Control


func _ready() -> void:
	layer = 4
	var title_font := _font(FONT_TITLE, TITLE_WEIGHT, TRACKING_PX)
	var sub_font := _font(FONT_SUB, SUB_WEIGHT, 1)
	_globe = _card([[IntroConfig.TITLE_GLOBE_TEXT, title_font, SIZE_TITLE]])
	_dive = _card(
		[
			[IntroConfig.TITLE_DIVE_TEXT, title_font, SIZE_TITLE],
			[IntroConfig.TITLE_DIVE_SUB, sub_font, SIZE_SUB],
		]
	)
	update(0.0)


func _font(path: String, weight: int, tracking: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = tracking
	return fv


func _card(lines: Array) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = CARD_Y
	box.anchor_bottom = CARD_Y
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	for l: Array in lines:
		var ls := LabelSettings.new()
		ls.font = l[1]
		ls.font_size = int(l[2])
		ls.font_color = Color(1.0, 1.0, 1.0)
		ls.shadow_color = SHADOW
		ls.shadow_size = 14
		ls.shadow_offset = Vector2(0.0, 3.0)
		var lab := Label.new()
		lab.text = str(l[0])
		lab.label_settings = ls
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lab)
	return root


## Opacity 0..1 of a card window [in0, in1, out0, out1] at time t (smooth in and out).
static func card_alpha(w: Vector4, t: float) -> float:
	return smoothstep(w.x, w.y, t) * (1.0 - smoothstep(w.z, w.w, t))


func update(t: float) -> void:
	_apply(_globe, IntroConfig.TITLE_GLOBE, t)
	_apply(_dive, IntroConfig.TITLE_DIVE, t)


func _apply(card: Control, w: Vector4, t: float) -> void:
	var a: float = card_alpha(w, t)
	card.visible = a > 0.002
	card.modulate.a = a
	var life: float = clampf((t - w.x) / maxf(w.w - w.x, 0.01), 0.0, 1.0)
	card.position.y = DRIFT_PX * (0.5 - life)
