class_name Burst
extends Node2D
## A quick expanding ring: where a hit landed, a parry rang, or a note sounded.
## Gold means "on the beat".

var color := Color.WHITE
var radius := 14.0
var life := 0.22
var _t := 0.0


static func spawn(parent: Node, at: Vector2, tint: Color, size: float = 14.0, seconds: float = 0.22) -> Burst:
	var b := Burst.new()
	b.color = tint
	b.radius = size
	b.life = seconds
	b.z_index = 20
	parent.add_child(b)
	b.global_position = at
	return b


func _ready() -> void:
	material = FxNodes.unshaded()


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / life
	var c := color
	c.a = 1.0 - k
	draw_arc(Vector2.ZERO, radius * (0.4 + 0.6 * k), 0.0, TAU, 20, c, 2.0)
