extends GutTest
## The GDScript room parser must agree with the Python one, using the shared
## golden fixture (tests/fixtures/rooms/sample.expected.json).

const FIX := "res://tests/fixtures/rooms/"


func _entities(room: RoomData) -> Array:
	var global: Dictionary = ContentDB.json("legend")["entities"]
	var out := []
	for y in room.height:
		for x in room.width:
			var ch := room.char_at(x, y)
			if room.legend.has(ch):
				out.append([room.legend[ch]["kind"], x, y])
			elif global.has(ch):
				out.append([global[ch], x, y])
	return out


func test_matches_golden_summary() -> void:
	var room := RoomData.load_file(FIX + "sample.room")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX + "sample.expected.json"))
	assert_eq(room.id, expected["id"])
	assert_eq(room.width, int(expected["width"]))
	assert_eq(room.height, int(expected["height"]))
	assert_eq(room.header, expected["header"])
	assert_eq(room.legend, expected["legend"])
	assert_eq(Array(room.errors), expected["errors"])
	var got := _entities(room)
	var want: Array = expected["entities"]
	assert_eq(got.size(), want.size())
	for i in mini(got.size(), want.size()):
		assert_eq(got[i][0], want[i][0])
		assert_eq(got[i][1], int(want[i][1]))
		assert_eq(got[i][2], int(want[i][2]))


func test_ragged_rows_reported() -> void:
	var room := RoomData.new()
	room.parse("id = r\n[map]\n....\n...\n")
	assert_eq(room.errors.size(), 1)


func test_all_real_rooms_parse() -> void:
	for id in ContentDB.json("world")["rooms"]:
		var room := ContentDB.room(id)
		assert_eq(room.errors.size(), 0, "%s: %s" % [id, room.errors])
		assert_eq(room.id, id)
