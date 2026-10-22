extends Node
## Review captures: drive Orpheus from a scripted timeline and save frames.
##
## Run under a real (software) renderer, e.g.
##   BOO_CAPTURE=/abs/out/shot BOO_CAPTURE_AT=60,120 BOO_INPUT="right@10-90;jump@40" \
##   xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy
##
## BOO_INPUT entries are action@frame or action@first-last, separated by ';'.
## BOO_PLAYER_AT="x,y" moves Orpheus (world pixels) before the first frame.

var _frame := 0
var _shots: Array[int] = []
var _prefix := ""
var _timeline: Array = []          # [action, first, last]
var controls := ScriptedControls.new()


func _ready() -> void:
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS     # keep counting while the map pauses the game
	process_physics_priority = -100
	_prefix = OS.get_environment("BOO_CAPTURE")
	for s in OS.get_environment("BOO_CAPTURE_AT").split(",", false):
		_shots.append(int(s))
	_shots.sort()
	for entry in OS.get_environment("BOO_INPUT").split(";", false):
		var parts := entry.split("@")
		var span := parts[1].split("-")
		_timeline.append([StringName(parts[0]), int(span[0]), int(span[-1])])


func attach(player: Orpheus) -> void:
	player.controls = controls
	var at := OS.get_environment("BOO_PLAYER_AT")
	if at != "":
		var xy := at.split(",")
		player.global_position = Vector2(float(xy[0]), float(xy[1]))


func _physics_process(_delta: float) -> void:
	controls.update(_timeline, _frame)
	_frame += 1


func _process(_delta: float) -> void:
	if _shots.is_empty():
		return
	if _frame >= _shots[0]:
		var n: int = _shots.pop_front()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%04d.png" % [_prefix, n])
		print("captured %s_%04d.png" % [_prefix, n])
		if _shots.is_empty():
			get_tree().quit()


class ScriptedControls:
	extends RefCounted
	var _held := {}
	var _pressed := {}

	func update(timeline: Array, frame: int) -> void:
		var now := {}
		for t in timeline:
			if frame >= t[1] and frame <= t[2]:
				now[t[0]] = true
		_pressed.clear()
		for a in now:
			if not _held.has(a):
				_pressed[a] = true
				_send(a, true)
		for a in _held:
			if not now.has(a):
				_send(a, false)
		_held = now

	## Also feed real input events, so menus and dialogue see the script too.
	func _send(action: StringName, down: bool) -> void:
		var name := action
		if action == &"right":
			name = &"move_right"
		elif action == &"left":
			name = &"move_left"
		if not InputMap.has_action(name):
			return
		var ev := InputEventAction.new()
		ev.action = name
		ev.pressed = down
		Input.parse_input_event(ev)

	func axis() -> float:
		return (1.0 if _held.has(&"right") else 0.0) - (1.0 if _held.has(&"left") else 0.0)

	func held(action: StringName) -> bool:
		return _held.has(action)

	func pressed(action: StringName) -> bool:
		return _pressed.has(action)
