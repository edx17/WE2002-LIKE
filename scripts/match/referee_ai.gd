class_name RefereeAI
extends RefCounted
## The referee runs the classic diagonal: a few metres to the side of play,
## 12-18 m from the ball, never in a passing lane, never touching the ball.
## Drives a PlayerController (same movement and animation as the players).

var _think := 0.0
var _move := Vector2.ZERO
var _sprint := false


func fill(intent: PlayerIntent, p: PlayerController, delta: float) -> void:
	intent.begin_frame()
	_think -= delta
	if _think <= 0.0:
		_think = 0.25
		var b := p.ball.global_position
		# Diagonal from one corner flag to the other: stay on the opposite side
		# of the ball relative to the pitch centre line, a bit behind it.
		var side := -signf(b.z) if absf(b.z) > 4.0 else 1.0
		var target := Vector3(clampf(b.x - signf(b.x) * 6.0, -45.0, 45.0), 0.0,
			clampf(b.z + side * 13.0, -PitchBuilder.HALF_WIDTH + 3.0, PitchBuilder.HALF_WIDTH - 3.0))
		var to := DirectionResolver.flat(target - p.global_position)
		_move = DirectionResolver.to_stick(to).normalized() if to.length() > 2.0 else Vector2.ZERO
		_sprint = to.length() > 12.0
	intent.move = _move
	intent.sprint = _sprint
