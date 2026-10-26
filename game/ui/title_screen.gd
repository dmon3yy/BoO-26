class_name TitleScreen
extends CanvasLayer
## The title: Continue (from the last Hearth), New game, or Enter a Word.
## Emits `chosen` with "continue", "new" or "word" once the game state is
## ready to start.

signal chosen(how: String)

var _lines: Array[String] = []
var _labels: Array[Label] = []
var _sel := 0
var _word_box: LineEdit
var _message: Label
var _t := 0.0
var _title: Label


func _ready() -> void:
	layer = 30
	var theme: Dictionary = ContentDB.json("themes")["arcadia_winter"]
	for layer_spec in theme["backgrounds"]:
		var s := Sprite2D.new()
		s.texture = ContentDB.texture("res://game/art/backgrounds/%s.png" % layer_spec["tex"])
		s.centered = false
		add_child(s)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.06, 0.45)
	shade.size = Vector2(480, 270)
	add_child(shade)
	_title = UiKit.label("BALLAD OF ORPHEUS", Vector2(0, 52), UiKit.GOLD)
	_title.scale = Vector2(3, 3)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size.x = 160
	add_child(_title)
	var sub := UiKit.label("a song against the winter", Vector2(0, 86), UiKit.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size.x = 480
	add_child(sub)
	if FileAccess.file_exists(Save.slot_path(0)):
		_lines.append("Continue")
	_lines.append_array(["New game", "Enter a Word"])
	for i in _lines.size():
		var l := UiKit.label("", Vector2(0, 140 + i * 16), UiKit.INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size.x = 480
		add_child(l)
		_labels.append(l)
	_message = UiKit.label("", Vector2(0, 204), UiKit.DIM)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.size.x = 480
	add_child(_message)
	var keys := UiKit.label("UP/DOWN: choose   JUMP or ENTER: start", Vector2(0, 250), UiKit.DIM)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.size.x = 480
	add_child(keys)
	Music.play_theme("arcadia")
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	_title.position.y = 52 + roundf(sin(_t * 1.2) * 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _word_box:
		if event.is_action_pressed(&"pause") and not event is InputEventKey:
			_close_word_box()
		return
	if event.is_action_pressed(&"up"):
		_sel = posmod(_sel - 1, _lines.size())
	elif event.is_action_pressed(&"down"):
		_sel = posmod(_sel + 1, _lines.size())
	elif event.is_action_pressed(&"jump") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"attack"):
		_choose(_lines[_sel])
	else:
		return
	get_viewport().set_input_as_handled()
	_refresh()


func _refresh() -> void:
	for i in _labels.size():
		_labels[i].text = ("> " + _lines[i] + " <") if i == _sel else _lines[i]
		_labels[i].add_theme_color_override("font_color", UiKit.GOLD if i == _sel else UiKit.INK)


func _choose(line: String) -> void:
	match line:
		"Continue":
			if Save.load_game(0) == OK:
				chosen.emit("continue")
			else:
				_message.text = "That save couldn't be read. Try your Word."
		"New game":
			GameState.reset()
			chosen.emit("new")
		"Enter a Word":
			_open_word_box()


func _open_word_box() -> void:
	_message.text = "Type or paste your Word, then press Enter. (Esc: back)"
	_word_box = LineEdit.new()
	_word_box.position = Vector2(90, 216)
	_word_box.size = Vector2(300, 16)
	_word_box.add_theme_font_override("font", UiKit.font())
	_word_box.add_theme_font_size_override("font_size", 8)
	_word_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word_box.placeholder_text = "XXXX-XXXX-XXXX"
	add_child(_word_box)
	_word_box.grab_focus()
	_word_box.text_submitted.connect(_try_word)
	_word_box.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_close_word_box.call_deferred())


func _close_word_box() -> void:
	if _word_box:
		_word_box.queue_free()
		_word_box = null
	_message.text = ""


func _try_word(text: String) -> void:
	if Save.read_word(text) == OK:
		chosen.emit("word")
	else:
		_message.text = "That Word doesn't ring true. Check it and try again."
