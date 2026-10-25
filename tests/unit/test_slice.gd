extends GutTest
## M3, the vertical slice: what a new game holds, the crouch strike, the
## Colchis Bull's armour, pickups, gates, dropped olives, enemies coming back, the journal.

const WorldManager := preload("res://game/world/world_manager.gd")

var world: Node2D


func before_each() -> void:
	GameState.reset()
	Music.stop()


func after_each() -> void:
	get_tree().paused = false


func _world(room: String) -> Node2D:
	world = WorldManager.new()
	add_child_autofree(world)
	world.start(room)
	await wait_physics_frames(3)
	return world


func _origin(room: String) -> Vector2:
	return world.room_origin[room]


# --- a new game -------------------------------------------------------------------

func test_a_new_game_starts_empty_handed() -> void:
	assert_false(GameState.has_ability(&"club"))
	assert_false(GameState.has_ability(&"lyre"))
	assert_true(GameState.has(""), "an empty need is always met")


func test_flags_and_abilities_both_satisfy_a_need() -> void:
	assert_false(GameState.has("beat_bull"))
	GameState.set_flag(&"beat_bull")
	assert_true(GameState.has("beat_bull"))
	GameState.grant_ability(&"club")
	assert_true(GameState.has("club"))


# --- the world ----------------------------------------------------------------------

func test_the_club_is_picked_up_by_walking_into_it() -> void:
	await _world("arcadia_01")
	var room: Room = world.rooms["arcadia_01"]
	var id := ""
	for k in room.pickups:
		if room.pickups[k]["kind"] == "pickup":
			id = k
	assert_ne(id, "", "the club lies in the Frozen Grove")
	world.player.global_position = room.pickups[id]["at"]
	await wait_physics_frames(3)
	assert_true(GameState.has_ability(&"club"))
	assert_true(GameState.collected.has(id))


func test_olives_are_counted() -> void:
	await _world("arcadia_01")
	var room: Room = world.rooms["arcadia_01"]
	for k in room.pickups:
		if room.pickups[k]["kind"] == "olive":
			world.player.global_position = room.pickups[k]["at"]
			break
	await wait_physics_frames(3)
	assert_eq(GameState.olives, 1)


func test_the_pen_gate_opens_when_the_bull_is_beaten() -> void:
	await _world("arcadia_08")
	var room: Room = world.rooms["arcadia_08"]
	assert_eq(room.gates.size(), 1, "the gate east is shut")
	GameState.set_flag(&"beat_bull")
	assert_eq(room.gates.size(), 0, "and opens once the flag is raised")


func test_a_beaten_guardian_stays_beaten() -> void:
	GameState.set_flag(&"beat_bull")
	await _world("arcadia_08")
	assert_null(get_tree().get_first_node_in_group(&"boss"))


func test_death_leaves_half_the_olives_to_pick_up_again() -> void:
	await _world("arcadia_01")
	GameState.olives = 10
	world.player.global_position = _origin("arcadia_01") + Vector2(150, 224)
	await wait_physics_frames(4)
	await world.die()
	assert_eq(GameState.olives, 5, "half kept")
	assert_eq(GameState.dropped_olives["amount"], 5, "half left behind")
	assert_eq(GameState.deaths, 1)
	world.player.global_position = Vector2(GameState.dropped_olives["x"], GameState.dropped_olives["y"])
	await wait_physics_frames(3)
	assert_eq(GameState.olives, 10, "all back, no fight needed")
	assert_true(GameState.dropped_olives.is_empty())


func _enemies_in(room_id: String) -> Array:
	return world.rooms[room_id].get_children().filter(func(n): return n is Enemy and not n.is_queued_for_deletion())


func test_beaten_enemies_stay_down_until_you_rest_or_die() -> void:
	await _world("arcadia_02")
	var before := _enemies_in("arcadia_02").size()
	assert_gt(before, 0)
	var e: Enemy = _enemies_in("arcadia_02")[0]
	e.take_hit(99, 1, 0.0, false)
	await wait_physics_frames(2)
	# Walk far enough away that the room is unloaded, then come back.
	world.place_player("arcadia_06", _origin("arcadia_06") + Vector2(200, 128))
	await wait_physics_frames(2)
	assert_false(world.rooms.has("arcadia_02"), "the temple was unloaded")
	world.place_player("arcadia_02", _origin("arcadia_02") + Vector2(100, 208))
	await wait_physics_frames(2)
	assert_eq(_enemies_in("arcadia_02").size(), before - 1, "still beaten after wandering off")
	await world.die()
	world.place_player("arcadia_02", _origin("arcadia_02") + Vector2(100, 208))
	await wait_physics_frames(2)
	assert_eq(_enemies_in("arcadia_02").size(), before, "back after a death")


func test_zeus_restrings_the_lyre() -> void:
	await _world("arcadia_06")
	world.restring_lyre()
	assert_true(GameState.has_ability(&"lyre"))
	assert_true(GameState.has_ability(&"song:zeus"))


func test_ambrosia_costs_olives_and_adds_a_heart() -> void:
	await _world("arcadia_06")
	GameState.olives = 40
	world.buy_ambrosia(30)
	assert_eq(GameState.olives, 10)
	assert_eq(GameState.max_hp, 14)
	assert_true(GameState.get_flag(&"bought_ambrosia"))


# --- the journal ----------------------------------------------------------------------

func test_the_journal_grows_with_the_story() -> void:
	var before := JournalView.entries().size()
	GameState.set_flag(&"met_zeus")
	GameState.grant_ability(&"song:zeus")
	var after := JournalView.entries()
	assert_gt(after.size(), before)
	assert_eq(after[0]["id"], "_songs", "the songs page comes first once he knows one")


# --- fights -------------------------------------------------------------------------------

func _arena() -> Orpheus:
	var arena := Node2D.new()
	add_child_autofree(arena)
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000, 32)
	shape.shape = rect
	floor_body.position = Vector2(0, 16)
	floor_body.add_child(shape)
	arena.add_child(floor_body)
	var o := Orpheus.new()
	arena.add_child(o)
	await wait_physics_frames(3)
	return o


func test_a_standing_swing_passes_over_a_scorpion_but_a_crouch_strike_lands() -> void:
	GameState.grant_ability(&"club")
	var o := await _arena()
	var s := Enemy.create("scorpion")
	o.get_parent().add_child(s)
	s.global_position = Vector2(18, 0)
	await wait_physics_frames(2)
	o.kit.low = false
	assert_false(s.hurtbox().intersects(o.kit.club_box()), "too low for a standing swing")
	o.kit.low = true
	assert_true(s.hurtbox().intersects(o.kit.club_box()), "a crouch strike reaches it")


func test_crouching_makes_him_a_smaller_target() -> void:
	var o := await _arena()
	var standing := o.hurtbox()
	o.crouching = true
	assert_lt(o.hurtbox().size.y, standing.size.y)


func test_the_bulls_front_is_armour() -> void:
	var o := await _arena()
	var b := Enemy.create("colchis_bull") as Bull
	o.get_parent().add_child(b)
	b.global_position = Vector2(60, 0)
	await wait_physics_frames(1)
	b.facing = -1                        # facing Orpheus
	b.take_hit(3, 1, 0.0, false)         # Orpheus swings right, into its face
	assert_eq(b.hp, b.max_hp, "the bronze shrugs it off")
	b.take_hit(3, -1, 0.0, false)        # from behind
	assert_eq(b.hp, b.max_hp - 3)
	b.mode = "dazed"
	b.take_hit(3, 1, 0.0, false)         # dazed: anywhere
	assert_eq(b.hp, b.max_hp - 6)
