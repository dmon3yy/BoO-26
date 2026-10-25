class_name PauseMenu
extends CanvasLayer
## Esc / Enter / Start pauses (and resumes). Up and Down pick a line, Jump
## chooses it, Left and Right change a setting. The rhythm settings live
## here: assist widens the beat windows, and the Beat Lab measures your own
## device's audio and input delay so "on the beat" means on the beat for you.

signal closed

## Asked before opening (the world says no while dying, resting or on the map).
var can_open: Callable = func(): return true

const LINES := ["Resume", "Journal", "Rhythm assist", "Input offset", "Calibrate the beat (Beat Lab)", "Screen shake"]

var _sel := 0
var _labels: Array[Label] = []
var _lab: Control
var _journal: JournalView


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.88)
	bg.size = Vector2(480, 270)
	add_child(bg)
	add_child(UiKit.label("PAUSED", Vector2(40, 40), UiKit.GOLD))
	for i in LINES.size():
		var l := UiKit.label("", Vector2(40, 70 + i * 16), UiKit.INK)
		add_child(l)
		_labels.append(l)
	add_child(UiKit.label("UP/DOWN: choose   JUMP: select   LEFT/RIGHT: change   ESC: resume", Vector2(40, 240), UiKit.DIM))


func open() -> void:
	visible = true
	_sel = 0
	get_tree().paused = true
	_refresh()


func close() -> void:
	visible = false
	Settings.save_settings()
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed(&"pause") and not get_tree().paused and can_open.call():
			open()
			get_viewport().set_input_as_handled()
		return
	if _lab or is_instance_valid(_journal):
		return
	if event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"up"):
		_sel = posmod(_sel - 1, LINES.size())
	elif event.is_action_pressed(&"down"):
		_sel = posmod(_sel + 1, LINES.size())
	elif event.is_action_pressed(&"move_left"):
		_change(-1)
	elif event.is_action_pressed(&"move_right"):
		_change(1)
	elif event.is_action_pressed(&"jump"):
		_choose()
	else:
		return
	get_viewport().set_input_as_handled()
	_refresh()


func _change(dir: int) -> void:
	match _sel:
		2: Settings.rhythm_assist = not Settings.rhythm_assist
		3: Settings.input_offset += dir * 0.005
		5: Settings.screen_shake = not Settings.screen_shake


func _choose() -> void:
	match _sel:
		0: close()
		1: open_journal()
		4: _open_lab()
		_: _change(1)


func open_journal() -> void:
	_journal = JournalView.new()
	_journal.closed.connect(func(): _journal = null; _refresh())
	add_child(_journal)


func _open_lab() -> void:
	_lab = load("res://game/spikes/beat_lab.tscn").instantiate()
	_lab.overlay = true
	_lab.process_mode = Node.PROCESS_MODE_ALWAYS
	_lab.tree_exited.connect(func(): _lab = null; _refresh())
	add_child(_lab)


func _refresh() -> void:
	var values := ["", "", "on" if Settings.rhythm_assist else "off",
		"%+d ms" % int(round(Settings.input_offset * 1000.0)), "", "on" if Settings.screen_shake else "off"]
	for i in LINES.size():
		var v: String = values[i]
		_labels[i].text = ("> " if i == _sel else "  ") + LINES[i] + ("   " + v if v != "" else "")
		_labels[i].add_theme_color_override("font_color", UiKit.GOLD if i == _sel else UiKit.INK)
