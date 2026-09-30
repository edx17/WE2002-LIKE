class_name WECamera
extends Camera3D
## Classic WE broadcast camera: high on the side of the pitch, looking across
## it, tracking the ball along the length of the field with a lead in the
## direction of play. Not a free modern camera.
##
## Follows: ball + centre of the pitch + direction of play.

@export var follow_speed := 3.0
@export var lateral_follow := 0.55
@export var lead := 7.0
## How fast the lead swings when possession changes. 0.2 s here changes
## everything about how the game feels.
@export var lead_speed := 1.8
@export var dead_zone := 1.5
@export var height := 18.0
@export var distance := 30.0
@export var max_x := 44.0
@export var zoom_levels: Array[float] = [0.7, 1.0, 1.35]

var ball: Ball
var zoom_index := 1

var _focus := Vector3.ZERO
var _lead_x := 0.0


func cycle_zoom() -> void:
	zoom_index = (zoom_index + 1) % zoom_levels.size()


func snap() -> void:
	if ball == null:
		return
	_lead_x = 0.0
	_focus = Vector3(clampf(ball.global_position.x, -max_x, max_x), 0.0, ball.global_position.z * lateral_follow)
	_place()


func _process(delta: float) -> void:
	if ball == null:
		return
	var b := ball.global_position
	var attack := 0.0
	var owner := ball.owner_player as PlayerController
	if owner != null:
		attack = owner.attack_dir
	else:
		attack = clampf(ball.linear_velocity.x / 15.0, -1.0, 1.0) * 0.6
	_lead_x = lerpf(_lead_x, attack * lead, 1.0 - exp(-lead_speed * delta))

	var target_x := b.x + _lead_x
	var dx := target_x - _focus.x
	var goal_x := _focus.x
	if absf(dx) > dead_zone:
		goal_x = target_x - signf(dx) * dead_zone
	_focus.x = clampf(lerpf(_focus.x, goal_x, 1.0 - exp(-follow_speed * delta)), -max_x, max_x)
	_focus.z = lerpf(_focus.z, b.z * lateral_follow, 1.0 - exp(-follow_speed * 0.8 * delta))
	_place()


func _place() -> void:
	var z := zoom_levels[zoom_index]
	global_position = _focus + Vector3(0.0, height * z, distance * z)
	look_at(_focus + Vector3(0.0, 0.0, -2.0), Vector3.UP)
