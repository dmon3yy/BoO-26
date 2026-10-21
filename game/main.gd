extends Node2D
## Entry point. For M0 this boots straight into the world so the art-bar rooms
## can be walked; a title screen arrives in M3.
##
## Environment switches (used by tools and CI, ignored otherwise):
##   BOO_START_ROOM  start in a specific room
##   BOO_CAPTURE     save review frames (see game/spikes/capture.gd)

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
	world = WorldManager.new()
	world.name = "World"
	add_child(world)
	var start := OS.get_environment("BOO_START_ROOM")
	world.start(start if start != "" else GameState.room_id)
	if capture:
		capture.attach.call_deferred(world.player)
	if OS.get_environment("BOO_DIALOGUE") != "":
		_open_dialogue.call_deferred(OS.get_environment("BOO_DIALOGUE"))


func _open_dialogue(id: String) -> void:
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
