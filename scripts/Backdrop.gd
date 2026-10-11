class_name Backdrop
extends MeshInstance3D

## Distant hills all round the Rift Lake map (the far shore and the basalt hills of the basin),
## so low and cinematic views meet a continuous horizon instead of the bare sky texture's ground
## band. One ring mesh 1.6-3.6 km from the map centre, heights from noise (rises from below the
## water at the inner edge to 6-42 m: a low far shore under the sky's escarpment),
## vertex-coloured olive woodland patches fading to blue-grey
## air with distance (its own haze; scene fog is off on it). Never seen from the default RTS
## camera. Main adds it; the intro does not.

const CENTRE := Vector2(256.0, 256.0)
const R_IN: float = 1600.0
const R_OUT: float = 3600.0
const SEGMENTS: int = 768
const RINGS: int = 24
const LOW := Color(0.16, 0.21, 0.12)
const HIGH := Color(0.34, 0.33, 0.25)
## Aerial-perspective colour of distant hills (blue-grey, not the warm ground haze).
const AIR := Color(0.36, 0.42, 0.46)
## Share of the haze colour mixed into the hills (near ring .. far ring).
const HAZE_NEAR: float = 0.2
const HAZE_FAR: float = 0.5


func _ready() -> void:
	name = "Backdrop"
	mesh = _build()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# own haze (baked into the vertex colours, HAZE_NEAR..HAZE_FAR): scene fog at 2-3 km
	# bleached the hills into
	# the sky (2026-10-11)
	m.disable_fog = true
	material_override = m


func _build() -> ArrayMesh:
	var fn := FastNoiseLite.new()
	fn.seed = 4200
	fn.frequency = 0.0009
	fn.fractal_octaves = 5
	var patch := FastNoiseLite.new()
	patch.seed = 4201
	patch.frequency = 0.012
	patch.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RINGS + 1:
		var t: float = float(j) / RINGS
		var r: float = lerpf(R_IN, R_OUT, t)
		for i in SEGMENTS + 1:
			var a: float = TAU * float(i % SEGMENTS) / SEGMENTS
			var p := Vector2(cos(a), sin(a)) * r + CENTRE
			var n: float = fn.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			# from 8 m under the water at the inner edge to the ridge line
			var h: float = lerpf(-8.0, lerpf(6.0, 42.0, n * n), smoothstep(0.0, 0.6, t))
			var c: Color = LOW.lerp(HIGH, clampf(h / 110.0 + (n - 0.5) * 0.3, 0.0, 1.0))
			# woodland patches on the slopes
			c = c.darkened(0.35 * clampf(patch.get_noise_2d(p.x, p.y) + 0.2, 0.0, 1.0))
			c = c.lerp(AIR, lerpf(HAZE_NEAR, HAZE_FAR, t))
			st.set_color(c)
			st.add_vertex(Vector3(p.x, h, p.y))
	for j in RINGS:
		for i in SEGMENTS:
			var a0: int = j * (SEGMENTS + 1) + i
			var b0: int = a0 + SEGMENTS + 1
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	st.generate_normals()
	return st.commit()
