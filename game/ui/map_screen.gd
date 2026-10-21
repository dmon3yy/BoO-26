class_name MapScreen
extends CanvasLayer
## The auto-map: every room you've visited, drawn on the world grid.
##
## MAP (Tab / M / the gamepad's Back button) opens and closes it; the game
## pauses while it's up. Rooms appear once you've been in them; the room
## you're in is lit, Orpheus is the blinking dot, Hearths are the embers.

const CELL := Vector2(36, 20)          # one screen-sized grid cell on the map
const BG := Color(0.04, 0.04, 0.08, 0.97)
const ROOM := Color(0.2, 0.24, 0.42)
const HERE := Color(0.36, 0.42, 0.7)
const EDGE := Color(0.72, 0.58, 0.32)
const EMBER := Color(1.0, 0.6, 0.25)

var world: Node                        # the WorldManager

var _canvas: Control
var _title: Label
var _blink := 0.0


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(480, 270)
	add_child(bg)
	_canvas = Control.new()
	_canvas.size = Vector2(480, 270)
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	_title = UiKit.label("", Vector2(16, 12), UiKit.GOLD)
	add_child(_title)
	add_child(UiKit.label("MAP: close", Vector2(16, 250), UiKit.DIM))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"map") or (visible and event.is_action_pressed(&"pause")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		var room: Room = world.current
		_title.text = "%s  -  rooms found: %d" % [room.data.header.get("name", room.data.id),
			GameState.visited_rooms.size()]
		_canvas.queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_blink += delta
		_canvas.queue_redraw()


## Map-space rectangle of a room, centred so the current room sits mid-screen.
func _room_rect(id: String) -> Rect2:
	var cell_px: Vector2 = world.cell_px
	var here: Rect2 = world.current.rect
	var centre := Vector2(240, 135) - (here.get_center() / cell_px) * CELL
	var data := ContentDB.room(id)
	var origin: Vector2 = world.room_origin[id]
	return Rect2(centre + origin / cell_px * CELL, data.size_px() / cell_px * CELL)


func _draw_map() -> void:
	for id in world.room_origin:
		if not GameState.visited_rooms.has(id):
			continue
		var r := _room_rect(id).grow(-1)
		_canvas.draw_rect(r, HERE if id == world.current.data.id else ROOM)
		_canvas.draw_rect(r, EDGE, false, 1.0)
		var data := ContentDB.room(id)
		for y in data.height:
			var x := data.map_rows[y].find("H")
			if x >= 0:
				var at := r.position + Vector2((x + 0.5) / data.width * r.size.x, (y + 0.5) / data.height * r.size.y)
				_canvas.draw_rect(Rect2(at.round() - Vector2(1, 1), Vector2(3, 3)), EMBER)
	if fmod(_blink, 0.8) < 0.5:
		var p: Vector2 = world.player.global_position
		var dot: Vector2 = Vector2(240, 135) + (p - world.current.rect.get_center()) / world.cell_px * CELL
		_canvas.draw_rect(Rect2(dot.round() - Vector2(1, 2), Vector2(3, 3)), Color.WHITE)
