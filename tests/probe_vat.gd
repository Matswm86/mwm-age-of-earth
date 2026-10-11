extends SceneTree
## Dev probe (not shipped): checks the VAT vertex-id mapping (UV2.x) against the baked frame 0.
func _init() -> void:
	var v: VatModel = VatModel.load_model("australopith", true)
	var arr: Array = v.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var img: Image = (v.material.get_shader_parameter("vat") as Texture2D).get_image()
	print("mesh verts ", verts.size(), " uv2 ", uv2.size(), " vcount ", v.vertices, " fmt ", img.get_format())
	var bad: int = 0
	var worst: float = 0.0
	for k in verts.size():
		var vid: int = int(uv2[k].x * v.vertices)
		var c: Color = img.get_pixel((vid % 1024) * 2, vid / 1024)
		var d: float = verts[k].distance_to(Vector3(c.r, c.g, c.b))
		worst = maxf(worst, d)
		if d > 0.01:
			bad += 1
		if k < 5:
			print(k, " uv2 ", uv2[k], " vid ", vid, " mesh ", verts[k], " vat ", Vector3(c.r, c.g, c.b))
	print("bad ", bad, " worst ", worst)
	quit()
