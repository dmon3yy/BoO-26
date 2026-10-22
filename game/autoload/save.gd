extends Node
## Save files and the Word of the Gods.
##
## A save is GameState.to_dict() plus a version number, written as JSON to
## user://. When the format changes, bump SAVE_VERSION and add a migration
## step, so old saves upgrade instead of breaking.
##
## The "Word of the Gods" (the original game's password) is a short code for
## the save. Browser storage can be wiped; a Word copied into a note survives
## anything. It numbers things instead of spelling them out (see
## content/word.json), so early in the game it's about 20 characters.

const SAVE_VERSION := 2
const WORD_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # Crockford base32: no I, L, O, U
const WORD_GROUP := 4
const WORD_FORMAT := 1        # bump if the bit layout below ever changes
const WORD_CHECK := 2         # characters of checksum at the end (10 bits)

## Each entry upgrades a save from version N to N + 1.
var _migrations := {
	1: _migrate_1_to_2,
}


func slot_path(slot: int) -> String:
	return "user://save_%d.json" % slot


func save_game(slot: int) -> Error:
	var data := build_save()
	var tmp := slot_path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, slot_path(slot))


func load_game(slot: int) -> Error:
	if not FileAccess.file_exists(slot_path(slot)):
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(slot_path(slot))
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	return apply_save(parsed)


func build_save() -> Dictionary:
	return {"version": SAVE_VERSION, "state": GameState.to_dict()}


func apply_save(data: Dictionary) -> Error:
	var upgraded := migrate(data)
	if upgraded.is_empty():
		return ERR_INVALID_DATA
	GameState.from_dict(upgraded["state"])
	return OK


## Upgrade any older save dictionary to the current version. Returns {} if the
## save comes from the future or is malformed.
func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var version := int(d.get("version", 1))
	if version > SAVE_VERSION or not d.has("state"):
		return {}
	while version < SAVE_VERSION:
		d = _migrations[version].call(d)
		version += 1
		d["version"] = version
	return d


## Version 1 (pre-M0 prototype) called max health "hp_max".
func _migrate_1_to_2(d: Dictionary) -> Dictionary:
	var state: Dictionary = d["state"]
	if state.has("hp_max"):
		state["max_hp"] = state["hp_max"]
		state.erase("hp_max")
	return d


# --- Word of the Gods -------------------------------------------------------
#
# Layout, as a stream of bits written 5 to a character:
#   format (3 bits) · Hearth number · olives · max HP · abilities · flags ·
#   verses · season · rooms visited · keepsakes collected · checksum
# Numbers are written 4 bits at a time with a "more follows" bit, so small
# numbers are one character. A set is its length, then one bit per entry,
# trimmed after the last one you have: an empty set costs one character.

static var _index: Dictionary = {}


func make_word() -> String:
	var reg := ContentDB.json("word")
	var idx := world_index()
	var bits := PackedByteArray()
	_put(bits, WORD_FORMAT, 3)
	_put_number(bits, (idx["hearths"] as Array).find(GameState.hearth_id) + 1)
	_put_number(bits, GameState.olives)
	_put_number(bits, GameState.max_hp)
	_put_set(bits, _positions(reg["abilities"], GameState.abilities.keys(), "ability"))
	var raised := GameState.flags.keys().filter(func(f): return GameState.flags[f] == true)
	_put_set(bits, _positions(reg["flags"], raised, "flag"))
	_put_set(bits, GameState.verses.map(func(v): return v - 1))
	_put_number(bits, maxi(0, (reg["seasons"] as Array).find(String(GameState.season))))
	_put_set(bits, _positions(idx["rooms"], GameState.visited_rooms.keys(), "room"))
	_put_set(bits, _positions(idx["keepsakes"], GameState.collected.keys(), ""))
	while bits.size() % 5:
		bits.append(0)
	var body := ""
	for i in range(0, bits.size(), 5):
		body += WORD_ALPHABET[_bit_get(bits, i, 5)]
	return _group(body + _word_check(body))


func read_word(word: String) -> Error:
	var text := ""
	for ch in word.to_upper():
		# Forgive the letters people confuse with digits.
		if ch == "O":
			ch = "0"
		elif ch == "I" or ch == "L":
			ch = "1"
		if WORD_ALPHABET.contains(ch):
			text += ch     # dashes, spaces and line breaks are skipped
	if text.length() <= WORD_CHECK:
		return ERR_INVALID_DATA
	var body := text.left(-WORD_CHECK)
	if _word_check(body) != text.right(WORD_CHECK):
		return ERR_INVALID_DATA
	var bits := PackedByteArray()
	for ch in body:
		_put(bits, WORD_ALPHABET.find(ch), 5)
	var r := {"bits": bits, "at": 0}
	if _take(r, 3) != WORD_FORMAT:
		return ERR_INVALID_DATA
	var reg := ContentDB.json("word")
	var idx := world_index()
	var hearth := _take_number(r) - 1
	var olives := _take_number(r)
	var max_hp := _take_number(r)
	var abilities := _take_set(r)
	var flags := _take_set(r)
	var verses := _take_set(r)
	var season := _take_number(r)
	var rooms := _take_set(r)
	var keepsakes := _take_set(r)
	if r["at"] > bits.size():
		return ERR_INVALID_DATA
	GameState.reset()
	GameState.olives = olives
	GameState.max_hp = max_hp
	for i in abilities:
		if i < reg["abilities"].size():
			GameState.abilities[StringName(reg["abilities"][i])] = true
	for i in flags:
		if i < reg["flags"].size():
			GameState.flags[StringName(reg["flags"][i])] = true
	for v in verses:
		GameState.verses.append(v + 1)
	GameState.season = StringName(reg["seasons"][season]) if season < reg["seasons"].size() else &"winter"
	for i in rooms:
		if i < idx["rooms"].size():
			GameState.visited_rooms[idx["rooms"][i]] = true
	for i in keepsakes:
		if i < idx["keepsakes"].size():
			GameState.collected[idx["keepsakes"][i]] = true
	if hearth >= 0 and hearth < idx["hearths"].size():
		GameState.hearth_id = idx["hearths"][hearth]
		GameState.room_id = GameState.hearth_id.get_slice(":", 0)
	return OK


## Every Hearth, room and keepsake in the world, in a fixed order: rooms as
## listed in world.json, things within a room left to right, top to bottom.
static func world_index() -> Dictionary:
	if not _index.is_empty():
		return _index
	var kinds: Dictionary = ContentDB.json("legend")["entities"]
	var keep: Array = ContentDB.json("word")["keepsake_kinds"]
	var rooms: Array = ContentDB.json("world")["rooms"].keys()
	var hearths := []
	var keepsakes := []
	for id in rooms:
		var data := ContentDB.room(id)
		for y in data.height:
			for x in data.width:
				var ch := data.char_at(x, y)
				var kind: String = data.legend[ch]["kind"] if data.legend.has(ch) else kinds.get(ch, "")
				if kind == "hearth":
					hearths.append("%s:hearth_%d_%d" % [id, x, y])
				elif kind in keep:
					keepsakes.append("%s:%s_%d_%d" % [id, kind, x, y])
	_index = {"rooms": rooms, "hearths": hearths, "keepsakes": keepsakes}
	return _index


## Positions of `members` in `universe`. Members missing from it (e.g. an
## ability nobody added to word.json yet) are left out, with a warning.
static func _positions(universe: Array, members: Array, what: String) -> Array:
	var out := []
	for m in members:
		var i := universe.find(String(m))
		if i >= 0:
			out.append(i)
		elif what != "":
			push_warning("Word: %s '%s' is not in content/word.json, so a Word won't keep it" % [what, m])
	return out


static func _put(bits: PackedByteArray, value: int, width: int) -> void:
	for k in range(width - 1, -1, -1):
		bits.append((value >> k) & 1)


static func _bit_get(bits: PackedByteArray, at: int, width: int) -> int:
	var v := 0
	for k in width:
		v = (v << 1) | (bits[at + k] if at + k < bits.size() else 0)
	return v


static func _put_number(bits: PackedByteArray, n: int) -> void:
	n = maxi(0, n)
	var nibbles := [n & 15]
	n >>= 4
	while n > 0:
		nibbles.push_front(n & 15)
		n >>= 4
	for i in nibbles.size():
		_put(bits, 1 if i < nibbles.size() - 1 else 0, 1)
		_put(bits, nibbles[i], 4)


static func _put_set(bits: PackedByteArray, positions: Array) -> void:
	var length := 0
	for p in positions:
		length = maxi(length, int(p) + 1)
	_put_number(bits, length)
	for i in length:
		_put(bits, 1 if positions.has(i) else 0, 1)


static func _take(r: Dictionary, width: int) -> int:
	var v := _bit_get(r["bits"], r["at"], width)
	r["at"] += width
	return v


static func _take_number(r: Dictionary) -> int:
	var n := 0
	for _guard in 8:
		var more := _take(r, 1)
		n = (n << 4) | _take(r, 4)
		if not more:
			break
	return n


static func _take_set(r: Dictionary) -> Array:
	var out := []
	var length := mini(_take_number(r), 4096)
	for i in length:
		if _take(r, 1):
			out.append(i)
	return out


static func _word_check(body: String) -> String:
	var h := body.sha256_buffer()
	var v := (h[0] << 2) | (h[1] >> 6)
	return WORD_ALPHABET[(v >> 5) & 31] + WORD_ALPHABET[v & 31]


static func _group(text: String) -> String:
	var parts := PackedStringArray()
	for i in range(0, text.length(), WORD_GROUP):
		parts.append(text.substr(i, WORD_GROUP))
	return "-".join(parts)
