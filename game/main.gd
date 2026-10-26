extends Node2D
## Entry point: the title screen, then the world.
##
## Environment switches (used by tools and CI, ignored otherwise):
##   BOO_START_ROOM  skip the title and start in a specific room
##   BOO_CAPTURE     save review frames (see game/spikes/capture.gd); skips the title
##   BOO_STATE       "full" gives Orpheus his whole early kit (for captures and testing)
##   BOO_TITLE       show the title screen even while capturing
##   BOO_OLIVES      start with this many olives
##   BOO_DROP        "x,y": olives (half of BOO_OLIVES) already lie there

const WorldManager := preload("res://game/world/world_manager.gd")
const Capture := preload("res://game/spikes/capture.gd")

var world: Node2D


func _ready() -> void:
	var capture: Node = null
	if OS.get_environment("BOO_CAPTURE") != "":
		# Lives on the root so captures survive scene changes.
		capture = Capture.new()
		get_tree().root.add_child.call_deferred(capture)
	if _wants_beat_lab():
		get_tree().change_scene_to_file.call_deferred("res://game/spikes/beat_lab.tscn")
		return
	var start := OS.get_environment("BOO_START_ROOM")
	if (start != "" or OS.get_environment("BOO_CAPTURE") != "") and OS.get_environment("BOO_TITLE") == "":
		if OS.get_environment("BOO_STATE") == "full":
			for a in ["lyre", "club", "song:zeus", "song:hymn", "song:charm"]:
				GameState.grant_ability(StringName(a))
		GameState.olives = int(OS.get_environment("BOO_OLIVES"))
		var drop := OS.get_environment("BOO_DROP").split(",")
		if drop.size() == 2:
			GameState.drop_olives_on_death(start, Vector2(float(drop[0]), float(drop[1])))
		_start_world(start if start != "" else GameState.room_id, false)
		if capture:
			capture.attach.call_deferred(world.player)
		if OS.get_environment("BOO_DIALOGUE") != "":
			_open_dialogue.call_deferred(OS.get_environment("BOO_DIALOGUE"))
		return
	var title := TitleScreen.new()
	add_child(title)
	title.chosen.connect(func(how: String):
		title.queue_free()
		_start_world(GameState.room_id, how != "new"))


## Build the world. `at_hearth` wakes Orpheus at his last Hearth (Continue,
## or a Word); otherwise he starts where the room says.
func _start_world(room_id: String, at_hearth: bool) -> void:
	world = WorldManager.new()
	world.name = "World"
	add_child(world)
	if at_hearth and GameState.hearth_id != "":
		var spawn: Array = world.respawn_point()
		world.start(spawn[0])
		world.place_player(spawn[0], spawn[1])
	else:
		world.start(room_id)


func _open_dialogue(id: String) -> void:
	if world == null:
		return
	var box := DialogueBox.new()
	add_child(box)
	world.player.frozen = true
	box.finished.connect(func(): world.player.frozen = false; box.queue_free())
	box.start(load("res://content/dialogue/%s.dialogue" % id))


## The Beat Lab opens with BOO_SCENE=beat_lab, or "?lab" in the web build's URL.
func _wants_beat_lab() -> bool:
	if OS.get_environment("BOO_SCENE") == "beat_lab":
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.search", true)).contains("lab")
	return false


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if event.is_action_pressed(&"debug_dialogue"):
		_open_dialogue("zeus")
		return
	if event.is_action_pressed(&"debug_beat_lab"):
		get_tree().change_scene_to_file("res://game/spikes/beat_lab.tscn")
		return
	if event.is_action_pressed(&"debug_next_room"):
		# Cycle the art-bar rooms during M0 review.
		var ids: Array = ContentDB.json("world")["rooms"].keys()
		var next: String = ids[(ids.find(GameState.room_id) + 1) % ids.size()]
		world.queue_free()
		world = WorldManager.new()
		add_child(world)
		world.start(next)
