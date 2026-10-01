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

