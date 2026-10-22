extends Node
## Everything about the current playthrough that a save file must remember.
##
## Things in the world are identified by stable IDs of the form
## "room_id:entity_id" (e.g. "arcadia_01:ambrosia"), so a save can say "this was
## collected" no matter how the room's layout changes later.

var olives := 0
var max_hp := 12
var abilities: Dictionary = {}        # StringName -> true
var flags: Dictionary = {}            # StringName -> Variant
var collected: Dictionary = {}        # "room:entity" -> true
var verses: Array[int] = []
var visited_rooms: Dictionary = {}    # room_id -> true (feeds the auto-map)
var season := &"winter"
var room_id := "arcadia_01"
var hearth_id := ""
var dropped_olives := {}              # {"room": String, "x": float, "y": float, "amount": int}
var play_time := 0.0


func reset() -> void:
	olives = 0
	max_hp = 12
	abilities.clear()
	flags.clear()
	collected.clear()
	verses.clear()
	visited_rooms.clear()
	season = &"winter"
	room_id = "arcadia_01"
	hearth_id = ""
	dropped_olives = {}
	play_time = 0.0


func _process(delta: float) -> void:
	play_time += delta


func has_ability(ability: StringName) -> bool:
	return abilities.has(ability)


func grant_ability(ability: StringName) -> void:
	if not abilities.has(ability):
		abilities[ability] = true
		Events.ability_gained.emit(ability)


func revoke_ability(ability: StringName) -> void:
	abilities.erase(ability)


func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[flag] = value
	Events.flag_set.emit(flag)


func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func add_olives(amount: int) -> void:
	olives = maxi(0, olives + amount)
	Events.olives_changed.emit(olives)


## Souls-lite death: half your olives (rounded up) stay where you fell; you
## keep the rest. Dying again before you reach them overwrites the old pile,
## so the first one is lost.
func drop_olives_on_death(room: String, at: Vector2) -> void:
	var dropped := ceili(olives / 2.0)
	if dropped > 0:
		dropped_olives = {"room": room, "x": at.x, "y": at.y, "amount": dropped}
	else:
		dropped_olives = {}
	olives -= dropped
	Events.olives_changed.emit(olives)


func recover_dropped_olives() -> int:
	var amount: int = dropped_olives.get("amount", 0)
	dropped_olives = {}
	add_olives(amount)
	return amount


func to_dict() -> Dictionary:
	var verse_list := []
	for v in verses:
		verse_list.append(v)
	return {
		"olives": olives,
		"max_hp": max_hp,
		"abilities": abilities.keys().map(func(k): return String(k)),
		"flags": _stringify_keys(flags),
		"collected": collected.keys(),
		"verses": verse_list,
		"visited_rooms": visited_rooms.keys(),
		"season": String(season),
		"room_id": room_id,
		"hearth_id": hearth_id,
		"dropped_olives": dropped_olives,
		"play_time": play_time,
	}


func from_dict(d: Dictionary) -> void:
	reset()
	olives = int(d.get("olives", 0))
	max_hp = int(d.get("max_hp", 12))
	for a in d.get("abilities", []):
		abilities[StringName(a)] = true
	for f in d.get("flags", {}):
		flags[StringName(f)] = d["flags"][f]
	for c in d.get("collected", []):
		collected[c] = true
	for v in d.get("verses", []):
		verses.append(int(v))
	for r in d.get("visited_rooms", []):
		visited_rooms[r] = true
	season = StringName(d.get("season", "winter"))
	room_id = d.get("room_id", "arcadia_01")
	hearth_id = d.get("hearth_id", "")
	dropped_olives = d.get("dropped_olives", {})
	play_time = float(d.get("play_time", 0.0))


func _stringify_keys(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[String(k)] = src[k]
	return out
