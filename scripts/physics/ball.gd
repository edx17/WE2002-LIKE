class_name Ball
extends RigidBody3D
## The ball is an independent physical object. Nobody ever writes
## "ball.position = in front of the player": players only REQUEST things
## (a control velocity while dribbling, a kick velocity + spin) and the ball
## integrates them together with gravity, drag, spin and bounces.

const RADIUS := 0.11
const MASS := 0.43
const GRAVITY := 9.81
## Quadratic air drag coefficient k (F = -k·|v|·v).
const AIR_DRAG := 0.0045
## Rolling resistance on grass (m/s²).
const ROLL_DECEL := 1.4
## Magnus force per (rad/s · m/s).
const MAGNUS := 0.0022
const SPIN_DECAY := 0.7
const MAX_SPEED := 40.0

## Player currently in possession (dribbling), or null for a loose ball.
var owner_player: Node = null
## Last player that touched the ball (restarts, stats).
var last_touch: Node = null
## Goalkeeper holding the ball in his hands (owner_player is the keeper).
var held := false
## Custom spin vector (rad/s) used for Magnus curve. Visual rotation is
## handled separately.
var spin := Vector3.ZERO

var _control_velocity := Vector3.ZERO
var _control_rate := 0.0
var _pending_velocity: Variant = null
var _kick_frame := 0
var _pending_position: Variant = null


func _ready() -> void:
	mass = MASS
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0


func is_grounded() -> bool:
	return global_position.y <= RADIUS + 0.03


## Strike the ball. Replaces its velocity; the kicker loses possession.
## Seconds since the last kick (keepers need time to react to it).
func kick_age() -> float:
	return float(Engine.get_physics_frames() - _kick_frame) / float(Engine.physics_ticks_per_second)


func kick(velocity: Vector3, new_spin := Vector3.ZERO, by: Node = null) -> void:
	_kick_frame = Engine.get_physics_frames()
	_pending_velocity = velocity.limit_length(MAX_SPEED)
	spin = new_spin
	owner_player = null
	held = false
	_control_rate = 0.0
	if by != null:
		last_touch = by


## Dribble control: ask the ball to move at `desired` (horizontal) with a
## given responsiveness (1/s). Must be re-issued every physics frame.
func control(desired: Vector3, rate: float) -> void:
	_control_velocity = desired
	_control_rate = rate


func take_possession(player: Node, first_touch_velocity: Vector3) -> void:
	kick(first_touch_velocity, Vector3.ZERO, player)
	owner_player = player


## Teleport (restarts). Leaves the ball dead and loose.
func place(pos: Vector3) -> void:
	_pending_position = pos
	_pending_velocity = Vector3.ZERO
	spin = Vector3.ZERO
	owner_player = null
	held = false
	_control_rate = 0.0


## Keeper catches the ball: it stays in his hands until he releases it.
func hold(keeper: Node) -> void:
	kick(Vector3.ZERO, Vector3.ZERO, keeper)
	owner_player = keeper
	held = true


## Moves a held ball with the keeper's hands (call every frame).
func carry(pos: Vector3) -> void:
	_pending_position = pos
	_pending_velocity = Vector3.ZERO


## Drops a held ball at the keeper's feet so he can kick it.
func release_hold(feet: Vector3) -> void:
	held = false
	_pending_position = Vector3(feet.x, RADIUS, feet.z)
	_pending_velocity = Vector3.ZERO


## Current velocity, including a kick queued this frame.
func current_velocity() -> Vector3:
	if _pending_velocity != null:
		return _pending_velocity
	return linear_velocity


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	if _pending_position != null:
		var xform := state.transform
		xform.origin = _pending_position
		state.transform = xform
		_pending_position = null
	if _pending_velocity != null:
		state.linear_velocity = _pending_velocity
		state.angular_velocity = Vector3.ZERO
		_pending_velocity = null

	var v := state.linear_velocity
	var grounded := state.transform.origin.y <= RADIUS + 0.03 and absf(v.y) < 1.0

	# Air drag.
	var s := v.length()
	if s > 0.01:
		v -= v * (AIR_DRAG * s / MASS) * dt
	# Magnus (curve / dip / hang).
	if not grounded and spin.length_squared() > 0.0001:
		v += spin.cross(v) * (MAGNUS / MASS) * dt
	spin *= exp(-SPIN_DECAY * dt)
	# Rolling resistance.
	if grounded:
		var h := Vector2(v.x, v.z)
		var hs := h.length()
		if hs > 0.0:
			h *= maxf(hs - ROLL_DECEL * dt, 0.0) / hs
		v.x = h.x
		v.z = h.y
	# Player control (dribbling) blends the horizontal velocity only.
	if _control_rate > 0.0:
		var k := 1.0 - exp(-_control_rate * dt)
		v.x = lerpf(v.x, _control_velocity.x, k)
		v.z = lerpf(v.z, _control_velocity.z, k)
		if grounded and v.y > 0.0:
			v.y *= 0.5
		_control_rate = 0.0

	state.linear_velocity = v
	if grounded:
		# Roll without slipping (visual + no friction fight with the ground).
		state.angular_velocity = Vector3(v.z, 0.0, -v.x) / RADIUS
