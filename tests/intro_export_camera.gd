extends Node

## Writes the intro's planet-stage camera path (IntroConfig keys, evaluated by Intro.gd) to JSON
## for the Blender render (tools/intro/render_earth.py), so video and game share one path.
## godot --headless --audio-driver Dummy res://tests/intro_export_camera.tscn -- <out.json> [fps]
## (dev-only, excluded from the APK with tests/*)
## Godot frame (Y up, km, planet at origin); the Blender script converts axes.


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0]
	var fps: float = args[1].to_float() if args.size() > 1 else 30.0
	var intro: Intro = load("res://scenes/Intro.tscn").instantiate()
	intro.capture_mode = true
	add_child(intro)
	var frames: Array = []
	var n: int = int(ceil((IntroConfig.SWITCH_T + 0.5) * fps))
	for f in n:
		var tt: float = float(f) / fps
		intro.seek(tt)
		var tr: Transform3D = intro.cam.global_transform
		var q: Quaternion = tr.basis.get_rotation_quaternion()
		(
			frames
			. append(
				{
					"t": tt,
					"pos": [tr.origin.x, tr.origin.y, tr.origin.z],
					"x": [tr.basis.x.x, tr.basis.x.y, tr.basis.x.z],
					"y": [tr.basis.y.x, tr.basis.y.y, tr.basis.y.z],
					"z": [tr.basis.z.x, tr.basis.z.y, tr.basis.z.z],
					"q": [q.x, q.y, q.z, q.w],
					"fov": intro.cam.fov,
					"near": intro.cam.near,
					"far": intro.cam.far,
					"veil": intro.veil_amount(tt),
				}
			)
		)
	var data := {
		"fps": fps,
		"sun_dir": [intro.sun_dir().x, intro.sun_dir().y, intro.sun_dir().z],
		"target": [IntroConfig.TARGET_LAT, IntroConfig.TARGET_LON],
		"clear_hole_deg": IntroConfig.CLEAR_HOLE_DEG,
		"cloud_drift": [IntroConfig.CLOUD_DRIFT.x, IntroConfig.CLOUD_DRIFT.y],
		"patch":
		[IntroConfig.PATCH.x, IntroConfig.PATCH.y, IntroConfig.PATCH.z, IntroConfig.PATCH.w],
		"fine": [IntroConfig.FINE.x, IntroConfig.FINE.y, IntroConfig.FINE.z, IntroConfig.FINE.w],
		"relief_exag": IntroConfig.RELIEF_EXAG,
		"sky_ra_at_lon0": IntroConfig.SKY_RA_AT_LON0,
		"frames": frames,
	}
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(data))
	fa.close()
	print("wrote %d frames to %s" % [frames.size(), out_path])
	get_tree().quit()
