class_name SpikeConfig
extends RefCounted

## Every number the tech spike uses, in one place. Gameplay numbers that exist in
## data/balance.json are copied here with their key; the rest are spike placeholders.

# --- map (GDD section 10) ---
const MAP_SIZE: float = 512.0
## Terrain grid spacing in metres; heights come from assets/terrain/game/height_f32.bin on the GPU.
const TERRAIN_STEP: float = 1.0
## Height samples per side in height_f32.bin (0.5 m apart, tools/game/bake_terrain.py).
const HEIGHT_SAMPLES: int = 1025
const HEIGHT_SPACING: float = 0.5
## Vertical exaggeration baked into the height file (real relief is only 4.8 m at 1:10;
## builder's call).
const EXAGGERATION: float = 3.0
const NAV_CELLS: int = 128
## log2(NAV_CELLS): cell index -> row is `cell >> NAV_SHIFT`, column is `cell & (NAV_CELLS - 1)`.
const NAV_SHIFT: int = 7
const NAV_CELL_M: float = 4.0
## Lake surface (game y). The height file is relative to the real lake level.
const WATER_LEVEL: float = 0.0
## A nav cell is blocked when its centre is below this height (lake and wet shore).
const NAV_MIN_HEIGHT: float = 0.35
## A nav cell is blocked when its height differs from a neighbour by more than this (m per 4 m).
const NAV_MAX_STEP: float = 2.6

# --- units ---
const MAX_UNITS: int = 210
## Unit-count presets: 2 x 75 (1 vs 1 pop cap), 3 x 55 (1 vs 2), 3 x 70 (spike target).
const PRESETS: Array[Dictionary] = [
	{"name": "150", "teams": 2, "per_team": 75},
	{"name": "165", "teams": 3, "per_team": 55},
	{"name": "210", "teams": 3, "per_team": 70},
]
const DEFAULT_PRESET: int = 2
## balance.json units.forager.speed (m/s).
const UNIT_SPEED: float = 3.2
## Spike placeholder: no unit vision exists in balance.json yet (buildings use 30-34 m).
const UNIT_SIGHT_M: float = 24.0
const UNIT_RADIUS: float = 0.5
## Hominin bodies are drawn this much larger than life (1.3 m -> 1.56 m) so they read at RTS zoom
## (owner 2026-10-11: units larger and crisper); the simulation sizes do not change.
const UNIT_DRAW_SCALE: float = 1.2
## Units closer than this push each other apart (m).
const SEPARATION_DIST: float = 1.15
const SEPARATION_PUSH: float = 6.0
## Arrival radius = this x sqrt(group size) (m), so a big group stops as a blob, not a pile.
const ARRIVE_SPREAD: float = 0.75
const TURN_RATE: float = 10.0
## Team colours (player first). Float form only (Color8 breaks on Android).
## DESIGN 2.2: team_ochre (player), team_kaolin, team_yellow.
const TEAM_COLOURS: Array[Color] = [
	Color(0.769, 0.259, 0.118),
	Color(0.902, 0.878, 0.824),
	Color(0.878, 0.690, 0.251),
]
## Bench spawn points (land west of the camp on the Rift Lake map).
const SPAWN_POINTS: Array[Vector2] = [
	Vector2(380.0, 290.0),
	Vector2(410.0, 300.0),
	Vector2(370.0, 262.0),
]

# --- simulation ---
## Fixed simulation rate in game time; at 1.5x game speed it runs 45 ticks per real second.
const SIM_HZ: float = 30.0
const MAX_TICKS_PER_FRAME: int = 4
## balance.json match.game_speeds.
const GAME_SPEEDS: Array[float] = [1.0, 1.5]
const FOG_HZ: float = 5.0

# --- camera (GDD section 8, DESIGN 7.6) ---
## Owner 2026-10-11: default zoom closer than the look target so a 1.3 m hominin is 50-70 px tall
## at 1080p (about 28 m from the focus at ~49 deg pitch).
const CAM_MIN_H: float = 12.0
const CAM_MAX_H: float = 60.0
const CAM_DEFAULT_H: float = 21.0
const CAM_TILT_NEAR: float = 48.0
const CAM_TILT_FAR: float = 58.0
## Vertical field of view (DESIGN 7.6: ~37 deg, 35 mm equivalent).
const CAM_FOV: float = 37.0

# --- input (GDD section 8) ---
const DRAG_START_PX: float = 24.0
const TAP_UNIT_PX: float = 40.0

# --- bench ---
const BENCH_SECONDS: float = 20.0
const BENCH_WARMUP: float = 3.0
## Each team gets a new move order this often during the bench (game seconds).
const BENCH_ORDER_EVERY: float = 5.0
## Bench focus = the player's camp, which is also the camera pose the opening intro ends on.
const BENCH_CENTRE: Vector2 = Vector2(412.0, 270.0)
## Bench runs: preset index, game speed.
const BENCH_RUNS: Array[Vector2] = [
	Vector2(0, 1.0),
	Vector2(1, 1.0),
	Vector2(2, 1.0),
	Vector2(2, 1.5),
]

# --- graphics quality ---
## High = owner's phone (SM-S931B), Low = 32-bit Samsung tablet. `effects` = SSAO, SSIL, SSR,
## volumetric haze and tilt-shift (Forward+); `grass` = share of grass blades drawn.
const QUALITY: Array[Dictionary] = [
	{
		"name": "High",
		"scale": 1.0,
		"shadows": true,
		"msaa": Viewport.MSAA_2X,
		"effects": true,
		"grass": 1.0
	},
	{
		"name": "Low",
		"scale": 0.75,
		"shadows": false,
		"msaa": Viewport.MSAA_DISABLED,
		"effects": false,
		"grass": 0.35
	},
]
