class_name JournalView
extends CanvasLayer
## Orpheus's journal, opened from the pause menu: every song he knows (with
## its notes), and every hint, god and promise so far. Entries live in
## content/journal.json, each with a `when`: "flag:met_zeus",
## "ability:club", "room:arcadia_08" or "always". Nothing is stored: the
## journal is worked out from the game state, so a Word restores it too.
##
## Up/Down pick an entry; Esc, Jump or Pause close it.

signal closed

const LIST := Rect2(24, 34, 130, 210)
const PAGE := Rect2(162, 34, 294, 210)

var _entries: Array = []
var _sel := 0
var _canvas: Control
var _labels: Array[Label] = []
var _title: Label
var _text: Label


static func unlocked(when: String) -> bool:
	if when == "always":
		return true
	var kind := when.get_slice(":", 0)
	var what := when.substr(kind.length() + 1)
	match kind:
		"flag": return GameState.get_flag(StringName(what)) == true
		"ability": return GameState.has_ability(StringName(what))
		"room": return GameState.visited_rooms.has(what)
	return false


## The entries Orpheus has so far, songs first.
static func entries() -> Array:
	var out := []
	var songs := ContentDB.json("songs")
	var known := []
	for id in songs:
		if not id.begins_with("_") and GameState.has_ability(StringName("song:" + id)):
			known.append(id)
	if not known.is_empty():
		out.append({"id": "_songs", "title": "Songs", "songs": known,
			"text": "Hold the lyre (Shift), then play the notes with the arrows. Z is the middle string: press Jump (Z or Space). Combat songs cost Muse; on the beat, half."})
	for e in ContentDB.json("journal").get("entries", []):
		if unlocked(String(e.get("when", "always"))):
			out.append(e)
	return out


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.07, 0.96)
	bg.size = Vector2(480, 270)
	add_child(bg)
	add_child(UiKit.label("JOURNAL", Vector2(24, 14), UiKit.GOLD))
	add_child(UiKit.panel(LIST, 0.5))
	add_child(UiKit.panel(PAGE, 0.5))
	_canvas = Control.new()
	_canvas.size = Vector2(480, 270)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_songs)
	add_child(_canvas)
	_title = UiKit.label("", PAGE.position + Vector2(8, 6), UiKit.GOLD)
	add_child(_title)
	_text = UiKit.label("", PAGE.position + Vector2(8, 20), UiKit.INK, PAGE.size.x - 16)
	add_child(_text)
	add_child(UiKit.label("UP/DOWN: choose   ESC: back", Vector2(24, 252), UiKit.DIM))
	_entries = entries()
	for i in _entries.size():
		var l := UiKit.label("", LIST.position + Vector2(6, 6 + i * 11), UiKit.INK)
		add_child(l)
		_labels.append(l)
	if _entries.is_empty():
		_text.text = "Nothing yet. The story has barely started."
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"jump") or event.is_action_pressed(&"attack"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
		return
	if _entries.is_empty():
		return
	if event.is_action_pressed(&"up"):
		_sel = posmod(_sel - 1, _entries.size())
	elif event.is_action_pressed(&"down"):
		_sel = posmod(_sel + 1, _entries.size())
	else:
		return
	get_viewport().set_input_as_handled()
	_refresh()


func _refresh() -> void:
	for i in _labels.size():
		_labels[i].text = ("> " if i == _sel else "  ") + String(_entries[i]["title"])
		_labels[i].add_theme_color_override("font_color", UiKit.GOLD if i == _sel else UiKit.INK)
	if _entries.is_empty():
		return
	var e: Dictionary = _entries[_sel]
	_title.text = String(e["title"])
	_text.text = String(e.get("text", ""))
	_canvas.queue_redraw()


## The Songs page: each song's name and its notes, drawn as arrows.
func _draw_songs() -> void:
	if _entries.is_empty() or not _entries[_sel].has("songs"):
		return
	var songs := ContentDB.json("songs")
	var y := PAGE.position.y + 74
	var f := UiKit.font()
	for id in _entries[_sel]["songs"]:
		var song: Dictionary = songs[id]
		_canvas.draw_string(f, Vector2(PAGE.position.x + 10, y), String(song["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.INK)
		var x := PAGE.position.x + 150
		for n in song["notes"]:
			_draw_note(Vector2(x, y - 3), String(n))
			x += 13
		var cost := "free" if song.get("kind", "") != "combat" else "%d Muse" % int(song.get("cost", 0))
		_canvas.draw_string(f, Vector2(PAGE.position.x + 220, y), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.DIM)
		y += 16


func _draw_note(at: Vector2, note: String) -> void:
	var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
	_canvas.draw_circle(at, 6.0, Color(0.2, 0.17, 0.12))
	if not dirs.has(note):
		# The middle string is played with Jump, so it shows Jump's key.
		_canvas.draw_string(UiKit.font(), at + Vector2(-2.5, 3.5), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.GOLD)
		return
	var d: Vector2 = dirs[note]
	var side := Vector2(-d.y, d.x)
	_canvas.draw_colored_polygon(PackedVector2Array([at + d * 4, at - d * 3 + side * 3.5, at - d * 3 - side * 3.5]), UiKit.GOLD)
