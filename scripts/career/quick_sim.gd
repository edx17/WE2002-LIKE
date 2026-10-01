class_name QuickSim
extends RefCounted
## Result of a match nobody watches: team strength from the best XI, a home
## advantage, Poisson goals; scorers weighted by shooting and position;
## occasional cards and injuries. Fast enough to simulate whole seasons.

const HOME_BONUS := 2.0


static func strength(squad: Array, players: Dictionary) -> float:
	var ovrs := []
	for pid: String in squad:
		var p: Dictionary = players[pid]
		if int(p.get("injury_weeks", 0)) > 0 or int(p.get("suspended", 0)) > 0:
			continue
		ovrs.append(Rating.overall(p))
	ovrs.sort()
	ovrs.reverse()
	var best := ovrs.slice(0, 11)
	if best.is_empty():
		return 40.0
	var total := 0.0
	for o: int in best:
		total += o
	# Missing players (fewer than 11 available) hurt a lot.
	return total / 11.0


static func poisson(lam: float, rng: RandomNumberGenerator) -> int:
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l:
			return k
		k += 1
	return k


## Returns {home_goals, away_goals, scorers: [pid], cards: [{pid, card}], injuries: [pid]}.
static func play(home_squad: Array, away_squad: Array, players: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var sh := strength(home_squad, players) + HOME_BONUS
	var sa := strength(away_squad, players)
	var hg := poisson(1.35 * exp((sh - sa) / 12.0), rng)
	var ag := poisson(1.05 * exp((sa - sh) / 12.0), rng)
	var scorers := []
	for i in hg:
		scorers.append(_pick_scorer(home_squad, players, rng))
	for i in ag:
		scorers.append(_pick_scorer(away_squad, players, rng))
	var cards := []
	var injuries := []
	for squad: Array in [home_squad, away_squad]:
		for pid: String in squad.slice(0, 11):
			var roll := rng.randf()
			if roll < 0.006:
				cards.append({"pid": pid, "card": "ROJA"})
			elif roll < 0.1:
				cards.append({"pid": pid, "card": "AMARILLA"})
			if rng.randf() < 0.01:
				injuries.append(pid)
	return {"home_goals": hg, "away_goals": ag, "scorers": scorers, "cards": cards, "injuries": injuries}


static func _pick_scorer(squad: Array, players: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	var weights := []
	for pid: String in squad.slice(0, 11):
		var p: Dictionary = players[pid]
		var w := pow(float(p.get("shooting", 50)) / 50.0, 3.0)
		match Rating.group(str(p.get("position", ""))):
			"CF":
				w *= 4.0
			"WM", "CMF":
				w *= 1.8
			"GK":
				w *= 0.0
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return squad[i]
	return squad[0]
