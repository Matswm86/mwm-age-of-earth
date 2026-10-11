class_name IconBaker
extends Node

## Renders HUD icons from the game's own models once at load (DESIGN 4: "a photographic icon
## rendered from the game's own models"): one 160 px transparent SubViewport per icon, its own
## world, a warm key light and sky-ish fill, camera framed on the model's bounds.

const SIZE: int = 160

var icons: Dictionary = {}


## spec: icon id -> [scene builder Callable returning Node3D, yaw (rad), pitch (deg)]
func bake(spec: Dictionary) -> void:
	for id: String in spec:
		var s: Array = spec[id]
		var builder: Callable = s[0]
		icons[id] = _render(builder.call(), float(s[1]), float(s[2]))


func _render(model: Node3D, yaw: float, pitch_deg: float) -> Texture2D:
	var sv := SubViewport.new()
	sv.size = Vector2i(SIZE, SIZE)
	sv.transparent_bg = true
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.86)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = WorldLook.SUN_COLOUR
	key.light_energy = 2.2
	key.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sv.add_child(key)
	model.rotation.y = yaw
	sv.add_child(model)
	var aabb: AABB = _bounds(model, Transform3D.IDENTITY)
	var c: Vector3 = aabb.get_center()
	var r: float = aabb.size.length() * 0.5
	var cam := Camera3D.new()
	cam.fov = 30.0
	var pitch: float = deg_to_rad(pitch_deg)
	var dist: float = r / sin(deg_to_rad(15.0)) * 0.72
	cam.position = c + Vector3(0.0, sin(pitch), cos(pitch)) * dist
	cam.near = dist * 0.05
	cam.far = dist * 4.0
	sv.add_child(cam)
	cam.look_at(c, Vector3.UP)
	cam.current = true
	return sv.get_texture()


func _bounds(n: Node, xf: Transform3D) -> AABB:
	var here: Transform3D = xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	var out := AABB()
	var first: bool = true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b: AABB = _bounds(c, here)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out
