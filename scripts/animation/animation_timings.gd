class_name AnimationTimings
extends RefCounted
## data/animation/clips.json: one source of truth for clip lengths and
## contact frames, read both by the Blender generator and by gameplay
## (kick windows, tackle/fall durations). Change a timing once, both follow.

static var _clips: Dictionary = {}


static func clips() -> Dictionary:
	if _clips.is_empty():
		var data: Variant = DataLoader.load_json("animation/clips.json")
		if data is Dictionary:
			_clips = data.get("clips", {})
	return _clips


static func length(clip: String, fallback: float) -> float:
	return float(clips().get(clip, {}).get("length", fallback))


static func contact(clip: String, fallback: float) -> float:
	return float(clips().get(clip, {}).get("contact", fallback))


static func loops(clip: String) -> bool:
	return bool(clips().get(clip, {}).get("loop", false))
