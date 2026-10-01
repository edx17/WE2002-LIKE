extends SceneTree
## Headless test suite:
##   godot --headless --path . -s tests/test_runner.gd
## Unit tests for the pure gameplay math plus physics simulations that check
## the solver's promises against the real engine.

const MATCH_SCENE := preload("res://scenes/match/Match.tscn")

var _failures := 0
var _checks := 0


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


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	InputSetup.ensure_actions()
	_test_direction_resolver()
	_test_contact_zones()
	_test_kick_formulas()
	_test_data()
	await _test_ground_pass_distance()
	await _test_lob_distance()
	await _test_shot_scores()
	await _test_dribble_keeps_ball()
	await _test_human_shot_flow()
	await _test_generated_model()
	await _test_ai_match_soak()
	await _test_5v5_soak()
	await _test_player_switch()
	await _test_offside()
	await _test_set_pieces()
	await _test_11v11_soak()
	await _test_match_time()
	await _test_fouls_and_cards()
	await _test_penalty()
	await _test_throw_in()
	await _test_substitutions()
	await _test_referee_and_menu()
	print("\n%d comprobaciones, %d fallos" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_failures += 1
		printerr("  FAIL ", what)


# --- unit ------------------------------------------------------------------------

func _test_direction_resolver() -> void:
	print("DirectionResolver")
	check(DirectionResolver.quantize(Vector2(0.1, 0.1), 8) == Vector2.ZERO, "deadzone devuelve cero")
	check(DirectionResolver.quantize(Vector2(0.9, 0.3), 8).is_equal_approx(Vector2.RIGHT), "8 dir: casi derecha → derecha")
	check(DirectionResolver.quantize(Vector2(0.7, -0.6), 8).is_equal_approx(Vector2(1, -1).normalized()), "8 dir: diagonal")
	check(DirectionResolver.quantize(Vector2(0.9, 0.3), 16).is_equal_approx(Vector2.from_angle(TAU / 16.0)), "16 dir: 22.5°")
	var seen := {}
	for i in 360:
		seen[DirectionResolver.index_of(DirectionResolver.quantize(Vector2.from_angle(deg_to_rad(i)), 8), 8)] = true
	check(seen.size() == 8, "8 dir produce exactamente 8 direcciones")
	check(DirectionResolver.to_world(Vector2.UP) == Vector3(0, 0, -1), "arriba en pantalla = -Z (lejos de la cámara)")
	check(DirectionResolver.signed_angle(Vector3.RIGHT, Vector3(0, 0, -1)) > 0.0, "giro positivo = izquierda")


func _test_contact_zones() -> void:
	print("BallInteraction")
	check(BallInteraction.zone_for_height(0.11) == BallInteraction.Zone.FOOT, "pelota al piso → PIE")
	check(BallInteraction.zone_for_height(0.7) == BallInteraction.Zone.THIGH, "0.7 m → MUSLO")
	check(BallInteraction.zone_for_height(1.2) == BallInteraction.Zone.CHEST, "1.2 m → PECHO")
	check(BallInteraction.zone_for_height(1.8) == BallInteraction.Zone.HEAD, "1.8 m → CABEZA")
	check(BallInteraction.zone_for_height(2.5) == BallInteraction.Zone.NONE, "2.5 m → fuera de alcance")
	var slow := BallInteraction.receive_quality(BallInteraction.Zone.FOOT, 5.0, 0.9, 0.9)
	var fast := BallInteraction.receive_quality(BallInteraction.Zone.FOOT, 25.0, 0.9, 0.9)
	var head := BallInteraction.receive_quality(BallInteraction.Zone.HEAD, 5.0, 0.9, 0.9)
	check(slow > fast, "pelota rápida es más difícil de controlar")
	check(slow > head, "controlar con el pie es más fácil que con la cabeza")


func _test_kick_formulas() -> void:
	print("KickSolver")
	var s := PlayerStats.new()
	var calm := KickSolver.accuracy(0.8, 0.0, 0.0, false, s)
	check(KickSolver.accuracy(0.8, 1.0, 0.0, false, s) < calm, "la presión baja la precisión")
	check(KickSolver.accuracy(0.8, 0.0, 1.0, false, s) < calm, "correr baja la precisión")
	check(KickSolver.accuracy(0.8, 0.0, 0.0, true, s) < calm, "pie malo baja la precisión")
	check(KickSolver.final_power(20.0, 1.0, 0.7, 1.0) < KickSolver.final_power(20.0, 1.0, 1.0, 1.0), "desequilibrio baja la potencia")
	check(KickSolver.final_power(20.0, 1.0, 1.0, 0.3) < KickSolver.final_power(20.0, 1.0, 1.0, 1.0), "mal contacto baja la potencia")
	check(KickSolver.ground_launch_speed(20.0, 5.0) > 5.0, "velocidad inicial > velocidad de llegada")
	check(KickSolver.launch_angle(25.0, 18.0, 1.5) > 0.0, "ángulo de remate alcanzable")
	check(KickSolver.launch_angle(5.0, 40.0, 1.0) < 0.0, "remate imposible detectado")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var req := KickSolver.KickRequest.new()
	req.type = KickSolver.KickType.SHOT
	req.origin = Vector3(30, 0.11, 0)
	req.target = Vector3(52.5, 0, 0)
	req.power = 0.6
	var good := KickSolver.solve(req, rng)
	req.contact_quality = 0.3
	var bad := KickSolver.solve(req, rng)
	check(bad.mishit and not good.mishit, "contacto 0.3 = le pegó mal")
	check(bad.velocity.length() < good.velocity.length(), "mal contacto sale más flojo")


func _test_generated_model() -> void:
	print("Pipeline de assets: modelo generado + AnimationTree")
	var m := _new_match("stage0_solo")
	await _frames(2)
	var p := m.players[0]
	check(p.get_node_or_null("Visual/Model") != null, "PLAYER_001 (GLB generado) reemplaza a la cápsula")
	var tree := p.get_node_or_null("AnimationTree") as AnimationTree
	check(tree != null and p.animation_selector.driver is AnimationTreeDriver, "AnimationTree construido y conectado")
	var shirt_ok := false
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var o := (mi as MeshInstance3D).get_surface_override_material(i) as StandardMaterial3D
			shirt_ok = shirt_ok or (o != null and o.albedo_texture != null)
	check(shirt_ok, "la camiseta del equipo se aplica como textura sobre el modelo")
	var short_shirt := p.find_child("Shirt_Short", true, false) as Node3D
	var long_shirt := p.find_child("Shirt_Long", true, false) as Node3D
	check(short_shirt != null and short_shirt.visible and long_shirt != null and not long_shirt.visible,
		"kit de manga corta: se ve Shirt_Short y no Shirt_Long")
	var gk: Dictionary = DataLoader.load_json("kits/gk_pink.json")
	var plain := KitTexture.build(gk, 0).get_image()
	var numbered := KitTexture.build(gk, 1).get_image()
	var w := numbered.get_width()
	check(plain.get_pixel(w / 50, numbered.get_height() / 2) != numbered.get_pixel(w / 50, numbered.get_height() / 2),
		"el dorsal se imprime en la espalda de la camiseta")
	check(is_equal_approx(PlayerController.SHOT_WINDUP, AnimationTimings.contact("SHOOT", -1.0)),
		"la ventana de remate sale del mismo JSON que el clip")
	var input := ScriptedInput.new()
	p.input_source = input
	p.teleport(Vector3(20, 0, 0), Vector3.RIGHT)
	m.ball.place(Vector3(20.55, Ball.RADIUS, 0))
	await _frames(30)
	input.move = Vector2.RIGHT
	input.sprint = true
	await _frames(120)
	var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var blend := float(tree.get("parameters/Locomotion/blend_position"))
	check(playback.get_current_node() == &"Locomotion" and blend > 0.8, "sprint → Locomotion con blend %.2f" % blend)
	input.release = PlayerIntent.Action.SHOOT
	var saw_shoot := false
	for i in 30:
		await physics_frame
		saw_shoot = saw_shoot or playback.get_current_node() == &"SHOOT" or playback.get_travel_path().has(&"SHOOT")
	check(saw_shoot, "el gameplay dispara el clip SHOOT")
	m.queue_free()
	await _frames(1)


func _test_data() -> void:
	print("Datos")
	var p := DataLoader.load_player("atacante_01")
	check(p.speed == 83 and p.control == 91 and p.id == "atacante_01", "jugador cargado desde JSON")
	check(DataLoader.load_team("team_a").get("short") == "CAP", "equipo cargado desde JSON")
	check((DataLoader.load_match("stage1_1v1").get("teams", []) as Array).size() == 2, "partido 1v1 cargado")


# --- simulation --------------------------------------------------------------------

func _new_match(id: String) -> MatchController:
	var m := MATCH_SCENE.instantiate() as MatchController
	m.match_id = id
	m.allow_human = false
	root.add_child(m)
	m.rng.seed = 1234
	m.referee.rng.seed = 1234
	return m


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Park every player far away so the ball flies undisturbed.
func _clear_players(m: MatchController) -> void:
	for p in m.players:
		p.input_source = null
		p.teleport(Vector3(-40, 0, -30), Vector3.RIGHT)


func _test_ground_pass_distance() -> void:
	print("Simulación: pase a ras")
	var m := _new_match("stage0_solo")
	await _frames(2)
	_clear_players(m)
	for dist: float in [12.0, 25.0]:
		var arrive := 5.0
		m.ball.place(Vector3(-20, Ball.RADIUS, 20))
		await _frames(2)
		m.ball.kick(Vector3.RIGHT * KickSolver.ground_launch_speed(dist, arrive))
		var start := m.ball.global_position.x
		var speed_at := -1.0
		for i in 600:
			await physics_frame
			if m.ball.global_position.x - start >= dist:
				speed_at = m.ball.linear_velocity.length()
				break
		check(absf(speed_at - arrive) < 1.0, "pase de %d m llega a %.1f m/s (esperado %.1f)" % [dist, speed_at, arrive])
	m.queue_free()
	await _frames(1)


func _test_lob_distance() -> void:
	print("Simulación: globo")
	var m := _new_match("stage0_solo")
	await _frames(2)
	_clear_players(m)
	var rng := RandomNumberGenerator.new()
	for dist: float in [20.0, 40.0]:
		var req := KickSolver.KickRequest.new()
		req.type = KickSolver.KickType.LOB_PASS
		req.origin = Vector3(-30, Ball.RADIUS, 20)
		req.target = req.origin + Vector3.RIGHT * dist
		req.power = 0.5
		req.stats.passing = 99
		var res := KickSolver.solve(req, rng)
		m.ball.place(req.origin)
		await _frames(2)
		m.ball.kick(res.velocity, res.spin)
		var landed := -1.0
		await _frames(10)
		for i in 900:
			await physics_frame
			if m.ball.global_position.y < Ball.RADIUS + 0.05:
				landed = m.ball.global_position.x - req.origin.x
				break
		check(absf(landed - dist) < dist * 0.12, "globo de %d m cae a %.1f m" % [dist, landed])
	m.queue_free()
	await _frames(1)


func _test_shot_scores() -> void:
	print("Simulación: remate")
	var m := _new_match("stage0_solo")
	await _frames(2)
	_clear_players(m)
	var req := KickSolver.KickRequest.new()
	req.type = KickSolver.KickType.SHOT
	req.origin = Vector3(36, Ball.RADIUS, 4)
	req.target = Vector3(52.5, 0, 1.5)
	req.power = 0.55
	req.stats.shooting = 99
	var res := KickSolver.solve(req, m.rng)
	m.ball.place(req.origin)
	await _frames(2)
	m.ball.kick(res.velocity, res.spin)
	var max_h := 0.0
	for i in 240:
		await physics_frame
		max_h = maxf(max_h, m.ball.global_position.y)
		if m.score[0] > 0:
			break
	check(m.score[0] == 1, "remate desde 16 m con potencia media es gol (altura máx %.2f m)" % max_h)

	req.power = 1.0
	res = KickSolver.solve(req, m.rng)
	await _frames(400)  # wait for the kickoff restart
	_clear_players(m)
	m.ball.place(req.origin)
	await _frames(2)
	m.ball.kick(res.velocity, res.spin)
	var crossed_height := -1.0
	for i in 240:
		await physics_frame
		if m.ball.global_position.x > PitchBuilder.HALF_LENGTH:
			crossed_height = m.ball.global_position.y
			break
	check(crossed_height > PitchBuilder.GOAL_HEIGHT, "potencia al máximo se va por arriba (%.2f m)" % crossed_height)
	m.queue_free()
	await _frames(1)


func _test_dribble_keeps_ball() -> void:
	print("Simulación: conducción")
	var m := _new_match("stage0_solo")
	await _frames(2)
	var p := m.players[0]
	var input := ScriptedInput.new()
	p.input_source = input
	await _frames(30)
	check(p.has_ball(), "el jugador arranca con la pelota en el saque")
	input.move = Vector2.RIGHT
	input.sprint = true
	var max_gap := 0.0
	for i in 240:
		await physics_frame
		max_gap = maxf(max_gap, DirectionResolver.flat(m.ball.global_position - p.global_position).length())
	check(p.has_ball(), "mantiene la pelota tras 2 s de sprint")
	check(p.speed > p.jog_speed(), "sprint con pelota supera el trote (%.1f m/s)" % p.speed)
	check(max_gap < BallInteraction.LOSE_DISTANCE, "la pelota nunca se escapa (máx %.2f m)" % max_gap)
	var desc := str(p.animation_selector.current)
	check(desc.begins_with("SPRINT_FORWARD") and desc.contains("BALL_CONTROL"), "animación elegida: %s" % desc)
	# Hard 180°: TURN state, still in possession afterwards.
	input.move = Vector2.LEFT
	var turned := false
	for i in 90:
		await physics_frame
		turned = turned or p.state == PlayerController.State.TURN
	check(turned, "giro de 180° a velocidad pasa por TURN")
	check(p.facing.x < -0.9, "terminó mirando para el otro lado")
	m.queue_free()
	await _frames(1)


func _test_human_shot_flow() -> void:
	print("Simulación: conducir y rematar con la misma entrada que un humano")
	var m := _new_match("stage0_solo")
	await _frames(2)
	var p := m.players[0]
	var input := ScriptedInput.new()
	p.input_source = input
	p.teleport(Vector3(28, 0, 0), Vector3.RIGHT)
	m.ball.place(Vector3(28.55, Ball.RADIUS, 0))
	await _frames(20)
	input.move = Vector2.RIGHT
	await _frames(120)
	check(p.has_ball(), "conduce hacia el arco")
	input.move = Vector2(1, -1)
	input.release = PlayerIntent.Action.SHOOT
	input.charge = 0.5
	var goal := false
	for i in 300:
		await physics_frame
		if m.score[0] > 0:
			goal = true
			break
	check(p.last_kick_type == KickSolver.KickType.SHOT, "se ejecutó un REMATE")
	check(goal, "el remate terminó en gol")
	m.queue_free()
	await _frames(1)


func _test_ai_match_soak() -> void:
	print("Simulación: 1v1 IA contra IA, 90 s")
	var m := _new_match("stage1_1v1")
	var restarts := []
	m.restarted.connect(func(kind: String) -> void: restarts.append(kind))
	var owners := {}
	var sane := true
	for i in 120 * 90:
		await physics_frame
		var b := m.ball.global_position
		if not b.is_finite() or absf(b.x) > 90.0 or absf(b.z) > 70.0 or b.y < -1.0:
			sane = false
			break
		if m.ball.owner_player != null:
			owners[(m.ball.owner_player as PlayerController).team] = true
	check(sane, "la pelota se mantiene en el mundo")
	check(owners.size() == 2, "ambos equipos tuvieron la pelota")
	print("       goles %d-%d, reanudaciones: %s" % [m.score[0], m.score[1], restarts])
	check(m.score[0] + m.score[1] + restarts.size() > 1, "el partido fluye (goles/reanudaciones)")
	m.queue_free()
	await _frames(1)


func _test_5v5_soak() -> void:
	print("Simulación: 5v5 IA contra IA, 120 s (comportamiento de equipo)")
	var m := _new_match("stage2_5v5")
	var swarm := 0.0
	var spacing := 0.0
	var keeper_wander := 0
	var frames := 120 * 120
	for i in frames:
		await physics_frame
		var b := m.ball.global_position
		for p in m.players:
			if not p.is_keeper and p.global_position.distance_to(b) < 4.0:
				swarm += 1.0
			if p.is_keeper and absf(p.global_position.x + p.attack_dir * PitchBuilder.HALF_LENGTH) > 18.0:
				keeper_wander += 1
		var pts: Array[Vector3] = []
		for p in m.players:
			if p.team == 0 and not p.is_keeper:
				pts.append(p.global_position)
		var sum := 0.0
		for a in pts.size():
			for c in range(a + 1, pts.size()):
				sum += pts[a].distance_to(pts[c])
		spacing += sum / 6.0
	print("       goles %d-%d, %s" % [m.score[0], m.score[1], m.stats])
	check(swarm / frames < 3.0, "no hay enjambre: %.1f jugadores de campo a menos de 4 m de la pelota" % (swarm / frames))
	check(spacing / frames > 12.0, "el equipo mantiene la forma: %.1f m entre compañeros" % (spacing / frames))
	check(keeper_wander == 0, "los arqueros no abandonan su zona")
	check(m.stats.passes_completed >= 15, "se completan pases entre compañeros (%d de %d)" % [m.stats.passes_completed, m.stats.passes])
	check(m.stats.shots >= 3, "hay remates (%d)" % m.stats.shots)
	m.queue_free()
	await _frames(1)


func _test_player_switch() -> void:
	print("Cambio de jugador")
	var m := MATCH_SCENE.instantiate() as MatchController
	m.match_id = "stage2_5v5"
	root.add_child(m)
	await _frames(2)
	var first := m.human
	check(first != null and not first.is_keeper and first.input_source is HumanInput, "el humano controla a un jugador de campo")
	m.switch_to_nearest()
	check(m.human != null and m.human.input_source is HumanInput and first.input_source is PlayerAI,
		"cambiar de jugador mueve el control y devuelve la IA al anterior")
	# A pass to a team-mate hands the pad to the receiver.
	var passer := m.human
	var mate: PlayerController = null
	for p in m.teammates_of(passer):
		if not p.is_keeper:
			mate = p
			break
	m.rng.seed = 5
	# Everyone else stands still, out of the way: only the pass is under test.
	for o in m.players:
		if o != passer:
			o.input_source = null
			o.teleport(Vector3(o.global_position.x, 0, 25.0 if o.team == 1 else -25.0), Vector3.RIGHT)
	passer.teleport(Vector3(-5, 0, 0), Vector3.RIGHT)
	mate.teleport(Vector3(8, 0, 0), Vector3.LEFT)
	m.ball.place(Vector3(-4.45, Ball.RADIUS, 0))
	var input := ScriptedInput.new()
	passer.input_source = input
	await _frames(20)
	input.move = Vector2.RIGHT
	input.charge = 0.4
	input.release = PlayerIntent.Action.PASS
	await _frames(40)  # windup + contact
	check(m.human == mate, "al pasar, el control pasa al receptor (%s → %s, controla %s, patada %d)" % [
		passer.name, mate.name, m.human.name, passer.last_kick_type])
	m.queue_free()
	await _frames(1)


## Freezes everyone and lays out a simple attack: passer with the ball at
## x=10, defenders on a line at x=20, receiver at `receiver_x`.
func _offside_scenario(receiver_x: float) -> Dictionary:
	var m := _new_match("stage3_11v11")
	await _frames(2)
	for p in m.players:
		p.input_source = null
	var attackers := m.players.filter(func(p: PlayerController) -> bool: return p.team == 0 and not p.is_keeper)
	var defenders := m.players.filter(func(p: PlayerController) -> bool: return p.team == 1 and not p.is_keeper)
	for i in defenders.size():
		(defenders[i] as PlayerController).teleport(Vector3(20, 0, -30 + i * 6.0), Vector3.LEFT)
	for p in m.players:
		if p.is_keeper:
			p.teleport(Vector3(50.0 * p.attack_dir * -1.0, 0, 0), Vector3.RIGHT * p.attack_dir)
	for i in attackers.size():
		(attackers[i] as PlayerController).teleport(Vector3(-20, 0, -30 + i * 6.0), Vector3.RIGHT)
	var passer: PlayerController = attackers[0]
	var receiver: PlayerController = attackers[1]
	passer.teleport(Vector3(10, 0, 3), Vector3.RIGHT)
	receiver.teleport(Vector3(receiver_x, 0, 3), Vector3.LEFT)
	m.ball.place(Vector3(10.55, Ball.RADIUS, 3))
	var input := ScriptedInput.new()
	passer.input_source = input
	await _frames(20)
	m.offside.reset()
	input.move = Vector2.RIGHT
	input.charge = 0.5
	input.release = PlayerIntent.Action.PASS
	var restarts: Array = []
	m.restarted.connect(func(k: String) -> void: restarts.append([k, m.set_piece.get("team", -1)]))
	var stopped := false
	for i in 120 * 5:
		await physics_frame
		stopped = stopped or m.phase == MatchController.Phase.STOPPED
		if receiver.has_ball() or not restarts.is_empty():
			break
	if stopped:
		await _frames(120 * 2)  # the free kick is taken after the pause
	return {"m": m, "receiver": receiver, "restarts": restarts, "stopped": stopped}


func _test_offside() -> void:
	print("Fuera de juego")
	var r := await _offside_scenario(30.0)
	var restarts: Array = r.restarts
	check(r.stopped and not restarts.is_empty() and restarts[0][0] == "TIRO LIBRE" and restarts[0][1] == 1,
		"pase a un jugador adelantado: fuera de juego y tiro libre para el rival")
	(r.m as MatchController).queue_free()
	await _frames(1)
	r = await _offside_scenario(15.0)
	check(not r.stopped and (r.receiver as PlayerController).has_ball(), "habilitado detrás de la línea: sigue el juego")
	(r.m as MatchController).queue_free()
	await _frames(1)


func _test_set_pieces() -> void:
	print("Pelota parada")
	var m := _new_match("stage3_11v11")
	await _frames(2)
	for p in m.players:
		p.input_source = null
	m._restart_at(0, Vector3(52.0, 0, 33.5), "CÓRNER")
	var in_box := 0
	var marked := 0
	for p in m.players:
		if p.team == 0 and m.in_penalty_area(p.global_position, 1.0):
			in_box += 1
			for d in m.opponents_of(p):
				if not d.is_keeper and d.global_position.distance_to(p.global_position) < 2.0:
					marked += 1
					break
	check(in_box >= 4, "córner: %d atacantes en el área" % in_box)
	check(marked >= 4, "córner: %d de ellos marcados" % marked)
	var fk := Vector3(30.5, 0, 3.0)  # ~22 m from goal: four-man wall
	m._restart_at(0, fk, "TIRO LIBRE")
	var wall := 0
	for p in m.players:
		if p.team == 1 and not p.is_keeper:
			var d := p.global_position.distance_to(fk)
			if absf(d - SetPieces.WALL_DISTANCE) < 0.6:
				wall += 1
	check(wall >= 4, "tiro libre a 22 m: barrera de %d a 9.15 m" % wall)
	var too_close := 0
	for p in m.players:
		if p.team == 1 and p.global_position.distance_to(fk) < SetPieces.WALL_DISTANCE - 0.3:
			too_close += 1
	check(too_close == 0, "ningún rival a menos de 9.15 m")
	m.queue_free()
	await _frames(1)


func _test_11v11_soak() -> void:
	print("Simulación: 11v11 IA contra IA, 90 s")
	var m := _new_match("stage3_11v11")
	var swarm := 0.0
	var spread := 0.0
	var samples := 0
	var frames := 120 * 90
	for i in frames:
		await physics_frame
		var b := m.ball.global_position
		for p in m.players:
			if not p.is_keeper and p.global_position.distance_to(b) < 4.0:
				swarm += 1.0
		var brain := m.brain_for(1)
		if brain.shape < 0.3:
			var xs: Array[float] = []
			for p in brain.players:
				if brain.role_of(p) in ["CB", "LB", "RB"] and not p.is_grounded_state():
					xs.append(p.global_position.x)
			xs.sort()
			spread += xs[xs.size() - 1] - xs[0]
			samples += 1
	print("       goles %d-%d, %s" % [m.score[0], m.score[1], m.stats])
	check(swarm / frames < 3.5, "11v11 sin enjambre: %.1f jugadores cerca de la pelota" % (swarm / frames))
	check(samples > 0 and spread / samples < 10.0, "línea de 4 en bloque: %.1f m entre el más adelantado y el más atrasado" % (spread / maxf(samples, 1)))
	check(m.stats.passes_completed >= 20, "11v11: %d pases completados de %d" % [m.stats.passes_completed, m.stats.passes])
	m.queue_free()
	await _frames(1)


func _frozen_match(id: String) -> MatchController:
	var m := _new_match(id)
	await _frames(2)
	for p in m.players:
		p.input_source = null
	return m


func _test_match_time() -> void:
	print("Tiempo de juego")
	var m := _new_match("stage4_partido")
	await _frames(2)
	m.half_seconds = 1.5
	var d0 := m.players[0].attack_dir
	var p0 := m.players[0]
	for i in 120 * 6:
		await physics_frame
		if m.half == 2 and m.phase == MatchController.Phase.PLAYING:
			break
	check(m.half == 2 and p0.attack_dir == -d0 and m.brain_for(0).attack_dir == -d0,
		"en el entretiempo los equipos cambian de arco")
	for i in 120 * 6:
		await physics_frame
		if m.phase == MatchController.Phase.FINISHED:
			break
	check(m.phase == MatchController.Phase.FINISHED and int(m.clock) == 90, "a los 90' termina el partido")
	m.queue_free()
	await _frames(1)
	var p := PlayerController.new()
	p.stats = PlayerStats.new()
	var fresh := p.sprint_speed()
	p.intent.sprint = true
	p.speed = 9.0
	for i in 60:
		p.update_stamina(1.0)
	check(p.stamina < 0.3 and p.sprint_speed() < fresh * 0.9,
		"sprintar cansa: energía %d%%, velocidad máx %.1f → %.1f m/s" % [roundi(p.stamina * 100), fresh, p.sprint_speed()])
	p.free()


func _test_fouls_and_cards() -> void:
	print("Faltas y tarjetas")
	var m := await _frozen_match("stage4_partido")
	var attacker: PlayerController = m.players.filter(func(x: PlayerController) -> bool: return x.team == 0 and not x.is_keeper)[0]
	var defender: PlayerController = m.players.filter(func(x: PlayerController) -> bool: return x.team == 1 and not x.is_keeper)[0]
	for p in m.players:
		if p != attacker and p != defender and not p.is_keeper:
			p.teleport(Vector3(-30, 0, p.global_position.z), Vector3.RIGHT)
	# Last man: through on goal, fouled from behind -> straight red.
	attacker.teleport(Vector3(32, 0, 0), Vector3.RIGHT)
	defender.teleport(Vector3(31, 0, 0), Vector3.RIGHT)
	m.ball.place(Vector3(32.6, Ball.RADIUS, 0))
	await _frames(5)
	var v := m.foul_judge.judge(defender, attacker, true)
	check(v.dogso and v.card == FoulJudge.RED, "último hombre, ocasión manifiesta: roja directa")
	# Second yellow becomes red.
	defender.yellow_cards = 1
	m.foul_judge.rng.seed = 1
	var reds := 0
	for i in 20:
		var vv := m.foul_judge.judge(defender, attacker, true)
		if vv.card == FoulJudge.RED:
			reds += 1
	check(reds == 20, "con una amarilla encima, la segunda es roja")
	# A red card sends him off; his team plays with one less, slots intact.
	var brain := m.brain_for(1)
	var roles_before := {}
	for p in brain.players:
		if p != defender:
			roles_before[p] = brain.role_of(p)
	var team_size := m.players.filter(func(x: PlayerController) -> bool: return x.team == 1).size()
	m.send_off(defender)
	var same := true
	for p in roles_before:
		same = same and brain.role_of(p) == roles_before[p]
	check(m.players.filter(func(x: PlayerController) -> bool: return x.team == 1).size() == team_size - 1 and same,
		"expulsado: el equipo queda con uno menos y el resto mantiene su puesto")
	m.queue_free()
	await _frames(1)


func _test_penalty() -> void:
	print("Penal")
	var m := await _frozen_match("stage4_partido")
	var attacker: PlayerController = m.players.filter(func(x: PlayerController) -> bool: return x.team == 0 and not x.is_keeper)[0]
	var defender: PlayerController = m.players.filter(func(x: PlayerController) -> bool: return x.team == 1 and not x.is_keeper)[0]
	attacker.teleport(Vector3(44, 0, 3), Vector3.RIGHT)
	defender.teleport(Vector3(43, 0, 3), Vector3.RIGHT)
	var kinds: Array = []
	m.restarted.connect(func(k: String) -> void: kinds.append(k))
	m._on_foul(defender, attacker, true)
	for i in 120 * 3:
		await physics_frame
		if not kinds.is_empty():
			break
	check(not kinds.is_empty() and kinds[0] == "PENAL", "falta dentro del área: penal")
	var spot := Vector3(PitchBuilder.HALF_LENGTH - 11.0, 0, 0)
	check(DirectionResolver.flat(m.ball.global_position).distance_to(spot) < 0.8, "la pelota va al punto penal")
	var inside := 0
	for p in m.players:
		if p != m.set_piece.get("taker") and not p.is_keeper and m.in_penalty_area(p.global_position, 1.0):
			inside += 1
	check(inside == 0, "nadie más dentro del área al patear")
	m.queue_free()
	await _frames(1)


func _test_throw_in() -> void:
	print("Lateral con la mano")
	var m := _new_match("stage4_partido")
	await _frames(2)
	m._restart_at(0, Vector3(10, 0, PitchBuilder.HALF_WIDTH - 0.3), "LATERAL")
	await _frames(10)
	var taker: PlayerController = m.set_piece.taker
	check(m.ball.held and m.ball.global_position.y > 1.8, "el que saca sostiene la pelota sobre la cabeza")
	taker.input_source = taker.ai
	var thrown := false
	for i in 120 * 4:
		await physics_frame
		if taker.last_kick_type == KickSolver.KickType.THROW_IN:
			thrown = true
			break
	check(thrown and not m.ball.held and m.ball.linear_velocity.length() > 3.0, "y la tira con las manos al campo")
	m.queue_free()
	await _frames(1)


func _test_substitutions() -> void:
	print("Cambios")
	var m := await _frozen_match("stage4_partido")
	var out: PlayerController = m.players.filter(func(x: PlayerController) -> bool: return x.team == 0 and x.role == "CF")[0]
	var slot := m.brain_for(0).slot_of(out)
	var in_id: String = m.bench[0][4]
	check(m.request_substitution(out, in_id), "se pide un cambio")
	check(out in m.players, "no se hace con la pelota en juego")
	m._stop("TEST", 0.2, func() -> void: pass)
	var newcomer: PlayerController = null
	for p in m.players:
		if p.stats.id == in_id:
			newcomer = p
	check(newcomer != null and not (out in m.players) and m.brain_for(0).slot_of(newcomer) == slot and m.subs_used[0] == 1,
		"en la detención entra el suplente en el mismo puesto")
	# AI coach: an injured computer player is replaced at the next stoppage.
	var hurt: PlayerController = m.players.filter(func(x: PlayerController) -> bool: return x.team == 1 and x.role == "CB")[0]
	hurt.injured = true
	await _frames(30)
	m._stop("TEST", 0.2, func() -> void: pass)
	check(not (hurt in m.players) and m.subs_used[1] == 1, "el DT de la máquina saca al lesionado")
	m.queue_free()
	await _frames(1)


func _test_referee_and_menu() -> void:
	print("Árbitro y menú de pausa")
	var m := _new_match("stage4_partido")
	var near := 0
	for i in 120 * 20:
		await physics_frame
		if i % 12 == 0 and m.official.global_position.distance_to(m.ball.global_position) < 35.0:
			near += 1
	check(m.official != null and near > 150, "el árbitro sigue la jugada (%d/200 muestras cerca)" % near)
	check(m.ball.last_touch != m.official, "el árbitro nunca toca la pelota")
	m.queue_free()
	await _frames(1)
	var hm := MATCH_SCENE.instantiate() as MatchController
	hm.match_id = "stage4_partido"
	root.add_child(hm)
	await _frames(2)
	hm.pause_menu.open()
	check(paused and hm.pause_menu.visible, "Esc/Start pausa el partido y abre el menú")
	hm.pause_menu.close()
	check(not paused, "y al cerrarlo sigue")
	hm.queue_free()
	await _frames(1)

