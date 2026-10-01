extends SceneTree
## "Firmeza" probe: the numbers behind how hard / solid the game feels.
##
##   godot --headless --path . -s tests/firmness_probe.gd
##
## Measures, with the same input a human would give:
##   * kick-off: does the rival take the ball before it is played?
##   * shots vs a real keeper from 12..30 m: goals / saves / wide
##   * passes to a team-mate at 8..28 m and several angles, with the receiver
##     still holding the stick (as a human does right after passing)
##   * movement: time to top speed, speed kept after an 8-way direction change

const DT := 1.0 / 120.0


class ScriptedInput:
	var move := Vector2.ZERO
	var sprint := false
	var release := PlayerIntent.NONE
	var charge := 0.5

	func fill(intent: PlayerIntent, _p: PlayerController, _delta: float) -> void:
		intent.begin_frame()
		intent.move = move
		intent.sprint = sprint
		if release != PlayerIntent.NONE:
			intent.release(release, charge)
			release = PlayerIntent.NONE


var m: MatchController
var out := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	InputSetup.ensure_actions()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or only == "kickoff":
		await _kickoff()
	if only == "" or only == "shots":
		await _shots()
	if only == "" or only == "passes":
		await _passes()
	print(JSON.stringify(out, "  "))
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _new(id: String, seed_value: int) -> MatchController:
	var mc := (load("res://scenes/match/Match.tscn") as PackedScene).instantiate() as MatchController
	mc.match_id = id
	mc.allow_human = false
	root.add_child(mc)
	mc.rng.seed = seed_value
	mc.referee.rng.seed = seed_value
	mc.half_seconds = 100000.0
	return mc


## Keeps the match "playing" whatever happened (goal, ball out).
func _resume() -> void:
	# Bring the ball back in first, or the old position (in the net, out of
	# play) is judged again on the next frame.
	m.ball.place(Vector3(0, Ball.RADIUS, 20))
	await _frames(2)
	m.phase = MatchController.Phase.PLAYING
	m._end_set_piece()
	m.offside.reset()
	for p in m.players:
		p.frozen = false


func _park(except: Array, base_x := 40.0) -> void:
	var i := 0
	for p in m.players:
		if p in except:
			continue
		p.input_source = null
		p.teleport(Vector3(base_x + (i % 4) * 3.0, 0, -30.0 + (i / 4) * 4.0), Vector3.RIGHT)
		i += 1


func _kickoff() -> void:
	var stolen := 0
	var trials := 6
	for t in trials:
		m = _new("stage3_11v11", 100 + t)
		await _frames(2)
		m.kickoff(0)
		var taker := m._kickoff_taker(0)
		var idle := ScriptedInput.new()
		taker.input_source = idle
		var lost := false
		for i in 360:  # 3 s waiting, like a human thinking
			await physics_frame
			var o := m.ball.owner_player as PlayerController
			if o != null and o.team == 1:
				lost = true
				break
			if m.ball.last_touch != null and (m.ball.last_touch as PlayerController).team == 1:
				lost = true
				break
		if lost:
			stolen += 1
		m.queue_free()
		await _frames(1)
	out["kickoff_stolen"] = "%d/%d" % [stolen, trials]


func _shots() -> void:
	m = _new("stage3_11v11", 7)
	await _frames(2)
	var shooter: PlayerController = null
	var keeper: PlayerController = null
	for p in m.players:
		if p.team == 0 and p.role == "CF" and shooter == null:
			shooter = p
		if p.team == 1 and p.is_keeper:
			keeper = p
	var input := ScriptedInput.new()
	var table := {}
	for dist: float in [12.0, 18.0, 25.0, 30.0]:
		var res := {"gol": 0, "atajada": 0, "afuera": 0}
		for t in 12:
			await _resume()
			_park([shooter, keeper], -48.0)
			input.release = PlayerIntent.NONE
			shooter.input_source = input
			keeper.input_source = keeper.ai
			var z: float = [-6.0, 0.0, 6.0][t % 3]
			shooter.teleport(Vector3(PitchBuilder.HALF_LENGTH - dist, 0, z), Vector3.RIGHT)
			keeper.teleport(Vector3(PitchBuilder.HALF_LENGTH - 1.0, 0, 0), Vector3.LEFT)
			m.ball.place(Vector3(PitchBuilder.HALF_LENGTH - dist + 0.55, Ball.RADIUS, z))
			await _frames(1)
			# (the referee may have handed the old ball position to the keeper)
			m.ball.place(Vector3(PitchBuilder.HALF_LENGTH - dist + 0.55, Ball.RADIUS, z))
			input.move = Vector2.ZERO
			keeper.input_source = null
			keeper.teleport(Vector3(PitchBuilder.HALF_LENGTH - 1.0, 0, 30), Vector3.LEFT)
			var sc0: int = m.score[0] + m.score[1]
			for fr in 70:  # the shooter settles the ball (kick cooldown)
				await physics_frame
				if shooter.state == PlayerController.State.SHOOT and OS.get_cmdline_user_args().has("--verbose"):
					print("   SHOOT during wait frame ", fr, " release ", input.release, " queued ", shooter._queued, " has ", shooter.has_ball())
				if m.score[0] + m.score[1] != sc0 and OS.get_cmdline_user_args().has("--verbose"):
					print("   GOAL during wait frame ", fr, " ball ", m.ball.global_position, " last ", m.ball.last_touch, " owner ", m.ball.owner_player)
					sc0 = m.score[0] + m.score[1]
			keeper.input_source = keeper.ai
			keeper.teleport(Vector3(PitchBuilder.HALF_LENGTH - 1.0 - minf(dist * 0.12, 3.0), 0, z * 0.25), Vector3.LEFT)
			await _frames(3)
			if OS.get_cmdline_user_args().has("--verbose") and m.phase != MatchController.Phase.PLAYING:
				print("   STOPPED before shot: ", m._restart, " ", m.hud._message.text)
			var post := 1.0 if t % 2 == 0 else -1.0
			input.move = Vector2(1, post).normalized()
			m.offside.reset()
			input.release = PlayerIntent.Action.SHOOT
			input.charge = clampf(0.35 + dist / 50.0, 0.4, 0.8)
			var goals: int = m.score[0] + m.score[1]
			var outcome := "afuera"
			var dived := false
			var cross := Vector3.ZERO
			var kpos := Vector3.ZERO
			var touched := false
			for i in 300:
				await physics_frame
				dived = dived or keeper.state == PlayerController.State.DIVE
				touched = touched or m.ball.last_touch == keeper
				if cross == Vector3.ZERO and m.ball.global_position.x > keeper.global_position.x:
					cross = m.ball.global_position
					kpos = keeper.global_position
				if m.score[0] + m.score[1] > goals or keeper.has_ball() or m.phase != MatchController.Phase.PLAYING:
					break
			m.ball.place(Vector3(0, Ball.RADIUS, 20))
			if m.score[0] + m.score[1] > goals:
				outcome = "gol"
			elif touched:
				outcome = "atajada"
			input.move = Vector2.ZERO
			res[outcome] += 1
			if OS.get_cmdline_user_args().has("--verbose"):
				print("   end ball ", m.ball.global_position, " phase ", m.phase, " score ", m.score, " restart ", m._restart)
				print("   ", m.last_kick_text, " | keeper ", keeper.global_position, " state ", keeper.state, " ai ", keeper.ai.mode)
				print("shot %dm z%.0f -> %s  ball@keeper %s keeper %s dived %s v %.1f" % [dist, z, outcome, cross, kpos, dived, m.ball.linear_velocity.length()])
		table["%dm" % dist] = res
	out["shots_vs_keeper"] = table
	m.queue_free()
	await _frames(1)


func _passes() -> void:
	m = _new("stage3_11v11", 11)
	await _frames(2)
	var passer: PlayerController = null
	var mate: PlayerController = null
	for p in m.players:
		if p.team == 0 and not p.is_keeper:
			if passer == null:
				passer = p
			elif mate == null:
				mate = p
	var pin := ScriptedInput.new()
	var rin := ScriptedInput.new()
	var ok := 0
	var total := 0
	var fails := []
	for dist: float in [8.0, 14.0, 20.0, 28.0]:
		for ang: float in [0.0, 25.0, 45.0, 70.0, -30.0, -90.0]:
			for charge: float in [0.25, 0.5]:
				await _resume()
				_park([passer, mate])
				passer.input_source = pin
				mate.input_source = rin
				var origin := Vector3(-20, 0, 0)
				passer.teleport(origin, Vector3.RIGHT)
				m.ball.place(origin + Vector3(0.55, Ball.RADIUS, 0))
				var dir := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(ang))
				mate.teleport(origin + dir * dist, -dir)
				pin.move = Vector2.ZERO
				rin.move = Vector2.ZERO
				await _frames(30)
				var stick := DirectionResolver.to_stick(dir).normalized()
				pin.move = stick
				pin.release = PlayerIntent.Action.PASS
				pin.charge = charge
				await _frames(20)
				pin.move = Vector2.ZERO
				# The human keeps holding the direction he passed with.
				rin.move = stick
				var got := false
				for i in 480:
					await physics_frame
					if mate.has_ball():
						got = true
						break
					if m.phase != MatchController.Phase.PLAYING:
						break
				rin.move = Vector2.ZERO
				total += 1
				if got:
					ok += 1
				else:
					if OS.get_cmdline_user_args().has("--verbose"):
						print("fail %d %d: ball %s mate %s owner %s last %s recv %s assist %s" % [dist, ang, m.ball.global_position, mate.global_position, m.ball.owner_player, m.ball.last_touch, m.pass_receiver, mate.receive_assist])
					fails.append("%dm %d° bar %.2f" % [dist, ang, charge])
	out["passes_delivered"] = "%d/%d" % [ok, total]
	out["passes_failed"] = fails
	m.queue_free()
	await _frames(1)
