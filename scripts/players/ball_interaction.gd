class_name BallInteraction
extends Node
## Body–ball contact. Where the ball arrives (foot, thigh, chest, head, body)
## decides how it can be controlled, and the player's attributes decide how
## well. Also runs the dribble: the ball is never glued, it is pushed.
##
##          head ●
##     shoulder  │  shoulder
##            ┌─────┐
##            │TORSO│
##            └─────┘
##          ●         ●
##      left foot   right foot

enum Zone { NONE, FOOT, THIGH, CHEST, HEAD, BODY, HANDS }

const ZONE_NAMES := {
	Zone.NONE: "", Zone.FOOT: "PIE", Zone.THIGH: "MUSLO", Zone.CHEST: "PECHO",
	Zone.HEAD: "CABEZA", Zone.BODY: "CUERPO", Zone.HANDS: "MANOS",
}
## Upper bound of each zone, height of the ball centre above the player's feet.
const ZONE_TOP := [
	[Zone.FOOT, 0.45], [Zone.THIGH, 0.95], [Zone.CHEST, 1.45], [Zone.HEAD, 2.0],
]
## Horizontal reach per zone (m).
const ZONE_REACH := {Zone.FOOT: 0.8, Zone.THIGH: 0.55, Zone.CHEST: 0.5, Zone.HEAD: 0.5, Zone.BODY: 0.45}
## How controllable a ball is in each zone.
const ZONE_CONTROL := {Zone.FOOT: 1.0, Zone.THIGH: 0.85, Zone.CHEST: 0.8, Zone.HEAD: 0.4, Zone.BODY: 0.35}
## Below this reception quality the ball bounces off instead of being controlled.
const CONTROL_THRESHOLD := 0.3
## Possession is lost if the ball gets this far from the dribbler.
const LOSE_DISTANCE := 1.7

var player: PlayerController
var last_zone: int = Zone.NONE


func _ready() -> void:
	player = get_parent() as PlayerController


static func zone_for_height(height: float) -> int:
	if height < -0.2:
		return Zone.NONE
	for entry: Array in ZONE_TOP:
		if height < entry[1]:
			return entry[0]
	return Zone.NONE


static func receive_quality(zone: int, relative_speed: float, control_n: float, technique_n: float) -> float:
	if zone == Zone.NONE:
		return 0.0
	var base: float = ZONE_CONTROL[zone] * lerpf(0.55, 1.0, control_n)
	var speed_penalty := clampf((relative_speed - 6.0) / 30.0, 0.0, 0.6) * (1.2 - technique_n)
	return clampf(base - speed_penalty, 0.0, 1.0)


## Zone the ball would touch right now, or NONE if out of reach.
func contact_zone(ball_pos: Vector3) -> int:
	var rel := ball_pos - player.global_position
	if player.is_keeper and player.match_ctx != null \
			and player.match_ctx.in_penalty_area(ball_pos, -player.attack_dir):
		# Keepers use their hands in their own box: longer reach, up to the bar.
		var flat := Vector2(rel.x, rel.z).length()
		var diving := player.state == PlayerController.State.DIVE
		if rel.y < (1.5 if diving else 2.45) and flat < (1.25 if diving else 0.95) and rel.y > -0.2:
			return Zone.HANDS
	var zone := zone_for_height(rel.y)
	if zone == Zone.NONE:
		return Zone.NONE
	if Vector2(rel.x, rel.z).length() > float(ZONE_REACH[zone]):
		return Zone.NONE
	return zone


## Resolves a loose ball reaching this player. Returns "control",
## "one_touch" or "deflect".
func receive(ball: Ball) -> String:
	var zone := contact_zone(ball.global_position)
	last_zone = zone
	var rel_v := ball.current_velocity() - player.velocity
	var rel_speed := rel_v.length()

	if zone == Zone.HANDS:
		return _keeper_save(ball, rel_speed)

	if player.has_queued_action() and (zone == Zone.FOOT or zone == Zone.HEAD):
		player.execute_queued_action(zone == Zone.HEAD, rel_speed)
		return "one_touch"

	var stats := player.stats
	var q := receive_quality(zone, rel_speed, stats.n(&"control"), stats.n(&"technique"))
	if q >= CONTROL_THRESHOLD:
		# First touch: the worse the reception, the further the ball squirms away.
		var heavy := (1.0 - q) * rel_speed * 0.35
		var first_touch := DirectionResolver.flat(player.velocity) + player.facing * heavy
		if ball.global_position.y > Ball.RADIUS + 0.1:
			first_touch.y = -1.0
		ball.take_possession(player, first_touch)
		player.on_ball_received(zone, q)
		return "control"

	# Could not tame it: bounce off the body.
	var centre := Vector3(player.global_position.x, ball.global_position.y, player.global_position.z)
	var n := (ball.global_position - centre).normalized()
	if n.length_squared() < 0.5:
		n = -rel_v.normalized()
	var v := ball.current_velocity()
	var vn := rel_v.dot(n)
	if vn < 0.0:
		v -= (1.35 * vn) * n
	ball.kick(v * 0.75, ball.spin * 0.3, player)
	return "deflect"


## Catch or parry. Hard, well-struck shots are parried away from goal.
func _keeper_save(ball: Ball, rel_speed: float) -> String:
	var gk := player.stats.n(&"goalkeeping")
	var diving := player.state == PlayerController.State.DIVE
	var q := gk * (1.0 - clampf((rel_speed - 9.0) / 30.0, 0.0, 0.7)) * (0.82 if diving else 1.0)
	if q > 0.42:
		ball.hold(player)
		player.match_ctx.on_keeper_save(player, true)
		return "control"
	var away := Vector3(player.attack_dir, 0.0, signf(ball.global_position.z - player.global_position.z))
	ball.kick(away.normalized() * rel_speed * 0.35 + Vector3.UP * 2.5, Vector3.ZERO, player)
	player.match_ctx.on_keeper_save(player, false)
	return "deflect"


## Dribble step. Returns false when possession is lost.
func dribble(ball: Ball) -> bool:
	var p := player
	var flat_dist := DirectionResolver.flat(ball.global_position - p.global_position).length()
	if flat_dist > LOSE_DISTANCE:
		return false
	var control_n := p.stats.n(&"control")
	var speed_ratio := clampf(p.speed / p.sprint_speed(), 0.0, 1.0)
	var sprinting := p.is_sprinting()
	# Sprinting = longer touches; poor control = longer still.
	var dist := lerpf(0.55, 0.85, speed_ratio)
	if sprinting:
		dist += 0.4 * (1.1 - control_n)
	var desired_pos := p.global_position + p.facing * dist
	var err := DirectionResolver.flat(desired_pos - ball.global_position)
	var desired_v := DirectionResolver.flat(p.velocity) + err * 7.0
	# ball_control_strength ≈ 0.55..0.92, lower when sprinting.
	var strength := lerpf(0.55, 0.92, control_n) * (0.8 if sprinting else 1.0)
	ball.control(desired_v, strength * 28.0)
	return true


## 1 = the ball sits on the sweet spot in front of the kicking foot.
func contact_quality(ball: Ball, kick_dir: Vector3) -> float:
	var ideal := player.global_position + player.facing * 0.55
	var err := DirectionResolver.flat(ball.global_position - ideal).length()
	var q := 1.0 - clampf((err - 0.15) / 0.7, 0.0, 0.7)
	var height := ball.global_position.y - Ball.RADIUS
	if height > 0.25:
		q *= lerpf(1.0, 0.7, clampf(height, 0.0, 1.0))
	var angle := absf(DirectionResolver.signed_angle(player.facing, kick_dir))
	if angle > deg_to_rad(60.0):
		q *= lerpf(1.0, 0.65, clampf((angle - deg_to_rad(60.0)) / deg_to_rad(120.0), 0.0, 1.0))
	return clampf(q, 0.2, 1.0)


## True when the ball sits on the side of the player's weaker foot.
func is_weak_foot(ball: Ball) -> bool:
	var right := player.facing.cross(Vector3.UP)
	var side := (ball.global_position - player.global_position).dot(right)
	if player.stats.preferred_foot == "left":
		return side > 0.08
	return side < -0.08
