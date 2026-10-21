extends GutTest
## The controller must really achieve the limits the world validator relies on
## (content/movement.json -> "limits").

const DT := 1.0 / 60.0
const BODY_W := 10.0


func _jump(hold_frames: int) -> Dictionary:
	var m := ContentDB.json("movement")
	var v := Vector2(float(m["run_speed"]), float(m["jump_velocity"]))
	var p := Vector2.ZERO
	var apex := 0.0
	var frame := 0
	while true:
		v = Orpheus.step_motion(v, 1.0, false, frame < hold_frames, m, DT, frame == hold_frames)
		p += v * DT
		apex = minf(apex, p.y)
		frame += 1
		if v.y > 0.0 and p.y >= 0.0:
			break
	return {"apex": -apex, "distance": p.x}


func test_full_jump_clears_declared_height() -> void:
	var lim: Dictionary = ContentDB.json("movement")["limits"]
	var r := _jump(999)
	assert_gte(r["apex"], float(lim["jump_height_tiles"]) * 16.0,
		"apex %.1fpx must reach %d tiles" % [r["apex"], lim["jump_height_tiles"]])


func test_full_jump_clears_declared_gap() -> void:
	var lim: Dictionary = ContentDB.json("movement")["limits"]
	var r := _jump(999)
	# The body may hang half its width over each edge.
	assert_gte(r["distance"] + BODY_W, float(lim["jump_gap_tiles"]) * 16.0,
		"flight %.1fpx must cross %d tiles" % [r["distance"], lim["jump_gap_tiles"]])


func test_tapping_jump_gives_a_short_hop() -> void:
	var full := _jump(999)
	var hop := _jump(4)
	assert_lt(hop["apex"], full["apex"] * 0.6, "hop %.1fpx vs full %.1fpx" % [hop["apex"], full["apex"]])


func test_ground_acceleration_reaches_run_speed() -> void:
	var m := ContentDB.json("movement")
	var v := Vector2.ZERO
	for i in 30:
		v = Orpheus.step_motion(v, 1.0, true, false, m, DT)
	assert_almost_eq(v.x, float(m["run_speed"]), 0.01)
