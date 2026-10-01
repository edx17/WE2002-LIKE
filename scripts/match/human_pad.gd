class_name HumanPad
extends RefCounted
## One human at the console: his controller, his team, the player he is
## driving right now and the colour of his cursor.

const COLORS := [Color(1.0, 0.85, 0.1), Color(0.2, 0.85, 1.0)]

var index := 0
var team := 0
var input: HumanInput
var player: PlayerController = null
var color := Color.YELLOW
var label := "1P"


func _init(pad_index: int, team_index: int) -> void:
	index = pad_index
	team = team_index
	input = HumanInput.new("p%d_" % (pad_index + 1))
	color = COLORS[pad_index % COLORS.size()]
	label = "%dP" % (pad_index + 1)


func action(name: String) -> StringName:
	return input.act(name)
