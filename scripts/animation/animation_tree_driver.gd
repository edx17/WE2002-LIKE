class_name AnimationTreeDriver
extends RefCounted
## Feeds the gameplay Descriptor into the AnimationTree built by PlayerModel:
##
##   Locomotion  BlendSpace1D by speed (IDLE / WALK / RUN / SPRINT)
##   PASS, SHOOT, HEAD, TACKLE, SLIDE, FALL, GET_UP, TURN_180, CELEBRATE
##
## Transitions are 0.05–0.1 s cross-fades, so a change of direction never
## "asks for permission". Turning lean is added procedurally on top.

var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var visual: Node3D
var _current := &"Locomotion"
var _last_state_time := 0.0
var _roll := 0.0
## > 0: poses are sampled at this rate and held in between (the stepped,
## "robotic" motion of the PS1 era). 0 = smooth, every frame.
var pose_fps := 0.0
var _pose_acc := 0.0


func _init(animation_tree: AnimationTree, visual_node: Node3D, stepped_fps := 0.0) -> void:
	tree = animation_tree
	visual = visual_node
	playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	pose_fps = stepped_fps
	if pose_fps > 0.0:
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func apply(d: AnimationSelector.Descriptor, _p: PlayerController, delta: float) -> void:
	tree.set("parameters/Locomotion/blend_position", d.speed_blend)
	var target := StringName(d.action) if d.action != "" else &"Locomotion"
	if not tree.tree_root.has_node(target):
		target = &"Locomotion"
	if playback != null:
		if target != _current:
			playback.travel(target)
		elif target != &"Locomotion" and d.state_time < _last_state_time:
			playback.start(target)  # same action again (pass after pass)
	_current = target
	_last_state_time = d.state_time

	var roll := deg_to_rad(clampf(d.turn_deg, -60.0, 60.0) * 0.2) * d.speed_blend
	if pose_fps > 0.0:
		_pose_acc += delta
		var step := 1.0 / pose_fps
		if _pose_acc < step:
			return  # hold the pose (and the lean) until the next step
		tree.advance(_pose_acc)
		_roll = lerpf(_roll, roll, 1.0 - exp(-14.0 * _pose_acc))
		_pose_acc = 0.0
	else:
		_roll = lerpf(_roll, roll, 1.0 - exp(-14.0 * delta))
	visual.rotation = Vector3(0.0, 0.0, _roll)
	visual.position.y = 0.0
