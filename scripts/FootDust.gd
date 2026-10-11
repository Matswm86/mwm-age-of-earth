class_name FootDust
extends GPUParticles3D

## Footstep dust under walking units (owner feedback 2026-10-11: dust under walking groups): one
## particle system; every 0.18 s each walking unit on screen (at most 24) kicks up a soft puff at
## its feet. Main calls tick() every frame; it only emits on the High preset.

const EVERY_S: float = 0.18
const MAX_PUFFS: int = 24

var _timer: float = 0.0


func _init() -> void:
	name = "FootDust"
	amount = 256
	lifetime = 1.4
	emitting = false
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-600, -50, -600), Vector3(1200, 100, 1200))
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0.0, 0.05, 0.0)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.4))
	c.add_point(Vector2(1.0, 1.6))
	var curve := CurveTexture.new()
	curve.curve = c
	pm.scale_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.5))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	process_material = pm
	draw_pass_1 = _puff_quad(Color(0.66, 0.56, 0.42, 0.55), 0.7)


static func create(parent: Node) -> FootDust:
	var f := FootDust.new()
	parent.add_child(f)
	return f


## `on` false (Low preset): no new puffs.
func tick(delta: float, units: Units, on: bool) -> void:
	if not on:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = EVERY_S
	var n: int = 0
	for i in units.count:
		if n >= MAX_PUFFS or units.moving[i] == 0 or not units.is_seen(i):
			continue
		var p: Vector2 = units.pos[i]
		var at := Vector3(p.x, units.hgt[i] + 0.1, p.y)
		var v := Vector3(randf_range(-0.3, 0.3), 0.25, randf_range(-0.3, 0.3))
		# flags 7 = position | rotation and scale | velocity
		emit_particle(Transform3D(Basis(), at), v, Color(1, 1, 1, 1), Color(), 7)
		n += 1


static func _puff_quad(col: Color, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = gt
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	q.material = m
	return q
