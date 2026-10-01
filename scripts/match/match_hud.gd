class_name MatchHUD
extends CanvasLayer
## Minimal, debug-first HUD: score, power bar, big messages and a panel that
## shows what gameplay and animation layers are deciding.

var match_ctx: MatchController
var _score: Label
var _message: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _bar_label: Label
var _debug: Label
var _help: Label
var _name_bar: Label
var _message_time := 0.0

const BAR_WIDTH := 260.0
const ACTION_NAMES := ["PASE", "REMATE", "FILTRADO", "GLOBO/CENTRO"]
const HELP := """MOVER  WASD / flechas / stick      SPRINT  Shift / Espacio / RB
PASE  J / A      REMATE  K / X      FILTRADO  I / Y      GLOBO  L / B      CAMBIAR JUGADOR  Q / LB
Mantener = cargar potencia · soltar = patear · sin pelota = acción de primera
DEFENDER: mantener PASE = presionar · tocar PASE = quite · REMATE = barrida
F2 8/16 direcciones · C zoom cámara · F3 debug · R reiniciar · F1 ayuda"""


func setup(m: MatchController) -> void:
	match_ctx = m
	_score = _label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score.position.y = 10
	_message = _label(48, HORIZONTAL_ALIGNMENT_CENTER)
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_debug = _label(14, HORIZONTAL_ALIGNMENT_LEFT)
	_debug.position = Vector2(12, 12)
	_debug.visible = false  # F3
	_help = _label(14, HORIZONTAL_ALIGNMENT_LEFT)
	_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.offset_left = 12
	_help.offset_top = -12
	_help.offset_bottom = -12
	_help.text = HELP
	_help.visible = false

	# WE-style bar under the action: position, number, name of the controlled player.
	_name_bar = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	_name_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name_bar.offset_left = -260
	_name_bar.offset_right = 260
	_name_bar.offset_top = -48
	_name_bar.offset_bottom = -14
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.12, 0.14, 0.82)
	bar_bg.set_corner_radius_all(14)
	bar_bg.border_color = Color(0.7, 0.7, 0.72)
	bar_bg.set_border_width_all(2)
	_name_bar.add_theme_stylebox_override(&"normal", bar_bg)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0, 0, 0, 0.6)
	_bar_bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bar_bg.offset_left = -BAR_WIDTH - 24
	_bar_bg.offset_right = -24
	_bar_bg.offset_top = -40
	_bar_bg.offset_bottom = -24
	add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.95, 0.8, 0.1)
	_bar_fill.size = Vector2(0, 16)
	_bar_bg.add_child(_bar_fill)
	_bar_label = _label(14, HORIZONTAL_ALIGNMENT_LEFT, _bar_bg)
	_bar_label.position = Vector2(0, -22)


func _label(size: int, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 6)
	l.horizontal_alignment = align
	(parent if parent != null else self).add_child(l)
	return l


func flash(text: String, seconds: float, big: bool) -> void:
	_message.text = text
	_message.add_theme_font_size_override(&"font_size", 48 if big else 28)
	_message_time = seconds


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		_debug.visible = not _debug.visible
	elif event.is_action_pressed(&"toggle_help"):
		_help.visible = not _help.visible


func _process(delta: float) -> void:
	if match_ctx == null:
		return
	var names := []
	for t in 2:
		names.append(str(match_ctx.team_data[t].get("short", "EQ%d" % (t + 1))))
	var secs := int(match_ctx.clock)
	_score.text = "%s  %d - %d  %s     %02d:%02d" % [names[0], match_ctx.score[0], match_ctx.score[1], names[1], secs / 60, secs % 60]

	_message_time -= delta
	_message.visible = _message_time > 0.0

	var h := match_ctx.human
	_name_bar.visible = h != null
	if h != null:
		_name_bar.text = "%s   %d   %s" % [h.role, h.stats.number, h.stats.name]
	if h == null:
		_bar_bg.visible = false
		_debug.text = ""
		return
	var charging := h.intent.charging_action
	_bar_bg.visible = charging != PlayerIntent.NONE
	if _bar_bg.visible:
		_bar_fill.size.x = BAR_WIDTH * h.intent.charge
		_bar_fill.color = Color(0.95, 0.25, 0.1) if h.intent.charge > 0.88 and charging == PlayerIntent.Action.SHOOT else Color(0.95, 0.8, 0.1)
		_bar_label.text = ACTION_NAMES[charging]

	if _debug.visible:
		var ai_lines := ""
		for p in match_ctx.players:
			if p.input_source is PlayerAI:
				ai_lines += "\nIA %s: %s · %s" % [p.stats.name, PlayerAI.MODE_NAMES[(p.input_source as PlayerAI).mode],
					PlayerController.State.keys()[p.state]]
		_debug.text = "ESTADO  %s\nANIM    %s\nDIR     %d direcciones · vel %.1f m/s · balance %.2f\nCONTACTO %s\nÚLTIMO  %s%s" % [
			PlayerController.State.keys()[h.state],
			str(h.animation_selector.current),
			match_ctx.direction_steps, h.speed, h.balance_modifier(),
			BallInteraction.ZONE_NAMES[h.interaction.last_zone],
			match_ctx.last_kick_text, ai_lines]
