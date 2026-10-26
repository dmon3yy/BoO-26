class_name Npc
extends Node2D
## Someone Orpheus can talk to: stand close and press UP. Who they are, how
## they look and which conversation they start all live in content/npcs.json.

var who := ""
var spec: Dictionary
var sheet: RigSprite


func _ready() -> void:
	spec = ContentDB.json("npcs")[who]
	z_index = 3
	sheet = RigSprite.new(String(spec["rig"]))
	sheet.facing = int(spec.get("facing", -1))
	add_child(sheet)
	sheet.play("idle")
	var l: Dictionary = spec.get("light", {})
	if not l.is_empty():
		add_child(FxNodes.light(Vector2(l["offset"][0], l["offset"][1]), l))
		var c: Array = l.get("color", [1, 1, 1])
		add_child(FxNodes.halo(Vector2(l["offset"][0], l["offset"][1]), Color(c[0], c[1], c[2], 0.5),
			float(l.get("halo", 30.0))))


## The conversation to start now. Each NPC can name a different dialogue
## title once a flag is raised (e.g. Zeus after he's restrung the lyre).
func dialogue_title() -> String:
	for step in spec.get("titles", []):
		if GameState.has(String(step[0])):
			return String(step[1])
	return String(spec.get("title", "start"))


func look_at_x(x: float) -> void:
	if spec.get("turns", true) and absf(x - global_position.x) > 4.0:
		sheet.facing = 1 if x > global_position.x else -1
