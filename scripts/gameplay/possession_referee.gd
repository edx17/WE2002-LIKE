class_name PossessionReferee
extends RefCounted
## Decides who owns the ball each physics frame: dribbling, 50/50 balls,
## receptions, tackles and slides. The physics engine moves the ball; this
## class decides football.

signal event(text: String)
signal foul(offender: PlayerController, victim: PlayerController)

var ball: Ball
var players: Array[PlayerController] = []
var rng := RandomNumberGenerator.new()

var _cooldowns := {}
var _contest_timer := 0.0


func _init(match_ball: Ball) -> void:
	ball = match_ball


func set_cooldown(p: PlayerController, seconds: float) -> void:
	_cooldowns[p] = seconds


func can_touch(p: PlayerController) -> bool:
	return float(_cooldowns.get(p, 0.0)) <= 0.0 and p.can_play_ball() and not p.frozen


func update(delta: float) -> void:
	for p: PlayerController in _cooldowns.keys():
		_cooldowns[p] = float(_cooldowns[p]) - delta
		if _cooldowns[p] <= 0.0:
			_cooldowns.erase(p)
	_contest_timer -= delta

	var owner := ball.owner_player as PlayerController
	if owner != null:
		if not owner.can_play_ball() or not owner.interaction.dribble(ball):
			ball.owner_player = null
			set_cooldown(owner, 0.25)
		else:
			_contest(owner)
		return
	_free_ball()


func _free_ball() -> void:
	var best: PlayerController = null
	var best_dist := INF
	for p in players:
		if not can_touch(p) or p.state == PlayerController.State.SLIDE:
			continue
		if p.interaction.contact_zone(ball.global_position) == BallInteraction.Zone.NONE:
			continue
		var d := DirectionResolver.flat(ball.global_position - p.global_position).length()
		if d < best_dist:
			best_dist = d
			best = p
	if best == null:
		return
	var outcome := best.interaction.receive(ball)
	if outcome != "control":
		set_cooldown(best, 0.25)
	if outcome == "deflect":
		event.emit("REBOTE EN %s" % BallInteraction.ZONE_NAMES[best.interaction.last_zone])


## Balón dividido: an opponent whose foot is closer to the ball than the
## dribbler's can knock it loose.
func _contest(owner: PlayerController) -> void:
	if _contest_timer > 0.0:
		return
	for p in players:
		if p.team == owner.team or not can_touch(p) or p.state == PlayerController.State.SLIDE:
			continue
		var d_opp := DirectionResolver.flat(ball.global_position - p.global_position).length()
		var d_own := DirectionResolver.flat(ball.global_position - owner.global_position).length()
		if d_opp > 0.6 or d_opp >= d_own:
			continue
		_contest_timer = 0.3
		var att := owner.stats.n(&"control") * 0.5 + owner.stats.n(&"strength") * 0.3 + owner.stats.n(&"balance") * 0.2
		var def := p.stats.n(&"tackling") * 0.5 + p.stats.n(&"strength") * 0.3 + p.stats.n(&"aggression") * 0.2
		if rng.randf() < clampf(0.5 + (def - att) * 0.8, 0.1, 0.9):
			var dir := (DirectionResolver.flat(ball.global_position - p.global_position).normalized() + p.facing).normalized()
			ball.kick(dir * rng.randf_range(2.5, 5.0), Vector3.ZERO, p)
			set_cooldown(owner, 0.3)
			event.emit("BALÓN DIVIDIDO")
		return


## Standing tackle. Returns true if the ball was won.
func resolve_tackle(tackler: PlayerController) -> bool:
	var owner := ball.owner_player as PlayerController
	if owner == null or owner.team == tackler.team:
		return false
	var to_ball := DirectionResolver.flat(ball.global_position - tackler.global_position)
	if to_ball.length() > 1.5 or tackler.facing.dot(to_ball.normalized()) < 0.2:
		event.emit("QUITE AL AIRE")
		return false
	var chance := clampf(0.45 + 0.9 * (tackler.stats.n(&"tackling")
		- 0.5 * (owner.stats.n(&"control") + owner.stats.n(&"balance"))), 0.12, 0.88)
	if rng.randf() < chance:
		var side := tackler.facing.cross(Vector3.UP) * rng.randf_range(-0.4, 0.4)
		ball.kick((tackler.facing + side).normalized() * rng.randf_range(3.0, 6.0), Vector3.ZERO, tackler)
		set_cooldown(owner, 0.4)
		event.emit("QUITE LIMPIO")
		return true
	if rng.randf() < 0.15 * tackler.stats.n(&"aggression"):
		owner.knock_down()
		foul.emit(tackler, owner)
	return false


## Slide tackle contact check, called every frame of the slide.
## Returns true once something has been hit.
func check_slide(slider: PlayerController) -> bool:
	var to_ball := DirectionResolver.flat(ball.global_position - slider.global_position)
	if ball.global_position.y < 0.5 and to_ball.length() < 1.15 and slider.facing.dot(to_ball.normalized()) > 0.0:
		var owner := ball.owner_player as PlayerController
		ball.kick(slider.facing * rng.randf_range(7.0, 11.0) + Vector3.UP * 1.5, Vector3.ZERO, slider)
		if owner != null:
			set_cooldown(owner, 0.4)
		set_cooldown(slider, 0.5)
		event.emit("BARRIDA")
		return true
	for p in players:
		if p.team == slider.team or p.is_grounded_state():
			continue
		if DirectionResolver.flat(p.global_position - slider.global_position).length() < 0.9:
			p.knock_down()
			foul.emit(slider, p)
			return true
	return false
