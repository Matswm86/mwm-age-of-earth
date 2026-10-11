class_name RtsCamera
extends Camera3D

## Steep RTS camera (GDD section 8): looks north (-Z) at `focus` on the ground; height 18-60 m,
## tilt 48 deg at the near end and 55 deg at the far end. Two-finger drag pans, pinch zooms
## (driven by Main). The ground height under the focus is smoothed so panning over ridges
## does not shake the view.

var terrain: RtsTerrain
var focus: Vector2 = Vector2(256.0, 256.0)
var height: float = SpikeConfig.CAM_DEFAULT_H
## Tilt-shift depth of field on the top and bottom screen edges (WorldLook); off on Low.
var tilt_shift: bool = true
var _ground_y: float = 0.0
var _ca: CameraAttributesPractical


func setup(t: RtsTerrain, at: Vector2) -> void:
	terrain = t
	fov = SpikeConfig.CAM_FOV
	near = 0.5
	far = 400.0
	focus = at
	_ground_y = terrain.height_at(at.x, at.y)
	current = true
	_ca = WorldLook.make_camera_attributes()
	attributes = _ca
	apply()


func tilt_deg() -> float:
	var t: float = inverse_lerp(SpikeConfig.CAM_MIN_H, SpikeConfig.CAM_MAX_H, height)
	return lerpf(SpikeConfig.CAM_TILT_NEAR, SpikeConfig.CAM_TILT_FAR, clampf(t, 0.0, 1.0))


func apply() -> void:
	height = clampf(height, SpikeConfig.CAM_MIN_H, SpikeConfig.CAM_MAX_H)
	focus = focus.clamp(Vector2.ZERO, Vector2(SpikeConfig.MAP_SIZE, SpikeConfig.MAP_SIZE))
	var tilt: float = deg_to_rad(tilt_deg())
	var back: float = height / tan(tilt)
	position = Vector3(focus.x, _ground_y + height, focus.y + back)
	look_at(Vector3(focus.x, _ground_y, focus.y), Vector3.UP)
	if _ca != null:
		WorldLook.update_tilt_shift(_ca, height / sin(tilt), tilt_shift)


## Metres of ground per screen pixel at the focus (for panning).
func metres_per_px() -> float:
	var dist: float = height / sin(deg_to_rad(tilt_deg()))
	var vh: float = get_viewport().get_visible_rect().size.y
	return 2.0 * dist * tan(deg_to_rad(fov * 0.5)) / maxf(vh, 1.0)


func pan_pixels(delta_px: Vector2) -> void:
	var mpp: float = metres_per_px()
	focus.x -= delta_px.x * mpp
	focus.y -= delta_px.y * mpp / sin(deg_to_rad(tilt_deg()))
	apply()


func zoom_by(factor: float) -> void:
	height *= factor
	apply()


func _process(delta: float) -> void:
	var gy: float = maxf(terrain.height_at(focus.x, focus.y), SpikeConfig.WATER_LEVEL)
	_ground_y = lerpf(_ground_y, gy, minf(1.0, delta * 3.0))
	apply()
