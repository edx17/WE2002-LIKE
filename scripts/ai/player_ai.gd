class_name PlayerAI
extends RefCounted
## Off-ball / on-ball brain for one player. It never moves the body directly:
## it fills the same PlayerIntent a pad does, so AI players are bound by the
## same 8/16 directions, acceleration, turn rate and kick imprecision.
##
## Never "WHERE BALL? → RUN". Each decision picks a tactical mode first.

enum Mode { POSITION, DEFEND, MARK, COVER, SUPPORT, RUN, PRESS, RECOVER, ATTACK }

const MODE_NAMES := ["POSITION", "DEFEND", "MARK", "COVER", "SUPPORT", "RUN", "PRESS", "RECOVER", "ATTACK"]

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


func _decide(p: PlayerController) -> void:
	var carrier := p.ball.owner_player as PlayerController
	if carrier == p:
		_attack(p)
	elif carrier != null and carrier.team != p.team:
		_defend(p, carrier)
	elif carrier != null:
		_support(p)
	else:
		_loose_ball(p)


# --- with the ball -------------------------------------------------------------

func _attack(p: PlayerController) -> void:
	mode = Mode.ATTACK
	var m := p.match_ctx
	var goal := m.goal_center(p.attack_dir)
	var to_goal := DirectionResolver.flat(goal - p.global_position)
	var dist := to_goal.length()
	var threat := m.nearest_opponent(p)
	var threat_dist := INF
	if threat != null:
		threat_dist = p.global_position.distance_to(threat.global_position)

	var lane_clear := not m.is_lane_blocked(p, goal, 1.8)
	if dist < 24.0 and (lane_clear or threat_dist < 1.8 or dist < 13.0):
		# Aim at the far post: stick up/down selects the post.
		var post := -signf(p.global_position.z)
		if post == 0.0:
			post = 1.0 if rng.randf() < 0.5 else -1.0
		_move = Vector2(p.attack_dir, post).normalized()
		_release = PlayerIntent.Action.SHOOT
		_release_charge = clampf(0.4 + dist / 45.0 + rng.randf_range(-0.08, 0.08), 0.35, 0.85)
		_sprint = false
		return

	# Dribble: pick the best of the 8 directions (progress vs danger).
	var best := Vector2.ZERO
	var best_score := -INF
	for i in 8:
		var d2 := Vector2.from_angle(i * TAU / 8.0)
		var d3 := DirectionResolver.to_world(d2)
		var score := d3.dot(to_goal / dist) * 1.2
		for opp in m.opponents_of(p):
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
	_move = best
	_sprint = threat_dist > 4.0 or best_score > 0.9


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
	if my_time <= their_time + 0.25:
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
	# Stage 2+: formation slots, width, runs. For now: hold home ahead of the ball.
	mode = Mode.SUPPORT
	var target := p.home_position
	target.x = clampf(p.ball.global_position.x + p.attack_dir * 10.0, -45.0, 45.0)
	_move = _towards(p, target, 1.5)
	_sprint = false


static func _arrival_time(p: PlayerController, ball: Ball) -> float:
	return p.global_position.distance_to(ball.global_position) / p.sprint_speed()


static func _towards(p: PlayerController, target: Vector3, tolerance: float) -> Vector2:
	var d := DirectionResolver.flat(target - p.global_position)
	if d.length() <= tolerance:
		return Vector2.ZERO
	return DirectionResolver.to_stick(d).normalized()
