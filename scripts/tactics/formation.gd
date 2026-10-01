class_name Formation
extends RefCounted
## A team shape from data/formations: one slot per player with a defensive
## and an attacking position, both in team space (see the JSON _doc).

var name := ""
var slots: Array[Dictionary] = []


static func load_id(id: String) -> Formation:
	var f := Formation.new()
	var data: Variant = DataLoader.load_json("formations/%s.json" % id)
	if data is Dictionary:
		f.name = str(data.get("name", id))
		for slot: Dictionary in data.get("slots", []):
			f.slots.append(slot)
	return f


func role(i: int) -> String:
	return str(slots[i].get("role", "MF")) if i < slots.size() else "MF"


## Team-space point for slot i at a given shape (0 = defending, 1 = attacking).
func point(i: int, shape: float) -> Vector2:
	var d: Array = slots[i].get("def", [0.3, 0.0])
	var a: Array = slots[i].get("att", d)
	return Vector2(lerpf(float(d[0]), float(a[0]), shape), lerpf(float(d[1]), float(a[1]), shape))


## Team space -> world. progress 0 = own goal line, 1 = opponent goal line.
static func to_world(progress: float, width: float, attack_dir: float) -> Vector3:
	return Vector3((progress - 0.5) * 2.0 * PitchBuilder.HALF_LENGTH * attack_dir, 0.0, width * PitchBuilder.HALF_WIDTH)


static func progress_of(world_x: float, attack_dir: float) -> float:
	return world_x * attack_dir / (2.0 * PitchBuilder.HALF_LENGTH) + 0.5
