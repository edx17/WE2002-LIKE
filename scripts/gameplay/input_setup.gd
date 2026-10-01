class_name InputSetup
extends RefCounted
## Registers the input map in code (keyboard + pad) so the project runs
## without editor configuration and bindings stay readable in one place.
##
## Pad layout follows the classic WE mapping on an Xbox-style pad:
## A = pase, X = remate, Y = pase filtrado, B = centro/globo, RB = sprint,
## LB = cambiar de jugador.
##
## Two local players: every gameplay action exists as p1_* and p2_*.
##   P1: WASD, J K I L, Shift, Q, T     + joystick 1 (device 0)
##   P2: arrows, numpad 1 2 5 3, numpad 0, numpad 4, numpad 6 + joystick 2 (device 1)
## Playing alone, P1 also gets the arrows, Space and every joystick.
## Unprefixed actions (move_*, pass, shoot...) answer to anyone: menus use them.

const GAMEPLAY := ["move_left", "move_right", "move_up", "move_down", "pass", "shoot", "through", "lob",
	"sprint", "switch_player", "cycle_tactics"]

const P1_KEYS := {
	"move_left": [KEY_A], "move_right": [KEY_D], "move_up": [KEY_W], "move_down": [KEY_S],
	"pass": [KEY_J], "shoot": [KEY_K], "through": [KEY_I], "lob": [KEY_L],
	"sprint": [KEY_SHIFT], "switch_player": [KEY_Q], "cycle_tactics": [KEY_T],
}
const P1_SOLO_EXTRA := {
	"move_left": [KEY_LEFT], "move_right": [KEY_RIGHT], "move_up": [KEY_UP], "move_down": [KEY_DOWN],
	"sprint": [KEY_SPACE],
}
const P2_KEYS := {
	"move_left": [KEY_LEFT], "move_right": [KEY_RIGHT], "move_up": [KEY_UP], "move_down": [KEY_DOWN],
	"pass": [KEY_KP_1], "shoot": [KEY_KP_2], "through": [KEY_KP_5], "lob": [KEY_KP_3],
	"sprint": [KEY_KP_0], "switch_player": [KEY_KP_4], "cycle_tactics": [KEY_KP_6],
}
const PAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
	"pass": [JOY_BUTTON_A], "shoot": [JOY_BUTTON_X], "through": [JOY_BUTTON_Y], "lob": [JOY_BUTTON_B],
	"sprint": [JOY_BUTTON_RIGHT_SHOULDER], "switch_player": [JOY_BUTTON_LEFT_SHOULDER],
	"cycle_tactics": [JOY_BUTTON_RIGHT_STICK],
}
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

static var _two_players := false


static func ensure_actions() -> void:
	# Shared actions: anyone (menus, single player).
	for action: String in GAMEPLAY:
		var keys: Array = P1_KEYS[action] + P1_SOLO_EXTRA.get(action, [])
		_add(StringName(action), keys, PAD_BUTTONS[action], _axes(action), -1)
	_add(&"toggle_directions", [KEY_F2], [JOY_BUTTON_LEFT_STICK])
	_add(&"camera_zoom", [KEY_C], [JOY_BUTTON_BACK])
	_add(&"toggle_debug", [KEY_F3], [])
	_add(&"toggle_help", [KEY_F1], [])
	_add(&"reset_match", [KEY_R], [])
	_add(&"pause_menu", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	if not InputMap.has_action(&"p1_pass"):
		configure(false)


## Rebuilds the per-player actions for one or two humans.
static func configure(two_players: bool) -> void:
	_two_players = two_players
	for action: String in GAMEPLAY:
		var p1 := StringName("p1_" + action)
		var p2 := StringName("p2_" + action)
		for a: StringName in [p1, p2]:
			if InputMap.has_action(a):
				InputMap.erase_action(a)
		var p1_keys: Array = P1_KEYS[action]
		if not two_players:
			p1_keys = p1_keys + P1_SOLO_EXTRA.get(action, [])
		# Alone: every joystick drives P1. Two players: one joystick each.
		_add(p1, p1_keys, PAD_BUTTONS[action], _axes(action), 0 if two_players else -1)
		_add(p2, P2_KEYS[action], PAD_BUTTONS[action], _axes(action), 1)


static func is_two_players() -> bool:
	return _two_players


static func _axes(action: String) -> Array:
	return [PAD_AXES[action]] if PAD_AXES.has(action) else []


static func _add(action: StringName, keys: Array, buttons: Array, axes: Array = [], device := -1) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for key: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button: int in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.device = device
		InputMap.action_add_event(action, ev)
	for axis: Array in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis[0]
		ev.axis_value = axis[1]
		ev.device = device
		InputMap.action_add_event(action, ev)
