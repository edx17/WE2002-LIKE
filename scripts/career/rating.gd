class_name Rating
extends RefCounted
## Overall rating (OVR, 1..99) of a player for his position, WE-style:
## a weighted average of the attributes that position needs.

const WEIGHTS := {
	"GK": {"goalkeeping": 5, "reaction": 3, "agility": 2, "balance": 1},
	"CB": {"tackling": 4, "heading": 3, "strength": 3, "speed": 1, "balance": 2, "reaction": 2, "passing": 1},
	"FB": {"speed": 3, "acceleration": 2, "tackling": 3, "passing": 2, "stamina": 2, "control": 1},
	"DMF": {"tackling": 3, "passing": 3, "strength": 2, "stamina": 2, "reaction": 2, "control": 1},
	"CMF": {"passing": 4, "control": 3, "technique": 3, "stamina": 1, "reaction": 2, "shooting": 1},
	"WM": {"speed": 3, "acceleration": 2, "control": 3, "technique": 2, "passing": 2, "agility": 1},
	"CF": {"shooting": 4, "shot_power": 2, "control": 2, "speed": 2, "acceleration": 2, "heading": 1, "reaction": 1},
}
const GROUP := {"GK": "GK", "CB": "CB", "LB": "FB", "RB": "FB", "LWB": "FB", "RWB": "FB", "DMF": "DMF",
	"CMF": "CMF", "AMF": "CMF", "LMF": "WM", "RMF": "WM", "WG": "WM", "CF": "CF", "SS": "CF"}


static func group(position: String) -> String:
	return GROUP.get(position, "CMF")


static func overall(p: Dictionary, position := "") -> int:
	var pos := position if position != "" else str(p.get("position", "CMF"))
	var w: Dictionary = WEIGHTS[group(pos)]
	var total := 0.0
	var weight := 0.0
	for key: String in w:
		total += float(p.get(key, 50)) * float(w[key])
		weight += float(w[key])
	return roundi(total / weight)


## Market value in Master League points: rating and age.
static func value(p: Dictionary) -> int:
	var ovr := overall(p)
	var age := int(p.get("age", 25))
	var age_factor := clampf(1.3 - absf(age - 25) * 0.06, 0.35, 1.3)
	return int(round(pow(maxf(ovr - 40, 1), 2.2) * 2.0 * age_factor / 10.0) * 10)


static func salary(p: Dictionary) -> int:
	return int(round(value(p) * 0.08 / 10.0) * 10)
