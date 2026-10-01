class_name MatchController
extends Node3D
## Runs a match from a JSON setup (data/matches): spawns ball, players and
## pitch, applies the laws that exist at this stage (goals, throw-ins,
## corners, goal kicks, fouls) and exposes the queries players need
## (targets, pressure, goals).

# Loaded at runtime (not preload): Player.tscn's scripts reference this class.
const PLAYER_SCENE_PATH := "res://scenes/players/Player.tscn"
const BALL_SCENE_PATH := "res://scenes/ball/Ball.tscn"

enum Phase { PLAYING, STOPPED }

signal goal_scored(team: int)
signal restarted(kind: String)

## Match setup in data/matches. Can be overridden from the command line:
##   godot -- --match=stage0_solo
##   godot -- --attract          (every player driven by AI)
##   godot -- --zoom=0           (camera zoom level: 0 close, 1 normal, 2 wide)
@export var match_id := "stage2_5v5"
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
var clock := 0.0
var direction_steps := 8
var last_kick_text := ""
## One TeamBrain per team when the match setup gives formations (5v5+).
var brains: Array = [null, null]

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

	var look := LookProfile.load_profile(str(setup.get("look", LookProfile.DEFAULT)))
	LookProfile.apply_to_scene(self, look)
	LookProfile.apply_camera(camera, look)
	PitchBuilder.build(self, look)
	ball = (load(BALL_SCENE_PATH) as PackedScene).instantiate() as Ball
	add_child(ball)
	referee = PossessionReferee.new(ball)
	referee.rng = rng
	referee.event.connect(func(text: String) -> void: hud.flash(text, 0.8, false))
	referee.foul.connect(_on_foul)

	var teams: Array = setup.get("teams", [])
	for t in teams.size():
		_spawn_team(t, teams[t])
	referee.players = players

	camera.ball = ball
	hud.setup(self)
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
		brains[index] = brain
	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	var entries: Array = entry.get("players", [])
	for slot in entries.size():
		var pe: Dictionary = entries[slot]
		var p := player_scene.instantiate() as PlayerController
		p.stats = DataLoader.load_player(str(pe.get("id", "")))
		p.name = "%s_%s" % [team.get("short", "T%d" % index), p.stats.id]
		p.team = index
		p.attack_dir = attack
		var home: Array = pe.get("home", [0, 0])
		p.home_position = Vector3(float(home[0]), 0.0, float(home[1]))
		p.role = str(pe.get("role", brain.formation.role(slot) if brain != null else p.stats.position))
		p.is_keeper = p.role == "GK"
		p.match_ctx = self
		p.ball = ball
		p.direction_steps = direction_steps
		add_child(p)
		p.set_colors(primary, secondary)
		PlayerModel.attach(p, p.stats.appearance, gk_kit if p.is_keeper else kit, p.stats.number)
		p.kicked.connect(_on_kicked)
		p.ai = PlayerAI.new()
		p.ai.rng.seed = rng.randi()
		if brain != null:
			brain.players.append(p)
			p.home_position = brain.kickoff_position(p)
		var control := str(pe.get("control", "ai"))
		if control == "human" and allow_human and human == null:
			p.input_source = HumanInput.new()
			human = p
		elif control != "none":
			p.input_source = p.ai
		p.set_human(p == human)
		players.append(p)


func _physics_process(delta: float) -> void:
	if phase == Phase.STOPPED:
		_stop_timer -= delta
		if _stop_timer <= 0.0:
			phase = Phase.PLAYING
			_restart.call()
		return
	clock += delta
	for brain: TeamBrain in brains:
		if brain != null:
			brain.update(delta)
	referee.update(delta)
	if ball.owner_player != null:
		pass_receiver = null
	_check_ball_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_directions"):
		set_direction_steps(16 if direction_steps == 8 else 8)
	elif event.is_action_pressed(&"switch_player"):
		switch_to_nearest()
	elif event.is_action_pressed(&"camera_zoom"):
		camera.cycle_zoom()
	elif event.is_action_pressed(&"reset_match"):
		score = [0, 0]
		clock = 0.0
		kickoff(0)


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


func _on_foul(offender: PlayerController, victim: PlayerController) -> void:
	if phase != Phase.PLAYING:
		return
	var spot := DirectionResolver.flat(victim.global_position)
	_stop("FALTA DE %s" % offender.stats.name.to_upper(), 1.6, _restart_at.bind(victim.team, spot, "TIRO LIBRE"))


func _stop(message: String, seconds: float, restart: Callable) -> void:
	phase = Phase.STOPPED
	_stop_timer = seconds
	_restart = restart
	for p in players:
		p.frozen = true
	hud.flash(message, seconds, true)


func kickoff(team: int) -> void:
	phase = Phase.PLAYING
	ball.place(Vector3(0, Ball.RADIUS, 0))
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
		# Opponents back off 5 m.
		if p.team != team:
			var away := DirectionResolver.flat(p.global_position - spot)
			if away.length() < 5.0:
				var push := away.normalized() if away.length() > 0.1 else into_pitch
				p.teleport(spot + push * 5.0, -push)
	if taker != null:
		taker.teleport(spot - into_pitch * 0.55, into_pitch)
		_give_control(taker)
	restarted.emit(kind)


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
