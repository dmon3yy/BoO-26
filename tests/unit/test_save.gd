extends GutTest
## Saves, migrations, the Word of the Gods, and the Souls-lite olive drop.


func before_each() -> void:
	GameState.reset()


func _fill_state() -> void:
	GameState.olives = 42
	GameState.grant_ability(&"sandals")
	GameState.set_flag(&"met_zeus")
	GameState.collected["arcadia_01:olive_26_4"] = true
	GameState.verses.append(1)
	GameState.room_id = "arcadia_02"


func test_save_round_trip() -> void:
	_fill_state()
	assert_eq(Save.save_game(9), OK)
	GameState.reset()
	assert_eq(Save.load_game(9), OK)
	assert_eq(GameState.olives, 42)
	assert_true(GameState.has_ability(&"sandals"))
	assert_true(GameState.get_flag(&"met_zeus"))
	assert_true(GameState.collected.has("arcadia_01:olive_26_4"))
	assert_eq(GameState.verses, [1])
	assert_eq(GameState.room_id, "arcadia_02")
	DirAccess.remove_absolute(Save.slot_path(9))


func test_migrates_version_1() -> void:
	var v1 := {"version": 1, "state": {"olives": 5, "hp_max": 20}}
	assert_eq(Save.apply_save(v1), OK)
	assert_eq(GameState.max_hp, 20)
	assert_eq(GameState.olives, 5)


func test_rejects_saves_from_the_future() -> void:
	assert_eq(Save.apply_save({"version": 999, "state": {}}), ERR_INVALID_DATA)


func test_word_of_the_gods_round_trip() -> void:
	_fill_state()
	var word := Save.make_word()
	assert_true(word.contains("-"))
	GameState.reset()
	assert_eq(Save.read_word(word), OK)
	assert_eq(GameState.olives, 42)
	assert_true(GameState.has_ability(&"sandals"))


func test_word_keeps_everything_that_matters() -> void:
	_fill_state()
	GameState.max_hp = 16
	GameState.verses.append(9)
	GameState.season = &"thaw"
	GameState.visited_rooms["arcadia_01"] = true
	GameState.visited_rooms["erebos_01"] = true
	GameState.hearth_id = "arcadia_05:hearth_8_29"
	var word := Save.make_word()
	GameState.reset()
	assert_eq(Save.read_word(word), OK)
	assert_eq(GameState.max_hp, 16)
	assert_true(GameState.get_flag(&"met_zeus"))
	assert_eq(GameState.verses, [1, 9])
	assert_eq(GameState.season, &"thaw")
	assert_true(GameState.visited_rooms.has("erebos_01"))
	assert_eq(GameState.hearth_id, "arcadia_05:hearth_8_29")
	assert_eq(GameState.room_id, "arcadia_05")


func test_word_is_short_enough_to_copy() -> void:
	_fill_state()
	GameState.hearth_id = "arcadia_05:hearth_8_29"
	for id in ContentDB.json("world")["rooms"]:
		GameState.visited_rooms[id] = true
	var word := Save.make_word()
	assert_lt(word.replace("-", "").length(), 30, word)


func test_every_hearth_has_a_number() -> void:
	assert_true(Save.world_index()["hearths"].has("arcadia_05:hearth_8_29"))


func test_word_forgives_case_and_lookalikes() -> void:
	_fill_state()
	var word := Save.make_word().to_lower().replace("0", "o").replace("1", "l")
	GameState.reset()
	assert_eq(Save.read_word(word), OK)
	assert_eq(GameState.olives, 42)


func test_word_detects_a_typo() -> void:
	_fill_state()
	var word := Save.make_word()
	var i := word.length() / 2
	var swapped := "A" if word[i] != "A" else "B"
	var broken := word.substr(0, i) + swapped + word.substr(i + 1)
	assert_ne(Save.read_word(broken), OK)


func test_death_drops_half_the_olives_and_they_can_be_recovered() -> void:
	GameState.olives = 30
	GameState.drop_olives_on_death("arcadia_01", Vector2(100, 200))
	assert_eq(GameState.olives, 15)
	assert_eq(GameState.dropped_olives["amount"], 15)
	assert_eq(GameState.recover_dropped_olives(), 15)
	assert_eq(GameState.olives, 30)


func test_odd_olive_counts_drop_the_larger_half() -> void:
	GameState.olives = 7
	GameState.drop_olives_on_death("arcadia_01", Vector2.ZERO)
	assert_eq(GameState.dropped_olives["amount"], 4)
	assert_eq(GameState.olives, 3)


func test_dying_again_loses_the_first_pile() -> void:
	GameState.olives = 30
	GameState.drop_olives_on_death("arcadia_01", Vector2(100, 200))
	GameState.olives = 4
	GameState.drop_olives_on_death("arcadia_02", Vector2(10, 20))
	assert_eq(GameState.dropped_olives["amount"], 2)
	assert_eq(GameState.dropped_olives["room"], "arcadia_02")
