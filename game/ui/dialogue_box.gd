class_name DialogueBox
extends CanvasLayer
## Shows Dialogue Manager conversations in the game's own pixel style.
##
##   var box := DialogueBox.new()
##   add_child(box)
##   box.start(load("res://content/dialogue/zeus.dialogue"), "start")
##
## JUMP or ATTACK advances (or finishes the typewriter); UP/DOWN pick a reply.

signal finished

const CHARS_PER_SECOND := 45.0
const BOTTOM := Rect2(8, 192, 464, 70)
const TOP := Rect2(8, 8, 464, 70)

## Where the box sits. The world puts it at the top when the speakers stand
## low on the screen, so the box never hides who's talking.
var at_top := false
var BOX := BOTTOM

var _resource: Resource
var _states: Array = []
var _line: DialogueLine
var _panel: Panel
var _speaker: Label
var _text: Label
var _replies: Array[Label] = []
var _choice := 0
var _typing := false
var _reply_panel: Panel


func _ready() -> void:
	layer = 20
	BOX = TOP if at_top else BOTTOM
	_panel = UiKit.panel(BOX)
	add_child(_panel)
	_speaker = UiKit.label("", BOX.position + Vector2(8, 5), UiKit.GOLD)
	add_child(_speaker)
	_text = UiKit.label("", BOX.position + Vector2(8, 18), UiKit.INK, BOX.size.x - 16)
	add_child(_text)
	visible = false


## `states` are extra objects the dialogue can read and change by name,
## e.g. [{"World": world}] lets a line say `do World.give_olives(5)`.
func start(resource: Resource, title: String = "start", states: Array = []) -> void:
	_resource = resource
	_states = states
	visible = true
	await _show(await DialogueManager.get_next_dialogue_line(_resource, title, _states))


func _show(line: DialogueLine) -> void:
	for r in _replies:
		r.queue_free()
	_replies.clear()
	_line = line
	if _line == null:
		visible = false
		finished.emit()
		return
	_speaker.text = _line.character
	_text.text = _line.text
	_text.visible_ratio = 0.0
	_typing = true
	var tw := create_tween()
	tw.tween_property(_text, "visible_ratio", 1.0, maxf(0.1, _line.text.length() / CHARS_PER_SECOND))
	tw.finished.connect(func(): _typing = false; _show_replies())


func _show_replies() -> void:
	if _line == null or _line.responses.is_empty():
		return
	_choice = 0
	var y := BOX.position.y - 12.0 * _line.responses.size() - 4.0
	if at_top:
		y = BOX.end.y + 8.0
	var reply_panel := UiKit.panel(Rect2(BOX.position.x + 180, y - 4, BOX.size.x - 180, 12.0 * _line.responses.size() + 6))
	add_child(reply_panel)
	_reply_panel = reply_panel
	for i in _line.responses.size():
		var l := UiKit.label("", Vector2(BOX.position.x + 188, y + i * 12.0), UiKit.INK)
		add_child(l)
		_replies.append(l)
	_refresh_replies()


func _refresh_replies() -> void:
	for i in _replies.size():
		var mark := "> " if i == _choice else "  "
		_replies[i].text = mark + _line.responses[i].text
		_replies[i].add_theme_color_override("font_color", UiKit.GOLD if i == _choice else UiKit.DIM)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _line == null:
		return
	var confirm := event.is_action_pressed(&"jump") or event.is_action_pressed(&"attack")
	if _typing:
		if confirm:
			_text.visible_ratio = 1.0
			get_viewport().set_input_as_handled()
		return
	if not _replies.is_empty():
		if event.is_action_pressed(&"up"):
			_choice = posmod(_choice - 1, _replies.size())
			_refresh_replies()
		elif event.is_action_pressed(&"down"):
			_choice = posmod(_choice + 1, _replies.size())
			_refresh_replies()
		elif confirm:
			var next_id: String = _line.responses[_choice].next_id
			_clear_reply_panel()
			get_viewport().set_input_as_handled()
			_show(await DialogueManager.get_next_dialogue_line(_resource, next_id, _states))
		get_viewport().set_input_as_handled()
		return
	if confirm:
		get_viewport().set_input_as_handled()
		_show(await DialogueManager.get_next_dialogue_line(_resource, _line.next_id, _states))


func _clear_reply_panel() -> void:
	if _reply_panel:
		_reply_panel.queue_free()
		_reply_panel = null
