class_name PlaceholderAnimator
extends RefCounted
## Procedural stand-in for real animations: leans, bobs and tilts the capsule
## so the gameplay states are readable before any rig exists. It consumes the
## same Descriptor an AnimationTree will.

var visual: Node3D
var _phase := 0.0
var _pitch := 0.0
var _roll := 0.0
var _height := 0.0


func _init(visual_node: Node3D) -> void:
	visual = visual_node


func apply(d: AnimationSelector.Descriptor, _p: PlayerController, delta: float) -> void:
	var pitch := -d.speed_blend * deg_to_rad(12.0)
	var roll := deg_to_rad(clampf(d.turn_deg, -60.0, 60.0) * 0.25) * d.speed_blend
	var height := 0.0
	_phase += delta * lerpf(6.0, 16.0, d.speed_blend)
	var bob := absf(sin(_phase)) * 0.06 * d.speed_blend

	match d.action:
		"PASS", "SHOOT":
			# Wind back, then snap forward through the ball.
			pitch = deg_to_rad(12.0) if d.state_time < 0.1 else deg_to_rad(-22.0)
		"HEAD":
			pitch = deg_to_rad(-25.0)
			height = 0.15
		"TACKLE":
			pitch = deg_to_rad(-18.0)
			height = -0.1
		"SLIDE":
			pitch = deg_to_rad(70.0)
			height = -0.55
		"FALL":
			pitch = deg_to_rad(-80.0)
			height = -0.6
		"GET_UP":
			pitch = deg_to_rad(-35.0)
			height = -0.25
		"TURN_180":
			pitch = deg_to_rad(8.0)
			roll *= 1.5
		"CELEBRATE":
			height = absf(sin(_phase * 0.7)) * 0.5
	var k := 1.0 - exp(-18.0 * delta)
	_pitch = lerpf(_pitch, pitch, k)
	_roll = lerpf(_roll, roll, k)
	_height = lerpf(_height, height, k)
	visual.rotation = Vector3(_pitch, 0.0, _roll)
	visual.position.y = _height + bob
