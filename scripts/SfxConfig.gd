class_name SfxConfig
extends RefCounted

## Every sound number in one place (Sfx.gd plays them). Files: assets/audio/<group>/<name>.wav|ogg
## (short one-shots are WAV samples, loops and anything over 4 s are OGG Vorbis streams) and
## assets/intro/audio/. Sources and licences: CREDITS.md, section "Sound".
## Loudness of the files: ambience -24 LUFS, effects and animals -18, voices -20; the dB numbers
## below are the in-game mix on top of that.

const DIR: String = "res://assets/audio/"
const INTRO_DIR: String = "res://assets/intro/audio/"
const SAVE_PATH: String = "user://audio.cfg"

## Buses created at start (all send to Master). Default slider positions 0..1.
const BUSES: Array[String] = ["Ambience", "SFX", "Voices", "UI"]
const DEFAULT_VOLUME: Dictionary = {
	"Master": 0.9, "Ambience": 0.8, "SFX": 0.9, "Voices": 0.9, "UI": 0.7
}
const SLIDER_NAMES: Dictionary = {
	"Master": "All sound",
	"Ambience": "Nature",
	"SFX": "Effects",
	"Voices": "Band voices",
	"UI": "Buttons"
}

# --- 3D voices ---
## Simultaneous positional sounds (oldest is cut when all are busy).
const POOL_SIZE: int = 24
const UNIT_SIZE: float = 14.0
const MAX_DISTANCE: float = 150.0
const PANNING: float = 0.6
## Non-positional players (UI, stings, intro foley) used round-robin.
const FLAT_PLAYERS: int = 8
## The listener sits this far from the camera focus toward the camera (0 = on the ground).
const LISTENER_LIFT: float = 0.3

# --- event -> [files in DIR, volume dB, pitch spread, bus] ---
const EVENTS: Dictionary = {
	"contact":
	[
		[
			"voices/contact_1",
			"voices/contact_2",
			"voices/contact_3",
			"voices/contact_4",
			"voices/contact_5"
		],
		-3.0,
		0.06,
		"Voices"
	],
	"ack": [["voices/ack_1", "voices/ack_2", "voices/ack_3", "voices/ack_4"], -4.0, 0.06, "Voices"],
	"alarm": [["voices/alarm_1", "voices/alarm_2", "voices/alarm_3"], 0.0, 0.04, "Voices"],
	"chorus": [["voices/chorus_1", "voices/chorus_2"], -3.0, 0.03, "Voices"],
	"gather_food":
	[["sfx/rustle_1", "sfx/rustle_2", "sfx/rustle_3", "sfx/rustle_4"], -8.0, 0.1, "SFX"],
	"gather_wood":
	[
		[
			"sfx/wood_snap_1",
			"sfx/wood_snap_2",
			"sfx/wood_snap_3",
			"sfx/wood_chop_1",
			"sfx/wood_chop_2",
			"sfx/wood_chop_3"
		],
		-8.0,
		0.08,
		"SFX"
	],
	"gather_stone":
	[
		["sfx/stone_knock_1", "sfx/stone_knock_2", "sfx/stone_knock_3", "sfx/stone_knock_4"],
		-7.0,
		0.08,
		"SFX"
	],
	"drop_food": [["sfx/rustle_1", "sfx/rustle_3"], -6.0, 0.08, "SFX"],
	"drop_wood":
	[["sfx/build_knock_1", "sfx/build_knock_3", "sfx/wood_crack_1"], -6.0, 0.06, "SFX"],
	"drop_stone": [["sfx/stone_knock_2", "sfx/stone_knock_4"], -5.0, 0.06, "SFX"],
	"build_place": [["sfx/build_place_1", "sfx/build_place_2"], -2.0, 0.05, "SFX"],
	"build_knock":
	[
		["sfx/build_knock_1", "sfx/build_knock_2", "sfx/build_knock_3", "sfx/build_knock_4"],
		-9.0,
		0.1,
		"SFX"
	],
	"building_done": [["sfx/build_place_1", "sfx/wood_crack_1"], -3.0, 0.03, "SFX"],
	"knap": [["sfx/knap_crack"], 0.0, 0.03, "SFX"],
	"footstep":
	[["sfx/footstep_1", "sfx/footstep_2", "sfx/footstep_3", "sfx/footstep_4"], -6.0, 0.08, "SFX"],
	"hyena_whoop":
	[
		["animals/hyena_whoop_1", "animals/hyena_whoop_2", "animals/hyena_whoop_3"],
		-2.0,
		0.04,
		"SFX"
	],
	"hyena_giggle":
	[
		["animals/hyena_giggle_1", "animals/hyena_giggle_2", "animals/hyena_giggle_3"],
		-4.0,
		0.05,
		"SFX"
	],
	"bigcat": [["animals/bigcat_growl_1", "animals/bigcat_growl_2"], -2.0, 0.04, "SFX"],
	"gazelle":
	[
		["animals/gazelle_snort_1", "animals/gazelle_snort_2", "animals/gazelle_snort_3"],
		-6.0,
		0.08,
		"SFX"
	],
	"hooves": [["animals/hooves_1", "animals/hooves_2"], -6.0, 0.1, "SFX"],
	"croc_hiss": [["animals/croc_hiss_1", "animals/croc_hiss_2"], -6.0, 0.06, "SFX"],
	"croc_splash": [["animals/croc_splash_1", "animals/croc_splash_2"], -5.0, 0.06, "SFX"],
	"bird_eagle": [["animals/bird_eagle_1", "animals/bird_eagle_2"], -6.0, 0.03, "Ambience"],
	"bird_wood":
	[
		[
			"animals/bird_weaver_1",
			"animals/bird_weaver_2",
			"animals/bird_dove_1",
			"animals/bird_dove_2",
			"animals/bird_hornbill_1",
			"animals/bird_hornbill_2",
			"animals/bird_goaway_1",
			"animals/bird_goaway_2",
			"animals/bird_drongo_1",
			"animals/bird_drongo_2",
			"animals/bird_bulbul_1",
			"animals/bird_bulbul_2"
		],
		-8.0,
		0.03,
		"Ambience"
	],
	"bird_shore": [["animals/bird_ibis_1"], -8.0, 0.03, "Ambience"],
	"thunder": [["amb/thunder_far_1", "amb/thunder_far_2"], -6.0, 0.03, "Ambience"],
	"ui_tap": [["ui/tap_1", "ui/tap_2"], 0.0, 0.03, "UI"],
	"ui_confirm": [["ui/confirm"], 0.0, 0.0, "UI"],
	"ui_cancel": [["ui/cancel"], 0.0, 0.0, "UI"],
	"research_done": [["sfx/research_shimmer"], 0.0, 0.0, "UI"],
	"age_up": [["sfx/age_swell"], 0.0, 0.0, "UI"],
	# intro foley (non-positional)
	"bark_scrape":
	[
		["sfx/bark_scrape_1", "sfx/bark_scrape_2", "sfx/bark_scrape_3", "sfx/bark_scrape_4"],
		0.0,
		0.1,
		"SFX"
	],
	"rustle": [["sfx/rustle_1", "sfx/rustle_2", "sfx/rustle_3", "sfx/rustle_4"], 0.0, 0.1, "SFX"],
	"land_thud": [["sfx/land_thud"], 0.0, 0.03, "SFX"],
}
## Techs whose finish is an age-up (GDD 4): sting + band chorus. Other techs: stone strike.
const AGE_UP_TECHS: Array[String] = ["fire_kept", "first_words"]

# --- voices on select / command (GDD 12) ---
## Chance a selection or an order gets a call, and the minimum gap between calls.
const SELECT_CHANCE: float = 0.75
const ORDER_CHANCE: float = 0.6
const VOICE_GAP_S: float = 0.7
## Selection is polled (Main has no selection signal) at this interval.
const SELECT_POLL_S: float = 0.08
## Each Forager's own pitch offset (index hash), on top of the event's spread.
const UNIT_PITCH_SPREAD: float = 0.08

# --- work sounds (polled, GDD 12) ---
const WORK_POLL_S: float = 0.25
## Per worker: seconds between gather / build sounds, and the hearing radius round the listener.
const GATHER_EVERY: Vector2 = Vector2(1.4, 2.8)
const BUILD_EVERY: Vector2 = Vector2(0.7, 1.3)
const WORK_RANGE_M: float = 60.0
const WORK_MAX_PER_POLL: int = 2
## Node kind -> gather event (Game.ResNode.kind).
const GATHER_EVENT: Dictionary = {
	"fruit": "gather_food",
	"tuber": "gather_food",
	"wood": "gather_wood",
	"stone": "gather_stone",
	"carcass": "gather_stone"
}

# --- predator alarm (GDD 11.2 hint 6, GDD 12) ---
const ALARM_RANGE_M: float = 16.0
const ALARM_COOLDOWN_S: float = 25.0

# --- wildlife calls from real animal positions ---
## Seconds between calls (random in range); then a weighted pick.
const WILDLIFE_EVERY: Vector2 = Vector2(4.0, 9.0)
const WILDLIFE_WEIGHTS: Dictionary = {
	"bird_wood": 6.0,
	"bird_eagle": 1.0,
	"bird_shore": 1.0,
	"gazelle": 2.0,
	"hyena": 1.5,
	"bigcat": 0.6,
	"croc": 1.2
}
## Birds call from the canopy (m over the ground) within this radius of the woodland / Home Tree.
const BIRD_HEIGHT_M: float = 7.0
const BIRD_SPREAD_M: float = 26.0
## A distant thunder roll every this many seconds (random), non-positional.
const THUNDER_EVERY: Vector2 = Vector2(180.0, 420.0)
## Chance a gazelle snort is followed by hooves bounding off.
const HOOVES_CHANCE: float = 0.35

# --- ambience layers (looped, non-positional, mixed by camera state) ---
const AMB_LAYERS: Dictionary = {
	"wind_grass": "amb/wind_grass",
	"wind_high": "amb/wind_high",
	"lake": "amb/lake_lap",
	"insects": "amb/insects",
	"frogs": "amb/frogs"
}
## Mix update rate and smoothing (per second).
const AMB_UPDATE_S: float = 0.2
const AMB_SMOOTH: float = 1.5
## Water probe: points on two rings round the focus (m); fraction under water drives lake/frogs.
const WATER_RINGS: Array[float] = [14.0, 32.0]
const WATER_POINTS: int = 8
## Linear gains: [base, per unit of the driver]. Drivers: zoom 0..1, water 0..1, shore 0..1.
const MIX_WIND_GRASS: Vector2 = Vector2(0.55, 0.25)
const MIX_WIND_HIGH: Vector2 = Vector2(0.06, 0.8)
const MIX_LAKE: Vector2 = Vector2(0.08, 0.9)
const MIX_INSECTS: Vector2 = Vector2(0.7, -0.45)
const MIX_FROGS: Vector2 = Vector2(0.0, 0.8)
## Ambience fade-in when the game starts without the intro (s).
const AMB_FADE_IN_S: float = 2.5

# --- Menu volume panel (left side, under the readout) ---
const PANEL_POS: Vector2 = Vector2(16.0, 300.0)
const PANEL_WIDTH: float = 760.0
const ROW_PX: float = 130.0

# --- intro (IntroConfig.CUES drive it; times are offsets from the cue, seconds) ---
## [cue, offset, kind, name, volume dB]. kind: "bed" (looping or long, fades out at the end),
## "one" (one-shot), "amb" (start the game ambience under the intro).
const INTRO_EVENTS: Array[Array] = [
	["music_start", 0.0, "bed", "space_hum", -2.0],
	["planet_reveal", 0.0, "one", "rise", -4.0],
	["dive", 0.0, "one", "dive_wind", -2.0],
	["clouds", -0.4, "one", "cloud_whoosh", -1.0],
	["landfall", 0.0, "bed", "dawn_chorus", -3.0],
	["landfall", 0.5, "amb", "", 0.0],
	["wake", 0.6, "one", "wake_call", -2.0],
	["handover", 0.0, "fade", "", 0.0],
]
## The space hum fades out over this window (intro seconds) as the dive reaches the air.
const HUM_FADE: Vector2 = Vector2(50.0, 60.0)
const HUM_DB: float = -2.0
## Climb: bark scrape every climb cycle (CLIMB_CYCLE_M / CLIMB_V s), leaf rustle every 3rd.
const CLIMB_STEP_S: float = 0.545
const WALK_STEP_S: float = 0.45
## Band contact calls when the climber reaches the band: [offset after the walk ends, pitch].
const BAND_CALLS: Array[Vector2] = [Vector2(0.2, 1.0), Vector2(0.9, 0.9), Vector2(1.5, 1.08)]
const BAND_CALL_LEAD_S: float = 2.2
## Ambience mix under the intro's ground stage (zoom, water) until Main takes over.
const INTRO_AMB_ZOOM: float = 0.3
const INTRO_AMB_WATER: float = 0.25


static func path_of(file: String) -> String:
	for ext: String in [".wav", ".ogg"]:
		if ResourceLoader.exists(DIR + file + ext):
			return DIR + file + ext
	return ""


static func intro_path(file: String) -> String:
	for ext: String in [".wav", ".ogg"]:
		if ResourceLoader.exists(INTRO_DIR + file + ext):
			return INTRO_DIR + file + ext
	return ""
