class_name RigSprite
extends Sprite2D
## A baked rig sheet (game/art/characters/<rig>.png and .json) that animates
## itself: gods, people, the Bull. Orpheus and the small enemies animate
## their own sheets the same way.
##
##   var s := RigSprite.new("zeus")
##   add_child(s)
##   s.play("idle")

var anims: Dictionary
var anim := ""
var facing := 1
var _frame_w := 32
var _origin := Vector2.ZERO
var _t := 0.0


func _init(rig: String) -> void:
	var base := "res://game/art/characters/" + rig
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	anims = meta["anims"]
	_frame_w = int(meta["frame_size"][0])
	_origin = Vector2(meta["origin"][0], meta["origin"][1])
	texture = ContentDB.lit_texture(base)
	hframes = int(meta["frames"])
	centered = false
	play(anims.keys()[0])


## Switch animation (restarting it if `restart` or if it's a different one).
func play(name_: String, restart: bool = false) -> void:
	if not anims.has(name_) or (name_ == anim and not restart):
		return
	anim = name_
	_t = 0.0
	_show()


## True once a non-looping animation has reached its last frame.
func finished() -> bool:
	var a: Dictionary = anims[anim]
	return not a.get("loop", true) and _t * float(a["fps"]) >= float(a["count"])


func _process(delta: float) -> void:
	_t += delta
	_show()


func _show() -> void:
	var a: Dictionary = anims[anim]
	var idx := int(_t * float(a["fps"]))
	idx = idx % int(a["count"]) if a.get("loop", true) else mini(idx, int(a["count"]) - 1)
	frame = int(a["start"]) + idx
	flip_h = facing < 0
	offset = -_origin
	if facing < 0:
		offset.x = -(_frame_w - _origin.x - 1)
