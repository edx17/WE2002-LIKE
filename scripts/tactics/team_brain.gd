class_name TeamBrain
extends RefCounted
## The team's collective decisions, refreshed a few times per second:
## where the block sits (shape between defending and attacking, sliding
## with the ball) and who does what. Exactly ONE player presses the ball;
## one covers behind him; the rest mark or hold their slot. With the ball,
## one player offers short support and the most advanced one runs in behind.
##
## PlayerAI asks assignment(p) and only then decides how to move.

enum Mode { POSITION, PRESS, COVER, MARK, SUPPORT, RUN, KEEPER }
const MODE_NAMES := ["POSITION", "PRESS", "COVER", "MARK", "SUPPORT", "RUN", "KEEPER"]
const THINK_EVERY := 0.15
## How far the whole block shifts with the ball (team-space units).
const BALL_SHIFT := 0.35

var team := 0
var attack_dir := 1.0
var formation: Formation
var players: Array[PlayerController] = []  # slot order
var match_ctx: MatchController
var shape := 0.5  # 0 defending .. 1 attacking (smoothed)
var in_possession := false

var _assignments := {}
var _timer := 0.0


func _init(m: MatchController, team_index: int, form: Formation) -> void:
	match_ctx = m
	team = team_index
	formation = form


func slot_of(p: PlayerController) -> int:
	return players.find(p)


func is_keeper(p: PlayerController) -> bool:
	return formation.role(slot_of(p)) == "GK"


func assignment(p: PlayerController) -> Dictionary:
	return _assignments.get(p, {"mode": Mode.POSITION, "target": p.home_position})


## Kick-off position of a slot: defensive shape, own half.
func kickoff_position(p: PlayerController) -> Vector3:
	var pt := formation.point(slot_of(p), 0.0)
	return Formation.to_world(minf(pt.x, 0.46), pt.y, attack_dir)


func update(delta: float) -> void:
	_timer -= delta
	var ball := match_ctx.ball
	var owner := ball.owner_player as PlayerController
	var target_shape := shape
	if owner != null:
		in_possession = owner.team == team
		target_shape = 1.0 if in_possession else 0.0
	shape = move_toward(shape, target_shape, delta * 1.2)
	if _timer > 0.0:
		return
	_timer = THINK_EVERY
	_assignments.clear()

	var ball_pos := ball.global_position
	var ball_prog := Formation.progress_of(ball_pos.x, attack_dir)
	var outfield: Array[PlayerController] = []
	for p in players:
		if is_keeper(p):
			_assignments[p] = {"mode": Mode.KEEPER, "target": p.global_position}
		else:
			outfield.append(p)
	for p in outfield:
		_assignments[p] = {"mode": Mode.POSITION, "target": _slot_target(p, ball_prog, ball_pos)}

	if owner != null and owner.team == team:
		_attacking(owner, outfield, ball_pos)
	else:
		_defending(owner, outfield, ball_pos)


func _slot_target(p: PlayerController, ball_prog: float, ball_pos: Vector3) -> Vector3:
	var pt := formation.point(slot_of(p), shape)
	var prog := clampf(pt.x + (ball_prog - 0.5) * BALL_SHIFT, 0.05, 0.9)
	var width := clampf(pt.y * lerpf(0.6, 0.9, shape) + ball_pos.z / PitchBuilder.HALF_WIDTH * 0.3, -0.92, 0.92)
	return Formation.to_world(prog, width, attack_dir)


func _defending(owner: PlayerController, outfield: Array[PlayerController], ball_pos: Vector3) -> void:
	# One presser (fastest to the ball), one cover behind him.
	var by_time := outfield.duplicate()
	by_time.sort_custom(func(a: PlayerController, b: PlayerController) -> bool:
		return _arrival(a, ball_pos) < _arrival(b, ball_pos))
	if by_time.is_empty():
		return
	var presser: PlayerController = by_time[0]
	_assignments[presser] = {"mode": Mode.PRESS, "target": ball_pos}
	var own_goal := match_ctx.goal_center(-attack_dir)
	if by_time.size() > 1 and owner != null:
		var cover: PlayerController = by_time[1]
		var behind := ball_pos + DirectionResolver.flat(own_goal - ball_pos).normalized() * 7.0
		_assignments[cover] = {"mode": Mode.COVER, "target": behind}
	# Others: mark the most dangerous free opponent near their slot.
	var marked := {}
	for p in outfield:
		if _assignments[p].mode != Mode.POSITION:
			continue
		var slot: Vector3 = _assignments[p].target
		var best: PlayerController = null
		var best_d := 14.0
		for o in match_ctx.opponents_of(p):
			if marked.has(o) or o == owner or match_ctx.is_keeper(o):
				continue
			var d := o.global_position.distance_to(slot)
			if d < best_d:
				best_d = d
				best = o
		if best != null:
			marked[best] = true
			var goal_side := DirectionResolver.flat(own_goal - best.global_position).normalized() * 1.8
			_assignments[p] = {"mode": Mode.MARK, "target": best.global_position + goal_side, "mark": best}


func _attacking(owner: PlayerController, outfield: Array[PlayerController], ball_pos: Vector3) -> void:
	var others := outfield.filter(func(p: PlayerController) -> bool: return p != owner)
	if others.is_empty():
		return
	# Short support: the closest team-mate offers an open angle near the carrier.
	others.sort_custom(func(a: PlayerController, b: PlayerController) -> bool:
		return a.global_position.distance_to(ball_pos) < b.global_position.distance_to(ball_pos))
	var supporter: PlayerController = others[0]
	_assignments[supporter] = {"mode": Mode.SUPPORT, "target": _support_spot(owner)}
	# Runner: the most advanced team-mate attacks the space behind the last defender.
	var runner: PlayerController = null
	for p in others:
		if p == supporter:
			continue
		if runner == null or p.global_position.x * attack_dir > runner.global_position.x * attack_dir:
			runner = p
	if runner != null and Formation.progress_of(ball_pos.x, attack_dir) > 0.3:
		var line := _last_defender_x()
		var tgt: Vector3 = _assignments[runner].target
		tgt.x = clampf(line + attack_dir * 5.0, -48.0, 48.0)
		_assignments[runner] = {"mode": Mode.RUN, "target": tgt}


## Best of a ring of candidate spots around the carrier: away from opponents,
## with a clear passing lane, slightly forward.
func _support_spot(owner: PlayerController) -> Vector3:
	var best := owner.global_position
	var best_score := -INF
	for deg: float in [-110.0, -70.0, -35.0, 0.0, 35.0, 70.0, 110.0]:
		var dir := Vector3(attack_dir, 0, 0).rotated(Vector3.UP, deg_to_rad(deg))
		var spot := owner.global_position + dir * 11.0
		if absf(spot.z) > PitchBuilder.HALF_WIDTH - 2.0 or absf(spot.x) > PitchBuilder.HALF_LENGTH - 3.0:
			continue
		var space := 10.0
		for o in match_ctx.opponents_of(owner):
			space = minf(space, o.global_position.distance_to(spot))
		var score := space * 0.3 + dir.x * attack_dir * 1.5
		if match_ctx.is_lane_blocked(owner, spot, 1.5):
			score -= 4.0
		if score > best_score:
			best_score = score
			best = spot
	return best


func _last_defender_x() -> float:
	var deepest := 0.0
	var found := false
	for o in match_ctx.players:
		if o.team == team or match_ctx.is_keeper(o):
			continue
		var x := o.global_position.x * attack_dir
		if not found or x > deepest:
			deepest = x
			found = true
	return (deepest if found else 30.0) * attack_dir


static func _arrival(p: PlayerController, pos: Vector3) -> float:
	return p.global_position.distance_to(pos) / p.sprint_speed()
