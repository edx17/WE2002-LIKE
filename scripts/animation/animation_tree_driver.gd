class_name AnimationTreeDriver
extends RefCounted
## Feeds the gameplay Descriptor into a real AnimationTree.
##
## Expected tree (root = AnimationNodeStateMachine), with SHORT transitions
## (0.05–0.1 s) so a change of direction never "asks for permission":
##
##   Locomotion  BlendSpace2D  x = turn (-1 right .. 1 left), y = speed 0..1
##               (Idle / Walk / Run / Sprint + lean-left / lean-right clips)
##   Ball        BlendSpace1D  Control / Dribble / Shield / Receive
##   PASS, SHOOT, HEAD, TACKLE, SLIDE        (actions)
##   FALL, GET_UP, CELEBRATE, TURN_180       (reactions)
##
## A player scene opts in simply by having an "AnimationTree" child.

var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback


func _init(animation_tree: AnimationTree) -> void:
	tree = animation_tree
	tree.active = true
	playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func apply(d: AnimationSelector.Descriptor, _p: PlayerController, _delta: float) -> void:
	var blend := Vector2(clampf(d.turn_deg / 45.0, -1.0, 1.0), d.speed_blend)
	var target := d.action
	if target == "":
		target = "Ball" if d.ball != "" else "Locomotion"
	if target == "Ball":
		tree.set("parameters/Ball/blend_position", d.speed_blend)
	else:
		tree.set("parameters/Locomotion/blend_position", blend)
	if playback != null and playback.get_current_node() != StringName(target):
		playback.travel(target)
