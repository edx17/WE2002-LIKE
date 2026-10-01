class_name TeamTactics
extends RefCounted
## Team instructions from data/tactics (all 0..1).

var name := "Equilibrado"
## How high and with how many players the team presses.
var pressing := 0.5
## Height of the back line.
var defensive_line := 0.5
## Width with the ball.
var width := 0.6
## How much the block shifts with the ball.
var compactness := 0.6
## Back line steps up together to catch attackers offside.
var offside_trap := true


static func load_id(id: String) -> TeamTactics:
	var t := TeamTactics.new()
	if id == "":
		return t
	var data: Variant = DataLoader.load_json("tactics/%s.json" % id)
	if data is Dictionary:
		for key: String in ["name", "pressing", "defensive_line", "width", "compactness", "offside_trap"]:
			if data.has(key):
				t.set(key, data[key])
	return t
