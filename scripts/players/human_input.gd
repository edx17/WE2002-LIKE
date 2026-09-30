class_name HumanInput
extends RefCounted
## Pad/keyboard -> PlayerIntent. Kick buttons work like the classic power
## bar: hold to charge, release to execute.

const ACTIONS := {
	PlayerIntent.Action.PASS: &"pass",
	PlayerIntent.Action.SHOOT: &"shoot",
	PlayerIntent.Action.THROUGH: &"through",
	PlayerIntent.Action.LOB: &"lob",
}
## Seconds to fill the bar.
const CHARGE_TIME := 0.9

var _hold_time := {}


func fill(intent: PlayerIntent, _player: Node, delta: float) -> void:
	intent.begin_frame()
	intent.move = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	intent.sprint = Input.is_action_pressed(&"sprint")
	intent.charging_action = PlayerIntent.NONE
	intent.charge = 0.0
	for action: int in ACTIONS:
		var name: StringName = ACTIONS[action]
		if Input.is_action_just_pressed(name):
			intent.press(action)
			_hold_time[action] = 0.0
		if Input.is_action_pressed(name):
			intent.held |= (1 << action)
			_hold_time[action] = float(_hold_time.get(action, 0.0)) + delta
			intent.charging_action = action
			intent.charge = charge_for(_hold_time[action])
		else:
			intent.held &= ~(1 << action)
		if Input.is_action_just_released(name):
			intent.release(action, charge_for(float(_hold_time.get(action, 0.0))))
			_hold_time.erase(action)


static func charge_for(hold_seconds: float) -> float:
	return clampf(hold_seconds / CHARGE_TIME, 0.0, 1.0)
