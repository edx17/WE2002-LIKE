class_name InputSetup
extends RefCounted
## Registers the input map in code (keyboard + pad) so the project runs
## without editor configuration and bindings stay readable in one place.
##
## Pad layout follows the classic WE mapping on an Xbox-style pad:
## A = pase, X = remate, Y = pase filtrado, B = centro/globo, RB = sprint,
## LB = cambiar de jugador.


static func ensure_actions() -> void:
	_add(&"move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add(&"move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add(&"move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add(&"move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add(&"pass", [KEY_J], [JOY_BUTTON_A])
	_add(&"shoot", [KEY_K], [JOY_BUTTON_X])
	_add(&"through", [KEY_I], [JOY_BUTTON_Y])
	_add(&"lob", [KEY_L], [JOY_BUTTON_B])
	_add(&"sprint", [KEY_SHIFT, KEY_SPACE], [JOY_BUTTON_RIGHT_SHOULDER])
	_add(&"switch_player", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_add(&"toggle_directions", [KEY_F2], [JOY_BUTTON_LEFT_STICK])
	_add(&"camera_zoom", [KEY_C], [JOY_BUTTON_BACK])
	_add(&"toggle_debug", [KEY_F3], [])
	_add(&"toggle_help", [KEY_F1], [])
	_add(&"reset_match", [KEY_R], [JOY_BUTTON_START])


static func _add(action: StringName, keys: Array, buttons: Array, axes: Array = []) -> void:
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
		InputMap.action_add_event(action, ev)
	for axis: Array in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis[0]
		ev.axis_value = axis[1]
		InputMap.action_add_event(action, ev)
