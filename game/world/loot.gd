class_name Loot
extends RefCounted
## Olives that aren't part of a room's layout: the ones beaten enemies drop,
## and the pile Orpheus leaves behind when he dies.


## Scatter `count` olives from `at` (world position) into `parent`.
static func scatter(parent: Node, at: Vector2, count: int) -> void:
	for i in count:
		var o := LooseOlive.new()
		o.velocity = Vector2(randf_range(-70, 70), randf_range(-170, -110))
		parent.add_child(o)
		o.global_position = at + Vector2(randf_range(-3, 3), 0)


class LooseOlive:
	extends CharacterBody2D
	## Pops out, bounces, then drifts to Orpheus when he's close. Gone after
	## a while, so a farmed room doesn't fill up.
	const LIFE := 18.0
	const MAGNET := 30.0
	var _t := 0.0
	var _sprite: Sprite2D

	func _ready() -> void:
		add_to_group(&"loose_olives")
		collision_layer = 0
		collision_mask = Layers.SOLID | Layers.LEDGE
		z_index = 6
		var shape := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(4, 4)
		shape.shape = r
		shape.position = Vector2(0, -2)
		add_child(shape)
		_sprite = Sprite2D.new()
		_sprite.texture = ContentDB.lit_texture("res://game/art/props/olive")
		_sprite.position = Vector2(0, -4)
		add_child(_sprite)

	func ready_to_collect() -> bool:
		return _t > 0.35

	func _physics_process(delta: float) -> void:
		_t += delta
		if _t > LIFE:
			queue_free()
			return
		_sprite.visible = _t < LIFE - 3.0 or int(_t * 10.0) % 2 == 0
		var p := get_tree().get_first_node_in_group(&"player") as Node2D
		if p and ready_to_collect() and global_position.distance_to(p.global_position + Vector2(0, -12)) < MAGNET:
			global_position = global_position.move_toward(p.global_position + Vector2(0, -12), 160.0 * delta)
			return
		velocity.y = minf(velocity.y + 600.0 * delta, 300.0)
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		if is_on_floor() and velocity.y >= 0.0 and absf(get_real_velocity().y) < 1.0 and _t < 1.0:
			velocity.y = -40.0 * maxf(0.0, 1.0 - _t)     # a little bounce


class OlivePile:
	extends Node2D
	## Half of Orpheus's olives, where he fell. His echo guards them; once it's
	## gone, touch the pile to take them back.
	var amount := 0
	var echo: Node = null

	func _ready() -> void:
		z_index = 2
		var s := Sprite2D.new()
		s.texture = ContentDB.lit_texture("res://game/art/props/olive_pile")
		s.position = Vector2(0, -s.texture.get_size().y / 2.0) if s.texture else Vector2.ZERO
		add_child(s)
		add_child(FxNodes.light(Vector2(0, -8), {"color": [0.6, 0.75, 1.0], "energy": 1.0, "scale": 1.2,
			"flicker": 0.08, "shadow": false}))
		add_child(FxNodes.halo(Vector2(0, -6), Color(0.6, 0.75, 1.0, 0.45), 18.0))

	func guarded() -> bool:
		return is_instance_valid(echo)
