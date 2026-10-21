extends GutTest
## M1 movement feel: the numbers in content/movement.json do what they claim.

const DT := 1.0 / 60.0


func _airtime_near_apex(held: bool) -> int:
	var m := ContentDB.json("movement")
	var v := Vector2(0, float(m["jump_velocity"]))
	var frames := 0
	for i in 120:
		v = Orpheus.step_motion(v, 0.0, false, held, m, DT)
		if absf(v.y) < float(m["apex_window"]):
			frames += 1
		if v.y > 200.0:
			break
	return frames


func test_holding_jump_hangs_longer_at_the_top() -> void:
	assert_gt(_airtime_near_apex(true), _airtime_near_apex(false),
		"apex frames held %d vs released %d" % [_airtime_near_apex(true), _airtime_near_apex(false)])


func test_reversing_on_the_ground_brakes_harder_than_starting() -> void:
	var m := ContentDB.json("movement")
	var run := float(m["run_speed"])
	var turned := Orpheus.step_motion(Vector2(run, 0), -1.0, true, false, m, DT)
	var started := Orpheus.step_motion(Vector2.ZERO, 1.0, true, false, m, DT)
	assert_gt(run - turned.x, started.x, "turning sheds speed faster than starting gains it")


func test_hitstop_freezes_then_restores_time() -> void:
	Hitstop.freeze(get_tree(), 0.05)
	assert_true(Hitstop.active())
	await wait_seconds(0.15)
	assert_eq(Engine.time_scale, 1.0)


func test_respawn_point_follows_the_last_hearth() -> void:
	var world: Node2D = load("res://game/world/world_manager.gd").new()
	add_child_autofree(world)
	GameState.hearth_id = "arcadia_05:hearth_8_29"
	var spawn: Array = world.respawn_point()
	assert_eq(spawn[0], "arcadia_05")
	# Room origin (6, 0) cells; the Hearth's foot is the bottom-centre of tile (8, 29).
	assert_eq(spawn[1], Vector2(6 * 480 + 8.5 * 16, 30 * 16))
	GameState.hearth_id = ""
	assert_eq(world.respawn_point()[0], "arcadia_01", "no Hearth yet: back to the start")
