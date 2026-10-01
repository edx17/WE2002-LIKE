extends Control
## Title screen (placeholder until the Phase 6 menus): quick match, two
## players versus / co-op, Master League. Command-line flags used by tests
## and developers (--match, --attract, --players) skip straight to a match.

const MATCH_SCENE := "res://scenes/match/Match.tscn"


func _ready() -> void:
	InputSetup.ensure_actions()
	var args := " ".join(OS.get_cmdline_user_args())
	if "--match=" in args or "--attract" in args or "--players=" in args or "--half-minutes=" in args:
		_go_match("1", true)
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UIKit.background(self)
	var title := UIKit.label(self, "WE2002-LIKE", 64, Color(1.0, 0.86, 0.2))
	title.position = Vector2(80, 70)
	UIKit.label(self, "Un Winning Eleven espiritual · sin licencias · editable", 18).position = Vector2(84, 150)
	var box := UIKit.panel(self, Rect2(80, 220, 520, 360))
	var first := UIKit.button(box, "▶  Partido amistoso (1 jugador)", func() -> void: _go_match("1"))
	UIKit.button(box, "▶  2 jugadores · versus", func() -> void: _go_match("vs"))
	UIKit.button(box, "▶  2 jugadores · cooperativo", func() -> void: _go_match("coop"))
	UIKit.button(box, "★  Master League", _go_master_league)
	UIKit.button(box, "✕  Salir", func() -> void: get_tree().quit())
	UIKit.label(box, "\n↑↓ / stick para elegir · Enter / A para aceptar", 14, Color(0.7, 0.75, 0.8))
	first.grab_focus()


func _go_match(mode: String, from_args := false) -> void:
	var m := UIKit.start_match(get_tree(), {}, mode)
	if from_args:
		m.player_mode = mode  # cmdline --players= still wins inside the match
	get_tree().current_scene = m
	queue_free()


func _go_master_league() -> void:
	get_tree().change_scene_to_file("res://scenes/career/MasterLeague.tscn")
