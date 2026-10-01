class_name SetPieces
extends RefCounted
## Positions for dead-ball situations, held until the taker plays the ball:
##
##   CÓRNER      four attackers attack the box (near post, far post, penalty
##               spot, edge), each marked goal-side; keeper on his line
##   TIRO LIBRE  within ~32 m of goal: a wall of 3-4 at 9.15 m on the line
##               ball -> goal
##
## Distances: 9.15 m for free kicks and corners, 3 m for throw-ins.

const WALL_DISTANCE := 9.15


static func min_distance(kind: String) -> float:
	if kind == "LATERAL":
		return 3.0
	return 12.0 if kind == "PENAL" else WALL_DISTANCE


static func arrange(m: MatchController, kind: String, team: int, spot: Vector3, taker: PlayerController) -> void:
	for brain: TeamBrain in m.brains:
		if brain != null:
			brain.set_piece_targets.clear()
	match kind:
		"CÓRNER":
			_corner(m, team, spot, taker)
		"TIRO LIBRE":
			_free_kick(m, team, spot)
		"PENAL":
			_penalty(m, team, spot, taker)


static func _corner(m: MatchController, team: int, spot: Vector3, taker: PlayerController) -> void:
	var att := m.brain_for(team)
	var defn := m.brain_for(1 - team)
	if att == null or defn == null:
		return
	var a := att.attack_dir
	var gx := a * PitchBuilder.HALF_LENGTH
	var side := signf(spot.z)
	var targets: Array[Vector3] = [
		Vector3(gx - a * 4.0, 0, side * 2.5),     # near post
		Vector3(gx - a * 5.5, 0, -side * 3.5),    # far post
		Vector3(gx - a * 10.5, 0, side * 0.5),    # penalty spot
		Vector3(gx - a * 8.0, 0, -side * 8.0),    # back of the box
		Vector3(gx - a * 18.5, 0, 0.0),           # edge, for the knock-down
	]
	# Best headers go into the box.
	var candidates := att.players.filter(func(p: PlayerController) -> bool:
		return p != taker and not p.is_keeper)
	candidates.sort_custom(func(x: PlayerController, y: PlayerController) -> bool:
		return x.stats.heading > y.stats.heading)
	var attackers: Array[PlayerController] = []
	for i in mini(targets.size(), candidates.size()):
		var p: PlayerController = candidates[i]
		att.set_piece_targets[p] = targets[i]
		p.teleport(targets[i], Vector3(a, 0, 0))
		attackers.append(p)
	# Defenders: one on each attacker in the box, goal-side; keeper on the line.
	var free := defn.players.filter(func(p: PlayerController) -> bool: return not p.is_keeper)
	for target_att in attackers.slice(0, 4):
		if free.is_empty():
			break
		free.sort_custom(func(x: PlayerController, y: PlayerController) -> bool:
			return x.global_position.distance_to(target_att.global_position) < y.global_position.distance_to(target_att.global_position))
		var d: PlayerController = free.pop_front()
		var pos: Vector3 = (target_att as PlayerController).global_position + Vector3(a, 0, 0) * 1.0
		defn.set_piece_targets[d] = pos
		d.teleport(pos, Vector3(-a, 0, 0))
	for p in defn.players:
		if p.is_keeper:
			var line := Vector3(gx - a * 0.6, 0, side * 1.0)
			defn.set_piece_targets[p] = line
			p.teleport(line, Vector3(-a, 0, 0))


## Everyone except taker and keeper outside the box and behind the ball;
## keeper on his line. Nobody moves until the kick.
static func _penalty(m: MatchController, team: int, spot: Vector3, taker: PlayerController) -> void:
	var a := signf(spot.x)
	var gx := a * PitchBuilder.HALF_LENGTH
	var i := 0
	for p in m.players:
		var brain := m.brain_for(p.team)
		if p == taker or brain == null:
			continue
		var pos: Vector3
		if p.is_keeper and p.team != team:
			pos = Vector3(gx - a * 0.3, 0, 0)
		elif p.is_keeper:
			pos = brain.kickoff_position(p)
		else:
			# Arc of players just outside the area, behind the penalty spot.
			var z := (i % 10 - 4.5) * 3.2
			pos = Vector3(gx - a * (19.5 + (i / 10) * 2.0), 0, z)
			i += 1
		brain.set_piece_targets[p] = pos
		p.teleport(pos, Vector3(a, 0, 0) if p.team == team else Vector3(-a, 0, 0))


static func _free_kick(m: MatchController, team: int, spot: Vector3) -> void:
	var defn := m.brain_for(1 - team)
	if defn == null:
		return
	var goal := m.goal_center(-defn.attack_dir)
	var to_goal := DirectionResolver.flat(goal - spot)
	if to_goal.length() > 32.0:
		return
	var n := 4 if to_goal.length() < 24.0 else 3
	var centre := spot + to_goal.normalized() * WALL_DISTANCE
	var across := to_goal.normalized().cross(Vector3.UP)
	var free := defn.players.filter(func(p: PlayerController) -> bool: return not p.is_keeper)
	free.sort_custom(func(x: PlayerController, y: PlayerController) -> bool:
		return x.global_position.distance_to(centre) < y.global_position.distance_to(centre))
	for i in mini(n, free.size()):
		var p: PlayerController = free[i]
		var pos := centre + across * ((i - (n - 1) * 0.5) * 0.65)
		defn.set_piece_targets[p] = pos
		p.teleport(pos, -to_goal.normalized())
