class_name PlayerGrowth
extends RefCounted
## How players change over a career. Each player has a growth type and a
## potential (the rating he can reach):
##
##   precoz   grows until 23, peak 23-27, declines from 28
##   normal   grows until 26, peak 26-29, declines from 30
##   tardio   grows until 28, peak 28-31, declines from 32
##
## Playing matters: players who play grow faster.

const CURVES := {"precoz": [23, 28], "normal": [26, 30], "tardio": [28, 32]}
const FOCUS := {
	"GK": ["goalkeeping", "reaction", "agility"],
	"CB": ["tackling", "heading", "strength", "balance"],
	"FB": ["speed", "tackling", "passing", "stamina"],
	"DMF": ["tackling", "passing", "stamina", "strength"],
	"CMF": ["passing", "control", "technique", "reaction"],
	"WM": ["speed", "control", "technique", "acceleration"],
	"CF": ["shooting", "shot_power", "control", "acceleration"],
}
const PHYSICAL := ["speed", "acceleration", "stamina", "agility"]


## One week. `played` = he was on the pitch this week.
static func week(p: Dictionary, played: bool, rng: RandomNumberGenerator) -> void:
	var curve: Array = CURVES.get(str(p.get("growth", "normal")), CURVES.normal)
	var age := int(p.get("age", 25))
	if age < int(curve[0]):
		if Rating.overall(p) >= int(p.get("potential", 75)):
			return
		if rng.randf() < (0.5 if played else 0.22):
			var focus: Array = FOCUS[Rating.group(str(p.get("position", "CMF")))]
			for i in 2:
				var key: String = focus[rng.randi_range(0, focus.size() - 1)]
				p[key] = mini(99, int(p.get(key, 50)) + 1)
	elif age >= int(curve[1]):
		var chance := 0.22 + 0.06 * (age - int(curve[1]))
		if rng.randf() < chance:
			# Legs go first, then the rest of the game.
			var pool: Array = PHYSICAL + FOCUS[Rating.group(str(p.get("position", "CMF")))]
			var key: String = pool[rng.randi_range(0, pool.size() - 1)]
			p[key] = maxi(25, int(p.get(key, 50)) - 1)


## Close season: everyone a year older, contracts run down.
static func end_of_season(p: Dictionary) -> void:
	p.age = int(p.get("age", 25)) + 1
	p.contract_years = int(p.get("contract_years", 1)) - 1
