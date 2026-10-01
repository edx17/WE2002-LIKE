class_name PlayerAI
extends RefCounted
## Off-ball / on-ball brain for one player. It never moves the body directly:
## it fills the same PlayerIntent a pad does, so AI players are bound by the
## same 8/16 directions, acceleration, turn rate and kick imprecision.
##
## Never "WHERE BALL? → RUN". With a team (TeamBrain) the player first gets a
## tactical assignment (press, cover, mark, support, run, hold the slot) and
## only then decides how to move. With the ball it weighs pass vs dribble vs
## shot. Without a TeamBrain (1v1) it falls back to the solo behaviours.

enum Mode { POSITION, DEFEND, MARK, COVER, SUPPORT, RUN, PRESS, RECOVER, ATTACK, KEEPER, RECEIVE }

const MODE_NAMES := ["POSITION", "DEFEND", "MARK", "COVER", "SUPPORT", "RUN", "PRESS", "RECOVER", "ATTACK", "KEEPER", "RECEIVE"]
## Seconds a keeper holds the ball before distributing it.
const KEEPER_HOLD := 0.9

var mode: int = Mode.POSITION
var rng := RandomNumberGenerator.new()

var _think := 0.0
var _move := Vector2.ZERO
var _sprint := false
var _release := PlayerIntent.NONE
var _release_charge := 0.0
var _press := PlayerIntent.NONE


func fill(intent: PlayerIntent, p: PlayerController, delta: float) -> void:
	intent.begin_frame()
	if p.is_keeper:
		_keeper_reflex(intent, p)  # every frame: shots don't wait for the brain
	_think -= delta
	if _think <= 0.0:
		# Reaction attribute = how often the brain re-evaluates.
		_think = lerpf(0.32, 0.1, p.stats.n(&"reaction")) * rng.randf_range(0.85, 1.15)
		_decide(p)
	intent.move = _move
	intent.sprint = _sprint
	intent.held = 0
	if _press != PlayerIntent.NONE:
		intent.press(_press)
		_press = PlayerIntent.NONE
	if _release != PlayerIntent.NONE:
		intent.release(_release, _release_charge)
		_release = PlayerIntent.NONE
		# Don't chase your own pass: stop and re-think right after the kick.
		_move = Vector2.ZERO
		_think = 0.2


func _decide(p: PlayerController) -> void:
	var carrier := p.ball.owner_player as PlayerController
	if p.is_keeper:
		_keeper(p, carrier)
		return
	if carrier == p:
		_on_ball(p)
		return
	if carrier == null and p.match_ctx.pass_receiver == p:
		_receive(p)
		return
	var brain := p.match_ctx.brain_for(p.team)
	if brain == null:
		if carrier != null and carrier.team != p.team:
			_defend(p, carrier)
		elif carrier != null:
			_support(p)
		else:
			_loose_ball(p)
		return
	var a := brain.assignment(p)
	var target: Vector3 = a.target
	match int(a.mode):
		TeamBrain.Mode.PRESS:
			if carrier != null and carrier.team != p.team:
				_defend(p, carrier)
			else:
				_loose_ball(p)
		TeamBrain.Mode.COVER:
			mode = Mode.COVER
			_go(p, target, 1.0, 6.0)
		TeamBrain.Mode.MARK:
			mode = Mode.MARK
			_go(p, target, 0.8, 5.0)
		TeamBrain.Mode.SUPPORT:
			mode = Mode.SUPPORT
			_go(p, target, 1.5, 8.0)
		TeamBrain.Mode.RUN:
			mode = Mode.RUN
			_go(p, target, 1.0, 3.0)
		_:
			mode = Mode.POSITION
			_go(p, target, 1.5, 10.0)
			# A loose ball rolling right past me: take it.
			if carrier == null and p.global_position.distance_to(p.ball.global_position) < 4.0:
				_loose_ball(p)


## A pass is coming to me: meet the ball on its path, don't wait for it.
func _receive(p: PlayerController) -> void:
	mode = Mode.RECEIVE
	var b := p.ball.global_position
	var v := DirectionResolver.flat(p.ball.linear_velocity)
	var meet := b
	var t := 0.0
	while t <= 2.5:
		var q := b + v * t * (1.0 - 0.15 * t)  # rolling ball slows down
		if p.global_position.distance_to(q) / p.sprint_speed() <= t:
			meet = q
			break
		meet = q
		t += 0.1
	_move = _towards(p, meet, 0.2)
	_sprint = p.global_position.distance_to(meet) > 3.0


## Walk/run to a point; sprint only when far from it.
func _go(p: PlayerController, target: Vector3, tolerance: float, sprint_beyond: float) -> void:
	_move = _towards(p, target, tolerance)
	_sprint = p.global_position.distance_to(target) > sprint_beyond


# --- with the ball -------------------------------------------------------------

func _on_ball(p: PlayerController) -> void:
	mode = Mode.ATTACK
	var m := p.match_ctx
	var goal := m.goal_center(p.attack_dir)
	var to_goal := DirectionResolver.flat(goal - p.global_position)
	var dist := to_goal.length()
	var threat := m.nearest_opponent(p)
	var threat_dist := INF
	if threat != null:
		threat_dist = p.global_position.distance_to(threat.global_position)

	# 1. Shoot.
	var lane_clear := not m.is_lane_blocked(p, goal, 1.8)
	if dist < 24.0 and (lane_clear or threat_dist < 1.8 or dist < 13.0):
		_shoot(p, dist)
		return

	# 2. Pass, when a team-mate is clearly better placed or I'm being closed down.
	var pressured := threat_dist < 2.6
	var best_pass := _best_pass(p)
	var dribble := _best_dribble(p, to_goal / dist)
	if not best_pass.is_empty():
		var need: float = 0.9 if pressured else 1.6 + maxf(0.0, dribble[1])
		if best_pass.score > need:
			var aim: Vector3 = best_pass.target - p.global_position
			_move = DirectionResolver.to_stick(DirectionResolver.flat(aim)).normalized()
			_release = best_pass.action
			_release_charge = best_pass.charge
			_sprint = false
			return

	# 3. Dribble towards the best of the 8 directions.
	_move = dribble[0]
	_sprint = threat_dist > 4.0 or dribble[1] > 0.9


func _shoot(p: PlayerController, dist: float) -> void:
	# Aim at the far post: stick up/down selects the post.
	var post := -signf(p.global_position.z)
	if post == 0.0:
		post = 1.0 if rng.randf() < 0.5 else -1.0
	_move = Vector2(p.attack_dir, post).normalized()
	_release = PlayerIntent.Action.SHOOT
	_release_charge = clampf(0.4 + dist / 45.0 + rng.randf_range(-0.08, 0.08), 0.35, 0.85)
	_sprint = false


## Scores every team-mate as a pass: safe lane, space around the receiver,
## ground gained. Returns {} when nobody is worth it.
func _best_pass(p: PlayerController) -> Dictionary:
	var m := p.match_ctx
	var best := {}
	var my_prog := Formation.progress_of(p.global_position.x, p.attack_dir)
	for mate in m.teammates_of(p):
		if mate.is_keeper or not mate.can_play_ball():
			continue
		var target := mate.global_position + DirectionResolver.flat(mate.velocity) * 0.4
		var d := p.global_position.distance_to(target)
		if d < 5.0 or d > 42.0:
			continue
		var lane := _lane_clearance(p, target)
		var space := 8.0
		for o in m.opponents_of(p):
			space = minf(space, o.global_position.distance_to(target))
		var gain := (Formation.progress_of(target.x, p.attack_dir) - my_prog) * 2.0 * PitchBuilder.HALF_LENGTH
		var action := PlayerIntent.Action.PASS
		var safe := clampf((lane - 1.0) / 4.0, 0.0, 1.0)
		if safe < 0.3 and d > 15.0:
			action = PlayerIntent.Action.LOB  # lane blocked: go over it
			safe = 0.5
		elif gain > 12.0 and safe > 0.6 and space > 4.0:
			action = PlayerIntent.Action.THROUGH
		var score := safe * 1.6 + clampf(space / 6.0, 0.0, 1.0) + gain / 15.0 - d / 60.0
		if best.is_empty() or score > best.score:
			best = {"score": score, "target": target, "action": action,
				"charge": clampf(0.25 + d / 45.0 + rng.randf_range(-0.05, 0.05), 0.3, 0.95)}
	return best


## Distance from the closest opponent to the passing lane.
func _lane_clearance(p: PlayerController, target: Vector3) -> float:
	var a := DirectionResolver.flat(p.global_position)
	var b := DirectionResolver.flat(target)
	var clear := 10.0
	for o in p.match_ctx.opponents_of(p):
		var c := DirectionResolver.flat(o.global_position)
		var closest := Geometry3D.get_closest_point_to_segment(c, a, b)
		if closest.distance_to(a) > 0.8:
			clear = minf(clear, closest.distance_to(c))
	return clear


## [best stick direction, its score] among the 8 directions (progress vs danger).
func _best_dribble(p: PlayerController, goal_dir: Vector3) -> Array:
	var best := Vector2.ZERO
	var best_score := -INF
	for i in 8:
		var d2 := Vector2.from_angle(i * TAU / 8.0)
		var d3 := DirectionResolver.to_world(d2)
		var score := d3.dot(goal_dir) * 1.2
		for opp in p.match_ctx.opponents_of(p):
			var to_opp := DirectionResolver.flat(opp.global_position - p.global_position)
			var od := to_opp.length()
			if od < 6.0 and od > 0.01:
				var ang := absf(DirectionResolver.signed_angle(d3, to_opp / od))
				if ang < deg_to_rad(50.0):
					score -= (6.0 - od) / 6.0 * 1.8 * (1.0 - ang / deg_to_rad(50.0))
		var ahead := p.global_position + d3 * 6.0
		if absf(ahead.z) > PitchBuilder.HALF_WIDTH - 2.0:
			score -= 1.5
		if score > best_score:
			best_score = score
			best = d2
	return [best, best_score]


# --- without the ball ------------------------------------------------------------

func _defend(p: PlayerController, carrier: PlayerController) -> void:
	var m := p.match_ctx
	var own_goal := m.goal_center(-p.attack_dir)
	var c := carrier.global_position
	var to_goal := DirectionResolver.flat(own_goal - c)
	var carrier_goal_dist := to_goal.length()
	var d_carrier := p.global_position.distance_to(c)

	# Goal-side jockeying: stand between the carrier and our goal, tighter the
	# closer he gets to it.
	var jockey := lerpf(1.4, 2.8, clampf(carrier_goal_dist / 40.0, 0.0, 1.0))
	if carrier.speed < 1.5:
		jockey = 1.0  # he stopped: close him down and challenge
	var target := c + to_goal.normalized() * jockey + DirectionResolver.flat(carrier.velocity) * 0.25
	var beaten := DirectionResolver.flat(c - p.global_position).dot(to_goal) > 0.5

	if d_carrier > 7.0 or beaten:
		mode = Mode.RECOVER
		_sprint = true
	else:
		mode = Mode.DEFEND
		_sprint = d_carrier > 3.5
	_move = _towards(p, target, 0.35)

	var aggression := p.stats.n(&"aggression")
	var ball_exposed := DirectionResolver.flat(p.ball.global_position - c).length() > 0.6 \
		or carrier.state == PlayerController.State.TURN
	if d_carrier < 1.7 and not beaten:
		mode = Mode.PRESS
		var chance := 0.1 + (0.45 * aggression if ball_exposed else 0.0)
		if rng.randf() < chance:
			_press = PlayerIntent.Action.PASS
			_move = _towards(p, p.ball.global_position, 0.0)
	elif beaten and d_carrier < 2.6 and carrier_goal_dist < 28.0 and rng.randf() < 0.25 * aggression:
		_move = _towards(p, p.ball.global_position + DirectionResolver.flat(p.ball.linear_velocity) * 0.2, 0.0)
		_press = PlayerIntent.Action.SHOOT


func _loose_ball(p: PlayerController) -> void:
	var m := p.match_ctx
	var ball := p.ball
	var my_time := _arrival_time(p, ball)
	var their_time := INF
	for opp in m.opponents_of(p):
		their_time = minf(their_time, _arrival_time(opp, ball))
	if my_time <= their_time + 0.25 or m.brain_for(p.team) != null:
		mode = Mode.PRESS
		var t := minf(my_time, 1.5)
		var predicted := ball.global_position + DirectionResolver.flat(ball.linear_velocity) * t * 0.7
		_move = _towards(p, predicted, 0.1)
		_sprint = true
	else:
		# Cover: goal-side of the ball instead of chasing it.
		mode = Mode.COVER
		var own_goal := m.goal_center(-p.attack_dir)
		var from_ball := DirectionResolver.flat(own_goal - ball.global_position).normalized()
		_move = _towards(p, ball.global_position + from_ball * 5.0, 0.8)
		_sprint = p.global_position.distance_to(ball.global_position) > 12.0


func _support(p: PlayerController) -> void:
	mode = Mode.SUPPORT
	var target := p.home_position
	target.x = clampf(p.ball.global_position.x + p.attack_dir * 10.0, -45.0, 45.0)
	_move = _towards(p, target, 1.5)
	_sprint = false


# --- goalkeeper ---------------------------------------------------------------------

func _keeper(p: PlayerController, carrier: PlayerController) -> void:
	mode = Mode.KEEPER
	var m := p.match_ctx
	var ball := p.ball
	var own_goal := m.goal_center(-p.attack_dir)
	_sprint = false
	if carrier == p:
		# Holding: look up, then distribute to the best-placed team-mate.
		_move = Vector2.ZERO
		if p.state_time > KEEPER_HOLD or not ball.held:
			var best := _best_pass(p)
			if best.is_empty():
				_move = Vector2(p.attack_dir, 0.0)
				_release = PlayerIntent.Action.LOB
				_release_charge = 0.75
			else:
				var aim: Vector3 = best.target - p.global_position
				_move = DirectionResolver.to_stick(DirectionResolver.flat(aim)).normalized()
				_release = best.action
				_release_charge = best.charge
		return
	var b := ball.global_position
	var in_box := m.in_penalty_area(b, -p.attack_dir)
	# Loose ball in my box that I reach first: go and claim it.
	if carrier == null and in_box:
		var my_t := _arrival_time(p, ball)
		var their_t := INF
		for o in m.opponents_of(p):
			their_t = minf(their_t, _arrival_time(o, ball))
		if my_t < their_t:
			_move = _towards(p, b, 0.1)
			_sprint = true
			return
	# One-on-one: come out to narrow the angle and block.
	if carrier != null and carrier.team != p.team and in_box and p.global_position.distance_to(b) < 9.0:
		_move = _towards(p, b - DirectionResolver.flat(b - own_goal).normalized() * 1.2, 0.2)
		_sprint = true
		if p.global_position.distance_to(b) < 1.6:
			_press = PlayerIntent.Action.PASS
		return
	# Positioning: on the line between ball and goal centre, further out the
	# closer the ball is.
	var to_ball := DirectionResolver.flat(b - own_goal)
	var out := clampf(to_ball.length() * 0.12, 0.8, 5.5)
	var spot := own_goal + to_ball.normalized() * out
	spot.z = clampf(spot.z, -PitchBuilder.GOAL_HALF_WIDTH, PitchBuilder.GOAL_HALF_WIDTH)
	_move = _towards(p, spot, 0.25)
	_sprint = p.global_position.distance_to(spot) > 4.0


## Every frame: if a shot will cross my line out of my standing reach, dive.
func _keeper_reflex(intent: PlayerIntent, p: PlayerController) -> void:
	var ball := p.ball
	if ball.owner_player != null or not p.can_dive():
		return
	var v := ball.linear_velocity
	var own_goal_x := -p.attack_dir * PitchBuilder.HALF_LENGTH
	if signf(v.x) != signf(own_goal_x) or absf(v.x) < 6.0:
		return
	var t := (p.global_position.x - ball.global_position.x) / v.x
	if t <= 0.0 or t > 0.9:
		return
	var cross := ball.global_position + v * t
	cross.y -= 0.5 * Ball.GRAVITY * t * t
	var lateral := absf(cross.z - p.global_position.z)
	if absf(cross.z) > PitchBuilder.GOAL_HALF_WIDTH + 1.0 or cross.y > 2.7:
		return
	# Reaction: better keepers commit later and more accurately.
	if lateral > 0.7 and lateral < p.dive_reach() and t < lerpf(0.35, 0.6, p.stats.n(&"goalkeeping")):
		intent.dive_target = cross


static func _arrival_time(p: PlayerController, ball: Ball) -> float:
	return p.global_position.distance_to(ball.global_position) / p.sprint_speed()


static func _towards(p: PlayerController, target: Vector3, tolerance: float) -> Vector2:
	var d := DirectionResolver.flat(target - p.global_position)
	if d.length() <= tolerance:
		return Vector2.ZERO
	return DirectionResolver.to_stick(d).normalized()
