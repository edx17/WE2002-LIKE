class_name DataLoader
extends RefCounted
## All football data (players, teams, match setups) lives in JSON under
## res://data. A file with the same relative path under user://mods/data
## overrides the bundled one, so the game is moddable without rebuilding.

const DATA_ROOT := "res://data/"
const MOD_ROOT := "user://mods/data/"


static func resolve(relative: String) -> String:
	var mod_path := MOD_ROOT + relative
	if FileAccess.file_exists(mod_path):
		return mod_path
	return DATA_ROOT + relative


static func load_json(relative: String) -> Variant:
	var path := resolve(relative)
	if not FileAccess.file_exists(path):
		push_error("DataLoader: no existe %s" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("DataLoader: %s línea %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func load_player(id: String) -> PlayerStats:
	var data: Variant = load_json("players/%s.json" % id)
	if not data is Dictionary:
		return PlayerStats.new()
	var stats := PlayerStats.from_dict(data)
	if stats.id == "":
		stats.id = id
	return stats


static func load_team(id: String) -> Dictionary:
	var data: Variant = load_json("teams/%s.json" % id)
	return data if data is Dictionary else {}


static func load_match(id: String) -> Dictionary:
	var data: Variant = load_json("matches/%s.json" % id)
	return data if data is Dictionary else {}
