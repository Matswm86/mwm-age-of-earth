class_name SelectBox
extends Control

## Drag-box rectangle drawn while one finger drags on empty ground.

var rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_rect(a: Vector2, b: Vector2) -> void:
	rect = Rect2(a, Vector2.ZERO).expand(b)
	visible = true
	queue_redraw()


func hide_rect() -> void:
	visible = false


func _draw() -> void:
	draw_rect(rect, Color(0.45, 1.0, 0.45, 0.15), true)
	draw_rect(rect, Color(0.45, 1.0, 0.45, 0.9), false, 3.0)
