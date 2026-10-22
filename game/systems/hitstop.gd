class_name Hitstop
extends RefCounted
## Hitstop: freeze the whole game for a few frames so a hit lands with weight.
##
##   Hitstop.freeze(get_tree(), 0.06)
##   while Hitstop.active(): await get_tree().process_frame    # to wait it out
##
## A small watcher node counts real (unscaled) milliseconds and wakes the game
## back up. Overlapping calls keep the longest freeze instead of stacking.
## "Frozen" is a time scale of 1%, not 0, so physics never divides by zero.

const FROZEN := 0.01

static var _until_ms := 0


static func freeze(tree: SceneTree, seconds: float) -> void:
	_until_ms = maxi(_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = FROZEN
	if not tree.root.has_node("HitstopWatcher"):
		var w := Watcher.new()
		w.name = "HitstopWatcher"
		tree.root.add_child(w)


static func active() -> bool:
	return Engine.time_scale <= FROZEN


class Watcher:
	extends Node

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		if Time.get_ticks_msec() >= Hitstop._until_ms:
			Engine.time_scale = 1.0
			name = "HitstopWatcherDone"     # a freeze this frame gets a fresh watcher
			queue_free()
