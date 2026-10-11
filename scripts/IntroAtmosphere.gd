class_name IntroAtmosphere
extends RefCounted

## Sunlight transmittance table for the intro atmosphere (Bruneton & Neyret 2008, section 4):
## for each height (v = sqrt(h / 100 km)) and cos sun zenith (u = mu * 0.5 + 0.5) the fraction of
## sunlight that survives the path to the top of the atmosphere, per RGB. Built once at start
## (256 x 64 x 40 steps, about 0.2 s on a laptop) so the shaders read one texel instead of
## ray-marching towards the sun per sample. Constants match shaders/earth_common.gdshaderinc.

const BETA_R: Vector3 = Vector3(5.802e-3, 13.558e-3, 33.1e-3)
const BETA_M_EXT: float = 4.44e-3
const BETA_O: Vector3 = Vector3(0.650e-3, 1.881e-3, 0.085e-3)
const H_R: float = 8.0
const H_M: float = 1.2


static func transmittance_lut() -> ImageTexture:
	var size: Vector2i = IntroConfig.LUT_SIZE
	var steps: int = IntroConfig.LUT_STEPS
	var r_p: float = IntroConfig.PLANET_R
	var r_a: float = IntroConfig.ATMOS_R
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBH)
	for j in size.y:
		var v: float = float(j) / float(size.y - 1)
		var h: float = v * v * (r_a - r_p)
		var r: float = r_p + h
		for i in size.x:
			var mu: float = float(i) / float(size.x - 1) * 2.0 - 1.0
			# distance to the top of the atmosphere along the sun ray from (0, r)
			var b: float = r * mu
			var len: float = -b + sqrt(maxf(b * b - (r * r - r_a * r_a), 0.0))
			var dt: float = len / float(steps)
			var od := Vector3.ZERO
			for k in steps:
				var t: float = dt * (float(k) + 0.5)
				var x: float = sqrt(1.0 - mu * mu) * t
				var y: float = r + mu * t
				var hh: float = maxf(sqrt(x * x + y * y) - r_p, 0.0)
				var ozone: float = maxf(0.0, 1.0 - absf(hh - 25.0) / 15.0)
				od += Vector3(exp(-hh / H_R), exp(-hh / H_M), ozone) * dt
			var tau: Vector3 = BETA_R * od.x + Vector3.ONE * (BETA_M_EXT * od.y) + BETA_O * od.z
			img.set_pixel(i, j, Color(exp(-tau.x), exp(-tau.y), exp(-tau.z)))
	return ImageTexture.create_from_image(img)
