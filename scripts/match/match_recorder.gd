class_name MatchRecorder
extends RefCounted
## Rolling recording of the last seconds of play: the foundation for replays
## (Phase 10) and the VAR. Every other physics frame (60 Hz) it stores, for
## the ball and every body on the pitch, position, facing and animation; and
## it keeps time-stamped marks of key moments (kicks, goals, fouls, offside
## flags) so a review can jump straight to "the moment of the pass".
##
## Frames: {t, ball: Vector3, ball_rot: Quaternion, ids: PackedStringArray,
##          pos: PackedVector3Array, yaw: PackedFloat32Array, anim: PackedStringArray}
## Marks:  {t, kind, player_id, pos, ...}

const SECONDS := 20.0
const HZ := 60.0

var match_ctx: MatchController
var frames: Array[Dictionary] = []
var marks: Array[Dictionary] = []
## Match time in seconds since kick-off (real seconds of play).
var time := 0.0
var _accum := 0.0


func _init(m: MatchController) -> void:
	match_ctx = m


func capture(delta: float) -> void:
	time += delta
	_accum += delta
	if _accum < 1.0 / HZ:
		return
	_accum = 0.0
	var bodies: Array[PlayerController] = match_ctx.players.duplicate()
	if match_ctx.official != null:
		bodies.append(match_ctx.official)
	var ids := PackedStringArray()
	var pos := PackedVector3Array()
	var yaw := PackedFloat32Array()
	var anim := PackedStringArray()
	for p in bodies:
		ids.append(p.stats.id if p.stats != null else str(p.name))
		pos.append(p.global_position)
		yaw.append(p.rotation.y)
		anim.append(str(p.animation_selector.current) if p.animation_selector != null else "")
	frames.append({"t": time, "ball": match_ctx.ball.global_position, "ball_rot": match_ctx.ball.quaternion,
		"ids": ids, "pos": pos, "yaw": yaw, "anim": anim})
	var oldest := time - SECONDS
	while not frames.is_empty() and float(frames[0].t) < oldest:
		frames.pop_front()
	while not marks.is_empty() and float(marks[0].t) < oldest:
		marks.pop_front()


func mark(kind: String, player: PlayerController = null, extra: Dictionary = {}) -> void:
	var m := {"t": time, "kind": kind, "player_id": player.stats.id if player != null else "",
		"pos": player.global_position if player != null else match_ctx.ball.global_position}
	m.merge(extra)
	marks.append(m)


## Recorded seconds available.
func duration() -> float:
	return 0.0 if frames.is_empty() else float(frames[-1].t) - float(frames[0].t)


## The frame closest to `seconds_ago` before now.
func frame_ago(seconds_ago: float) -> Dictionary:
	return frame_at(time - seconds_ago)


func frame_at(t: float) -> Dictionary:
	if frames.is_empty():
		return {}
	var lo := 0
	var hi := frames.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(frames[mid].t) < t:
			lo = mid + 1
		else:
			hi = mid
	return frames[lo]


## Last mark of a kind (e.g. "kick" before a goal: the VAR offside check).
func last_mark(kind: String, before := INF) -> Dictionary:
	for i in range(marks.size() - 1, -1, -1):
		if marks[i].kind == kind and float(marks[i].t) <= before:
			return marks[i]
	return {}


func clear() -> void:
	frames.clear()
	marks.clear()
