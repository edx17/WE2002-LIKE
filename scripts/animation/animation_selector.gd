class_name AnimationSelector
extends Node
## Gameplay → animation, never the other way around.
##
## The gameplay layer states facts ("sprinting forward, has the ball under
## control, turning 22° right"); this node turns them into clip names:
##   SPRINT_FORWARD + TURN_RIGHT + BALL_CONTROL
## and hands them to a driver: the procedural placeholder capsule, or the
## AnimationTree of a generated GLB player (see PlayerModel).

class Descriptor:
	var locomotion := "IDLE"      ## IDLE / WALK / RUN / SPRINT
	var heading := "FORWARD"      ## FORWARD (players run where they face)
	var turn := ""                ## TURN_LEFT / TURN_RIGHT
	var turn_deg := 0.0
	var ball := ""                ## BALL_CONTROL / BALL_RECEIVE
	var action := ""              ## PASS / SHOOT / TACKLE / SLIDE / HEAD / FALL / GET_UP / CELEBRATE
	var speed_blend := 0.0        ## 0 idle .. 1 top sprint
	var state_time := 0.0

	func clips() -> PackedStringArray:
		var out := PackedStringArray()
		if action != "":
			out.append(action)
		elif locomotion == "IDLE":
			out.append("IDLE")
		else:
			out.append("%s_%s" % [locomotion, heading])
		if turn != "":
			out.append(turn)
		if ball != "":
			out.append(ball)
		return out

	func _to_string() -> String:
		return " + ".join(clips())


const ACTION_NAMES := {
	PlayerController.State.PASS: "PASS",
	PlayerController.State.SHOOT: "SHOOT",
	PlayerController.State.TACKLE: "TACKLE",
	PlayerController.State.SLIDE: "SLIDE",
	PlayerController.State.HEAD: "HEAD",
	PlayerController.State.JUMP: "JUMP",
	PlayerController.State.FALL: "FALL",
	PlayerController.State.GET_UP: "GET_UP",
	PlayerController.State.CELEBRATE: "CELEBRATE",
	PlayerController.State.TURN: "TURN_180",
	PlayerController.State.DIVE: "DIVE",
}

var current := Descriptor.new()
## Any object with apply(descriptor: Descriptor, player: PlayerController, delta: float).
var driver: Object = null


func _ready() -> void:
	# Placeholder until PlayerModel attaches a generated model + AnimationTree.
	driver = PlaceholderAnimator.new((get_parent() as Node).get_node("Visual") as Node3D)


func set_driver(new_driver: Object) -> void:
	driver = new_driver
	var visual := (get_parent() as Node).get_node("Visual") as Node3D
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO


static func evaluate(p: PlayerController) -> Descriptor:
	var d := Descriptor.new()
	d.state_time = p.state_time
	d.speed_blend = clampf(p.speed / p.sprint_speed(), 0.0, 1.0)
	d.action = ACTION_NAMES.get(p.state, "")
	if d.action == "DIVE":
		d.action = "DIVE_LEFT" if DirectionResolver.signed_angle(p.facing, p.dive_velocity.normalized()) > 0.0 else "DIVE_RIGHT"
	if p.speed < 0.3:
		d.locomotion = "IDLE"
	elif p.speed < 3.0:
		d.locomotion = "WALK"
	elif p.speed <= p.jog_speed() * 1.02:
		d.locomotion = "RUN"
	else:
		d.locomotion = "SPRINT"
	d.turn_deg = p.turn_angle_deg
	if absf(p.turn_angle_deg) > 8.0 and d.locomotion != "IDLE":
		d.turn = "TURN_LEFT" if p.turn_angle_deg > 0.0 else "TURN_RIGHT"
	if p.state == PlayerController.State.CONTROL and p.state_time < 0.25:
		d.ball = "BALL_RECEIVE"
	elif p.has_ball():
		d.ball = "BALL_CONTROL"
	return d


func update(p: PlayerController, delta: float) -> void:
	current = evaluate(p)
	if driver != null:
		driver.apply(current, p, delta)
