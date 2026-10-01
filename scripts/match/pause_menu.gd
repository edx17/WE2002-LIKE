class_name PauseMenu
extends CanvasLayer
## Esc / Start: pauses the match. Resume, tactics, formation, substitutions
## (applied at the next stoppage, max 3), restart, quit.
## Navigate with the movement keys/stick, PASS confirms, SHOOT goes back.

const FORMATIONS := ["4-4-2", "4-3-3", "3-5-2"]

var match_ctx: MatchController
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _hint: Label
var _items: Array[Dictionary] = []
var _index := 0
var _screen := "main"
var _sub_out: PlayerController = null


func setup(m: MatchController) -> void:
	match_ctx = m
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	style.border_color = Color(0.75, 0.75, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override(&"panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	_panel.add_child(box)
	_title = _label(28)
	box.add_child(_title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_hint = _label(14)
	_hint.modulate = Color(0.8, 0.8, 0.85)
	box.add_child(_hint)
	visible = false


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	return l


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if match_ctx.human == null:
		return
	visible = true
	get_tree().paused = true
	_show("main")


func close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_menu"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed(&"move_down"):
		_index = (_index + 1) % _items.size()
		_render()
	elif event.is_action_pressed(&"move_up"):
		_index = posmod(_index - 1, _items.size())
		_render()
	elif event.is_action_pressed(&"pass") or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ENTER):
		var cb: Callable = _items[_index].action
		cb.call()
	elif event.is_action_pressed(&"shoot"):
		if _screen == "main":
			close()
		else:
			_show("main")
	get_viewport().set_input_as_handled()


func _show(screen: String) -> void:
	_screen = screen
	_items.clear()
	_index = 0
	var m := match_ctx
	var team := m.human.team
	var brain := m.brain_for(team)
	match screen:
		"main":
			_title.text = "PAUSA   %s %d - %d %s   %d'" % [m.team_data[0].get("short", ""), m.score[0], m.score[1],
				m.team_data[1].get("short", ""), int(m.clock)]
			_items.append({"text": "Reanudar", "action": close})
			if brain != null:
				_items.append({"text": "Táctica: %s" % brain.tactics.name, "action": func() -> void:
					m.cycle_tactics()
					_show("main")})
				_items.append({"text": "Formación: %s" % brain.formation.name, "action": func() -> void:
					var i := FORMATIONS.find(brain.formation.name)
					brain.formation = Formation.load_id(FORMATIONS[(i + 1) % FORMATIONS.size()])
					_show("main")})
				var left: int = m.max_substitutions - int(m.subs_used[team]) - m._queued_count(team)
				_items.append({"text": "Cambios (%d disponibles)" % left, "action": func() -> void: _show("subs_out")})
			_items.append({"text": "Reiniciar partido", "action": func() -> void:
				close()
				m.restart_match()})
			_items.append({"text": "Salir del juego", "action": func() -> void: get_tree().quit()})
			_hint.text = "↑↓ elegir · PASE confirmar · REMATE volver"
		"subs_out":
			_title.text = "¿QUIÉN SALE?"
			for p in m.players:
				if p.team != team:
					continue
				var tag := ""
				if p.injured:
					tag = "  LESIONADO"
				for q: Dictionary in m.queued_subs:
					if q.out == p:
						tag = "  (sale en la próxima detención)"
				_items.append({"text": "%-4s %2d  %-12s  energía %3d%%%s" % [p.role, p.stats.number, p.stats.name, roundi(p.stamina * 100.0), tag],
					"action": func() -> void:
						_sub_out = p
						_show("subs_in")})
			_hint.text = "Los cambios se hacen en la próxima pelota parada"
		"subs_in":
			_title.text = "¿QUIÉN ENTRA por %s?" % _sub_out.stats.name
			for id: String in m.bench[team]:
				var st := DataLoader.load_player(id)
				_items.append({"text": "%-4s %2d  %s" % [st.position, st.number, st.name], "action": func() -> void:
					if m.request_substitution(_sub_out, id):
						m.hud.flash("CAMBIO PEDIDO: ENTRA %s" % st.name.to_upper(), 1.5, false)
					_show("main")})
			if _items.is_empty():
				_items.append({"text": "(no quedan suplentes)", "action": func() -> void: _show("main")})
	_render()


func _render() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in _items.size():
		var l := _label(20)
		l.text = ("▶ " if i == _index else "   ") + str(_items[i].text)
		if i == _index:
			l.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.2))
		_list.add_child(l)
