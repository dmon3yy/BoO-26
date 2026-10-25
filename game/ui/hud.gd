class_name Hud
extends CanvasLayer
## The heads-up display: health, the Muse meter, the beat, and the lyre.
##
##   top left    health (each pip is 2 HP) and the Muse meter
##   top right   the beat pulse, and how your last timed input was graded
##   above him   the notes you're playing while holding the lyre
##
## It only listens to Events and reads the player, so nothing in combat
## knows the HUD exists.

const PIP := 2                       # HP per pip
const GRADE_NAMES := ["MISS", "GOOD", "PERFECT"]
const GRADE_COLORS := [Color(0.85, 0.35, 0.3), Color(0.55, 0.8, 1.0), Color(1.0, 0.85, 0.4)]

var player: Orpheus
var camera: Camera2D

var _hp := 12
var _max_hp := 12
var _muse := 0.0
var _max_muse := 100.0
var _grade := -1
var _grade_t := 0.0
var _song_label: Label
var _song_t := 0.0
var _canvas: Control


func _ready() -> void:
	layer = 12
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_song_label = UiKit.label("", Vector2(0, 40), UiKit.GOLD)
	_song_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_song_label.size.x = 480
	add_child(_song_label)
	Events.player_hp_changed.connect(func(hp, m): _hp = hp; _max_hp = m)
	Events.muse_changed.connect(func(v, m): _muse = v; _max_muse = m)
	Events.beat_graded.connect(_on_graded)
	Events.song_played.connect(_on_song)


func _on_graded(grade: int, what: String) -> void:
	if what == "song_failed":
		_song_label.text = "Not enough Muse"
		_song_t = 1.5
		return
	_grade = grade
	_grade_t = 0.5


func _on_song(id: String, _at: Vector2) -> void:
	_song_label.text = ContentDB.json("songs")[id].get("name", id)
	_song_t = 2.0


func _process(delta: float) -> void:
	_grade_t = maxf(0.0, _grade_t - delta)
	_song_t = maxf(0.0, _song_t - delta)
	_song_label.modulate.a = clampf(_song_t, 0.0, 1.0)
	_canvas.queue_redraw()


func _draw_hud() -> void:
	var c := _canvas
	# Health: one pip per 2 HP, full, half or empty.
	for i in ceili(_max_hp / float(PIP)):
		var at := Vector2(10 + i * 11, 10)
		var fill := clampi(_hp - i * PIP, 0, PIP)
		c.draw_circle(at, 4.5, Color(0, 0, 0, 0.6))
		c.draw_circle(at, 3.5, Color(0.3, 0.12, 0.14))
		if fill == PIP:
			c.draw_circle(at, 3.5, Color(0.86, 0.25, 0.3))
		elif fill > 0:
			c.draw_rect(Rect2(at - Vector2(3, 3), Vector2(3, 6)), Color(0.86, 0.25, 0.3))
	# Muse: a gold bar that glows when full.
	var bar := Rect2(6, 19, 60, 4)
	c.draw_rect(bar.grow(1), Color(0, 0, 0, 0.6))
	c.draw_rect(bar, Color(0.18, 0.15, 0.1))
	var k := _muse / maxf(_max_muse, 1.0)
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), UiKit.GOLD)
	c.draw_string(UiKit.font(), Vector2(70, 25), "MUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.DIM)

	# The beat: a dot that swells on every beat, ringed by your last grade.
	var dot := Vector2(466, 12)
	if Music.is_playing():
		var p := Music.pulse()
		c.draw_circle(dot, 3.0 + 3.0 * p, Color(UiKit.GOLD, 0.25 + 0.6 * p))
		c.draw_circle(dot, 2.0, UiKit.GOLD)
	if _grade >= 0 and _grade_t > 0.0:
		var col: Color = GRADE_COLORS[_grade]
		col.a = minf(1.0, _grade_t * 3.0)
		c.draw_arc(dot, 8.0, 0.0, TAU, 16, col, 1.0)
		c.draw_string(UiKit.font(), Vector2(380, 16), GRADE_NAMES[_grade], HORIZONTAL_ALIGNMENT_RIGHT, 72, 8, col)

	# The lyre: the notes played so far, drawn as arrows above Orpheus.
	if player and player.kit.state == "lyre" and camera:
		var head := player.global_position - camera.get_screen_center_position() + Vector2(240, 135) + Vector2(0, -44)
		var notes := player.kit.notes
		var start := head.x - notes.size() * 5.0
		for i in notes.size():
			var n: Dictionary = notes[i]
			_draw_note(c, Vector2(start + i * 10 + 5, head.y), n["note"], UiKit.GOLD if n["on_beat"] else UiKit.INK)


func _draw_note(c: Control, at: Vector2, note: String, col: Color) -> void:
	var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	if not dirs.has(note):
		c.draw_circle(at, 2.5, col)
		return
	var d: Vector2 = dirs[note]
	var side := Vector2(-d.y, d.x)
	c.draw_colored_polygon(PackedVector2Array([at + d * 4, at - d * 3 + side * 3.5, at - d * 3 - side * 3.5]), col)
