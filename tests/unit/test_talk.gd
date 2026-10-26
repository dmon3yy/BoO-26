extends GutTest
## Talking to people with real key presses, the way a player does. Regression:
## Enter (which the title screen teaches) used to do nothing in a conversation.

const WorldManager := preload("res://game/world/world_manager.gd")

var world: Node2D


func before_each() -> void:
	GameState.reset()
	Music.stop()


func after_each() -> void:
	get_tree().paused = false


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await wait_process_frames(2)


func _talk_through(confirm: Key, frames_between: int, room_id := "arcadia_01") -> void:
	world = WorldManager.new()
	add_child_autofree(world)
	world.start(room_id)
	await wait_physics_frames(3)
	var room: Room = world.rooms[room_id]
	world.talk_to(room.npcs[0])
	await wait_process_frames(3)
	var box: DialogueBox = null
	for c in world.get_children():
		if c is DialogueBox:
			box = c
	assert_not_null(box)
	var saw_replies := false
	for i in 60:
		if not is_instance_valid(box) or not box.visible:
			break
		await wait_process_frames(frames_between)
		if is_instance_valid(box) and not box._replies.is_empty():
			saw_replies = true
			await _key(KEY_DOWN)
			assert_eq(box._choice, 1, "Down moves to the second reply")
		await _key(confirm)
	if room_id == "arcadia_01":
		assert_true(saw_replies, "Eurydice offers replies")
		assert_true(GameState.get_flag(&"met_eurydice"), "the conversation reached its end")
	await wait_physics_frames(2)
	assert_false(get_tree().paused, "and the world runs again")


func test_enter_answers_and_moves_on() -> void:
	await _talk_through(KEY_ENTER, 4)


func test_jump_works_too_even_when_pressed_impatiently() -> void:
	await _talk_through(KEY_Z, 2)


func test_space_works_too() -> void:
	await _talk_through(KEY_SPACE, 4)


func test_enter_works_with_zeus() -> void:
	await _talk_through(KEY_ENTER, 4, "arcadia_06")
	assert_true(GameState.has_ability(&"lyre"), "he restrung the lyre")
	assert_true(GameState.get_flag(&"met_zeus"))
