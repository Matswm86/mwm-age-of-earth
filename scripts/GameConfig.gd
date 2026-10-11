class_name GameConfig
extends RefCounted

## Layout, look and feel numbers for the Age 1 opening (not balance: those live in
## data/balance.json). Positions are map metres (x east, z south) on the Rift Lake map; the
## player's camp sits ~35 m from the waterline where the look target put it.

# --- player camp and resource kit (GDD 5.1: walk distances to the Home Tree) ---
const HOME := Vector2(406.0, 262.0)
## Where the 6 starting Foragers stand (they climb down from the tree, GDD 11.1).
const START_RING_M: float = 9.0
## 6 fig bushes ~12 m round the Home Tree (kit "fruit", 600 = 6 x 100).
const FIG_BUSHES: Array[Vector2] = [
	Vector2(418.0, 252.0),
	Vector2(421.0, 266.0),
	Vector2(413.0, 276.0),
	Vector2(395.0, 273.0),
	Vector2(393.0, 255.0),
	Vector2(404.0, 247.0),
]
## 2 tuber patches ~45 m north (kit "tuber", 500 = 2 x 250).
const TUBER_PATCHES: Array[Vector2] = [Vector2(398.0, 220.0), Vector2(420.0, 224.0)]
## 2 starting carcasses ~60 m south (kit "carcass", 300 = 2 x 150).
const CARCASSES: Array[Vector2] = [Vector2(418.0, 318.0), Vector2(398.0, 322.0)]
## Woodland ~30 m west (kit "wood" 6000): dead-wood heaps under an acacia stand.
const WOODLAND := Vector2(378.0, 250.0)
const WOOD_HEAPS: Array[Vector2] = [
	Vector2(381.0, 244.0),
	Vector2(374.0, 255.0),
	Vector2(384.0, 258.0),
	Vector2(370.0, 243.0),
]
## Cobble bed ~55 m south-west in a dry stream bed (kit "stone" 1800).
const STONE_BEDS: Array[Vector2] = [
	Vector2(374.0, 304.0), Vector2(381.0, 309.0), Vector2(368.0, 312.0)
]
## Rival band camp, far north along the shore (no AI in this build; they idle and wander).
const RIVAL_HOME := Vector2(372.0, 120.0)
const RIVAL_COUNT: int = 6

# --- wildlife ---
const GAZELLE_HERD := Vector2(352.0, 228.0)
const GAZELLES: int = 8
const HYENA_DEN := Vector2(424.0, 334.0)
const HYENAS: int = 3
const LEOPARD_PATH: Array[Vector2] = [
	Vector2(330.0, 300.0), Vector2(300.0, 260.0), Vector2(320.0, 220.0), Vector2(350.0, 270.0)
]
const CROCODILES: Array[Vector2] = [
	Vector2(447.0, 247.0), Vector2(452.0, 286.0), Vector2(446.0, 214.0)
]

# --- building footprints (DESIGN 7.7, metres across) ---
const FOOTPRINT: Dictionary = {
	"home_tree": 12.0,
	"nest_grove": 8.0,
	"cache": 4.0,
	"knapping_floor": 6.0,
}
## Trampled red-earth floor radius around each building (DESIGN 7.2).
const TRAMPLE_R: Dictionary = {
	"home_tree": 16.0,
	"nest_grove": 7.0,
	"cache": 4.0,
	"knapping_floor": 5.0,
}
const BUILD_NAMES: Dictionary = {
	"home_tree": "Home Tree",
	"nest_grove": "Nest Grove",
	"cache": "Cache",
	"knapping_floor": "Knapping Floor",
}
## Buildings the player can place in Age 1 in this build (command card order).
const BUILD_MENU: Array[String] = ["nest_grove", "cache", "knapping_floor"]
## Builders that count toward build speed (GDD 5.2: time / n, max 4).
const MAX_BUILDERS: int = 4
## Training queue length at the Home Tree.
const QUEUE_MAX: int = 5

# --- gathering ---
## Food sources and their balance kind; resource nodes are drawn from real props.
const NODE_RADIUS: Dictionary = {
	"fruit": 1.6, "tuber": 2.2, "carcass": 1.6, "wood": 1.8, "stone": 2.0
}
## A depleted node's workers look for the same kind within this radius (m).
const RETARGET_M: float = 30.0

# --- camera start (the intro hands over on SpikeConfig.BENCH_CENTRE) ---
const CAM_START := Vector2(412.0, 270.0)

# --- look ---
const SELECT := Color(0.608, 0.878, 0.478)
const ATTACK := Color(0.824, 0.271, 0.176)
const OUTLINE := Color(0.118, 0.110, 0.102)
const NEUTRAL_DISC := Color(0.431, 0.404, 0.361)
const BONE := Color(0.66, 0.60, 0.50)
## Crocodile source texture is pale yellow; multiply toward Nile-croc olive grey.
const CROC_TINT := Color(0.42, 0.43, 0.34)

# --- HUD (DESIGN 2.3, 4, 5) ---
const PANEL := Color(0.949, 0.925, 0.878, 0.92)
const PANEL_ALT := Color(0.890, 0.839, 0.737)
const TEXT := Color(0.165, 0.149, 0.125)
const TEXT_DIM := Color(0.353, 0.322, 0.275)
const PRIMARY := Color(0.184, 0.431, 0.384)
const DANGER := Color(0.557, 0.165, 0.078)
const SAFE_M: float = 48.0
const BTN: float = 150.0
const BTN_GAP: float = 24.0
const FONT_NUM: int = 40
const FONT_BODY: int = 36
const FONT_SMALL: int = 32

# --- onboarding (GDD 11.2): at most 6 words each ---
const HINT_SELECT: String = "Tap to select"
const HINT_GATHER: String = "Tap figs to gather"
const HINT_TRAIN: String = "More Foragers here"
const HINT_NEST: String = "Build nests for more"
const HINT_KNAP: String = "Find the stone that cuts"
const HINT_PREDATOR: String = "Stay together"
const HINT_KNAP_AT_S: float = 120.0
