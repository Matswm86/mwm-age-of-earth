class_name IntroStars
extends MultiMeshInstance3D

## The real night sky for the intro: the 9,096 stars of the Yale Bright Star Catalogue (5th ed.)
## with a position and V magnitude, as one MultiMesh of camera-facing quads
## (shaders/intro_stars.gdshader). Source data: assets/intro/stars_bsc5.png, two RGBA pixels
## per star (RA 16 bit, Dec 16 bit; V mag, B-V), written by tools/intro/bake_intro_assets.py.

var material: ShaderMaterial


func build() -> void:
	var tex: Texture2D = load(IntroConfig.TEX_DIR + "stars_bsc5.png")
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var d: PackedByteArray = img.get_data()
	var count: int = 0
	var total: int = d.size() / 8
	for s in total:
		if d[s * 8 + 7] == 255:
			count += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mm.mesh = quad
	mm.instance_count = count
	var k: int = 0
	for s in total:
		var o: int = s * 8
		if d[o + 7] != 255:
			continue
		var ra: float = float(d[o] * 256 + d[o + 1]) / 65535.0 * 360.0
		var dec: float = float(d[o + 2] * 256 + d[o + 3]) / 65535.0 * 180.0 - 90.0
		var vmag: float = float(d[o + 4]) / 25.0 - 2.0
		var bv: float = float(d[o + 5]) / 100.0 - 0.5
		var dir: Vector3 = IntroConfig.geo_dir(dec, ra - IntroConfig.SKY_RA_AT_LON0)
		var flux: float = pow(10.0, -0.4 * (vmag - 1.0))
		mm.set_instance_transform(k, Transform3D.IDENTITY)
		mm.set_instance_custom_data(k, Color(dir.x, dir.y, dir.z, flux))
		mm.set_instance_color(k, bv_colour(bv))
		k += 1
	multimesh = mm
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/intro_stars.gdshader")
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# quads are placed in the vertex shader round the camera; never cull them
	custom_aabb = AABB(Vector3(-1e9, -1e9, -1e9), Vector3(2e9, 2e9, 2e9))


## Star colour from the B-V index: temperature (Ballesteros 2012), then a black-body RGB fit.
static func bv_colour(bv: float) -> Color:
	var b: float = clampf(bv, -0.4, 2.0)
	var t: float = 4600.0 * (1.0 / (0.92 * b + 1.7) + 1.0 / (0.92 * b + 0.62))
	var x: float = t / 100.0
	var r: float = 1.0
	var g: float
	var bl: float
	if x <= 66.0:
		g = clampf((99.47 * log(x) - 161.12) / 255.0, 0.0, 1.0)
		bl = 0.0 if x <= 19.0 else clampf((138.52 * log(x - 10.0) - 305.04) / 255.0, 0.0, 1.0)
	else:
		r = clampf(329.7 * pow(x - 60.0, -0.1332) / 255.0, 0.0, 1.0)
		g = clampf(288.12 * pow(x - 60.0, -0.0755) / 255.0, 0.0, 1.0)
		bl = 1.0
	# keep stars mostly white to the eye; colour shows as a tint
	return Color(r, g, bl).lerp(Color(1.0, 1.0, 1.0), 0.35)
