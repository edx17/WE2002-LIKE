class_name MasterLeague
extends RefCounted
## The Master League career: the foundation every other competition mode
## builds on. All state lives in one Dictionary (`state`) that saves as JSON.
##
## A season: two divisions (10 clubs each, double round-robin, 18 matchdays)
## plus the "Copa Master" knockout (16 clubs) slotted between matchdays.
## You start in division 2 with the modest "Equipo Master" squad and
## points to spend; you earn points with results, pay salaries at the end
## of the season, buy players from other clubs, and watch your players grow
## (and age). Two go up, two go down.

const SAVE_DIR := "user://saves/"
const VERSION := 1
const START_POINTS := 6000
const WIN_POINTS := 1200
const DRAW_POINTS := 600
const LOSS_POINTS := 250
const CUP_WEEKS_AFTER := [3, 7, 11, 15]  # cup round after these matchdays
const CUP_NAMES := ["Octavos", "Cuartos", "Semifinal", "Final"]
const MAX_SQUAD := 30
const MIN_SQUAD := 16
const PROMOTED := 2

var state: Dictionary = {}
var rng := RandomNumberGenerator.new()


# --- creation, saving --------------------------------------------------------------

static func new_career(seed := 0) -> MasterLeague:
	var ml := MasterLeague.new()
	ml.rng.seed = seed if seed != 0 else Time.get_ticks_usec()
	var world: Dictionary = DataLoader.load_json("world/world.json")
	var plist: Dictionary = DataLoader.load_json("world/players.json")
	var players := {}
	for p: Dictionary in plist.players:
		var pd := p.duplicate()
		pd.merge({"injury_weeks": 0, "suspended": 0, "yellows": 0, "goals": 0, "apps": 0}, false)
		players[pd.id] = pd
	var clubs := {}
	for c: Dictionary in world.clubs:
		clubs[c.id] = c.duplicate(true)
	var master: Dictionary = world.master_team.duplicate(true)
	master["division"] = 2
	# The Master team takes the place of the weakest club of division 2.
	var d2 := clubs.values().filter(func(c: Dictionary) -> bool: return int(c.division) == 2)
	d2.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id > b.id)
	var dropped: Dictionary = d2[0]
	clubs.erase(dropped.id)
	clubs[master.id] = master
	for c: Dictionary in clubs.values():
		ml._number_squad(c, players)
	ml.state = {
		"version": VERSION, "season": 1, "year": int(world.get("season_start_year", 2002)),
		"user_club": master.id, "points": START_POINTS, "clubs": clubs, "players": players,
		"step": 0, "news": ["Bienvenido a la Master League. Objetivo: ascender a la Primera División."],
		"history": [], "free_agents": [],
	}
	ml._start_season()
	return ml


static func load_slot(slot := 1) -> MasterLeague:
	var path := SAVE_DIR + "master_league_%d.json" % slot
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return null
	var ml := MasterLeague.new()
	ml.state = data
	ml.rng.seed = int(data.get("rng_seed", 1)) + int(data.get("step", 0))
	ml._normalise_numbers()
	return ml


func save_slot(slot := 1) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	state["rng_seed"] = rng.seed
	var f := FileAccess.open(SAVE_DIR + "master_league_%d.json" % slot, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(state))
	return true


## JSON turns ints into floats; restore the counters we compare as ints.
func _normalise_numbers() -> void:
	state.step = int(state.step)
	state.season = int(state.season)
	state.points = int(state.points)


## Gives a shirt number to everyone who doesn't have one (lowest free).
func _number_squad(club: Dictionary, players: Dictionary) -> void:
	var used := {}
	for pid: String in club.squad:
		if players[pid].has("number"):
			used[int(players[pid].number)] = true
	var next := 1
	for pid: String in club.squad:
		var p: Dictionary = players[pid]
		if p.has("number"):
			continue
		while used.has(next):
			next += 1
		p.number = next
		used[next] = true


# --- season structure ---------------------------------------------------------------

func _start_season() -> void:
	var clubs: Dictionary = state.clubs
	var divisions := {"1": [], "2": []}
	for c: Dictionary in clubs.values():
		divisions[str(int(c.division))].append(c.id)
	for d: String in divisions:
		divisions[d].sort()
	state.divisions = divisions
	var leagues := {}
	for d: String in divisions:
		var ids: Array = divisions[d].duplicate()
		# Shuffle so the fixture order changes every season.
		for i in range(ids.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = ids[i]
			ids[i] = ids[j]
			ids[j] = tmp
		leagues[d] = {"fixtures": Competition.round_robin(ids), "table": Competition.new_table(divisions[d])}
	state.leagues = leagues
	# Cup: all of division 1 + the 6 best of division 2 by prestige (the user's club always in).
	var d2: Array = divisions["2"].duplicate()
	d2.sort_custom(func(a: String, b: String) -> bool: return int(clubs[a].get("prestige", 1)) > int(clubs[b].get("prestige", 1)))
	var cup_teams: Array = divisions["1"].duplicate() + d2.slice(0, 6)
	if not (state.user_club in cup_teams):
		cup_teams[cup_teams.size() - 1] = state.user_club
	state.cup = {"name": "Copa Master", "round": 0, "alive": cup_teams, "ties": Competition.knockout_round(cup_teams, rng),
		"winner": ""}
	# Calendar: league matchdays with cup rounds in between.
	var calendar := []
	var days: int = state.leagues["1"].fixtures.size()
	var cup_round := 0
	for day in days:
		calendar.append({"type": "league", "day": day})
		if cup_round < CUP_WEEKS_AFTER.size() and day == CUP_WEEKS_AFTER[cup_round]:
			calendar.append({"type": "cup", "round": cup_round})
			cup_round += 1
	state.calendar = calendar
	state.step = 0
	state.scorers = {}


func current_event() -> Dictionary:
	if int(state.step) >= state.calendar.size():
		return {}
	return state.calendar[int(state.step)]


func user_division() -> String:
	return str(int(club(state.user_club).division))


func club(id: String) -> Dictionary:
	return state.clubs[id]


func player(pid: String) -> Dictionary:
	return state.players[pid]


## The user's match in the current event, or {} (e.g. knocked out of the cup).
func user_fixture() -> Dictionary:
	var ev := current_event()
	if ev.is_empty():
		return {}
	for m: Dictionary in _event_matches(ev):
		if m.home == state.user_club or m.away == state.user_club:
			return m.merged({"competition": _event_name(ev)})
	return {}


func _event_matches(ev: Dictionary) -> Array:
	if ev.type == "league":
		var out := []
		for d: String in state.leagues:
			for m: Dictionary in state.leagues[d].fixtures[int(ev.day)]:
				out.append(m.merged({"division": d}))
		return out
	return state.cup.ties


func _event_name(ev: Dictionary) -> String:
	if ev.type == "league":
		return "Liga · Fecha %d" % (int(ev.day) + 1)
	return "%s · %s" % [state.cup.name, CUP_NAMES[mini(int(ev.round), CUP_NAMES.size() - 1)]]


# --- line-ups and the match engine --------------------------------------------------

## Best available XI for the club's formation, then 5 substitutes (one keeper).
func lineup(club_id: String) -> Dictionary:
	var c := club(club_id)
	var form := Formation.load_id(str(c.get("formation", "4-4-2")))
	var available: Array = c.squad.filter(func(pid: String) -> bool:
		var p := player(pid)
		return int(p.get("injury_weeks", 0)) <= 0 and int(p.get("suspended", 0)) <= 0)
	var used := {}
	var xi := []
	for i in form.slots.size():
		var role := form.role(i)
		var best := ""
		var best_score := -INF
		for pid: String in available:
			if used.has(pid):
				continue
			var p := player(pid)
			var same_group := Rating.group(str(p.position)) == Rating.group(role)
			if role == "GK" and str(p.position) != "GK":
				continue
			if role != "GK" and str(p.position) == "GK":
				continue
			var score := float(Rating.overall(p, role)) + (8.0 if same_group else 0.0)
			if score > best_score:
				best_score = score
				best = pid
		if best != "":
			used[best] = true
			xi.append({"pid": best, "role": role})
	var bench := []
	var rest: Array = available.filter(func(pid: String) -> bool: return not used.has(pid))
	rest.sort_custom(func(a: String, b: String) -> bool: return Rating.overall(player(a)) > Rating.overall(player(b)))
	var keeper: String = ""
	for pid: String in rest:
		if str(player(pid).position) == "GK":
			keeper = pid
			break
	if keeper != "":
		bench.append(keeper)
	for pid: String in rest:
		if bench.size() >= 5:
			break
		if pid != keeper:
			bench.append(pid)
	return {"xi": xi, "bench": bench}


## Match setup for MatchController (see setup_override): inline teams/players.
func match_setup(fixture: Dictionary, players_mode := "1") -> Dictionary:
	var teams := []
	for i in 2:
		var cid: String = fixture.home if i == 0 else fixture.away
		var c := club(cid)
		var lu := lineup(cid)
		var entries := []
		for e: Dictionary in lu.xi:
			entries.append({"data": _stats_for_match(e.pid), "role": e.role, "control": "ai"})
		var bench := []
		for pid: String in lu.bench:
			bench.append({"data": _stats_for_match(pid)})
		var kit_data: Variant = DataLoader.load_json("kits/%s.json" % c.kit)
		var primary := "#cccccc"
		if kit_data is Dictionary:
			primary = str(kit_data.primary)
		teams.append({"team": {"name": c.name, "short": c.short, "kit": c.kit, "gk_kit": c.gk_kit,
			"colors": {"primary": primary, "secondary": "#ffffff"}},
			"attack_dir": 1 if i == 0 else -1, "formation": c.get("formation", "4-4-2"),
			"tactics": c.get("tactics", "equilibrado"), "players": entries, "bench": bench})
	var human_team := 0 if fixture.home == state.user_club else 1
	return {"name": fixture.get("competition", ""), "direction_steps": 8, "half_minutes": 5, "referee": true,
		"max_substitutions": 3, "players": players_mode, "human_team": human_team, "teams": teams,
		"knockout": current_event().get("type", "") == "cup"}


func _stats_for_match(pid: String) -> Dictionary:
	var p := player(pid).duplicate()
	for k: String in ["age", "growth", "potential", "contract_years", "injury_weeks", "suspended", "yellows",
			"goals", "apps"]:
		p.erase(k)
	return p


# --- results ------------------------------------------------------------------------

## Plays out the current event: the user's match result (from the real match
## engine) if given, everything else simulated. Then the week goes by.
func advance(user_result: Dictionary = {}) -> void:
	var ev := current_event()
	if ev.is_empty():
		return
	var played := {}
	for m: Dictionary in _event_matches(ev):
		var result: Dictionary
		var is_user: bool = m.home == state.user_club or m.away == state.user_club
		if is_user and not user_result.is_empty():
			result = user_result
		else:
			result = QuickSim.play(lineup_ids(m.home), lineup_ids(m.away), state.players, rng)
		_apply_match(ev, m, result, played)
		if is_user:
			_user_points(m, int(result.home_goals), int(result.away_goals))
	_weekly(played)
	if ev.type == "cup":
		_advance_cup()
	state.step = int(state.step) + 1
	if int(state.step) >= state.calendar.size():
		end_season()


func lineup_ids(club_id: String) -> Array:
	var lu := lineup(club_id)
	var ids := []
	for e: Dictionary in lu.xi:
		ids.append(e.pid)
	return ids + lu.bench


func _apply_match(ev: Dictionary, m: Dictionary, r: Dictionary, played: Dictionary) -> void:
	var hg := int(r.home_goals)
	var ag := int(r.away_goals)
	if ev.type == "league":
		var fixture_list: Array = state.leagues[m.division].fixtures[int(ev.day)]
		for f: Dictionary in fixture_list:
			if f.home == m.home and f.away == m.away:
				f["hg"] = hg
				f["ag"] = ag
		Competition.record(state.leagues[m.division].table, m.home, m.away, hg, ag)
	else:
		m["hg"] = hg
		m["ag"] = ag
		m["winner"] = r.get("winner", Competition.tie_winner(m.home, m.away, hg, ag, rng))
	for pid: String in r.get("scorers", []):
		if state.players.has(pid):
			player(pid).goals = int(player(pid).get("goals", 0)) + 1
			state.scorers[pid] = int(state.scorers.get(pid, 0)) + 1
	for c: Dictionary in r.get("cards", []):
		if not state.players.has(c.pid):
			continue
		var p := player(c.pid)
		if c.card == "ROJA":
			p.suspended = int(p.get("suspended", 0)) + 2  # this week counts down one
		else:
			p.yellows = int(p.get("yellows", 0)) + 1
			if int(p.yellows) % 3 == 0:
				p.suspended = int(p.get("suspended", 0)) + 2
	for pid: String in r.get("injuries", []):
		if state.players.has(pid):
			player(pid).injury_weeks = rng.randi_range(1, 4) + 1
	var on_pitch: Array = r.get("played", lineup_ids(m.home).slice(0, 11) + lineup_ids(m.away).slice(0, 11))
	for pid: String in on_pitch:
		if state.players.has(pid):
			played[pid] = true
			player(pid).apps = int(player(pid).get("apps", 0)) + 1


func _user_points(m: Dictionary, hg: int, ag: int) -> void:
	var mine := hg if m.home == state.user_club else ag
	var theirs := ag if m.home == state.user_club else hg
	var earned := WIN_POINTS if mine > theirs else (DRAW_POINTS if mine == theirs else LOSS_POINTS)
	state.points = int(state.points) + earned
	var opp: String = m.away if m.home == state.user_club else m.home
	_news("%s %d - %d %s · +%d puntos" % [club(m.home).short, hg, ag, club(m.away).short, earned])
	if mine > theirs and club(opp).get("division", 2) == 1 and int(club(state.user_club).division) == 2:
		_news("¡Le ganaste a un equipo de Primera!")


func _weekly(played: Dictionary) -> void:
	for pid: String in state.players:
		var p: Dictionary = state.players[pid]
		if int(p.get("injury_weeks", 0)) > 0:
			p.injury_weeks = int(p.injury_weeks) - 1
		if int(p.get("suspended", 0)) > 0:
			p.suspended = int(p.suspended) - 1
		PlayerGrowth.week(p, played.has(pid), rng)


func _advance_cup() -> void:
	var cup: Dictionary = state.cup
	var winners := []
	for t: Dictionary in cup.ties:
		winners.append(t.get("winner", t.home))
	if winners.size() == 1:
		cup.winner = winners[0]
		cup.ties = []
		_news("%s gana la %s" % [club(cup.winner).name, cup.name])
		if cup.winner == state.user_club:
			state.points = int(state.points) + 5000
			_news("¡Campeones de la Copa! +5000 puntos")
		return
	cup.round = int(cup.round) + 1
	cup.alive = winners
	cup.ties = Competition.knockout_round(winners, rng)


# --- end of season ------------------------------------------------------------------

func end_season() -> void:
	var d1 := Competition.standings(state.leagues["1"].table)
	var d2 := Competition.standings(state.leagues["2"].table)
	var relegated := d1.slice(d1.size() - PROMOTED).map(func(r: Dictionary) -> String: return r.team)
	var promoted := d2.slice(0, PROMOTED).map(func(r: Dictionary) -> String: return r.team)
	var user_pos := _position(state.user_club)
	state.history.append({"season": int(state.season), "year": int(state.year), "champion_1": d1[0].team,
		"champion_2": d2[0].team, "cup": state.cup.get("winner", ""), "promoted": promoted, "relegated": relegated,
		"user_division": int(club(state.user_club).division), "user_position": user_pos})
	# Prizes by final position, then salaries.
	var div := int(club(state.user_club).division)
	var prize := maxi(0, (11 - user_pos)) * (600 if div == 1 else 300)
	if user_pos == 1:
		prize += 6000 if div == 1 else 3000
	state.points = int(state.points) + prize
	var wages := 0
	for pid: String in club(state.user_club).squad:
		wages += Rating.salary(player(pid))
	state.points = int(state.points) - wages
	_news("Fin de temporada: puesto %d · premio %d · salarios -%d" % [user_pos, prize, wages])
	for cid: String in relegated:
		club(cid).division = 2
	for cid: String in promoted:
		club(cid).division = 1
	if state.user_club in promoted:
		_news("¡ASCENSO A PRIMERA DIVISIÓN!")
	if state.user_club in relegated:
		_news("Descenso a Segunda División…")
	_age_and_contracts()
	state.season = int(state.season) + 1
	state.year = int(state.year) + 1
	_start_season()


func _position(cid: String) -> int:
	var d := str(int(club(cid).division))
	var rows := Competition.standings(state.leagues[d].table)
	for i in rows.size():
		if rows[i].team == cid:
			return i + 1
	return rows.size()


func _age_and_contracts() -> void:
	for cid: String in state.clubs:
		var c := club(cid)
		for pid: String in c.squad.duplicate():
			var p := player(pid)
			PlayerGrowth.end_of_season(p)
			p.yellows = 0
			# Retirement.
			if int(p.age) >= 37 or (int(p.age) >= 34 and rng.randf() < 0.35):
				c.squad.erase(pid)
				_news_if_user(cid, "%s se retira" % p.name)
				_replace_with_youth(c, p)
				continue
			if int(p.contract_years) <= 0:
				if cid == state.user_club:
					# Auto-renew if affordable, else he leaves.
					p.contract_years = 2
				else:
					p.contract_years = rng.randi_range(1, 3)


func _replace_with_youth(c: Dictionary, old: Dictionary) -> void:
	if c.squad.size() >= 22:
		return
	var pid := "%s_y%d_%d" % [c.id, int(state.season), rng.randi_range(100, 999)]
	var young := old.duplicate()
	young.id = pid
	young.name = "%s. %s" % [String.chr(65 + rng.randi_range(0, 25)), ["Lucero", "Bravo", "Ferro", "Vidal", "Sosa", "Paz", "Luna", "Rey"][rng.randi_range(0, 7)]]
	young.age = rng.randi_range(17, 19)
	young.potential = rng.randi_range(65, 92)
	young.growth = ["precoz", "normal", "tardio"][rng.randi_range(0, 2)]
	young.contract_years = 3
	for k: String in ["speed", "acceleration", "agility", "balance", "strength", "passing", "shooting", "shot_power",
			"heading", "tackling", "control", "technique", "reaction", "goalkeeping"]:
		if young.has(k):
			young[k] = maxi(30, int(young[k]) - rng.randi_range(8, 18))
	young.goals = 0
	young.apps = 0
	young.erase("number")
	state.players[pid] = young
	c.squad.append(pid)
	_number_squad(c, state.players)


# --- transfers ------------------------------------------------------------------------

func market(max_results := 40) -> Array:
	var out := []
	for cid: String in state.clubs:
		if cid == state.user_club:
			continue
		for pid: String in club(cid).squad:
			out.append(pid)
	out.sort_custom(func(a: String, b: String) -> bool: return Rating.overall(player(a)) > Rating.overall(player(b)))
	return out.slice(0, max_results)


## Offer `points` for a player. The selling club accepts if the offer
## reaches his value (more if he's a key man for them, less if we are a big club).
func make_offer(pid: String, points: int) -> Dictionary:
	if int(state.points) < points:
		return {"accepted": false, "reason": "No tenés suficientes puntos"}
	var seller := _club_of(pid)
	if seller == "" or seller == state.user_club:
		return {"accepted": false, "reason": "Ese jugador no está a la venta"}
	if club(state.user_club).squad.size() >= MAX_SQUAD:
		return {"accepted": false, "reason": "El plantel está completo (%d)" % MAX_SQUAD}
	if club(seller).squad.size() <= MIN_SQUAD:
		return {"accepted": false, "reason": "%s no puede vender más jugadores" % club(seller).name}
	var value := Rating.value(player(pid))
	var key_man := lineup_ids(seller).slice(0, 11).has(pid)
	var needed := value * (1.3 if key_man else 1.0)
	if points < needed:
		return {"accepted": false, "reason": "Rechazada: piden al menos %d puntos" % int(ceil(needed / 10.0) * 10)}
	club(seller).squad.erase(pid)
	club(state.user_club).squad.append(pid)
	player(pid).erase("number")
	_number_squad(club(state.user_club), state.players)
	player(pid).contract_years = 3
	state.points = int(state.points) - points
	_news("Fichaje: %s llega desde %s por %d puntos" % [player(pid).name, club(seller).name, points])
	return {"accepted": true, "reason": "¡Oferta aceptada!"}


func release(pid: String) -> bool:
	var squad: Array = club(state.user_club).squad
	if not (pid in squad) or squad.size() <= MIN_SQUAD:
		return false
	squad.erase(pid)
	state.free_agents.append(pid)
	_news("%s deja el club" % player(pid).name)
	return true


func _club_of(pid: String) -> String:
	for cid: String in state.clubs:
		if pid in club(cid).squad:
			return cid
	return ""


func _news(text: String) -> void:
	state.news.append(text)
	if state.news.size() > 30:
		state.news = state.news.slice(state.news.size() - 30)


func _news_if_user(cid: String, text: String) -> void:
	if cid == state.user_club:
		_news(text)
