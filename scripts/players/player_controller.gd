class_name PlayerController
extends CharacterBody3D
## Gameplay owner of a footballer: decides WHAT happens (movement, actions,
## state). Animation only reflects the result afterwards.
##
##   intent (human/AI) → direction resolver (8/16) → acceleration/turn →
##   movement → ball interaction → animation selection

enum State {
	IDLE, RUN, SPRINT, TURN, DRIBBLE, CONTROL, PASS, SHOOT, TACKLE, SLIDE,
	JUMP, HEAD, FALL, GET_UP, FOUL, INJURED, CELEBRATE,
}

signal state_changed(player: PlayerController, from: int, to: int)
signal kicked(player: PlayerController, type: int, result: KickSolver.KickResult)

const GRAVITY := 9.81
const DECELERATION := 22.0
## Hard turns above this angle at speed trigger the TURN state (brake + pivot).
const HARD_TURN_DEG := 110.0
const FOLLOW_THROUGH := 0.12
const TACKLE_FAIL_EXTRA := 0.25
const ONE_TOUCH_WINDOW := 0.7

# Timings shared with the animation clips (data/animation/clips.json).
static var PASS_WINDUP := AnimationTimings.contact("PASS", 0.09)
static var SHOT_WINDUP := AnimationTimings.contact("SHOOT", 0.15)
static var TACKLE_CONTACT := AnimationTimings.contact("TACKLE", 0.12)
static var TACKLE_TIME := AnimationTimings.length("TACKLE", 0.45)
static var SLIDE_TIME := AnimationTimings.length("SLIDE", 0.8)
static var FALL_TIME := AnimationTimings.length("FALL", 0.7)
static var GET_UP_TIME := AnimationTimings.length("GET_UP", 0.45)

var stats: PlayerStats = PlayerStats.new()
var team := 0
## +1 attacks the goal at +X, -1 the goal at -X.
var attack_dir := 1.0
var home_position := Vector3.ZERO
## Object with fill(intent: PlayerIntent, player: PlayerController, delta: float).
var input_source: Object = null
var intent := PlayerIntent.new()
var match_ctx: MatchController = null
var ball: Ball = null
## 8 = classic, 16 = finer (still digital).
var direction_steps := 8
## While true the input source is ignored (dead ball, restarts).
var frozen := false

var state: int = State.IDLE
var state_time := 0.0
var facing := Vector3.RIGHT
var desired_dir := Vector3.ZERO
var speed := 0.0
## Signed angle (deg) between facing and the requested direction. + = left.
var turn_angle_deg := 0.0
## Smoothed angular speed (deg/s) — hurts balance when kicking.
var turn_speed_deg := 0.0
var last_kick_type := -1

var _kick := {}
var _queued := {}
var _action_resolved := false

@onready var interaction: BallInteraction = $BallInteraction
@onready var animation_selector: AnimationSelector = $AnimationSelector
@onready var visual: Node3D = $Visual


func _ready() -> void:
	_apply_rotation()


# --- attribute-derived tuning -------------------------------------------------

func jog_speed() -> float:
	return lerpf(5.6, 7.0, stats.n(&"speed"))


func sprint_speed() -> float:
	return lerpf(7.2, 9.3, stats.n(&"speed"))


func acceleration() -> float:
	return lerpf(9.0, 18.0, stats.n(&"acceleration"))


## rad/s. Fast enough to feel instant between neighbouring directions, slow
## enough that a 180° costs something.
func turn_rate() -> float:
	return deg_to_rad(lerpf(620.0, 1100.0, stats.n(&"agility")))


# --- queries -----------------------------------------------------------------

func has_ball() -> bool:
	return ball != null and ball.owner_player == self


func is_sprinting() -> bool:
	return intent.sprint and speed > jog_speed() * 1.01


func is_grounded_state() -> bool:
	return state in [State.FALL, State.GET_UP, State.SLIDE]


## Can this player touch a loose ball / keep possession right now?
func can_play_ball() -> bool:
	return not (state in [State.FALL, State.GET_UP, State.TACKLE])


func has_queued_action() -> bool:
	return not _queued.is_empty()


func opponent_has_ball() -> bool:
	return ball != null and ball.owner_player != null and (ball.owner_player as PlayerController).team != team


# --- main loop ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	state_time += delta
	if not _queued.is_empty():
		_queued.time -= delta
		if _queued.time <= 0.0:
			_queued.clear()

	if frozen or input_source == null:
		intent.clear()
	else:
		input_source.fill(intent, self, delta)

	match state:
		State.PASS, State.SHOOT:
			_update_kick(delta)
		State.TACKLE:
			_update_tackle(delta)
		State.SLIDE:
			_update_slide(delta)
		State.FALL:
			speed = move_toward(speed, 0.0, 14.0 * delta)
			if state_time >= FALL_TIME:
				_set_state(State.GET_UP)
		State.GET_UP:
			speed = 0.0
			if state_time >= GET_UP_TIME:
				_set_state(State.IDLE)
		State.CELEBRATE:
			speed = move_toward(speed, 0.0, DECELERATION * delta)
		_:
			_update_locomotion(delta)
			if not frozen:
				_handle_actions()

	_move(delta)
	animation_selector.update(self, delta)


func _update_locomotion(delta: float) -> void:
	var carrying := has_ball()
	var q := DirectionResolver.quantize(intent.move, direction_steps)
	desired_dir = DirectionResolver.to_world(q)

	# WE "pressure": holding pass while the rival has the ball runs at him.
	if _is_pressing():
		var to_ball := DirectionResolver.flat(ball.global_position - global_position)
		if to_ball.length() > 0.3:
			desired_dir = DirectionResolver.to_world(
				DirectionResolver.quantize(DirectionResolver.to_stick(to_ball).normalized(), direction_steps))

	var top := sprint_speed() if intent.sprint else jog_speed()
	if carrying:
		top *= lerpf(0.86, 0.95, stats.n(&"control"))

	var prev_facing := facing
	if desired_dir != Vector3.ZERO:
		var diff := DirectionResolver.signed_angle(facing, desired_dir)
		turn_angle_deg = rad_to_deg(diff)
		if state != State.TURN and absf(turn_angle_deg) > HARD_TURN_DEG and speed > jog_speed() * 0.6:
			_set_state(State.TURN)
		var rate := turn_rate()
		if intent.sprint:
			rate *= 0.75
		if carrying:
			rate *= 0.9
		facing = DirectionResolver.rotate_towards(facing, desired_dir, rate * delta)
		# You run where you face: misalignment costs speed, not strafing.
		var misalign := absf(DirectionResolver.signed_angle(facing, desired_dir))
		var target := top * lerpf(0.35, 1.0, cos(minf(misalign, PI * 0.5)))
		if state == State.TURN:
			target = top * 0.3
		var rate_v := acceleration() if speed < target else DECELERATION
		speed = move_toward(speed, target, rate_v * delta)
	else:
		turn_angle_deg = 0.0
		speed = move_toward(speed, 0.0, DECELERATION * delta)

	var inst := rad_to_deg(absf(DirectionResolver.signed_angle(prev_facing, facing))) / maxf(delta, 0.0001)
	turn_speed_deg = lerpf(turn_speed_deg, inst, 1.0 - exp(-10.0 * delta))

	if state == State.TURN:
		if state_time > 0.2 or absf(turn_angle_deg) < 20.0:
			_set_state(_locomotion_state())
	else:
		_set_state(_locomotion_state())


func _locomotion_state() -> int:
	if state == State.CONTROL and state_time < 0.2:
		return State.CONTROL
	if has_ball():
		return State.DRIBBLE if speed > 0.3 else State.CONTROL
	if speed < 0.25:
		return State.IDLE
	if is_sprinting():
		return State.SPRINT
	return State.RUN


func _is_pressing() -> bool:
	return not has_ball() and opponent_has_ball() and intent.is_held(PlayerIntent.Action.PASS)


func _handle_actions() -> void:
	if has_ball():
		if intent.released_action != PlayerIntent.NONE:
			_start_kick(intent.released_action, intent.released_charge)
		return
	if opponent_has_ball():
		if intent.is_just_pressed(PlayerIntent.Action.PASS):
			var carrier := ball.owner_player as PlayerController
			if global_position.distance_to(carrier.global_position) < 2.2:
				_start_tackle()
		elif intent.is_just_pressed(PlayerIntent.Action.SHOOT):
			_start_slide()
		return
	# Loose ball (or a team-mate has it): queue a first-time action.
	if intent.released_action != PlayerIntent.NONE:
		_queued = {
			"action": intent.released_action,
			"power": intent.released_charge,
			"aim": DirectionResolver.quantize(intent.move, direction_steps),
			"time": ONE_TOUCH_WINDOW,
		}


func _move(delta: float) -> void:
	velocity.x = facing.x * speed
	velocity.z = facing.z * speed
	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Bumping into someone costs speed.
	var actual := Vector2(velocity.x, velocity.z).length()
	if actual < speed:
		speed = actual
	_apply_rotation()


func _apply_rotation() -> void:
	rotation.y = atan2(-facing.x, -facing.z)


func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_time = 0.0
	state_changed.emit(self, old, new_state)


# --- kicks -------------------------------------------------------------------

func _start_kick(action: int, power: float) -> void:
	var aim := DirectionResolver.quantize(intent.move, direction_steps)
	var dir := DirectionResolver.to_world(aim) if aim != Vector2.ZERO else facing
	_kick = {"action": action, "power": power, "dir": dir, "aim": aim, "done": false}
	_set_state(State.SHOOT if action == PlayerIntent.Action.SHOOT else State.PASS)


func _update_kick(delta: float) -> void:
	var windup := SHOT_WINDUP if state == State.SHOOT else PASS_WINDUP
	speed = move_toward(speed, jog_speed() * 0.35, 18.0 * delta)
	if not _kick.done:
		# Plant foot: turn quickly towards the kick direction.
		facing = DirectionResolver.rotate_towards(facing, _kick.dir, turn_rate() * 1.5 * delta)
		if state_time >= windup:
			_kick.done = true
			if has_ball() or interaction.contact_zone(ball.global_position) == BallInteraction.Zone.FOOT:
				_execute_kick(_kick.action, _kick.power, _kick.dir, _kick.aim, false, false, 0.0)
	elif state_time >= windup + FOLLOW_THROUGH:
		_kick.clear()
		_set_state(_locomotion_state())


func execute_queued_action(header: bool, incoming_speed: float) -> void:
	var q := _queued.duplicate()
	_queued.clear()
	var aim: Vector2 = q.aim
	var dir := DirectionResolver.to_world(aim) if aim != Vector2.ZERO else facing
	facing = DirectionResolver.rotate_towards(facing, dir, deg_to_rad(60.0))
	_execute_kick(q.action, q.power, dir, aim, true, header, incoming_speed)
	_set_state(State.HEAD if header else (State.SHOOT if q.action == PlayerIntent.Action.SHOOT else State.PASS))
	_kick = {"done": true}


func _execute_kick(action: int, power: float, dir: Vector3, aim: Vector2, one_touch: bool, header: bool, incoming_speed: float) -> void:
	var req := KickSolver.KickRequest.new()
	req.type = _kick_type(action, dir, header)
	req.origin = ball.global_position
	req.direction = dir
	req.power = power
	req.stats = stats
	req.contact_quality = 0.85 if header else interaction.contact_quality(ball, dir)
	req.balance = balance_modifier()
	req.pressure = match_ctx.pressure_on(self) if match_ctx else 0.0
	req.movement = clampf(speed / sprint_speed(), 0.0, 1.0)
	req.weak_foot = not header and interaction.is_weak_foot(ball)
	req.foot_sign = 1.0 if stats.preferred_foot == "right" else -1.0
	req.one_touch = one_touch
	req.incoming_speed = incoming_speed
	if req.type == KickSolver.KickType.SHOT or (header and action == PlayerIntent.Action.SHOOT):
		req.target = match_ctx.shot_target(self, aim) if match_ctx else global_position + dir * 20.0
	else:
		req.target = match_ctx.pass_target(self, req.type, dir, power) if match_ctx else global_position + dir * lerpf(8.0, 35.0, power)
	var rng := match_ctx.rng if match_ctx else RandomNumberGenerator.new()
	var result := KickSolver.solve(req, rng)
	ball.kick(result.velocity, result.spin, self)
	if match_ctx:
		match_ctx.referee.set_cooldown(self, 0.3)
	last_kick_type = req.type
	kicked.emit(self, req.type, result)


func _kick_type(action: int, dir: Vector3, header: bool) -> int:
	if header:
		return KickSolver.KickType.HEADER
	match action:
		PlayerIntent.Action.SHOOT:
			return KickSolver.KickType.SHOT
		PlayerIntent.Action.THROUGH:
			return KickSolver.KickType.THROUGH_PASS
		PlayerIntent.Action.LOB:
			# Wide and in the attacking third = cross.
			if absf(global_position.z) > 18.0 and global_position.x * attack_dir > 25.0:
				return KickSolver.KickType.CROSS
			return KickSolver.KickType.LOB_PASS
	if dir.x * attack_dir < -0.7:
		return KickSolver.KickType.BACK_PASS
	return KickSolver.KickType.GROUND_PASS


## 0.5..1. Turning hard or sprinting while kicking unbalances the player.
func balance_modifier() -> float:
	var turn_penalty := clampf(turn_speed_deg / 720.0, 0.0, 1.0) * 0.35
	var sprint_penalty := 0.08 if is_sprinting() else 0.0
	return clampf(1.0 - (turn_penalty + sprint_penalty) * (1.15 - stats.n(&"balance")), 0.5, 1.0)


func on_ball_received(zone: int, quality: float) -> void:
	if state in [State.IDLE, State.RUN, State.SPRINT, State.DRIBBLE]:
		_set_state(State.CONTROL)
	interaction.last_zone = zone
	if match_ctx:
		match_ctx.on_ball_received(self, zone, quality)


# --- defending ---------------------------------------------------------------

func _start_tackle() -> void:
	_action_resolved = false
	_set_state(State.TACKLE)


func _update_tackle(delta: float) -> void:
	if ball.owner_player != null:
		var to_ball := DirectionResolver.flat(ball.global_position - global_position)
		if to_ball.length() > 0.2:
			facing = DirectionResolver.rotate_towards(facing, to_ball.normalized(), turn_rate() * delta)
	if not _action_resolved and state_time >= TACKLE_CONTACT:
		_action_resolved = true
		var won := match_ctx.referee.resolve_tackle(self) if match_ctx else false
		_kick = {"won": won}
	speed = move_toward(speed, jog_speed() * 0.5, 16.0 * delta)
	var duration := TACKLE_TIME if _kick.get("won", false) else TACKLE_TIME + TACKLE_FAIL_EXTRA
	if state_time >= duration:
		_kick.clear()
		_set_state(_locomotion_state())


func _start_slide() -> void:
	_action_resolved = false
	var dir := DirectionResolver.to_world(DirectionResolver.quantize(intent.move, direction_steps))
	if dir != Vector3.ZERO:
		facing = dir
	speed = maxf(speed + 2.0, 7.5)
	_set_state(State.SLIDE)


func _update_slide(delta: float) -> void:
	speed = move_toward(speed, 0.0, 9.0 * delta)
	if not _action_resolved and state_time < SLIDE_TIME * 0.7 and match_ctx:
		_action_resolved = match_ctx.referee.check_slide(self)
	if state_time >= SLIDE_TIME:
		_set_state(State.GET_UP)


## Knocked over (foul, collision).
func knock_down() -> void:
	if has_ball():
		ball.owner_player = null
	_kick.clear()
	_queued.clear()
	_set_state(State.FALL)


func celebrate() -> void:
	_set_state(State.CELEBRATE)


# --- restarts ----------------------------------------------------------------

func teleport(pos: Vector3, face: Vector3) -> void:
	global_position = Vector3(pos.x, 0.0, pos.z)
	velocity = Vector3.ZERO
	speed = 0.0
	facing = DirectionResolver.flat(face).normalized()
	if facing == Vector3.ZERO:
		facing = Vector3.RIGHT * attack_dir
	_kick.clear()
	_queued.clear()
	_set_state(State.IDLE)
	_apply_rotation()


func set_colors(primary: Color, secondary: Color) -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = primary
	($Visual/Body as MeshInstance3D).material_override = body
	var shorts := StandardMaterial3D.new()
	shorts.albedo_color = secondary
	($Visual/Shorts as MeshInstance3D).material_override = shorts


func set_human(is_human: bool) -> void:
	($Visual/Cursor as Node3D).visible = is_human
