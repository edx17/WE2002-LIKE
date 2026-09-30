extends Node3D
## Model preview: seed of the future player editor.
##
##   godot --path . res://scenes/tools/ModelPreview.tscn -- --appearance=player_001 --kit=team_a_home
##
## Shows a generated player wearing a kit under the match lighting, cycling
## through every clip. ←/→ change clip, ↑/↓ change appearance, K changes kit.

var appearances: PackedStringArray = []
var kits: PackedStringArray = []
var clips: PackedStringArray = []
var appearance_index := 0
var kit_index := 0
var clip_index := 0
var auto_cycle := true

var _holder: Node3D
var _anim: AnimationPlayer
var _label: Label
var _clip_time := 0.0


func _ready() -> void:
	appearances = _ids("appearance", "player_")
	kits = _ids("kits", "")
	clips = PackedStringArray(AnimationTimings.clips().keys())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--appearance="):
			appearance_index = maxi(0, appearances.find(arg.trim_prefix("--appearance=")))
		elif arg.begins_with("--kit="):
			kit_index = maxi(0, kits.find(arg.trim_prefix("--kit=")))
		elif arg.begins_with("--clip="):
			clip_index = maxi(0, clips.find(arg.trim_prefix("--clip=")))
			auto_cycle = false
	LookProfile.apply_to_scene(self, LookProfile.load_profile())
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.19, 0.4, 0.15)
	ground.material_override = grass
	add_child(ground)
	_holder = Node3D.new()
	add_child(_holder)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.position = Vector3(2.2, 1.5, 3.6)
	cam.look_at(Vector3(0, 0.95, 0))
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	ui.add_child(_label)
	_load_model()


func _ids(folder: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DataLoader.DATA_ROOT + folder):
		if f.ends_with(".json") and f.begins_with(prefix):
			out.append(f.get_basename())
	out.sort()
	return out


func _load_model() -> void:
	for c in _holder.get_children():
		c.queue_free()
	var id := appearances[appearance_index]
	var path := PlayerModel.model_path(id)
	if not ResourceLoader.exists(path):
		_label.text = "%s: falta el GLB, corré tools/asset_pipeline/player_generator.py" % id
		return
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.rotation.y = PI
	_holder.add_child(model)
	var kit: Variant = DataLoader.load_json("kits/%s.json" % kits[kit_index])
	PlayerModel.apply_kit(model, kit if kit is Dictionary else {})
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_play()


func _play() -> void:
	var clip := clips[clip_index]
	_clip_time = 0.0
	if _anim.has_animation(clip):
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_anim.play(clip, 0.08)
	_label.text = "%s · %s · %s   (%.2f s)\n←/→ clip · ↑/↓ jugador · K camiseta" % [
		appearances[appearance_index], kits[kit_index], clip, AnimationTimings.length(clip, 0.0)]


func _process(delta: float) -> void:
	_holder.rotation.y += delta * 0.35
	_clip_time += delta
	if auto_cycle and _clip_time > maxf(1.6, AnimationTimings.length(clips[clip_index], 1.0) * 3.0):
		clip_index = (clip_index + 1) % clips.size()
		_play()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_RIGHT:
			clip_index = (clip_index + 1) % clips.size()
			auto_cycle = false
			_play()
		KEY_LEFT:
			clip_index = posmod(clip_index - 1, clips.size())
			auto_cycle = false
			_play()
		KEY_UP, KEY_DOWN:
			appearance_index = posmod(appearance_index + (1 if event.physical_keycode == KEY_UP else -1), appearances.size())
			_load_model()
		KEY_K:
			kit_index = (kit_index + 1) % kits.size()
			_load_model()
