extends SceneTree
## Behaviour probe: measures our engine with the same protocol used to
## measure WE2002 (data/reference/we2002_behavior.json) and compares.
##
##   godot --headless --path . -s tests/behavior_probe.gd [-- --out=behavior_report.json]
##
## Metrics whose target is still null are reported as PENDIENTE; the exit
## code is non-zero only when a measured target falls outside tolerance.

const REFERENCE := "reference/we2002_behavior.json"
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


var results := {}
var m: MatchController
var p: PlayerController
var input := ScriptedInput.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	InputSetup.ensure_actions()
	await _setup()
	await _movement()
	await _turns()
	await _dribble()
	await _kicks()
	await _camera()
	var failed := _report()
	quit(1 if failed else 0)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _setup() -> void:
	m = (load("res://scenes/match/Match.tscn") as PackedScene).instantiate() as MatchController
	m.match_id = "stage0_solo"
	m.allow_human = false
	root.add_child(m)
	m.rng.seed = 99
	await _frames(2)
	p = m.players[0]
	p.input_source = input


## Park the ball far away so the player runs free.
func _free_run(pos := Vector3(-40, 0, 0)) -> void:
	input.move = Vector2.ZERO
	input.sprint = false
	m.ball.place(Vector3(0, Ball.RADIUS, 30))
	p.teleport(pos, Vector3.RIGHT)
	await _frames(3)


func _top_speed(sprint: bool) -> float:
	input.move = Vector2.RIGHT
	input.sprint = sprint
	await _frames(240)
	var x0 := p.global_position.x
	await _frames(120)
	return (p.global_position.x - x0)


func _movement() -> void:
	await _free_run()
	results.jog_top_speed = await _top_speed(false)
	await _free_run()
	# Acceleration from standstill.
	input.move = Vector2.RIGHT
	input.sprint = true
	var sprint_top := p.sprint_speed()
	var t := 0.0
	while p.speed < 0.9 * sprint_top and t < 5.0:
		await physics_frame
		t += DT
	results.time_to_90pct_sprint = t
	results.sprint_top_speed = await _top_speed(true)
	# Braking.
	var x0 := p.global_position.x
	input.move = Vector2.ZERO
	t = 0.0
	while p.speed > 0.05 and t < 5.0:
		await physics_frame
		t += DT
	results.stop_time_from_sprint = t
	results.stop_distance_from_sprint = p.global_position.x - x0


func _turns() -> void:
	await _free_run()
	input.move = Vector2.RIGHT
	await _frames(180)
	input.move = Vector2(1, -1)
	var target := DirectionResolver.to_world(Vector2(1, -1).normalized())
	var t := 0.0
	while rad_to_deg(absf(DirectionResolver.signed_angle(p.facing, target))) > 5.0 and t < 3.0:
		await physics_frame
		t += DT
	results.turn_45_time_jog = t

	await _free_run()
	input.move = Vector2.RIGHT
	input.sprint = true
	await _frames(240)
	input.move = Vector2.LEFT
	t = 0.0
	while p.velocity.x > -0.5 * p.jog_speed() and t < 3.0:
		await physics_frame
		t += DT
	results.turn_180_time_sprint = t


func _with_ball(pos := Vector3(-30, 0, 0)) -> void:
	input.move = Vector2.ZERO
	input.sprint = false
	p.teleport(pos, Vector3.RIGHT)
	m.ball.place(pos + Vector3(0.55, Ball.RADIUS, 0))
	await _frames(30)


func _dribble() -> void:
	for sprint: bool in [false, true]:
		await _with_ball()
		input.move = Vector2.RIGHT
		input.sprint = sprint
		await _frames(180)
		var gap := 0.0
		var n := 0
		var x0 := p.global_position.x
		for i in 120:
			await physics_frame
			gap += DirectionResolver.flat(m.ball.global_position - p.global_position).length()
			n += 1
		results["dribble_ball_gap_" + ("sprint" if sprint else "jog")] = gap / n
		if sprint:
			results.dribble_sprint_speed = p.global_position.x - x0


## Releases a kick and returns [windup_seconds, launch_speed, ball_start].
func _kick(action: int, charge: float) -> Array:
	await _with_ball()
	var start := m.ball.global_position
	input.charge = charge
	input.release = action
	var t := 0.0
	# Dribbling drifts the ball at ~1 m/s; a kick is anything clearly faster.
	while m.ball.linear_velocity.length() < 3.0 and t < 1.0:
		await physics_frame
		t += DT
	await physics_frame
	return [t, m.ball.linear_velocity.length(), start]


func _kicks() -> void:
	var r := await _kick(PlayerIntent.Action.PASS, 0.5)
	results.pass_windup = r[0]
	results.pass_speed_half_bar = r[1]
	var t := 0.0
	var start: Vector3 = r[2]
	while DirectionResolver.flat(m.ball.global_position - start).length() < 20.0 and t < 6.0:
		await physics_frame
		t += DT
	results.pass_travel_20m = t + DT

	r = await _kick(PlayerIntent.Action.SHOOT, 0.5)
	results.shot_windup = r[0]
	results.shot_speed_half_bar = r[1]
	r = await _kick(PlayerIntent.Action.SHOOT, 1.0)
	results.shot_speed_full_bar = r[1]

	# Lob: solver aimed at 30 m, flight time until it lands.
	var req := KickSolver.KickRequest.new()
	req.type = KickSolver.KickType.LOB_PASS
	req.origin = Vector3(-30, Ball.RADIUS, 20)
	req.target = req.origin + Vector3.RIGHT * 30.0
	req.stats = p.stats
	var res := KickSolver.solve(req, m.rng)
	p.teleport(Vector3(-40, 0, -30), Vector3.RIGHT)
	m.ball.place(req.origin)
	await _frames(2)
	m.ball.kick(res.velocity, res.spin)
	await _frames(12)
	t = 12 * DT
	while m.ball.global_position.y > Ball.RADIUS + 0.05 and t < 6.0:
		await physics_frame
		t += DT
	results.lob_flight_30m = t


func _camera() -> void:
	var cam := m.camera
	results.camera_pitch_deg = rad_to_deg(atan(cam.height / cam.distance))
	# Visible pitch length at the centre of the screen (focus plane).
	var dist := Vector2(cam.height, cam.distance).length()
	var hfov := 2.0 * atan(tan(deg_to_rad(cam.fov) * 0.5) * 16.0 / 9.0)
	results.camera_visible_length = 2.0 * dist * tan(hfov * 0.5)
	# Possession swing: settle the lead towards +X, then flip the carrier's
	# attacking direction (same effect as the other team winning the ball).
	await _with_ball(Vector3(0, 0, 0))
	await _frames(360)
	p.attack_dir = -1.0
	var t := 0.0
	while cam._lead_x > 0.0 and t < 5.0:
		await physics_frame
		t += DT
	results.camera_lead_swing = t
	p.attack_dir = 1.0


func _report() -> bool:
	var ref: Dictionary = DataLoader.load_json(REFERENCE).get("metrics", {})
	var failed := false
	var pending := 0
	print("\n%-28s %10s %10s %8s  %s" % ["MÉTRICA", "NUESTRO", "WE2002", "Δ", "ESTADO"])
	var report := {}
	for key: String in ref:
		var spec: Dictionary = ref[key]
		var ours: Variant = results.get(key)
		var target: Variant = spec.get("target")
		var status := "PENDIENTE"
		var delta := ""
		if ours == null:
			status = "SIN SONDA"
		elif target != null:
			var rel := (float(ours) - float(target)) / maxf(absf(float(target)), 0.0001)
			delta = "%+.0f%%" % (rel * 100.0)
			status = "OK" if absf(rel) <= float(spec.get("tolerance", 0.1)) else "FUERA"
			failed = failed or status == "FUERA"
		else:
			pending += 1
		print("%-28s %10s %10s %8s  %s" % [key, "-" if ours == null else "%.2f %s" % [ours, spec.get("unit", "")],
			"-" if target == null else "%.2f" % target, delta, status])
		report[key] = {"ours": ours, "target": target, "status": status, "unit": spec.get("unit", "")}
	print("\n%d métricas pendientes de medir en WE2002." % pending)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var f := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			f.store_string(JSON.stringify(report, "  "))
	return failed
