extends Control
## Master League screen (placeholder UI until Phase 6): club, points, next
## match, division table, squad, news; play / simulate / transfers / save.

var ml: MasterLeague
var _match: MatchController = null
var _root: Control
var _view := "hub"


func _ready() -> void:
	InputSetup.ensure_actions()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ml = MasterLeague.load_slot(1)
	if ml == null:
		ml = MasterLeague.new_career()
		ml.save_slot(1)
	_render()


func _render() -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	UIKit.background(_root)
	if _view == "market":
		_render_market()
	else:
		_render_hub()


func _render_hub() -> void:
	var st := ml.state
	var me := ml.club(st.user_club)
	var head := UIKit.panel(_root, Rect2(20, 14, 1240, 64))
	UIKit.label(head, "MASTER LEAGUE · %s · Temporada %d (%d) · %s División · %d PUNTOS" % [
		me.name, int(st.season), int(st.year), "Primera" if ml.user_division() == "1" else "Segunda", int(st.points)], 22,
		Color(1.0, 0.86, 0.2))
	# Next match + actions.
	var left := UIKit.panel(_root, Rect2(20, 90, 400, 330))
	var fx := ml.user_fixture()
	var ev := ml.current_event()
	if fx.is_empty():
		UIKit.label(left, ("Esta semana: %s\n(no jugás)" % ml._event_name(ev)) if not ev.is_empty() else "Temporada terminada", 18)
	else:
		UIKit.label(left, fx.competition, 16, Color(0.7, 0.8, 1.0))
		UIKit.label(left, "%s\n      vs\n%s" % [ml.club(fx.home).name, ml.club(fx.away).name], 20)
	var play := UIKit.button(left, "▶  Jugar partido", _play_match)
	play.disabled = fx.is_empty()
	UIKit.button(left, "⏩  Simular semana", _simulate)
	UIKit.button(left, "💰  Fichajes", func() -> void:
		_view = "market"
		_render())
	UIKit.button(left, "💾  Guardar", func() -> void:
		ml.save_slot(1)
		_render())
	UIKit.button(left, "⌂  Menú principal", func() -> void: get_tree().change_scene_to_file("res://scenes/menu/Title.tscn"))
	(play if not play.disabled else left.get_child(left.get_child_count() - 4) as Button).grab_focus()
	# Table.
	var table := UIKit.panel(_root, Rect2(430, 90, 400, 330))
	UIKit.label(table, "%s DIVISIÓN" % ("PRIMERA" if ml.user_division() == "1" else "SEGUNDA"), 18, Color(1.0, 0.86, 0.2))
	UIKit.label(table, "#   Club                     PJ  DG   Pts", 14, Color(0.7, 0.75, 0.8), true)
	var rows := Competition.standings(st.leagues[ml.user_division()].table)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var c := ml.club(r.team)
		var col := Color(1.0, 0.86, 0.2) if r.team == st.user_club else (Color(0.6, 1.0, 0.6) if i < 2 and ml.user_division() == "2" else Color(0.92, 0.93, 0.96))
		UIKit.label(table, "%-3d %-24s %2d %+3d  %3d" % [i + 1, c.name.left(24), int(r.played), int(r.gf) - int(r.ga), int(r.points)], 14, col, true)
	# Squad.
	var squad := UIKit.panel(_root, Rect2(840, 90, 420, 610))
	UIKit.label(squad, "PLANTEL", 18, Color(1.0, 0.86, 0.2))
	UIKit.label(squad, "Pos  #  Nombre            Edad OVR  Estado", 14, Color(0.7, 0.75, 0.8), true)
	var lu := ml.lineup(st.user_club)
	var starters := {}
	for e: Dictionary in lu.xi:
		starters[e.pid] = true
	var ids: Array = me.squad.duplicate()
	ids.sort_custom(func(a: String, b: String) -> bool: return Rating.overall(ml.player(a)) > Rating.overall(ml.player(b)))
	for pid: String in ids:
		var p := ml.player(pid)
		var status := ""
		if int(p.get("injury_weeks", 0)) > 0:
			status = "lesión %d" % int(p.injury_weeks)
		elif int(p.get("suspended", 0)) > 0:
			status = "suspendido"
		elif starters.has(pid):
			status = "titular"
		UIKit.label(squad, "%-4s %2d  %-17s %2d   %2d   %s" % [p.position, int(p.get("number", 0)), str(p.name).left(17),
			int(p.age), Rating.overall(p), status], 13, Color(0.92, 0.93, 0.96), true)
	# News.
	var news := UIKit.panel(_root, Rect2(20, 430, 810, 270))
	UIKit.label(news, "NOTICIAS", 18, Color(1.0, 0.86, 0.2))
	for line: String in st.news.slice(maxi(0, st.news.size() - 9)):
		UIKit.label(news, "· " + line, 14)


func _render_market() -> void:
	var st := ml.state
	var box := UIKit.panel(_root, Rect2(20, 14, 1240, 690))
	UIKit.label(box, "FICHAJES · tenés %d puntos · oferta = valor de mercado (+30%% si es titular en su club)" % int(st.points), 20, Color(1.0, 0.86, 0.2))
	var back := UIKit.button(box, "← Volver", func() -> void:
		_view = "hub"
		_render(), 16)
	back.grab_focus()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1200, 560)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	for pid: String in ml.market(60):
		var p := ml.player(pid)
		var value := Rating.value(p)
		var key := ml.lineup_ids(ml._club_of(pid)).slice(0, 11).has(pid)
		var price := int(ceil(value * (1.3 if key else 1.0) / 10.0) * 10)
		UIKit.button(list, "%-4s %-18s %2d años  OVR %2d  pot %2d  %-22s  %6d pts" % [p.position, str(p.name).left(18),
			int(p.age), Rating.overall(p), int(p.potential), ml.club(ml._club_of(pid)).name.left(22), price],
			func() -> void:
				var r := ml.make_offer(pid, price)
				ml.state.news.append(r.reason)
				_view = "hub"
				_render(), 14)


func _simulate() -> void:
	ml.advance()
	ml.save_slot(1)
	_render()


func _play_match() -> void:
	var fx := ml.user_fixture()
	if fx.is_empty():
		return
	visible = false
	_match = UIKit.start_match(get_tree(), ml.match_setup(fx), "1")
	_match.match_finished.connect(_on_match_finished)
	_match.exit_requested.connect(_on_match_abandoned)


func _on_match_finished(summary: Dictionary) -> void:
	await get_tree().create_timer(4.0).timeout
	var fx := ml.user_fixture()
	if summary.has("winner_team") and not fx.is_empty():
		summary["winner"] = fx.home if int(summary.winner_team) == 0 else fx.away
	_close_match()
	ml.advance(summary)
	ml.save_slot(1)
	_render()


func _on_match_abandoned() -> void:
	_close_match()
	_render()


func _close_match() -> void:
	if _match != null:
		_match.queue_free()
		_match = null
	get_tree().paused = false
	visible = true
