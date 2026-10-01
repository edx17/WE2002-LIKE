class_name PlayerIntent
extends RefCounted
## What a controller (human pad or AI) WANTS to do this frame.
## Humans and AI fill exactly the same structure, so the AI plays by the same
## rules, speeds and imprecision as the human.

enum Action { PASS, SHOOT, THROUGH, LOB }
const NONE := -1

## Raw direction, stick/screen space. The PlayerController quantizes it.
var move := Vector2.ZERO
var sprint := false
## Bitmasks of Action.
var held := 0
var just_pressed := 0
## Action released this frame (the kick trigger) and its power-bar charge.
var released_action := NONE
var released_charge := 0.0
## For the HUD power bar.
var charging_action := NONE
var charge := 0.0
## Goalkeepers only: where to dive (null = no dive this frame).
var dive_target: Variant = null


func begin_frame() -> void:
	just_pressed = 0
	released_action = NONE
	released_charge = 0.0
	dive_target = null


func clear() -> void:
	begin_frame()
	move = Vector2.ZERO
	sprint = false
	held = 0
	charging_action = NONE
	charge = 0.0


func press(action: int) -> void:
	just_pressed |= (1 << action)


func release(action: int, power: float) -> void:
	released_action = action
	released_charge = clampf(power, 0.0, 1.0)


func is_held(action: int) -> bool:
	return (held & (1 << action)) != 0


func is_just_pressed(action: int) -> bool:
	return (just_pressed & (1 << action)) != 0
