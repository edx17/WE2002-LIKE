class_name UIKit
extends RefCounted
## Tiny helpers for the placeholder menus (the real WE-style UI is Phase 6).

static func panel(parent: Node, rect: Rect2) -> VBoxContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.13, 0.94)
	style.border_color = Color(0.55, 0.6, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	p.add_theme_stylebox_override(&"panel", style)
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	p.add_child(box)
	return box


static var _mono: SystemFont = null


## Monospaced font for tables (columns line up).
static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Courier New", "monospace"])
	return _mono


static func label(parent: Node, text: String, size := 16, color := Color(0.92, 0.93, 0.96), monospace := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	if monospace:
		l.add_theme_font_override(&"font", mono())
	l.add_theme_color_override(&"font_color", color)
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, action: Callable, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override(&"font_size", size)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	parent.add_child(b)
	return b


static func background(parent: Node) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.22, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	for i in 14:
		var stripe := ColorRect.new()
		stripe.color = Color(0.11, 0.26, 0.14) if i % 2 == 0 else Color(0.09, 0.22, 0.12)
		stripe.anchor_left = i / 14.0
		stripe.anchor_right = (i + 1) / 14.0
		stripe.anchor_bottom = 1.0
		parent.add_child(stripe)


## Starts a match on top of the tree, replacing the current scene.
static func start_match(tree: SceneTree, setup: Dictionary, players_mode: String, match_id := "stage4_partido") -> MatchController:
	var m := (load("res://scenes/match/Match.tscn") as PackedScene).instantiate() as MatchController
	m.setup_override = setup
	m.match_id = match_id
	m.player_mode = players_mode
	tree.root.add_child(m)
	return m
