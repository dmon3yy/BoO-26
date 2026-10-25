class_name Narrator
extends CanvasLayer
## Hermes, telling the story while you play: captions across the top of the
## screen that type themselves out and move on by themselves. The game never
## stops for him. Lines come from content/narration.json.

const CHARS_PER_SECOND := 38.0
const HOLD := 1.6                  # seconds a finished line stays up, plus a little per word
const BOX := Rect2(100, 6, 272, 30)

var _queue: Array = []
var _panel: Panel
var _name: Label
var _text: Label
var _t := 0.0
var _line_time := 0.0


func _ready() -> void:
	layer = 14
	_panel = UiKit.panel(BOX, 0.7)
	add_child(_panel)
	_name = UiKit.label("HERMES", BOX.position + Vector2(6, 3), Color(0.6, 0.85, 0.95))
	add_child(_name)
	_text = UiKit.label("", BOX.position + Vector2(6, 12), UiKit.INK, BOX.size.x - 12)
	add_child(_text)
	_set_shown(false)


## Queue some lines. Each is a string, or [speaker, text] for someone else.
func say(lines: Array) -> void:
	_queue.append_array(lines)
	if not _panel.visible:
		_next()


func busy() -> bool:
	return _panel.visible


func _next() -> void:
	if _queue.is_empty():
		_set_shown(false)
		return
	var line: Variant = _queue.pop_front()
	var who := "HERMES"
	var text := str(line)
	if line is Array:
		who = String(line[0]).to_upper()
		text = String(line[1])
	_name.text = who
	_text.text = text
	_text.visible_characters = 0
	_t = 0.0
	_line_time = text.length() / CHARS_PER_SECOND + HOLD + text.split(" ").size() * 0.12
	# Tall enough for the wrapped text.
	var rows := ceili(UiKit.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / (BOX.size.x - 12)) + 1
	_panel.size.y = 14 + rows * 9
	_set_shown(true)


func _set_shown(on: bool) -> void:
	_panel.visible = on
	_name.visible = on
	_text.visible = on


func _process(delta: float) -> void:
	if not _panel.visible or get_tree().paused:
		return
	_t += delta
	_text.visible_characters = int(_t * CHARS_PER_SECOND)
	if _t >= _line_time:
		_next()
