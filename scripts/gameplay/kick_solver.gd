class_name KickSolver
extends RefCounted
## Pure functions that turn a kick REQUEST (what the player tried) into the
## ball velocity + spin that actually happens. Nothing here reads nodes, so
## it is fully testable and tunable.
##
##   final_power = base_power × player_power × balance_modifier × contact_modifier
##   accuracy    = player_accuracy × pressure_modifier × movement_modifier × weak_foot_modifier
##
## That is what produces "le pegué mal" instead of "el numerito 84 decidió
## que erraba".

enum KickType { GROUND_PASS, THROUGH_PASS, LOB_PASS, CROSS, CHIP, BACK_PASS, ONE_TOUCH, SHOT, HEADER }

const TYPE_NAMES := {
	KickType.GROUND_PASS: "PASE",
	KickType.THROUGH_PASS: "PASE FILTRADO",
	KickType.LOB_PASS: "GLOBO",
	KickType.CROSS: "CENTRO",
	KickType.CHIP: "VASELINA",
	KickType.BACK_PASS: "PASE ATRÁS",
	KickType.ONE_TOUCH: "PRIMERA",
	KickType.SHOT: "REMATE",
	KickType.HEADER: "CABEZAZO",
}

## Maximum horizontal error (degrees) at accuracy 0.
const MAX_ERROR_DEG := {
	KickType.GROUND_PASS: 12.0,
	KickType.THROUGH_PASS: 12.0,
	KickType.LOB_PASS: 10.0,
	KickType.CROSS: 12.0,
	KickType.CHIP: 10.0,
	KickType.BACK_PASS: 8.0,
	KickType.ONE_TOUCH: 16.0,
	KickType.SHOT: 14.0,
	KickType.HEADER: 18.0,
}

const G := Ball.GRAVITY
const DRAG_C := Ball.AIR_DRAG / Ball.MASS


class KickRequest:
	var type: int = KickType.GROUND_PASS
	var origin := Vector3.ZERO
	var target := Vector3.ZERO
	## Used when the target is degenerate.
	var direction := Vector3.RIGHT
	## Power bar 0..1.
	var power := 0.5
	## Where the foot met the ball, 1 = sweet spot.
	var contact_quality := 1.0
	## 0.5..1, lower when turning hard / sprinting.
	var balance := 1.0
	## 0..1, closeness of opponents.
	var pressure := 0.0
	## 0..1, own speed relative to top speed.
	var movement := 0.0
	var weak_foot := false
	## +1 right foot, -1 left foot (decides curl direction).
	var foot_sign := 1.0
	## Kicked first time (no control) and speed of the incoming ball.
	var one_touch := false
	var incoming_speed := 0.0
	var stats: PlayerStats = PlayerStats.new()


class KickResult:
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var accuracy := 1.0
	var final_power := 0.0
	var error_deg := 0.0
	var contact_quality := 1.0
	var mishit := false

	func describe(type: int) -> String:
		return "%s  vel %.1f m/s · precisión %d%% · contacto %d%% · desvío %+.1f°%s" % [
			TYPE_NAMES.get(type, "?"), velocity.length(), roundi(accuracy * 100.0),
			roundi(contact_quality * 100.0), error_deg, "  ¡LE PEGÓ MAL!" if mishit else ""]


static func final_power(base_power: float, player_power: float, balance_modifier: float, contact_quality: float) -> float:
	return base_power * player_power * balance_modifier * lerpf(0.7, 1.0, contact_quality)


static func accuracy(skill_n: float, pressure: float, movement: float, weak_foot: bool, stats: PlayerStats) -> float:
	var player_accuracy := lerpf(0.45, 1.0, skill_n)
	var pressure_modifier := 1.0 - pressure * 0.35 * (1.15 - stats.n(&"technique"))
	var movement_modifier := 1.0 - movement * 0.2 * (1.15 - stats.n(&"balance"))
	var weak_foot_modifier := 1.0
	if weak_foot:
		weak_foot_modifier = lerpf(0.55, 0.95, (stats.weak_foot - 1) / 3.0)
	return clampf(player_accuracy * pressure_modifier * movement_modifier * weak_foot_modifier, 0.05, 1.0)


## Speed a rolling ball needs to cover `distance` and still arrive at
## `arrive_speed`, accounting for rolling resistance and quadratic drag.
## Closed form of v·dv/ds = -(ROLL_DECEL + c·v²).
static func ground_launch_speed(distance: float, arrive_speed: float) -> float:
	var r := Ball.ROLL_DECEL / DRAG_C
	return sqrt((arrive_speed * arrive_speed + r) * exp(2.0 * DRAG_C * distance) - r)


## Low launch angle to hit (distance, height) at speed v, ignoring drag.
## Returns -1 when unreachable.
static func launch_angle(v: float, distance: float, height: float) -> float:
	var v2 := v * v
	var disc := v2 * v2 - G * (G * distance * distance + 2.0 * height * v2)
	if disc < 0.0:
		return -1.0
	return atan((v2 - sqrt(disc)) / (G * distance))


static func solve(req: KickRequest, rng: RandomNumberGenerator) -> KickResult:
	var r := KickResult.new()
	var s := req.stats
	var skill := s.n(&"passing")
	if req.type == KickType.SHOT:
		skill = s.n(&"shooting")
	elif req.type == KickType.HEADER:
		skill = s.n(&"heading")

	var contact := req.contact_quality
	if req.one_touch:
		# Striking a moving ball first time is harder the faster it comes.
		contact *= 1.0 - clampf((req.incoming_speed - 8.0) / 40.0, 0.0, 0.35) * (1.1 - s.n(&"technique"))
	r.contact_quality = clampf(contact, 0.05, 1.0)
	r.mishit = r.contact_quality < 0.45

	r.accuracy = accuracy(skill, req.pressure, req.movement, req.weak_foot, s) * lerpf(0.7, 1.0, r.contact_quality)

	var flat := DirectionResolver.flat(req.target - req.origin)
	if flat.length() < 0.5:
		flat = DirectionResolver.flat(req.direction).normalized() * 10.0
	var distance := flat.length()
	var dir := flat / distance

	r.error_deg = _noise(rng) * float(MAX_ERROR_DEG.get(req.type, 12.0)) * (1.0 - r.accuracy)
	dir = dir.rotated(Vector3.UP, deg_to_rad(r.error_deg))

	match req.type:
		KickType.SHOT, KickType.HEADER:
			_solve_shot(req, r, dir, distance, rng)
		KickType.LOB_PASS, KickType.CROSS, KickType.CHIP:
			_solve_lob(req, r, dir, distance, rng)
		_:
			_solve_ground(req, r, dir, distance)
	return r


static func _solve_ground(req: KickRequest, r: KickResult, dir: Vector3, distance: float) -> void:
	var s := req.stats
	var arrive := lerpf(3.0, 7.5, req.power)
	if req.type == KickType.THROUGH_PASS:
		arrive += 1.5
	var base := ground_launch_speed(distance, arrive)
	var v := final_power(base, lerpf(0.95, 1.03, s.n(&"passing")), req.balance, r.contact_quality)
	v = minf(v, 30.0)
	r.final_power = v
	# A bad contact pops the ball up a little.
	var lift := (1.0 - r.contact_quality) * 2.5
	r.velocity = dir * v + Vector3.UP * lift


static func _solve_lob(req: KickRequest, r: KickResult, dir: Vector3, distance: float, rng: RandomNumberGenerator) -> void:
	var s := req.stats
	var angle_deg := lerpf(40.0, 32.0, req.power)
	if req.type == KickType.CROSS:
		angle_deg = lerpf(28.0, 22.0, req.power)
	elif req.type == KickType.CHIP:
		angle_deg = 45.0
	angle_deg += _noise(rng) * 4.0 * (1.0 - r.accuracy)
	var angle := deg_to_rad(angle_deg)
	# Vacuum range formula + empirical drag compensation.
	var base := sqrt(G * distance / sin(2.0 * angle)) * (1.0 + 0.0025 * distance)
	var v := final_power(base, lerpf(0.96, 1.03, s.n(&"passing")), req.balance, r.contact_quality)
	r.final_power = v
	r.velocity = dir * cos(angle) * v + Vector3.UP * sin(angle) * v
	# Backspin makes the ball hang (Magnus lift).
	r.spin = dir.cross(Vector3.UP) * 6.0


static func _solve_shot(req: KickRequest, r: KickResult, dir: Vector3, distance: float, rng: RandomNumberGenerator) -> void:
	var s := req.stats
	var base := lerpf(14.0, 33.0, req.power)
	var power_stat := s.n(&"shot_power")
	if req.type == KickType.HEADER:
		base *= 0.55
		power_stat = s.n(&"heading")
	var v := final_power(base, lerpf(0.82, 1.06, power_stat), req.balance, r.contact_quality)
	r.final_power = v

	# Classic power bar: the more you charge, the higher it goes.
	# Overcharging sends it over the bar.
	var height := lerpf(0.15, 1.9, pow(req.power, 1.5))
	if req.power > 0.88:
		height += (req.power - 0.88) * 14.0
	height += _noise(rng) * 1.2 * (1.0 - r.accuracy)
	if r.mishit:
		height += rng.randf_range(-0.4, 2.5) * (0.45 - r.contact_quality) * 3.0
	# Drag makes the ball drop a bit more than the vacuum solution.
	height += 0.012 * distance
	var rel_height := height - (req.origin.y - Ball.RADIUS)
	var angle := launch_angle(v, distance, rel_height)
	if angle < 0.0:
		angle = deg_to_rad(35.0)
	r.velocity = dir * cos(angle) * v + Vector3.UP * sin(angle) * v
	# Inside-foot curl. Weak foot curls the other way.
	var foot := req.foot_sign * (-1.0 if req.weak_foot else 1.0)
	r.spin = Vector3.UP * foot * lerpf(3.0, 14.0, s.n(&"technique")) * (0.4 + 0.6 * req.power)


## Gaussian-ish noise in [-1, 1].
static func _noise(rng: RandomNumberGenerator) -> float:
	return clampf(rng.randfn(0.0, 0.5), -1.0, 1.0)
