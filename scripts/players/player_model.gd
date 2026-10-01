class_name PlayerModel
extends RefCounted
## Dresses a PlayerController with a generated model (assets/players/generated)
## and its team kit (assets/kits), then wires an AnimationTree built in code.
## Players without a generated model keep the placeholder capsule.

const MODEL_DIR := "res://assets/players/generated/"
## Hand-made models (docs/BLENDER_GUIA.md) override the generated ones.
const CUSTOM_DIR := "res://assets/players/custom/"
const KIT_DIR := "res://assets/kits/"
## Placeholder meshes replaced by the model.
const PLACEHOLDER_PARTS := ["LegLeft", "LegRight", "Shorts", "Body", "Head"]


static func model_path(appearance: String) -> String:
	var custom := CUSTOM_DIR + appearance + ".glb"
	if ResourceLoader.exists(custom):
		return custom
	return MODEL_DIR + appearance + ".glb"


## Returns true when a real model was attached.
static func attach(player: PlayerController, appearance: String, kit: Dictionary, number := 0) -> bool:
	if appearance == "" or not ResourceLoader.exists(model_path(appearance)):
		return false
	var scene := load(model_path(appearance)) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	# Generated players face Blender -Y = glTF +Z; gameplay forward is -Z.
	model.rotation.y = PI
	var visual := player.get_node("Visual") as Node3D
	visual.add_child(model)
	for part: String in PLACEHOLDER_PARTS:
		(visual.get_node(part) as Node3D).visible = false
	apply_kit(model, kit, number)

	var anim_player := _find(model, "AnimationPlayer") as AnimationPlayer
	if anim_player != null:
		var tree := build_tree(anim_player)
		tree.name = "AnimationTree"
		player.add_child(tree)
		tree.anim_player = tree.get_path_to(anim_player)
		tree.active = true
		player.animation_selector.set_driver(AnimationTreeDriver.new(tree, visual))
	return true


## Swap kit materials by name: the same model wears every team's kit.
## Kits choose short or long sleeves; the shirt carries the player's number.
static func apply_kit(model: Node, kit: Dictionary, number := 0) -> void:
	var long_sleeves := str(kit.get("sleeves", "short")) == "long"
	for shirt_name: String in ["Shirt_Short", "Shirt_Long"]:
		var shirt_node := model.find_child(shirt_name, true, false) as Node3D
		if shirt_node != null:
			shirt_node.visible = (shirt_name == "Shirt_Long") == long_sleeves
	var shirt := StandardMaterial3D.new()
	shirt.roughness = 1.0
	shirt.metallic_specular = 0.0
	shirt.cull_mode = BaseMaterial3D.CULL_DISABLED  # see the inside through sleeves/hem
	shirt.albedo_texture = KitTexture.build(kit, number)
	shirt.texture_repeat = true
	shirt.texture_filter = texture_filter()
	var shorts := _cloth(Color.html(str(kit.get("shorts", "#ffffff"))))
	var socks := _cloth(Color.html(str(kit.get("socks", kit.get("primary", "#cccccc")))))
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			var mat_name := mat.resource_name if mat != null else ""
			match mat_name:
				"KIT_SHIRT":
					mi.set_surface_override_material(i, shirt)
				"KIT_SHORTS":
					mi.set_surface_override_material(i, shorts)
				"KIT_SOCKS":
					mi.set_surface_override_material(i, socks)
				"FACE":
					# Painted face: keep the pixels crisp like the original.
					var face := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					face.texture_filter = texture_filter()
					mi.set_surface_override_material(i, face)


## Classic look: low-res textures shown unfiltered (data/look: players.texture_filter).
static func texture_filter() -> BaseMaterial3D.TextureFilter:
	var players: Dictionary = LookProfile.load_profile().get("players", {})
	if str(players.get("texture_filter", "nearest")) == "nearest":
		return BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func _cloth(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Root state machine: Locomotion (BlendSpace1D by speed) + one state per
## action/reaction clip. Transitions are short cross-fades and only happen
## when gameplay asks for them (travel); animation never drives gameplay.
static func build_tree(anim_player: AnimationPlayer) -> AnimationTree:
	for clip: String in AnimationTimings.clips():
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = \
				Animation.LOOP_LINEAR if AnimationTimings.loops(clip) else Animation.LOOP_NONE

	var sm := AnimationNodeStateMachine.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 1.0
	for point: Array in [["IDLE", 0.0], ["WALK", 0.3], ["RUN", 0.68], ["SPRINT", 1.0]]:
		var a := AnimationNodeAnimation.new()
		a.animation = point[0]
		loco.add_blend_point(a, point[1])
	sm.add_node(&"Locomotion", loco)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"Locomotion", start)

	for clip: String in AnimationTimings.clips():
		if clip in ["IDLE", "WALK", "RUN", "SPRINT"] or not anim_player.has_animation(clip):
			continue
		var a := AnimationNodeAnimation.new()
		a.animation = clip
		sm.add_node(StringName(clip), a)
		sm.add_transition(&"Locomotion", StringName(clip), _transition(0.05))
		sm.add_transition(StringName(clip), &"Locomotion", _transition(0.1))

	var tree := AnimationTree.new()
	tree.tree_root = sm
	return tree


static func _transition(xfade: float) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	return t


static func _find(node: Node, type: String) -> Node:
	var found := node.find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null
