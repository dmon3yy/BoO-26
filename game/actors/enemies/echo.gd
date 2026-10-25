class_name Echo
extends Enemy
## What's left of Orpheus where he last fell: a pale copy that guards the
## olives he dropped. It keeps close to the pile, raises its club on one beat
## and swings on the next. Beat it and the olives are yours again; die before
## you do and they're gone for good.

var pile: Node2D
var mode := "guard"            # guard | raise | rest
var _beats_left := 0


func _ready() -> void:
	super()
	add_to_group(&"echoes")
	collision_mask = Layers.SOLID      # it doesn't stand on ledges it can't see
	# A ghost: it gives off its own pale light instead of taking the room's.
	var glow := CanvasItemMaterial.new()
	glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = glow


func _on_beat(_index: int) -> void:
	var p := player()
	match mode:
		"guard":
			if p and not p.kit.is_dead() and p.global_position.distance_to(global_position) < 34.0:
				face(p.global_position.x - global_position.x)
				mode = "raise"
				play("parry")
		"raise":
			_swing()
			mode = "rest"
			_beats_left = 1
		"rest":
			_beats_left -= 1
			if _beats_left <= 0:
				mode = "guard"


func _act(_delta: float) -> void:
	var p := player()
	velocity.x = 0.0
	if mode != "guard" or p == null:
		return
	var post: Vector2 = pile.global_position if is_instance_valid(pile) else home
	var target_x := post.x
	if p.global_position.distance_to(post) < float(spec["sight"]):
		target_x = clampf(p.global_position.x, post.x - float(spec["leash"]), post.x + float(spec["leash"]))
	var dx := target_x - global_position.x
	if absf(dx) > 14.0:
		face(dx)
		velocity.x = signf(dx) * float(spec["walk_speed"])
		play("run")
	else:
		play("idle")


func _interrupted() -> void:
	mode = "rest"
	_beats_left = 1


func _swing() -> void:
	play("attack")
	_anim_time = 0.0
	var p := player()
	if p == null:
		return
	var r: Array = spec["swing_reach"]
	var box := Rect2(global_position + Vector2(0 if facing > 0 else -float(r[0]), -float(r[1]) - 6), Vector2(r[0], r[1]))
	if box.intersects(p.hurtbox()):
		p.kit.take_hit(int(spec["swing_damage"]), global_position, self)
