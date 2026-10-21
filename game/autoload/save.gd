extends Node
## Save files and the Word of the Gods.
##
## A save is GameState.to_dict() plus a version number, written as JSON to
## user://. When the format changes, bump SAVE_VERSION and add a migration
## step, so old saves upgrade instead of breaking.
##
## The "Word of the Gods" (the original game's password) is the same save,
## compressed and spelled in an unambiguous alphabet. Browser storage can be
## wiped; a Word copied into a note survives anything.

const SAVE_VERSION := 2
const WORD_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # Crockford base32: no I, L, O, U
const WORD_GROUP := 5

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

func make_word() -> String:
	var json := JSON.stringify(build_save())
	var packed := json.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	var payload := PackedByteArray()
	payload.append_array(_u32(json.to_utf8_buffer().size()))
	payload.append_array(packed)
	payload.append_array(_checksum(payload))
	return _group(encode_base32(payload))


func read_word(word: String) -> Error:
	var bytes := decode_base32(word)
	if bytes.size() < 8:
		return ERR_INVALID_DATA
	var payload := bytes.slice(0, bytes.size() - 4)
	if _checksum(payload) != bytes.slice(bytes.size() - 4):
		return ERR_INVALID_DATA
	var raw_size := payload.decode_u32(0)
	var json := payload.slice(4).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	var parsed: Variant = JSON.parse_string(json.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	return apply_save(parsed)


static func encode_base32(bytes: PackedByteArray) -> String:
	var out := ""
	var buffer := 0
	var bits := 0
	for b in bytes:
		buffer = (buffer << 8) | b
		bits += 8
		while bits >= 5:
			bits -= 5
			out += WORD_ALPHABET[(buffer >> bits) & 31]
	if bits > 0:
		out += WORD_ALPHABET[(buffer << (5 - bits)) & 31]
	return out


static func decode_base32(text: String) -> PackedByteArray:
	var out := PackedByteArray()
	var buffer := 0
	var bits := 0
	for ch in text.to_upper():
		# Forgive the letters people confuse with digits.
		if ch == "O":
			ch = "0"
		elif ch == "I" or ch == "L":
			ch = "1"
		var v := WORD_ALPHABET.find(ch)
		if v < 0:
			continue  # dashes, spaces, line breaks
		buffer = (buffer << 5) | v
		bits += 5
		if bits >= 8:
			bits -= 8
			out.append((buffer >> bits) & 255)
	return out


static func _group(text: String) -> String:
	var parts := PackedStringArray()
	for i in range(0, text.length(), WORD_GROUP):
		parts.append(text.substr(i, WORD_GROUP))
	return "-".join(parts)


static func _u32(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, n)
	return b


static func _checksum(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().slice(0, 4)
