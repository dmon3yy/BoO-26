class_name Venom
extends Node2D
## A glob of snake venom. It hurts Orpheus; a parry swats it away, and a
## PERFECT parry (on the beat) sends it back to hurt whatever it hits.

var velocity := Vector2.ZERO
var damage := 2
var hostile := true
var _life := 4.0


func _ready() -> void:
	z_index = 6
	material = FxNodes.unshaded()


## kit.take_hit calls this on a perfect parry: the venom turns around, faster.
func stagger(_seconds: float) -> void:
	hostile = false
	velocity = -velocity * 1.6


func _physics_process(delta: float) -> void:
	_life -= delta
	position += velocity * delta
	queue_redraw()
	var q := PhysicsPointQueryParameters2D.new()
	q.position = global_position
	q.collision_mask = Layers.SOLID
	if _life <= 0.0 or not get_world_2d().direct_space_state.intersect_point(q, 1).is_empty():
		queue_free()
		return
	var box := Rect2(global_position - Vector2(3, 3), Vector2(6, 6))
	if hostile:
		var p := get_tree().get_first_node_in_group(&"player") as Orpheus
		if p and box.intersects(p.hurtbox()):
			var result: String = p.kit.take_hit(damage, global_position, self)
			if result in ["hit", "blocked"]:
				queue_free()
	else:
		for e in get_tree().get_nodes_in_group(&"enemies"):
			if box.intersects(e.hurtbox()):
				e.take_hit(damage + 1, int(signf(velocity.x)), 120.0, true)
				queue_free()
				return


func _draw() -> void:
	var col := Color(0.55, 0.95, 0.35) if hostile else UiKit.GOLD
	draw_circle(Vector2.ZERO, 3.0, col)
	draw_circle(Vector2(-signf(velocity.x) * 3.0, 0), 2.0, Color(col, 0.5))
