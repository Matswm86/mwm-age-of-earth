class_name SpikeConfig
extends RefCounted

## Every number the tech spike uses, in one place. Gameplay numbers that exist in
## data/balance.json are copied here with their key; the rest are spike placeholders.

# --- map (GDD section 10) ---
const MAP_SIZE: float = 512.0
## Terrain mesh vertex spacing in metres (257 x 257 vertices, one draw call).
const TERRAIN_STEP: float = 2.0
const NAV_CELLS: int = 128
## log2(NAV_CELLS): cell index -> row is `cell >> NAV_SHIFT`, column is `cell & (NAV_CELLS - 1)`.
const NAV_SHIFT: int = 7
const NAV_CELL_M: float = 4.0
const WATER_LEVEL: float = 0.0
## A nav cell is blocked when its centre is below this height (lake and wet shore).
const NAV_MIN_HEIGHT: float = 0.35
## A nav cell is blocked when its height differs from a neighbour by more than this (m per 4 m).
const NAV_MAX_STEP: float = 2.6
const TERRAIN_SEED: int = 20261011
## Lake basin on the west side (placeholder until the Copernicus Turkana crop exists).
const LAKE_CENTRE: Vector2 = Vector2(105.0, 250.0)
const LAKE_RADIUS: float = 105.0

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
## Units closer than this push each other apart (m).
const SEPARATION_DIST: float = 1.15
const SEPARATION_PUSH: float = 6.0
## Arrival radius = this x sqrt(group size) (m), so a big group stops as a blob, not a pile.
const ARRIVE_SPREAD: float = 0.75
const TURN_RATE: float = 10.0
## Team colours (player first). Float form only (Color8 breaks on Android).
const TEAM_COLOURS: Array[Color] = [
	Color(0.15, 0.45, 0.95),
	Color(0.9, 0.18, 0.12),
	Color(0.95, 0.78, 0.15),
]
const SPAWN_POINTS: Array[Vector2] = [
	Vector2(290.0, 250.0),
	Vector2(330.0, 230.0),
	Vector2(320.0, 280.0),
]

# --- simulation ---
## Fixed simulation rate in game time; at 1.5x game speed it runs 45 ticks per real second.
const SIM_HZ: float = 30.0
const MAX_TICKS_PER_FRAME: int = 4
## balance.json match.game_speeds.
const GAME_SPEEDS: Array[float] = [1.0, 1.5]
const FOG_HZ: float = 5.0

# --- camera (GDD section 8) ---
const CAM_MIN_H: float = 18.0
const CAM_MAX_H: float = 60.0
## About 63 m visible across at this height in landscape (units ~43 px tall).
const CAM_DEFAULT_H: float = 38.0
const CAM_TILT_NEAR: float = 48.0
const CAM_TILT_FAR: float = 55.0
const CAM_FOV: float = 40.0

# --- input (GDD section 8) ---
const DRAG_START_PX: float = 24.0
const TAP_UNIT_PX: float = 40.0

# --- bench ---
const BENCH_SECONDS: float = 20.0
const BENCH_WARMUP: float = 3.0
## Each team gets a new move order this often during the bench (game seconds).
const BENCH_ORDER_EVERY: float = 5.0
const BENCH_CENTRE: Vector2 = Vector2(310.0, 255.0)
## Bench runs: preset index, game speed.
const BENCH_RUNS: Array[Vector2] = [
	Vector2(0, 1.0),
	Vector2(1, 1.0),
	Vector2(2, 1.0),
	Vector2(2, 1.5),
]

# --- graphics quality ---
## High = owner's phone (SM-S931B), Low = 32-bit Samsung tablet.
const QUALITY: Array[Dictionary] = [
	{"name": "High", "scale": 1.0, "shadows": true, "msaa": Viewport.MSAA_2X},
	{"name": "Low", "scale": 0.75, "shadows": false, "msaa": Viewport.MSAA_DISABLED},
]
