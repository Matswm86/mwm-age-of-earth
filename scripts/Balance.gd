class_name Balance
extends RefCounted

## data/balance.json, the one source of gameplay numbers (GDD: "if they disagree, the JSON wins").
## Loaded once on first use. The export preset includes data/*.json.

const PATH: String = "res://data/balance.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var text: String = FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("Balance: cannot read %s" % PATH)
	return _data


static func section(name: String) -> Dictionary:
	var d: Variant = data().get(name, {})
	return d if d is Dictionary else {}


static func building(id: String) -> Dictionary:
	var d: Variant = section("buildings").get(id, {})
	return d if d is Dictionary else {}


static func unit(id: String) -> Dictionary:
	var d: Variant = section("units").get(id, {})
	return d if d is Dictionary else {}


static func tech(id: String) -> Dictionary:
	var d: Variant = section("techs").get(id, {})
	return d if d is Dictionary else {}


## Gather rate (units per second) for a source kind: fruit, tuber, carcass, wood, stone, ...
static func gather_rate(kind: String) -> float:
	var rates: Dictionary = section("gather").get("rates", {})
	return float(rates.get(kind, 0.3))


static func carry() -> float:
	return float(section("gather").get("carry", 10))


static func drop_s() -> float:
	return float(section("gather").get("drop_s", 1.0))


## Cost dictionary {food, wood, stone, ochre} as ints (missing keys = 0).
static func cost_of(d: Dictionary) -> Dictionary:
	var c: Dictionary = d.get("cost", {})
	var out: Dictionary = {}
	for k: String in ["food", "wood", "stone", "ochre"]:
		out[k] = int(c.get(k, 0))
	return out


## The map kit entry of a kind (map_resources_per_player), e.g. ("food", "tuber").
static func kit(res: String, kind: String) -> Dictionary:
	var list: Array = section("map_resources_per_player").get(res, [])
	for e: Variant in list:
		if e is Dictionary and str(e.get("kind", "")) == kind:
			return e
	return {}
