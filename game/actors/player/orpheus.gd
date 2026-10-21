class_name Orpheus
extends CharacterBody2D
## Orpheus: movement, animation and his small personal light.
##
## The physics lives in `step_motion` — a pure function of (velocity, input,
## time) — so tests and the world validator use exactly the same numbers as
## the game. Everything here runs at a fixed 60 Hz physics tick.

const SHEET := "res://game/art/characters/orpheus"

var move: Dictionary
var sprite: Sprite2D
var anims: Dictionary
var facing := 1
var anim := "idle"
var frozen := false

## Optional stand-in for the keyboard/gamepad, used by replay tests and the
## screenshot tool. Must provide axis() -> float, held(action) and pressed(action).
var controls: Object = null

var _coyote := 0.0
var _buffer := 0.0
var _anim_time := 0.0
var _was_on_floor := false


func _ready() -> void:
	move = ContentDB.json("movement")
	z_index = 5
	collision_layer = 4
	collision_mask = 1 | 2
	floor_snap_length = 4.0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 30)
	shape.shape = rect
	shape.position = Vector2(0, -15)
	add_child(shape)

	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHEET + ".json"))
	anims = meta["anims"]
	sprite = Sprite2D.new()
	sprite.texture = ContentDB.lit_texture(SHEET)
	sprite.hframes = int(meta["frames"])
	sprite.centered = false
	sprite.offset = -Vector2(meta["origin"][0], meta["origin"][1])
	add_child(sprite)

	# A faint warm light so Orpheus stays readable in the dark.
	var glow := PointLight2D.new()
	glow.texture = ContentDB.texture(FxNodes.LIGHT)
	glow.texture_scale = 0.9
	glow.energy = 0.35
	glow.color = Color(1.0, 0.85, 0.7)
	glow.position = Vector2(0, -18)
	glow.height = 30.0
	add_child(glow)


## Advance velocity by one tick. `input_x` is -1..1, `jump_held` keeps the
## jump high, `jump_released` (true on the tick the button is let go) trims a
## rising jump into a short hop, `on_floor` selects ground or air rules.
static func step_motion(v: Vector2, input_x: float, on_floor: bool, jump_held: bool, m: Dictionary,
		dt: float, jump_released: bool = false) -> Vector2:
	if jump_released and v.y < 0.0:
		v.y *= float(m["jump_cut"])
	var target := input_x * float(m["run_speed"])
	var accel: float
	if on_floor:
		accel = float(m["ground_accel"]) if absf(input_x) > 0.01 else float(m["ground_decel"])
	else:
		accel = float(m["air_accel"])
	v.x = move_toward(v.x, target, accel * dt)
	var g := float(m["gravity"]) if (v.y < 0.0 and jump_held) else float(m["fall_gravity"])
	v.y = minf(v.y + g * dt, float(m["max_fall"]))
	return v


func _physics_process(delta: float) -> void:
	if frozen:
		return
	var x := _axis()
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = float(move["coyote_time"])
	else:
		_coyote -= delta
	if _pressed(&"jump"):
		_buffer = float(move["jump_buffer"])
	else:
		_buffer -= delta

	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = float(move["jump_velocity"])
		_buffer = 0.0
		_coyote = 0.0
		on_floor = false

	var released := _was_jump_held and not _held(&"jump")
	velocity = step_motion(velocity, x, on_floor, _held(&"jump"), move, delta, released)
	# Dropping through a ledge: hold down and jump.
	set_collision_mask_value(2, not (_held(&"down") and _pressed(&"jump")))
	move_and_slide()
	_was_jump_held = _held(&"jump")
	if absf(x) > 0.01:
		facing = 1 if x > 0 else -1
	_was_on_floor = on_floor
	_animate(delta, x)


var _was_jump_held := false


func _animate(delta: float, x: float) -> void:
	var want := "idle"
	if not is_on_floor():
		want = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 8.0:
		want = "run"
	if want != anim:
		anim = want
		_anim_time = 0.0
	_anim_time += delta
	var a: Dictionary = anims[anim]
	var idx := int(_anim_time * float(a["fps"]))
	idx = idx % int(a["count"]) if a.get("loop", true) else mini(idx, int(a["count"]) - 1)
	sprite.frame = int(a["start"]) + idx
	sprite.flip_h = facing < 0
	sprite.offset.x = -float(32 - 15 - 1) if facing < 0 else -15.0


func _axis() -> float:
	return controls.axis() if controls else Input.get_axis(&"move_left", &"move_right")


func _held(action: StringName) -> bool:
	return controls.held(action) if controls else Input.is_action_pressed(action)


func _pressed(action: StringName) -> bool:
	return controls.pressed(action) if controls else Input.is_action_just_pressed(action)
