class_name OffsideRule
extends RefCounted
## Law 11, the WE way: when a team-mate plays the ball, everyone of his team
## standing in an offside position is noted; if one of them is the next to
## touch it, the flag goes up. An opponent's touch (or an onside team-mate's)
## starts a new phase. Throw-ins, corners and goal kicks are exempt.

var match_ctx: MatchController
var _flagged := {}  # player -> position when the ball was played
var _kicker: PlayerController = null
var _last_touch: Node = null


func _init(m: MatchController) -> void:
	match_ctx = m


func reset() -> void:
	_flagged.clear()
	_kicker = null
	_last_touch = match_ctx.ball.last_touch if match_ctx.ball != null else null


## Progress (attacking team's frame) of the opponents' second-last player.
func second_last_progress(attacking_team: int) -> float:
	var dir := _attack_dir(attacking_team)
	var progs: Array[float] = []
	for p in match_ctx.players:
		if p.team != attacking_team:
			progs.append(Formation.progress_of(p.global_position.x, dir))
	progs.sort()
	if progs.size() >= 2:
		return progs[progs.size() - 2]
	return 1.0 if progs.is_empty() else progs[0]


## World x an attacker must stay behind to be onside (never inside his own half).
func line_x(attacking_team: int) -> float:
	var dir := _attack_dir(attacking_team)
	var prog := maxf(second_last_progress(attacking_team), 0.5)
	return (prog - 0.5) * 2.0 * PitchBuilder.HALF_LENGTH * dir


func is_offside_position(p: PlayerController) -> bool:
	var dir := p.attack_dir
	var prog := Formation.progress_of(p.global_position.x, dir)
	var ball_prog := Formation.progress_of(match_ctx.ball.global_position.x, dir)
	return prog > 0.5 and prog > ball_prog and prog > second_last_progress(p.team) + 0.004


## A player of `kicker`'s team just played the ball.
func on_kick(kicker: PlayerController) -> void:
	_flagged.clear()
	_kicker = kicker
	_last_touch = kicker
	for mate in match_ctx.teammates_of(kicker):
		if is_offside_position(mate):
			_flagged[mate] = mate.global_position


## Call every frame. Returns the offending player when the flag goes up.
func update() -> Dictionary:
	var touch := match_ctx.ball.last_touch
	if touch == _last_touch:
		return {}
	_last_touch = touch
	if _kicker == null or touch == null:
		return {}
	if _flagged.has(touch):
		var out := {"player": touch, "spot": _flagged[touch]}
		reset()
		return out
	# Anyone else touched it: new phase.
	_flagged.clear()
	_kicker = null
	return {}


func _attack_dir(team: int) -> float:
	for p in match_ctx.players:
		if p.team == team:
			return p.attack_dir
	return 1.0 if team == 0 else -1.0
