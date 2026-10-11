class_name AutoQuality
extends Node

## "Auto" quality: picks High or Low from the first seconds of the match. After WARMUP_S (the
## first frames compile pipelines and stutter) it records MEASURE_S of frame times and GPU
## times, then keeps the starting preset or switches once: High drops to Low when the median
## frame is slower than HIGH_MAX_FRAME_MS or the median GPU time is over HIGH_MAX_GPU_MS; Low
## (the start on 32-bit devices) rises to High when both are far under budget. Medians, so one
## hitch does not decide. The Menu quality button cycles Auto -> High -> Low -> Auto.
## Editor builds (the capture and probe bots on the laptop) start with Auto off so every shot
## uses the preset it asks for; AOE_AUTO_QUALITY=1 turns it on there.

const WARMUP_S: float = 1.0
const MEASURE_S: float = 3.0
## 60 fps target: 16.7 ms with vsync; above 20 ms the phone cannot hold 50 fps on High.
const HIGH_MAX_FRAME_MS: float = 20.0
const HIGH_MAX_GPU_MS: float = 15.0
## Low -> High only with lots of headroom (High costs several times Low on the GPU).
const LOW_UP_FRAME_MS: float = 17.5
const LOW_UP_GPU_MS: float = 5.0

## True while the player has Auto selected (the Menu button label shows "Auto (High)").
var active: bool = true
## True once the pick is made (or Auto was switched off).
var done: bool = false
## Last decision, for the log and the bench header.
var summary: String = ""

var _main: Main
var _t: float = 0.0
var _frames := PackedFloat32Array()
var _gpu := PackedFloat32Array()


## Adds the Auto picker under `main` and applies the starting preset (Low on 32-bit devices).
static func attach(main: Main) -> AutoQuality:
	var a := AutoQuality.new()
	a.name = "AutoQuality"
	a._main = main
	main.auto_quality = a
	main.add_child(a)
	if OS.has_feature("editor") and OS.get_environment("AOE_AUTO_QUALITY") != "1":
		a.stop()
	main.apply_quality(1 if OS.has_feature("arm32") and a.active else 0)
	return a


## Menu quality button: Auto -> High -> Low -> Auto (Auto measures afresh from High).
func cycle() -> void:
	if active:
		stop()
		_main.apply_quality(0)
	elif _main.quality == 0:
		_main.apply_quality(1)
	else:
		restart()
		_main.apply_quality(0)


## Menu button text for `main`'s current preset: "Quality: Auto (High)" while Auto is on.
static func label(main: Main) -> String:
	var name_q: String = str(SpikeConfig.QUALITY[main.quality]["name"])
	if main.auto_quality != null and main.auto_quality.active:
		return "Quality: Auto (%s)" % name_q
	return "Quality: %s" % name_q


## Auto on again: measure afresh from the current preset.
func restart() -> void:
	active = true
	done = false
	_t = 0.0
	_frames.resize(0)
	_gpu.resize(0)
	set_process(true)


func stop() -> void:
	active = false
	done = true
	set_process(false)


func _process(delta: float) -> void:
	if done:
		set_process(false)
		return
	if _main.bench != null and _main.bench.running:
		# the bench measures the preset it was started on
		stop()
		return
	_t += delta
	if _t < WARMUP_S:
		return
	_frames.append(delta * 1000.0)
	_gpu.append(PerfOverlay.gpu_ms())
	if _t < WARMUP_S + MEASURE_S:
		return
	done = true
	set_process(false)
	var f: float = _median(_frames)
	var g: float = _median(_gpu)
	var q: int = _main.quality
	if q == 0 and (f > HIGH_MAX_FRAME_MS or g > HIGH_MAX_GPU_MS):
		q = 1
	elif q == 1 and f < LOW_UP_FRAME_MS and g < LOW_UP_GPU_MS:
		q = 0
	summary = (
		"Auto quality: median frame %.1f ms, GPU %.1f ms over %d frames -> %s"
		% [f, g, _frames.size(), SpikeConfig.QUALITY[q]["name"]]
	)
	print(summary)
	_main.apply_quality(q)


static func _median(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s: PackedFloat32Array = v.duplicate()
	s.sort()
	return s[int(s.size() / 2.0)]
