class_name TeamBrain
extends RefCounted
## The team's collective decisions, refreshed a few times per second:
## where the block sits (shape between defending and attacking, sliding with
## the ball, set by the tactics), and who does what:
##
##   without the ball  one presser (two with a high press, in their half), one
##                     cover behind, a flat back line that moves together
##                     (offside trap), the rest mark goal-side or hold shape
##   with the ball     the nearest team-mates offer support in open space,
##                     forwards and wingers run on the last defender's
##                     shoulder (onside until the pass), full-backs overlap
##   set pieces        fixed positions handed out by SetPieces
##
## PlayerAI asks assignment(p) and only then decides how to move.

enum Mode { POSITION, PRESS, COVER, MARK, SUPPORT, RUN, KEEPER }
const MODE_NAMES := ["POSITION", "PRESS", "COVER", "MARK", "SUPPORT", "RUN", "KEEPER"]
const THINK_EVERY := 0.15
const BACK_LINE := ["CB", "LB", "RB", "SW", "DF", "LWB", "RWB"]
const FULL_BACKS := ["LB", "RB", "LWB", "RWB"]
const RUNNERS := ["CF", "WG", "SS"]

var team := 0
var attack_dir := 1.0
var formation: Formation
var tactics := TeamTactics.new()
var players: Array[PlayerController] = []
## Player -> formation slot. Survives send-offs and substitutions.
var _slots := {}
var match_ctx: MatchController
var shape := 0.5  # 0 defending .. 1 attacking (smoothed)
var in_possession := false
## Progress (team space) of the back line, for tests and the HUD.
var line_progress := 0.2
## Fixed targets while a set piece is being taken (player -> Vector3).
var set_piece_targets := {}

var _assignments := {}
var _timer := 0.0


func _init(m: MatchController, team_index: int, form: Formation) -> void:
	match_ctx = m
	team = team_index
	formation = form


func slot_of(p: PlayerController) -> int:
	return int(_slots.get(p, -1))


func add_player(p: PlayerController, slot: int) -> void:
	players.append(p)
	_slots[p] = slot


func remove_player(p: PlayerController) -> void:
	players.erase(p)
	_slots.erase(p)
	set_piece_targets.erase(p)
	_assignments.erase(p)


## Substitution: the new player takes the old one's slot.
func replace_player(old: PlayerController, new_player: PlayerController) -> void:
	var slot := slot_of(old)
	remove_player(old)
	add_player(new_player, slot)


func role_of(p: PlayerController) -> String:
	return formation.role(slot_of(p))


func is_keeper(p: PlayerController) -> bool:
	return role_of(p) == "GK"


func assignment(p: PlayerController) -> Dictionary:
	if set_piece_targets.has(p):
		return {"mode": Mode.POSITION, "target": set_piece_targets[p]}
	return _assignments.get(p, {"mode": Mode.POSITION, "target": p.home_position})


## Kick-off position of a slot: defensive shape, own half.
func kickoff_position(p: PlayerController) -> Vector3:
	var pt := formation.point(slot_of(p), 0.0)
	return Formation.to_world(minf(pt.x, 0.46), pt.y, attack_dir)


func progress(pos: Vector3) -> float:
	return Formation.progress_of(pos.x, attack_dir)


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
	var ball_prog := progress(ball_pos)
	var outfield: Array[PlayerController] = []
	for p in players:
		if is_keeper(p):
			_assignments[p] = {"mode": Mode.KEEPER, "target": p.global_position}
		else:
			outfield.append(p)
	for p in outfield:
		_assignments[p] = {"mode": Mode.POSITION, "target": _slot_target(p, ball_prog, ball_pos)}
	_hold_the_line(outfield, ball_prog)

	if owner != null and owner.team == team:
		_attacking(owner, outfield, ball_pos)
	else:
		_defending(owner, outfield, ball_pos, ball_prog)


func _slot_target(p: PlayerController, ball_prog: float, ball_pos: Vector3) -> Vector3:
	var pt := formation.point(slot_of(p), shape)
	var shift := lerpf(0.2, 0.45, tactics.compactness)
	var line_bias := (tactics.defensive_line - 0.5) * 0.12 * (1.0 - shape)
	var prog := clampf(pt.x + line_bias + (ball_prog - 0.5) * shift, 0.04, 0.9)
	var spread := lerpf(0.55, lerpf(0.7, 1.0, tactics.width), shape)
	var width := clampf(pt.y * spread + ball_pos.z / PitchBuilder.HALF_WIDTH * 0.3, -0.92, 0.92)
	return Formation.to_world(prog, width, attack_dir)


## The back line moves as one: every defender shares the line's height.
## Never deeper than needed, never behind the ball when it's in our half,
## and (offside trap) it steps up when the ball goes backwards.
func _hold_the_line(outfield: Array[PlayerController], ball_prog: float) -> void:
	var line := INF
	var count := 0
	for p in outfield:
		if role_of(p) in BACK_LINE and not (role_of(p) in FULL_BACKS and shape > 0.6):
			line = minf(line, progress(_assignments[p].target))
			count += 1
	if count == 0:
		return
	# Defending deep in our half: the line can't stay higher than the ball.
	line = minf(line, maxf(ball_prog - 0.06, 0.05))
	if not tactics.offside_trap:
		line -= 0.02
	line_progress = line
	for p in outfield:
		if role_of(p) in BACK_LINE and not (role_of(p) in FULL_BACKS and shape > 0.6):
			var t: Vector3 = _assignments[p].target
			_assignments[p].target = Formation.to_world(line, t.z / PitchBuilder.HALF_WIDTH, attack_dir)


func _defending(owner: PlayerController, outfield: Array[PlayerController], ball_pos: Vector3, ball_prog: float) -> void:
	if outfield.is_empty():
		return
	var by_time := outfield.duplicate()
	by_time.sort_custom(func(a: PlayerController, b: PlayerController) -> bool:
		return _arrival(a, ball_pos) < _arrival(b, ball_pos))
	# Pressing: always in our half; in theirs only as high as the tactics say.
	var engage := ball_prog < 0.5 + tactics.pressing * 0.5 or owner == null
	var pressers := 1
	if tactics.pressing > 0.65 and ball_prog > 0.55 and outfield.size() > 6:
		pressers = 2
	var own_goal := match_ctx.goal_center(-attack_dir)
	var used := 0
	if engage:
		for i in mini(pressers, by_time.size()):
			_assignments[by_time[i]] = {"mode": Mode.PRESS, "target": ball_pos}
			used += 1
	if owner != null and by_time.size() > used:
		var cover: PlayerController = by_time[used]
		var behind := ball_pos + DirectionResolver.flat(own_goal - ball_pos).normalized() * 7.0
		_assignments[cover] = {"mode": Mode.COVER, "target": behind}
	# Others: mark the most dangerous free opponent near their slot (goal-side),
	# defenders without dropping more than 5 m behind the line.
	var marked := {}
	for p in outfield:
		if _assignments[p].mode != Mode.POSITION:
			continue
		var slot: Vector3 = _assignments[p].target
		var best: PlayerController = null
		var best_d := 12.0
		for o in match_ctx.opponents_of(p):
			if marked.has(o) or o == owner or o.is_keeper:
				continue
			var d := o.global_position.distance_to(slot)
			if d < best_d:
				best_d = d
				best = o
		if best != null:
			marked[best] = true
			var target := best.global_position + DirectionResolver.flat(own_goal - best.global_position).normalized() * 1.8
			if role_of(p) in BACK_LINE and progress(target) < line_progress - 0.05:
				target = Formation.to_world(line_progress - 0.05, target.z / PitchBuilder.HALF_WIDTH, attack_dir)
			_assignments[p] = {"mode": Mode.MARK, "target": target, "mark": best}


func _attacking(owner: PlayerController, outfield: Array[PlayerController], ball_pos: Vector3) -> void:
	var others := outfield.filter(func(p: PlayerController) -> bool: return p != owner)
	if others.is_empty():
		return
	# Short support: the closest team-mates offer open angles near the carrier.
	others.sort_custom(func(a: PlayerController, b: PlayerController) -> bool:
		return a.global_position.distance_to(ball_pos) < b.global_position.distance_to(ball_pos))
	var supporters := 2 if others.size() > 5 else 1
	var taken: Array[Vector3] = []
	for i in mini(supporters, others.size()):
		var spot := _support_spot(owner, taken)
		taken.append(spot)
		_assignments[others[i]] = {"mode": Mode.SUPPORT, "target": spot}
	# Runners: forwards and wingers on the last defender's shoulder, onside.
	var line := _offside_line_x()
	var ball_prog := progress(ball_pos)
	for p in others:
		if _assignments[p].mode != Mode.POSITION:
			continue
		var role := role_of(p)
		if role in RUNNERS or (outfield.size() <= 5 and p == _most_advanced(others)):
			if ball_prog > 0.3:
				var tgt: Vector3 = _assignments[p].target
				tgt.x = line - attack_dir * 0.6  # hold onside until the pass
				_assignments[p] = {"mode": Mode.RUN, "target": tgt}
		elif role in FULL_BACKS and ball_prog > 0.5 and signf(ball_pos.z) == signf(_assignments[p].target.z):
			# Overlap down our side.
			var tgt: Vector3 = _assignments[p].target
			tgt.x = ball_pos.x + attack_dir * 8.0
			_assignments[p] = {"mode": Mode.RUN, "target": tgt}


## Best of a ring of candidate spots around the carrier: away from opponents,
## with a clear passing lane, slightly forward, not on top of other supporters.
func _support_spot(owner: PlayerController, taken: Array[Vector3]) -> Vector3:
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
		for t in taken:
			if t.distance_to(spot) < 8.0:
				score -= 5.0
		if score > best_score:
			best_score = score
			best = spot
	return best


func _most_advanced(group: Array) -> PlayerController:
	var best: PlayerController = null
	for p: PlayerController in group:
		if best == null or progress(p.global_position) > progress(best.global_position):
			best = p
	return best


## World x of the opponents' second-last defender (offside line).
func _offside_line_x() -> float:
	return match_ctx.offside.line_x(team)


static func _arrival(p: PlayerController, pos: Vector3) -> float:
	return p.global_position.distance_to(pos) / p.sprint_speed()
