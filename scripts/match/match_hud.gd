class_name MatchHUD
extends CanvasLayer
## Minimal, debug-first HUD: score, power bar, big messages and a panel that
## shows what gameplay and animation layers are deciding.

var match_ctx: MatchController
var _score: Label
var _message: Label
## One name bar + power bar per human: [{name, bar_bg, bar_fill, bar_label}].
var _pad_ui: Array[Dictionary] = []
var _debug: Label
var _help: Label
var _card_panel: ColorRect
var _card_label: Label
var _card_time := 0.0
var _message_time := 0.0

const BAR_WIDTH := 260.0
const ACTION_NAMES := ["PASE", "REMATE", "FILTRADO", "GLOBO/CENTRO"]
const HELP := """MOVER  WASD / flechas / stick      SPRINT  Shift / Espacio / RB
PASE  J / A      REMATE  K / X      FILTRADO  I / Y      GLOBO  L / B      CAMBIAR JUGADOR  Q / LB
2P: flechas · PASE num1 · REMATE num2 · FILTRADO num5 · GLOBO num3 · SPRINT num0 · CAMBIO num4
Mantener = cargar potencia · soltar = patear · sin pelota = acción de primera
DEFENDER: mantener PASE = presionar · tocar PASE = quite · REMATE = barrida
T táctica (equilibrado / presión alta / repliegue) · F2 8/16 direcciones · C zoom · F3 debug · R reiniciar · F1 ayuda"""


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

	for i in 2:
		_pad_ui.append(_make_pad_ui(i))

	# Card shown by the referee: coloured card + player.
	_card_panel = ColorRect.new()
	_card_panel.size = Vector2(46, 64)
	_card_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card_panel.offset_left = -200
	_card_panel.offset_top = 70
	_card_panel.offset_right = -154
	_card_panel.offset_bottom = 134
	_card_panel.visible = false
	add_child(_card_panel)
	_card_label = _label(24, HORIZONTAL_ALIGNMENT_LEFT)
	_card_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card_label.offset_left = -140
	_card_label.offset_top = 84
	_card_label.offset_right = 300
	_card_label.visible = false




## WE-style bar under the action (position, number, name of the controlled
## player) and the power bar, for human `i` in his cursor colour.
func _make_pad_ui(i: int) -> Dictionary:
	var name := _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	name.offset_top = -48
	name.offset_bottom = -14
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.82)
	style.set_corner_radius_all(14)
	style.border_color = HumanPad.COLORS[i]
	style.set_border_width_all(2)
	name.add_theme_stylebox_override(&"normal", style)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar_bg.offset_top = -78
	bar_bg.offset_bottom = -62
	add_child(bar_bg)
	var fill := ColorRect.new()
	fill.size = Vector2(0, 16)
	bar_bg.add_child(fill)
	var bar_label := _label(14, HORIZONTAL_ALIGNMENT_LEFT, bar_bg)
	bar_label.position = Vector2(0, -22)
	return {"name": name, "bar_bg": bar_bg, "bar_fill": fill, "bar_label": bar_label}


func _layout_pad_ui(i: int, count: int) -> void:
	# One human: centred. Two: P1 left, P2 right.
	var centre := 0.0 if count == 1 else (-330.0 if i == 0 else 330.0)
	var ui := _pad_ui[i]
	(ui.name as Label).offset_left = centre - 250
	(ui.name as Label).offset_right = centre + 250
	(ui.bar_bg as ColorRect).offset_left = centre - BAR_WIDTH * 0.5
	(ui.bar_bg as ColorRect).offset_right = centre + BAR_WIDTH * 0.5


func _label(size: int, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 6)
	l.horizontal_alignment = align
	(parent if parent != null else self).add_child(l)
	return l


func show_card(card: String, p: PlayerController) -> void:
	_card_panel.color = Color(0.98, 0.85, 0.1) if card == FoulJudge.YELLOW else Color(0.85, 0.1, 0.1)
	var second := card == FoulJudge.RED and p.yellow_cards >= 1
	_card_label.text = "%s %d  %s%s" % [p.role, p.stats.number, p.stats.name, "  (2ª amarilla)" if second else ""]
	_card_time = 2.5


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
	_score.text = "%s  %d - %d  %s     %d'" % [names[0], match_ctx.score[0], match_ctx.score[1], names[1], int(match_ctx.clock)]

	_message_time -= delta
	_message.visible = _message_time > 0.0
	_card_time -= delta
	_card_panel.visible = _card_time > 0.0
	_card_label.visible = _card_time > 0.0

	var pads := match_ctx.pads
	for i in _pad_ui.size():
		var ui := _pad_ui[i]
		var pad: HumanPad = pads[i] if i < pads.size() else null
		var pl: PlayerController = pad.player if pad != null else null
		(ui.name as Label).visible = pl != null
		(ui.bar_bg as ColorRect).visible = false
		if pl == null:
			continue
		_layout_pad_ui(i, pads.size())
		(ui.name as Label).text = "%s  %s   %d   %s" % [pad.label if pads.size() > 1 else "", pl.role, pl.stats.number, pl.stats.name]
		var charging := pl.intent.charging_action
		if charging != PlayerIntent.NONE:
			(ui.bar_bg as ColorRect).visible = true
			(ui.bar_fill as ColorRect).size.x = BAR_WIDTH * pl.intent.charge
			(ui.bar_fill as ColorRect).color = Color(0.95, 0.25, 0.1) if pl.intent.charge > 0.88 and charging == PlayerIntent.Action.SHOOT else pad.color
			(ui.bar_label as Label).text = ACTION_NAMES[charging]

	var h := match_ctx.human
	if h == null:
		_debug.text = ""
		return
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
