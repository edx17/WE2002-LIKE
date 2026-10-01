class_name Competition
extends RefCounted
## Generic competition engine, the base for the Master League and every
## future tournament (leagues with promotion/relegation, cups, continental
## and international tournaments, custom ones): fixtures + results + table
## or bracket. Pure data in/out (Dictionaries) so it saves as JSON.
##
## League:   double round-robin (circle method), 3/1/0 points, standard
##           tie-breakers (points, goal difference, goals for, name).
## Knockout: single match per tie, extra time -> penalties for draws.

## Double round robin. Returns [[{home, away}...] per matchday].
static func round_robin(teams: Array, double_round := true) -> Array:
	var t := teams.duplicate()
	if t.size() % 2 == 1:
		t.append("")  # bye
	var n := t.size()
	var rounds := []
	for r in n - 1:
		var day := []
		for i in n / 2:
			var a: String = t[i]
			var b: String = t[n - 1 - i]
			if a == "" or b == "":
				continue
			# Alternate home/away so nobody plays 3 at home in a row.
			if (r + i) % 2 == 0:
				day.append({"home": a, "away": b})
			else:
				day.append({"home": b, "away": a})
		rounds.append(day)
		# Rotate all but the first.
		var last: String = t.pop_back()
		t.insert(1, last)
	if double_round:
		var second := []
		for day: Array in rounds:
			var rev := []
			for m: Dictionary in day:
				rev.append({"home": m.away, "away": m.home})
			second.append(rev)
		rounds += second
	return rounds


static func new_table(teams: Array) -> Dictionary:
	var table := {}
	for t: String in teams:
		table[t] = {"team": t, "played": 0, "won": 0, "drawn": 0, "lost": 0, "gf": 0, "ga": 0, "points": 0}
	return table


static func record(table: Dictionary, home: String, away: String, hg: int, ag: int) -> void:
	for side: Array in [[home, hg, ag], [away, ag, hg]]:
		var row: Dictionary = table[side[0]]
		row.played += 1
		row.gf += side[1]
		row.ga += side[2]
		if side[1] > side[2]:
			row.won += 1
			row.points += 3
		elif side[1] == side[2]:
			row.drawn += 1
			row.points += 1
		else:
			row.lost += 1


## Rows sorted by points, goal difference, goals for, then id.
static func standings(table: Dictionary) -> Array:
	var rows := table.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.points != b.points:
			return a.points > b.points
		var gda: int = a.gf - a.ga
		var gdb: int = b.gf - b.ga
		if gda != gdb:
			return gda > gdb
		if a.gf != b.gf:
			return a.gf > b.gf
		return str(a.team) < str(b.team))
	return rows


## Knockout draw for a list of teams (power of two).
static func knockout_round(teams: Array, rng: RandomNumberGenerator) -> Array:
	var t := teams.duplicate()
	for i in range(t.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = t[i]
		t[i] = t[j]
		t[j] = tmp
	var ties := []
	for i in range(0, t.size() - 1, 2):
		ties.append({"home": t[i], "away": t[i + 1]})
	return ties


## Winner of a knockout tie; draws go to a penalty shoot-out (sim).
static func tie_winner(home: String, away: String, hg: int, ag: int, rng: RandomNumberGenerator) -> String:
	if hg != ag:
		return home if hg > ag else away
	return home if rng.randf() < 0.5 else away
