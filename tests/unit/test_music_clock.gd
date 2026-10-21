extends GutTest
## Beat grading: the maths behind "on the beat" bonuses.

const M := preload("res://game/autoload/music.gd")


func test_nearest_beat_delta_at_120bpm() -> void:
	# 120 bpm = 0.5 s per beat
	assert_almost_eq(M.nearest_beat_delta(1.0, 120.0, 0.0), 0.0, 1e-6)
	assert_almost_eq(M.nearest_beat_delta(1.03, 120.0, 0.0), 0.03, 1e-6)
	assert_almost_eq(M.nearest_beat_delta(0.97, 120.0, 0.0), -0.03, 1e-6)
	assert_almost_eq(M.nearest_beat_delta(1.2, 120.0, 0.0), 0.2, 1e-6)
	assert_almost_eq(M.nearest_beat_delta(1.3, 120.0, 0.0), -0.2, 1e-6)


func test_offset_shifts_the_grid() -> void:
	assert_almost_eq(M.nearest_beat_delta(1.1, 120.0, 0.1), 0.0, 1e-6)


func test_grade_windows() -> void:
	assert_eq(M.grade_delta(0.0, false), M.Grade.PERFECT)
	assert_eq(M.grade_delta(-0.049, false), M.Grade.PERFECT)
	assert_eq(M.grade_delta(0.07, false), M.Grade.GOOD)
	assert_eq(M.grade_delta(0.15, false), M.Grade.MISS)


func test_rhythm_assist_widens_windows() -> void:
	assert_eq(M.grade_delta(0.07, true), M.Grade.PERFECT)
	assert_eq(M.grade_delta(0.15, true), M.Grade.GOOD)
