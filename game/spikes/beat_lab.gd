extends Control
## Beat Lab (M0 spike): does "on the beat" feel right on *your* device?
##
##   JUMP     tap along to the beat; each tap is graded
##   ITEM     auto-calibrate: tap 16 beats, the average error becomes your input offset
##   ←/→      nudge input offset (5 ms)      ↑/↓  nudge visual offset (5 ms)
##   ATTACK   toggle rhythm assist           LYRE  switch song
##   PAUSE    save settings and return to the game
##
## The numbers on screen (output latency, threads, isolation) are what the web
## audio decision in docs/learn/M0.md is based on.

const SONGS := ["metronome", "erebos", "arcadia"]

var _song := 0
var _deltas: Array[float] = []
var _calibrating := 0
var _cal: Array[float] = []
var _grade_label: Label
var _stats_label: Label
var _info_label: Label
var _offsets_label: Label
var _last_grade := -1
var _flash := 0.0
var _dial: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var dial := Control.new()
	dial.set_anchors_preset(Control.PRESET_FULL_RECT)
	dial.draw.connect(_draw_dial.bind(dial))
	add_child(dial)
	_dial = dial
	add_child(UiKit.label("BEAT LAB", Vector2(16, 10), UiKit.GOLD))
	add_child(UiKit.label("JUMP: tap on the beat   ITEM: auto-calibrate (16 taps)   ATTACK: assist", Vector2(16, 24), UiKit.DIM))
	add_child(UiKit.label("LEFT/RIGHT: input offset   UP/DOWN: visual offset   LYRE: song   PAUSE: save + exit", Vector2(16, 35), UiKit.DIM))
	_grade_label = UiKit.label("", Vector2(200, 168), UiKit.INK)
	add_child(_grade_label)
	_stats_label = UiKit.label("", Vector2(16, 196), UiKit.INK, 448)
	add_child(_stats_label)
	_offsets_label = UiKit.label("", Vector2(16, 222), UiKit.INK, 448)
	add_child(_offsets_label)
	_info_label = UiKit.label(_platform_info(), Vector2(16, 248), UiKit.DIM, 448)
	add_child(_info_label)
	var forced := OS.get_environment("BOO_LAB_SONG")
	if forced != "":
		_song = maxi(0, SONGS.find(forced))
	Music.play_theme(SONGS[_song])


func _platform_info() -> String:
	var isolated := "n/a"
	if OS.has_feature("web"):
		isolated = str(JavaScriptBridge.eval("self.crossOriginIsolated", true))
	return "driver %s  mix %d Hz  latency %.0f ms  threads %s  isolated %s" % [
		AudioServer.get_driver_name(), int(AudioServer.get_mix_rate()),
		AudioServer.get_output_latency() * 1000.0, str(OS.has_feature("threads")), isolated]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"jump"):
		_tap()
	elif event.is_action_pressed(&"item"):
		_calibrating = 16
		_cal.clear()
	elif event.is_action_pressed(&"attack"):
		Settings.rhythm_assist = not Settings.rhythm_assist
	elif event.is_action_pressed(&"lyre"):
		_song = (_song + 1) % SONGS.size()
		Music.play_theme(SONGS[_song])
	elif event.is_action_pressed(&"move_left"):
		Settings.input_offset -= 0.005
	elif event.is_action_pressed(&"move_right"):
		Settings.input_offset += 0.005
	elif event.is_action_pressed(&"up"):
		Settings.visual_offset += 0.005
	elif event.is_action_pressed(&"down"):
		Settings.visual_offset -= 0.005
	elif event.is_action_pressed(&"pause"):
		Settings.save_settings()
		get_tree().change_scene_to_file("res://game/main.tscn")


func _tap() -> void:
	var r := Music.grade_now()
	_last_grade = r["grade"]
	_flash = 1.0
	_deltas.append(r["delta"])
	if _deltas.size() > 16:
		_deltas.pop_front()
	if _calibrating > 0:
		# Calibrate on the raw error, before the current offset is applied.
		_cal.append(r["delta"] + Settings.input_offset)
		_calibrating -= 1
		if _calibrating == 0:
			var mean := 0.0
			for d in _cal:
				mean += d
			Settings.input_offset = mean / _cal.size()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	var names := ["MISS", "GOOD", "PERFECT"]
	if _last_grade >= 0 and not _deltas.is_empty():
		_grade_label.text = "%s  %+d ms" % [names[_last_grade], int(_deltas[-1] * 1000.0)]
	var mean := 0.0
	var sd := 0.0
	if not _deltas.is_empty():
		for d in _deltas:
			mean += d
		mean /= _deltas.size()
		for d in _deltas:
			sd += (d - mean) * (d - mean)
		sd = sqrt(sd / _deltas.size())
	_stats_label.text = "last %d taps: mean %+d ms, spread %d ms%s" % [_deltas.size(), int(mean * 1000.0),
		int(sd * 1000.0), ("   CALIBRATING: %d taps left" % _calibrating) if _calibrating > 0 else ""]
	_offsets_label.text = "input offset %+d ms   visual offset %+d ms   assist %s   song %s @ %d bpm" % [
		int(Settings.input_offset * 1000.0), int(Settings.visual_offset * 1000.0),
		"on" if Settings.rhythm_assist else "off", Music.song_id, int(Music.bpm)]
	_dial.queue_redraw()


func _draw_dial(d: Control) -> void:
	var c := Vector2(240, 105)
	var p := Music.pulse()
	d.draw_circle(c, 18.0 + 30.0 * p, Color(0.95, 0.6, 0.25, 0.15 + 0.5 * p))
	d.draw_circle(c, 14.0, Color(0.95, 0.78, 0.38))
	var beat := int(floor(Music.beat_position()))
	for i in Music.beats_per_bar:
		var on := posmod(beat, Music.beats_per_bar) == i
		d.draw_rect(Rect2(c.x - 30 + i * 16, c.y + 44, 10, 4), UiKit.GOLD if on else Color(0.3, 0.3, 0.4))
	if _flash > 0.0 and _last_grade >= 0:
		var cols := [Color(0.8, 0.2, 0.2), Color(0.5, 0.8, 1.0), Color(1.0, 0.9, 0.4)]
		var col: Color = cols[_last_grade]
		col.a = _flash
		d.draw_arc(c, 48.0, 0, TAU, 48, col, 2.0)
