class_name RoomData
extends RefCounted
## A parsed .room file (see content/rooms/*.room).
##
## The grammar is shared with tools/rooms.py; tests/python/test_rooms.py and
## tests/unit/test_room_data.gd read the same fixture files so the two parsers
## never drift apart.
##
##   ; comment
##   key = value          header (id, theme, name, ...)
##   [legend]
##   X = kind key=value   room-specific entity characters
##   [map]                playable layer, one character per 16px tile
##   [back]               optional back-wall layer, same size as [map]

const TILE := 16

var id := ""
var header: Dictionary = {}
var legend: Dictionary = {}     # char -> {"kind": String, "params": Dictionary}
var map_rows: PackedStringArray = []
var back_rows: PackedStringArray = []
var width := 0
var height := 0
var errors: PackedStringArray = []


static func load_file(path: String) -> RoomData:
	var room := RoomData.new()
	if not FileAccess.file_exists(path):
		room.errors.append("missing file %s" % path)
		return room
	room.parse(FileAccess.get_file_as_string(path))
	return room


func parse(text: String) -> void:
	var section := ""
	for raw in text.split("\n"):
		var line := raw.rstrip("\r")
		if line.begins_with("[") and line.strip_edges().ends_with("]"):
			section = line.strip_edges().trim_prefix("[").trim_suffix("]")
			continue
		if section == "map" or section == "back":
			if line.strip_edges() == "":
				continue
			(map_rows if section == "map" else back_rows).append(line)
			continue
		var stripped := line.strip_edges()
		if stripped == "" or stripped.begins_with(";"):
			continue
		var eq := stripped.find("=")
		if eq < 0:
			errors.append("cannot read line: %s" % stripped)
			continue
		var key := stripped.substr(0, eq).strip_edges()
		var value := stripped.substr(eq + 1).strip_edges()
		if section == "legend":
			legend[key] = _parse_legend_value(value)
		else:
			header[key] = value
	id = header.get("id", "")
	height = map_rows.size()
	width = map_rows[0].length() if height > 0 else 0
	for i in map_rows.size():
		if map_rows[i].length() != width:
			errors.append("map row %d is %d wide, expected %d" % [i, map_rows[i].length(), width])
	if not back_rows.is_empty() and back_rows.size() != height:
		errors.append("[back] has %d rows, [map] has %d" % [back_rows.size(), height])


static func _parse_legend_value(value: String) -> Dictionary:
	var parts := value.split(" ", false)
	var params := {}
	for i in range(1, parts.size()):
		var kv := parts[i].split("=")
		if kv.size() == 2:
			params[kv[0]] = kv[1]
	return {"kind": parts[0] if parts.size() > 0 else "", "params": params}


func char_at(x: int, y: int) -> String:
	if y < 0 or y >= height or x < 0 or x >= width:
		return ""
	return map_rows[y][x]


func back_at(x: int, y: int) -> String:
	if back_rows.is_empty() or y < 0 or y >= back_rows.size() or x < 0 or x >= back_rows[y].length():
		return "."
	return back_rows[y][x]


func size_px() -> Vector2:
	return Vector2(width * TILE, height * TILE)
