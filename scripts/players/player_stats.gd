class_name PlayerStats
extends Resource
## Player attributes (1..99, WE style). Loaded from JSON in data/players so
## the whole roster is moddable without touching code.

@export var id := ""
@export var name := "Jugador"
@export var number := 0
@export var position := "CF"
@export_enum("right", "left") var preferred_foot := "right"
## 1..4 like the classic weak-foot rating: 4 = almost as good as the strong foot.
@export_range(1, 4) var weak_foot := 2

@export_range(1, 99) var speed := 75
@export_range(1, 99) var acceleration := 75
@export_range(1, 99) var agility := 75
@export_range(1, 99) var balance := 75
@export_range(1, 99) var strength := 75
@export_range(1, 99) var stamina := 75
@export_range(1, 99) var passing := 75
@export_range(1, 99) var shooting := 75
@export_range(1, 99) var shot_power := 75
@export_range(1, 99) var heading := 75
@export_range(1, 99) var tackling := 75
@export_range(1, 99) var control := 75
@export_range(1, 99) var technique := 75
@export_range(1, 99) var aggression := 75
@export_range(1, 99) var reaction := 75


static func from_dict(data: Dictionary) -> PlayerStats:
	var stats := PlayerStats.new()
	for key: String in data.keys():
		if not key in stats:
			push_warning("PlayerStats: atributo desconocido '%s'" % key)
			continue
		var current: Variant = stats.get(key)
		if typeof(current) == TYPE_INT:
			stats.set(key, int(data[key]))
		else:
			stats.set(key, data[key])
	return stats


## Normalised attribute 0..1.
func n(stat: StringName) -> float:
	return clampf(float(get(stat)) / 99.0, 0.0, 1.0)
