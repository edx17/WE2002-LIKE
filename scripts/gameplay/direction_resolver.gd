class_name DirectionResolver
extends RefCounted
## Turns raw stick/keyboard input into a deliberately "digital" direction.
##
## WE-style movement is NOT free 360°: the stick is snapped to 8 (classic) or
## 16 (finer) directions. That rigidity is a feature: it is what makes the
## player respond instantly and predictably.

const DEADZONE := 0.25


## Snaps a raw input vector (screen space, y down) to one of `steps` unit
## directions. Returns Vector2.ZERO inside the deadzone.
static func quantize(raw: Vector2, steps: int) -> Vector2:
	if raw.length() < DEADZONE:
		return Vector2.ZERO
	var step := TAU / float(steps)
	return Vector2.from_angle(snappedf(raw.angle(), step))


## Index (0..steps-1, 0 = screen right, counter-clockwise on screen is
## negative angle) of a quantized direction, or -1 for no direction.
static func index_of(dir: Vector2, steps: int) -> int:
	if dir == Vector2.ZERO:
		return -1
	return posmod(roundi(dir.angle() / (TAU / float(steps))), steps)


## Screen/stick space -> pitch space. Right on screen is +X (towards the right
## goal), up on screen is -Z (away from the broadcast camera).
static func to_world(dir: Vector2) -> Vector3:
	return Vector3(dir.x, 0.0, dir.y)


## Pitch space -> stick space (inverse of to_world, ignores height).
static func to_stick(dir: Vector3) -> Vector2:
	return Vector2(dir.x, dir.z)


## Signed angle (radians) from `from` to `to` around +Y.
## Positive = turning left (counter-clockwise seen from above).
static func signed_angle(from: Vector3, to: Vector3) -> float:
	return atan2(from.cross(to).dot(Vector3.UP), from.dot(to))


## Rotates a flat unit vector around +Y by at most `max_step` radians towards
## `target`.
static func rotate_towards(from: Vector3, target: Vector3, max_step: float) -> Vector3:
	var diff := signed_angle(from, target)
	return from.rotated(Vector3.UP, clampf(diff, -max_step, max_step)).normalized()


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
