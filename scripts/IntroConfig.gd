class_name IntroConfig
extends RefCounted

## Every number of the opening intro (GDD 11.1, Wayfarer GDD 4.3b) in one place.
## Planet stage units are kilometres (planet centre at the origin, +Y = north pole,
## dir(lat, lon) = (cos lat cos lon, sin lat, -cos lat sin lon)). Local stage units are metres
## (the RtsTerrain placeholder map, same frame as scenes/Main.tscn).

const PLANET_R: float = 6371.0
const ATMOS_R: float = 6471.0
const CLOUD_ALT: float = 6.0

# --- geography (degrees). Keep in sync with tools/intro/bake_intro_assets.py ---
## Dive target: west shore of Lake Turkana (picked on the Sentinel-2 mosaic; it is NOT the
## GDD start site near Lomekwi 3, whose coordinates are still owed from a verified source).
const TARGET_LAT: float = 4.0
const TARGET_LON: float = 35.86
## Ground height at the target (km, Copernicus GLO-30, lake level 362 m).
const TARGET_H: float = 0.37
const BMNG_REGION: Vector4 = Vector4(27.5, -4.7, 44.5, 12.3)
const PATCH: Vector4 = Vector4(34.4, 2.5, 37.0, 5.1)
const FINE: Vector4 = Vector4(35.625, 3.825, 35.975, 4.175)
## Clear-sky hole in the cloud layer round the target (degrees radius); the Turkana basin is
## one of the driest places in East Africa.
const CLEAR_HOLE_DEG: float = 5.5
## Rift relief exaggeration on the displaced patch (1 = true heights).
const RELIEF_EXAG: float = 1.35
## Patch mesh vertices per side (height map is 1025 px).
const PATCH_VERTS: int = 513
const PATCH_VERTS_LOW: int = 257

# --- sun ---
## Late afternoon at the target, sun in the west-south-west (matches Main's fixed sun).
const SUN_ELEV_DEG: float = 26.0
const SUN_AZ_DEG: float = 250.0
const SUN_POWER: float = 2.6
## Angle (deg, seen from the planet) between the sun and the camera at the start: the planet is
## a thin crescent and the sun is 25 deg off the view axis, in frame.
const START_PHASE_DEG: float = 155.0
## Sky rotation: right ascension (deg) that faces Earth longitude 0. Picked so Orion and the
## winter Milky Way sit behind the pale blue dot (artistic; not a real date).
const SKY_RA_AT_LON0: float = -40.0

# --- timeline (seconds) ---
## Planet stage keys: [t, altitude km, pitch deg (-90 = straight down), arc 0..1 from the start
## point to the target, heading deg]. Altitude is interpolated in log space, all channels with
## monotone cubic curves (no overshoot).
const KEYS: Array[Array] = [
	[0.0, 6.0e7, -90.0, 0.0, 0.0],
	[5.0, 3.5e7, -90.0, 0.0, 0.0],
	[11.0, 3.0e6, -90.0, 0.03, 0.0],
	[17.0, 2.5e5, -90.0, 0.2, 0.0],
	[24.0, 4.0e4, -90.0, 0.5, 0.0],
	[32.0, 1.5e4, -90.0, 0.75, 0.0],
	[40.0, 7000.0, -88.0, 0.9, 0.0],
	[47.0, 1500.0, -70.0, 0.98, 0.0],
	[52.0, 300.0, -45.0, 1.0, 0.0],
	[57.0, 60.0, -30.0, 1.0, 0.0],
	[61.0, 15.0, -24.0, 1.0, 0.0],
	[64.0, 4.5, -26.0, 1.0, 0.0],
]
## Time the camera crosses the cloud deck: the veil peaks and the scene switches to the local
## terrain. Veil ramps in/out over these windows.
const SWITCH_T: float = 64.0
const VEIL_IN: Vector2 = Vector2(61.6, 63.7)
const VEIL_OUT: Vector2 = Vector2(64.3, 66.2)
## Local stage: camera starts this high above the start focus at this pitch and settles into
## Main's opening RTS pose by LOCAL_END_T.
const LOCAL_START_H: float = 380.0
const LOCAL_START_PITCH: float = -60.0
const LOCAL_END_T: float = 72.5
## Cross-fade into the game scene.
const FADE_START_T: float = 73.5
const FADE_SECONDS: float = 1.4
## After the first viewing a tap skips; ignore taps in the first moments.
const SKIP_AFTER: float = 0.6
const SKIP_FADE_SECONDS: float = 0.6

## Audio hooks: cue name -> time. Intro.gd emits `cue` and plays res://assets/intro/audio/<name>.ogg
## if such a file exists (none yet).
const CUES: Dictionary = {
	"music_start": 0.0,
	"planet_reveal": 17.0,
	"earth_full": 32.0,
	"dive": 44.0,
	"clouds": 62.0,
	"landfall": 64.0,
	"handover": 73.5,
}

# --- look ---
const FOV: float = 40.0
## Stars fade with the planet's on-screen radius (pixels): full below, gone above.
const STAR_FADE_PX: Vector2 = Vector2(60.0, 260.0)
const STAR_GAIN: float = 1.6
## The pale blue dot sprite fades out as the real sphere grows from 1.5 to 4 px radius.
const DOT_FADE_PX: Vector2 = Vector2(1.5, 4.0)
## Cloud drift (texture u per second) of the two cloud copies.
const CLOUD_DRIFT: Vector2 = Vector2(0.0004, 0.00026)
const SAVE_PATH: String = "user://intro.cfg"

# --- textures ---
const TEX_DIR: String = "res://assets/intro/"
## Atmosphere ray-march steps along the view ray per quality.
const ATMOS_STEPS_HIGH: int = 12
const ATMOS_STEPS_LOW: int = 8
## Transmittance table size (cos sun zenith x height) and integration steps per texel.
const LUT_SIZE: Vector2i = Vector2i(256, 64)
const LUT_STEPS: int = 40


## Unit vector of a latitude / longitude (degrees) in the Earth-fixed frame.
static func geo_dir(lat_deg: float, lon_deg: float) -> Vector3:
	var la: float = deg_to_rad(lat_deg)
	var lo: float = deg_to_rad(lon_deg)
	return Vector3(cos(la) * cos(lo), sin(la), -cos(la) * sin(lo))


static func east_of(up: Vector3) -> Vector3:
	var e: Vector3 = Vector3.UP.cross(up)
	if e.length_squared() < 1e-8:
		return Vector3(0.0, 0.0, -1.0)
	return e.normalized()


static func box_radians(b: Vector4) -> Vector4:
	return Vector4(deg_to_rad(b.x), deg_to_rad(b.y), deg_to_rad(b.z), deg_to_rad(b.w))
