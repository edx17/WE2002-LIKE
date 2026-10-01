class_name MatchController
extends Node3D
## Runs a match from a JSON setup (data/matches): spawns ball, players and
## pitch, applies the laws that exist at this stage (goals, throw-ins,
## corners, goal kicks, fouls) and exposes the queries players need
## (targets, pressure, goals).

# Loaded at runtime (not preload): Player.tscn's scripts reference this class.
const PLAYER_SCENE_PATH := "res://scenes/players/Player.tscn"
const BALL_SCENE_PATH := "res://scenes/ball/Ball.tscn"

enum Phase { PLAYING, STOPPED, FINISHED }

signal goal_scored(team: int)
signal restarted(kind: String)

## Match setup in data/matches. Can be overridden from the command line:
##   godot -- --match=stage0_solo
##   godot -- --attract          (every player driven by AI)
##   godot -- --zoom=0           (camera zoom level: 0 close, 1 normal, 2 wide)
@export var match_id := "stage4_partido"
## Disable to drive every player from AI/scripts (tests, attract mode).
@export var allow_human := true

var ball: Ball
var players: Array[PlayerController] = []
var referee: PossessionReferee
var rng := RandomNumberGenerator.new()
var score := [0, 0]
var team_data: Array[Dictionary] = [{}, {}]
var human: PlayerController = null
var phase: int = Phase.PLAYING
## Game time in minutes (0..90), driven by real seconds via half_seconds.
var clock := 0.0
var half := 1
## Real seconds per half (WE-style short matches). Match setup "half_minutes".
var half_seconds := 300.0
var _kicked_off_first := 0
var direction_steps := 8
var last_kick_text := ""
## Last foul verdict (HUD, tests).
var last_foul := {}
## One TeamBrain per team when the match setup gives formations (5v5+).
var brains: Array = [null, null]
var offside: OffsideRule
var foul_judge: FoulJudge
## Players sent off (out of the match).
var sent_off: Array[PlayerController] = []
var pause_menu: PauseMenu
## Substitutes still on the bench (player ids), per team.
var bench: Array = [[], []]
var subs_used := [0, 0]
var max_substitutions := 3
var queued_subs: Array[Dictionary] = []
var _team_kits: Array = [{}, {}]
## The match official on the pitch (not in `players`: never plays the ball).
var official: PlayerController = null
## Advantage being played: {foul, team, time}.
var _advantage := {}
## Dead ball being taken: {kind, team, taker, time}; empty in open play.
var set_piece := {}

var _last_receiver: PlayerController = null
## Running match statistics (HUD, tests, tuning).
var stats := {"saves": 0, "passes": 0, "passes_completed": 0, "shots": 0}
var _pending_pass: PlayerController = null
## Team-mate a pass in flight is meant for (he comes to meet it), or null.
var pass_receiver: PlayerController = null

var _stop_timer := 0.0
var _restart := Callable()

@onready var camera: WECamera = $Camera
@onready var hud: MatchHUD = $HUD


func _ready() -> void:
	InputSetup.ensure_actions()
	process_physics_priority = 10  # after every player has moved
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--match="):
			match_id = arg.trim_prefix("--match=")
		elif arg == "--attract":
			allow_human = false
		elif arg.begins_with("--zoom="):
			camera.zoom_index = clampi(int(arg.trim_prefix("--zoom=")), 0, camera.zoom_levels.size() - 1)
	var setup := DataLoader.load_match(match_id)
	direction_steps = int(setup.get("direction_steps", 8))
	half_seconds = float(setup.get("half_minutes", 5.0)) * 60.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--half-minutes="):
			half_seconds = float(arg.trim_prefix("--half-minutes=")) * 60.0

	var look := LookProfile.load_profile(str(setup.get("look", LookProfile.DEFAULT)))
	LookProfile.apply_to_scene(self, look)
	LookProfile.apply_camera(camera, look)
	PitchBuilder.build(self, look)
	ball = (load(BALL_SCENE_PATH) as PackedScene).instantiate() as Ball
	add_child(ball)
	offside = OffsideRule.new(self)
	foul_judge = FoulJudge.new(self)
	foul_judge.rng = rng
	foul_judge.strictness = float(setup.get("referee_strictness", 0.5))
	max_substitutions = int(setup.get("max_substitutions", 3))
	referee = PossessionReferee.new(ball)
	referee.rng = rng
	referee.event.connect(func(text: String) -> void: hud.flash(text, 0.8, false))
	referee.foul.connect(_on_foul)

	var teams: Array = setup.get("teams", [])
	for t in teams.size():
		_spawn_team(t, teams[t])
	referee.players = players
	if bool(setup.get("referee", true)) and brains[0] != null:
		_spawn_official()

	camera.ball = ball
	hud.setup(self)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.setup(self)
	kickoff(0)


func _spawn_team(index: int, entry: Dictionary) -> void:
	var team := DataLoader.load_team(str(entry.get("id", "")))
	team_data[index] = team
	var colors: Dictionary = team.get("colors", {})
	var primary := Color.html(str(colors.get("primary", "#d03030")))
	var secondary := Color.html(str(colors.get("secondary", "#ffffff")))
	var attack := float(entry.get("attack_dir", 1.0 if index == 0 else -1.0))
	var kit: Dictionary = {}
	var kit_data: Variant = DataLoader.load_json("kits/%s.json" % team.get("kit", "")) if team.has("kit") else null
	if kit_data is Dictionary:
		kit = kit_data
	var gk_kit: Dictionary = kit
	var gk_data: Variant = DataLoader.load_json("kits/%s.json" % team.get("gk_kit", "")) if team.has("gk_kit") else null
	if gk_data is Dictionary:
		gk_kit = gk_data
	var formation_id := str(entry.get("formation", ""))
	var brain: TeamBrain = null
	if formation_id != "":
		brain = TeamBrain.new(self, index, Formation.load_id(formation_id))
		brain.attack_dir = attack
		brain.tactics = TeamTactics.load_id(str(entry.get("tactics", "")))
		brains[index] = brain
	_team_kits[index] = {"kit": kit, "gk_kit": gk_kit, "primary": primary, "secondary": secondary,
		"short": str(team.get("short", "T%d" % index)), "attack": attack}
	bench[index] = []
	for be: Dictionary in entry.get("bench", []):
		bench[index].append(str(be.get("id", "")))
	var entries: Array = entry.get("players", [])
	for slot in entries.size():
		var pe: Dictionary = entries[slot]
		var p := _create_player(index, str(pe.get("id", "")), slot, str(pe.get("role", "")))
		var control := str(pe.get("control", "ai"))
		if control == "human" and allow_human and human == null:
			p.input_source = HumanInput.new()
			human = p
		elif control != "none":
			p.input_source = p.ai
		p.set_human(p == human)
		var home: Array = pe.get("home", [])
		if brain == null and home.size() == 2:
			p.home_position = Vector3(float(home[0]), 0.0, float(home[1]))


## Builds a player of team `index` for formation `slot` (also used for subs).
func _create_player(index: int, player_id: String, slot: int, role_override := "") -> PlayerController:
	var tk: Dictionary = _team_kits[index]
	var brain := brain_for(index)
	var p := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	p.stats = DataLoader.load_player(player_id)
	p.name = "%s_%s" % [tk.short, p.stats.id]
	p.team = index
	p.attack_dir = float(tk.attack)
	if brain != null:
		p.attack_dir = brain.attack_dir
	p.role = role_override if role_override != "" else (brain.formation.role(slot) if brain != null else p.stats.position)
	p.is_keeper = p.role == "GK"
	p.match_ctx = self
	p.ball = ball
	p.direction_steps = direction_steps
	add_child(p)
	p.set_colors(tk.primary, tk.secondary)
	PlayerModel.attach(p, p.stats.appearance, tk.gk_kit if p.is_keeper else tk.kit, p.stats.number)
	p.kicked.connect(_on_kicked)
	p.ai = PlayerAI.new()
	p.ai.rng.seed = rng.randi()
	if brain != null:
		brain.add_player(p, slot)
		p.home_position = brain.kickoff_position(p)
	players.append(p)
	return p


# --- substitutions ----------------------------------------------------------------

## Queue a change; it happens at the next stoppage (like the real thing).
func request_substitution(out: PlayerController, in_id: String) -> bool:
	var team := out.team
	if subs_used[team] + _queued_count(team) >= max_substitutions or not (in_id in bench[team]) \
			or not (out in players):
		return false
	for q: Dictionary in queued_subs:
		if q.out == out or q.in_id == in_id:
			return false
	queued_subs.append({"out": out, "in_id": in_id})
	return true


func _queued_count(team: int) -> int:
	var n := 0
	for q: Dictionary in queued_subs:
		if (q.out as PlayerController).team == team:
			n += 1
	return n


func substitute(out: PlayerController, in_id: String) -> PlayerController:
	var team := out.team
	var brain := brain_for(team)
	if brain == null or not (out in players) or subs_used[team] >= max_substitutions:
		return null
	var slot := brain.slot_of(out)
	var pos := out.global_position
	var face := out.facing
	var was_human := out == human
	_remove_from_play(out)
	bench[team].erase(in_id)
	var p := _create_player(team, in_id, slot)
	p.teleport(pos, face)
	p.frozen = phase != Phase.PLAYING
	if was_human:
		human = p
		p.input_source = out.input_source
		p.set_human(true)
	else:
		p.input_source = p.ai
	subs_used[team] += 1
	stats["subs"] = int(stats.get("subs", 0)) + 1
	hud.flash("CAMBIO: SALE %s · ENTRA %s" % [out.stats.name.to_upper(), p.stats.name.to_upper()], 2.0, false)
	return p


## At every stoppage: queued changes, then the AI coach of computer teams.
func _apply_substitutions() -> void:
	for q: Dictionary in queued_subs.duplicate():
		substitute(q.out, q.in_id)
	queued_subs.clear()
	for team in 2:
		if human != null and human.team == team:
			continue
		_ai_coach(team)


## The computer's bench: injured players first, then the most tired after
## the hour mark. One change per stoppage, like-for-like position.
func _ai_coach(team: int) -> void:
	if subs_used[team] >= max_substitutions or bench[team].is_empty():
		return
	var out: PlayerController = null
	for p in players:
		if p.team == team and p.injured:
			out = p
			break
	if out == null and clock > 55.0:
		for p in players:
			if p.team == team and not p.is_keeper and p.stamina < 0.35 and (out == null or p.stamina < out.stamina):
				out = p
	if out == null:
		return
	var best_id := ""
	for id: String in bench[team]:
		var cand := DataLoader.load_player(id)
		var keeper_ok := (cand.position == "GK") == out.is_keeper
		if keeper_ok and (best_id == "" or _same_line(cand.position, out.role)):
			best_id = id
			if _same_line(cand.position, out.role):
				break
	if best_id != "":
		substitute(out, best_id)


static func _same_line(a: String, b: String) -> bool:
	var lines := [["GK"], ["CB", "LB", "RB", "LWB", "RWB"], ["DMF", "CMF", "AMF", "LMF", "RMF"], ["CF", "WG", "SS"]]
	for line: Array in lines:
		if a in line and b in line:
			return true
	return a == b


func _remove_from_play(p: PlayerController) -> void:
	players.erase(p)
	referee.players.erase(p)
	var brain := brain_for(p.team)
	if brain != null:
		brain.remove_player(p)
	if ball.owner_player == p:
		ball.owner_player = null
	p.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.collision_layer = 0
	p.collision_mask = 0
	p.global_position = Vector3(0, -50, 0)


func _spawn_official() -> void:
	official = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	official.stats = DataLoader.load_player("arbitro")
	official.name = "Arbitro"
	official.team = 2
	official.role = "REF"
	official.match_ctx = self
	official.ball = ball
	official.direction_steps = direction_steps
	add_child(official)
	# Ghost to physics: nobody bumps into the referee.
	official.collision_layer = 0
	official.collision_mask = 1
	official.set_colors(Color(0.08, 0.08, 0.08), Color(0.08, 0.08, 0.08))
	var kit: Variant = DataLoader.load_json("kits/referee.json")
	PlayerModel.attach(official, "referee", kit if kit is Dictionary else {}, 0)
	official.input_source = RefereeAI.new()
	official.teleport(Vector3(0, 0, 14), Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	if phase == Phase.FINISHED:
		return
	if phase == Phase.STOPPED:
		_stop_timer -= delta
		if _stop_timer <= 0.0:
			phase = Phase.PLAYING
			_restart.call()
		return
	var game_minutes := delta * 45.0 / half_seconds
	clock += game_minutes
	for p in players:
		p.update_stamina(game_minutes)
	if clock >= 45.0 * half:
		_end_of_half()
		return
	for brain: TeamBrain in brains:
		if brain != null:
			brain.update(delta)
	referee.update(delta)
	if ball.owner_player != null:
		pass_receiver = null
	_update_set_piece(delta)
	_update_advantage(delta)
	var flag := offside.update()
	if not flag.is_empty():
		var offender: PlayerController = flag.player
		_stop("FUERA DE JUEGO", 1.4, _restart_at.bind(1 - offender.team, DirectionResolver.flat(flag.spot), "TIRO LIBRE"))
		return
	_check_ball_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_directions"):
		set_direction_steps(16 if direction_steps == 8 else 8)
	elif event.is_action_pressed(&"switch_player"):
		switch_to_nearest()
	elif event.is_action_pressed(&"cycle_tactics"):
		cycle_tactics()
	elif event.is_action_pressed(&"camera_zoom"):
		camera.cycle_zoom()
	elif event.is_action_pressed(&"reset_match"):
		restart_match()


## In-match strategy change for the human's team (T), like WE's quick tactics.
const TACTICS_CYCLE := ["equilibrado", "presion_alta", "repliegue"]

func cycle_tactics() -> void:
	if human == null or brain_for(human.team) == null:
		return
	var brain := brain_for(human.team)
	var i := TACTICS_CYCLE.find(_tactics_id(brain))
	var next_id: String = TACTICS_CYCLE[(i + 1) % TACTICS_CYCLE.size()]
	brain.tactics = TeamTactics.load_id(next_id)
	hud.flash("TÁCTICA: %s" % brain.tactics.name.to_upper(), 1.2, false)


func _tactics_id(brain: TeamBrain) -> String:
	for id: String in TACTICS_CYCLE:
		if TeamTactics.load_id(id).name == brain.tactics.name:
			return id
	return ""


func restart_match() -> void:
	score = [0, 0]
	clock = 0.0
	if half == 2:
		_switch_sides()
	half = 1
	for p in players:
		p.stamina = 1.0
		p.injured = false
		p.yellow_cards = 0
	kickoff(0)


func _end_of_half() -> void:
	if half == 1:
		half = 2
		clock = 45.0
		_stop("DESCANSO", 3.0, func() -> void:
			_switch_sides()
			kickoff(1 - _kicked_off_first))
	else:
		clock = 90.0
		_stop("FINAL DEL PARTIDO  %d - %d" % [score[0], score[1]], 1.0, func() -> void:
			phase = Phase.FINISHED
			for p in players:
				p.frozen = true
			hud.flash("FINAL  %d - %d   ·   R para jugar otro" % [score[0], score[1]], 3600.0, true))


## Half time: teams change ends.
func _switch_sides() -> void:
	for p in players:
		p.attack_dir = -p.attack_dir
		p.home_position.x = -p.home_position.x
	for brain: TeamBrain in brains:
		if brain != null:
			brain.attack_dir = -brain.attack_dir


func set_piece_active() -> bool:
	return not set_piece.is_empty()


## Set-piece positions are held until the taker plays the ball (or 6 s pass).
func _update_set_piece(delta: float) -> void:
	if set_piece.is_empty():
		return
	set_piece.time += delta
	if set_piece.time > 6.0:
		_end_set_piece()


func _end_set_piece() -> void:
	set_piece = {}
	for brain: TeamBrain in brains:
		if brain != null:
			brain.set_piece_targets.clear()


func set_direction_steps(steps: int) -> void:
	direction_steps = steps
	for p in players:
		p.direction_steps = steps
	hud.flash("%d DIRECCIONES" % steps, 1.0, false)


# --- laws ------------------------------------------------------------------------

func _check_ball_out() -> void:
	var b := ball.global_position
	var r := Ball.RADIUS
	if absf(b.x) > PitchBuilder.HALF_LENGTH + r:
		var side := signf(b.x)
		if absf(b.z) < PitchBuilder.GOAL_HALF_WIDTH and b.y < PitchBuilder.GOAL_HEIGHT:
			_goal(_team_attacking(side))
			return
		var defending := _team_attacking(-side)
		var last := ball.last_touch as PlayerController
		if last != null and last.team == defending:
			var corner := Vector3(side * (PitchBuilder.HALF_LENGTH - 0.5), 0, signf(b.z) * (PitchBuilder.HALF_WIDTH - 0.5))
			_stop("CÓRNER", 1.2, _restart_at.bind(1 - defending, corner, "CÓRNER"))
		else:
			var goal_kick := Vector3(side * (PitchBuilder.HALF_LENGTH - 5.5), 0, signf(b.z) * 5.0)
			_stop("SAQUE DE ARCO", 1.2, _restart_at.bind(defending, goal_kick, "SAQUE DE ARCO"))
	elif absf(b.z) > PitchBuilder.HALF_WIDTH + r:
		var last := ball.last_touch as PlayerController
		var team := 0 if last == null else 1 - last.team
		var spot := Vector3(clampf(b.x, -PitchBuilder.HALF_LENGTH + 1.0, PitchBuilder.HALF_LENGTH - 1.0), 0,
			signf(b.z) * (PitchBuilder.HALF_WIDTH - 0.3))
		_stop("LATERAL", 1.0, _restart_at.bind(team, spot, "LATERAL"))


func _team_attacking(side: float) -> int:
	for p in players:
		if signf(p.attack_dir) == side:
			return p.team
	return 0 if side > 0.0 else 1


func _goal(team: int) -> void:
	score[team] += 1
	goal_scored.emit(team)
	for p in players:
		if p.team == team:
			p.celebrate()
	_stop("¡GOOOL!", 2.5, kickoff.bind(1 - team))
	offside.reset()


func _on_foul(offender: PlayerController, victim: PlayerController, slide: bool) -> void:
	if phase != Phase.PLAYING:
		return
	var verdict := foul_judge.judge(offender, victim, slide)
	stats["fouls"] = int(stats.get("fouls", 0)) + 1
	last_foul = verdict.merged({"offender": offender, "victim": victim})
	if verdict.injury:
		victim.injured = true
	var spot := DirectionResolver.flat(victim.global_position)
	if verdict.penalty:
		_book(offender, verdict.card)
		_stop("¡PENAL!", 2.0, _restart_at.bind(victim.team, _penalty_spot(victim.team), "PENAL"))
		return
	# Advantage: the fouled team still has (or is about to win) the ball.
	var owner := ball.owner_player as PlayerController
	if not verdict.dogso and owner != null and owner.team == victim.team and owner != victim:
		_book(offender, verdict.card)
		_advantage = {"team": victim.team, "spot": spot, "time": 0.0}
		hud.flash("VENTAJA", 1.0, false)
		return
	_book(offender, verdict.card)
	var msg := "FALTA DE %s" % offender.stats.name.to_upper()
	if verdict.card != "":
		msg += "  ·  TARJETA %s" % verdict.card
	_stop(msg, 1.8, _restart_at.bind(victim.team, spot, "TIRO LIBRE"))


## Plays on while the fouled team keeps the ball; if it is lost within 1.5 s
## the referee goes back for the free kick.
func _update_advantage(delta: float) -> void:
	if _advantage.is_empty():
		return
	_advantage.time += delta
	var owner := ball.owner_player as PlayerController
	if owner != null and owner.team != _advantage.team:
		var adv := _advantage
		_advantage = {}
		_stop("FALTA", 1.5, _restart_at.bind(int(adv.team), adv.spot as Vector3, "TIRO LIBRE"))
	elif _advantage.time > 1.5:
		_advantage = {}


func _book(p: PlayerController, card: String) -> void:
	if card == "":
		return
	stats["cards"] = int(stats.get("cards", 0)) + 1
	hud.show_card(card, p)
	if card == FoulJudge.YELLOW:
		p.yellow_cards += 1
	else:
		send_off(p)


## Red card: the player leaves; his team plays one short.
func send_off(p: PlayerController) -> void:
	if p == human:
		switch_to_nearest()
		if p == human:  # nobody to switch to
			human = null
	_remove_from_play(p)
	sent_off.append(p)


func _penalty_spot(attacking_team: int) -> Vector3:
	return Vector3(_attack_dir_of(attacking_team) * (PitchBuilder.HALF_LENGTH - 11.0), 0, 0)


func _stop(message: String, seconds: float, restart: Callable) -> void:
	phase = Phase.STOPPED
	_stop_timer = seconds
	_restart = restart
	for p in players:
		p.frozen = true
	hud.flash(message, seconds, true)
	_apply_substitutions()


func kickoff(team: int) -> void:
	phase = Phase.PLAYING
	if clock < 0.01:
		_kicked_off_first = team
	ball.place(Vector3(0, Ball.RADIUS, 0))
	_end_set_piece()
	offside.reset()
	var taker := _kickoff_taker(team)
	for p in players:
		p.frozen = false
		var home := p.home_position
		if brains[p.team] != null:
			home = (brains[p.team] as TeamBrain).kickoff_position(p)
		p.teleport(home, Vector3.RIGHT * p.attack_dir)
	if taker != null:
		taker.teleport(Vector3(-0.6 * taker.attack_dir, 0, 0), Vector3.RIGHT * taker.attack_dir)
		_give_control(taker)
	camera.snap()
	restarted.emit("SAQUE INICIAL")


func _restart_at(team: int, spot: Vector3, kind: String) -> void:
	ball.place(Vector3(spot.x, Ball.RADIUS, spot.z))
	var into_pitch := DirectionResolver.flat(-spot).normalized()
	if into_pitch == Vector3.ZERO:
		into_pitch = Vector3.RIGHT
	var taker := _restart_taker(team, spot, kind)
	for p in players:
		p.frozen = false
		if p.is_grounded_state() or p.state == PlayerController.State.CELEBRATE:
			p.teleport(p.global_position, p.facing)
		# Opponents back off (9.15 m, 3 m for throw-ins).
		var keep := SetPieces.min_distance(kind)
		if p.team != team:
			var away := DirectionResolver.flat(p.global_position - spot)
			if away.length() < keep:
				var push := away.normalized() if away.length() > 0.1 else into_pitch
				p.teleport(spot + push * keep, -push)
	var face := into_pitch
	if kind == "TIRO LIBRE" or kind == "CÓRNER" or kind == "PENAL":
		face = DirectionResolver.flat(goal_center(_attack_dir_of(team)) - spot).normalized()
	if taker != null:
		taker.teleport(spot - face * 0.55, face)
		_give_control(taker)
		if kind == "LATERAL":
			# Throw-in: the taker picks the ball up.
			taker.teleport(Vector3(spot.x, 0, spot.z), face)
			ball.hold(taker)
	offside.reset()
	set_piece = {"kind": kind, "team": team, "taker": taker, "time": 0.0}
	SetPieces.arrange(self, kind, team, spot, taker)
	restarted.emit(kind)


func _attack_dir_of(team: int) -> float:
	for p in players:
		if p.team == team:
			return p.attack_dir
	return 1.0


## Kick-off: the most advanced outfield player (the forward) takes it.
func _kickoff_taker(team: int) -> PlayerController:
	var best: PlayerController = null
	for p in players:
		if p.team != team or p.is_keeper:
			continue
		if best == null or p.home_position.x * p.attack_dir > best.home_position.x * best.attack_dir:
			best = p
	if best == null and human != null and human.team == team:
		return human
	return best


## Goal kicks go to the keeper; everything else to the nearest outfield player.
func _restart_taker(team: int, pos: Vector3, kind: String) -> PlayerController:
	var best: PlayerController = null
	if kind == "PENAL":
		# The best finisher takes it.
		for p in players:
			if p.team == team and not p.is_keeper and (best == null or p.stats.shooting > best.stats.shooting):
				best = p
		return best
	for p in players:
		if p.team != team:
			continue
		if kind == "SAQUE DE ARCO" and p.is_keeper:
			return p
		if p.is_keeper and players.size() > 2:
			continue
		if best == null or p.global_position.distance_to(pos) < best.global_position.distance_to(pos):
			best = p
	return best


# --- human control ----------------------------------------------------------------

## Moves the pad to another player of the human's team (never the keeper).
func set_human(p: PlayerController) -> void:
	if human == null or p == null or p == human or p.team != human.team or p.is_keeper:
		return
	var pad := human.input_source
	human.input_source = human.ai
	human.set_human(false)
	human = p
	human.input_source = pad
	human.set_human(true)


func _give_control(p: PlayerController) -> void:
	if human != null and p.team == human.team:
		set_human(p)


## Manual switch (Q / LB): the team-mate closest to the ball.
func switch_to_nearest() -> void:
	if human == null:
		return
	var best: PlayerController = null
	for p in teammates_of(human):
		if p.is_keeper:
			continue
		if best == null or p.global_position.distance_to(ball.global_position) < best.global_position.distance_to(ball.global_position):
			best = p
	set_human(best)


# --- queries used by players and AI --------------------------------------------

func brain_for(team: int) -> TeamBrain:
	return brains[team] as TeamBrain


func is_keeper(p: PlayerController) -> bool:
	return p.is_keeper


## Inside the penalty area at the goal on `goal_side` (+1 = goal at +X).
func in_penalty_area(pos: Vector3, goal_side: float) -> bool:
	return pos.x * signf(goal_side) > PitchBuilder.HALF_LENGTH - 16.5 and absf(pos.z) < 20.16


## Centre of the goal a team attacking towards `attack_dir` shoots at.
func goal_center(attack_dir: float) -> Vector3:
	return Vector3(signf(attack_dir) * PitchBuilder.HALF_LENGTH, 0.0, 0.0)


func opponents_of(p: PlayerController) -> Array[PlayerController]:
	var out: Array[PlayerController] = []
	for o in players:
		if o.team != p.team:
			out.append(o)
	return out


func teammates_of(p: PlayerController) -> Array[PlayerController]:
	var out: Array[PlayerController] = []
	for o in players:
		if o.team == p.team and o != p:
			out.append(o)
	return out


func nearest_opponent(p: PlayerController) -> PlayerController:
	var best: PlayerController = null
	var best_d := INF
	for o in opponents_of(p):
		var d := p.global_position.distance_to(o.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


## 0..1: how closed down the player is.
func pressure_on(p: PlayerController) -> float:
	var o := nearest_opponent(p)
	if o == null:
		return 0.0
	return clampf((3.0 - p.global_position.distance_to(o.global_position)) / 2.5, 0.0, 1.0)


func is_lane_blocked(p: PlayerController, target: Vector3, width: float) -> bool:
	var a := DirectionResolver.flat(p.global_position)
	var b := DirectionResolver.flat(target)
	for o in opponents_of(p):
		var c := DirectionResolver.flat(o.global_position)
		var closest := Geometry3D.get_closest_point_to_segment(c, a, b)
		if closest.distance_to(c) < width and closest.distance_to(a) > 0.5:
			return true
	return false


## Point in the goal a shot aims at. Stick up/down picks the post, neutral
## aims slightly towards the far side.
func shot_target(p: PlayerController, aim: Vector2) -> Vector3:
	var goal := goal_center(p.attack_dir)
	var aim_z := clampf(-p.global_position.z * 0.1, -1.5, 1.5)
	if absf(aim.y) > 0.1:
		aim_z = signf(aim.y) * (PitchBuilder.GOAL_HALF_WIDTH - 0.6)
	return Vector3(goal.x, 0.0, aim_z)


## Pass target: a team-mate inside a cone around the chosen direction, or
## space at a distance set by the power bar.
func pass_target(p: PlayerController, type: int, dir: Vector3, power: float) -> Vector3:
	var best: PlayerController = null
	var best_score := -INF
	for mate in teammates_of(p):
		var to := DirectionResolver.flat(mate.global_position - p.global_position)
		var angle := absf(DirectionResolver.signed_angle(dir, to.normalized()))
		if angle > deg_to_rad(40.0):
			continue
		var s := -rad_to_deg(angle) * 2.0 - to.length() * 0.3
		if s > best_score:
			best_score = s
			best = mate
	_last_receiver = best
	if best != null:
		var lead := 0.35
		var target := best.global_position + DirectionResolver.flat(best.velocity) * lead
		if type == KickSolver.KickType.THROUGH_PASS:
			target += Vector3.RIGHT * best.attack_dir * lerpf(4.0, 14.0, power)
		return target
	var dist := lerpf(8.0, 35.0, power)
	match type:
		KickSolver.KickType.THROUGH_PASS:
			dist = lerpf(12.0, 40.0, power)
		KickSolver.KickType.LOB_PASS, KickSolver.KickType.CROSS:
			dist = lerpf(15.0, 50.0, power)
	return p.global_position + dir * dist


# --- events ------------------------------------------------------------------------

func _on_kicked(p: PlayerController, type: int, result: KickSolver.KickResult) -> void:
	last_kick_text = "%s: %s" % [p.stats.name, result.describe(type)]
	# Offside: throw-ins, corners and goal kicks are exempt.
	var exempt: bool = not set_piece.is_empty() and set_piece.taker == p \
		and set_piece.kind in ["LATERAL", "CÓRNER", "SAQUE DE ARCO"]
	if exempt:
		offside.reset()
	else:
		offside.on_kick(p)
	if not set_piece.is_empty():
		_end_set_piece()
	if type == KickSolver.KickType.SHOT:
		stats.shots += 1
	elif type != KickSolver.KickType.HEADER:
		stats.passes += 1
		_pending_pass = p
	pass_receiver = _last_receiver if type != KickSolver.KickType.SHOT and _last_receiver != null \
		and _last_receiver.team == p.team else null
	# WE: control follows the pass to its receiver.
	if p == human and type != KickSolver.KickType.SHOT and _last_receiver != null and _last_receiver.team == p.team:
		set_human(_last_receiver)
	if result.mishit and p == human:
		hud.flash("¡LE PEGÓ MAL!", 0.8, false)


func on_keeper_save(keeper: PlayerController, caught: bool) -> void:
	stats.saves += 1
	hud.flash("¡ATAJADA DE %s!" % keeper.stats.name.to_upper() if caught else "¡DESPEJA %s!" % keeper.stats.name.to_upper(), 1.0, false)


func on_ball_received(p: PlayerController, zone: int, quality: float) -> void:
	if _pending_pass != null:
		if _pending_pass.team == p.team and _pending_pass != p:
			stats.passes_completed += 1
		_pending_pass = null
	# A team-mate controls the ball: the pad goes to him.
	if human != null and p.team == human.team and p != human and not p.is_keeper:
		set_human(p)
	if p == human and quality < 0.5:
		hud.flash("CONTROL CON %s… DEFECTUOSO" % BallInteraction.ZONE_NAMES[zone], 0.7, false)
