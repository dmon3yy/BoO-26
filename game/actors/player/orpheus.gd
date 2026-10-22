class_name Orpheus
extends CharacterBody2D
## Orpheus: movement, animation and his small personal light. His fighting
## kit (club, dodge, parry, health, lyre) lives in kit.gd, a child node.
##
## The physics lives in `step_motion` — a pure function of (velocity, input,
## time) — so tests and the world validator use exactly the same numbers as
## the game. Everything here runs at a fixed 60 Hz physics tick.

const SHEET := "res://game/art/characters/orpheus"

## Emitted on the tick he touches down, with the speed he was falling at.
signal landed(fall_speed: float)

var move: Dictionary
var sprite: Sprite2D
var anims: Dictionary
var facing := 1
var anim := "idle"
var frozen := false
var kit: OrpheusKit

## Optional stand-in for the keyboard/gamepad, used by replay tests and the
## screenshot tool. Must provide axis() -> float, held(action) and pressed(action).
var controls: Object = null

var _coyote := 0.0
var _buffer := 0.0
var _anim_time := 0.0
var _was_on_floor := false
var _drop_time := 0.0

## How long ledges stay see-through after Down + Jump, so he falls clear of them.
const DROP_TIME := 0.25


func _ready() -> void:
	move = ContentDB.json("movement")
	z_index = 5
	collision_layer = Layers.PLAYER
	collision_mask = Layers.SOLID | Layers.LEDGE
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

	kit = OrpheusKit.new(self)
	add_child(kit)
	add_to_group(&"player")


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
		if absf(input_x) <= 0.01:
			accel = float(m["ground_decel"])
		elif signf(input_x) != signf(v.x) and absf(v.x) > 1.0:
			accel = float(m["turn_accel"])     # reversing: plant the feet
		else:
			accel = float(m["ground_accel"])
	else:
		accel = float(m["air_accel"])
	v.x = move_toward(v.x, target, accel * dt)
	var g := float(m["gravity"]) if (v.y < 0.0 and jump_held) else float(m["fall_gravity"])
	# Hang time: holding jump softens gravity around the top of the arc.
	if not on_floor and jump_held and absf(v.y) < float(m["apex_window"]):
		g *= float(m["apex_gravity_scale"])
	v.y = minf(v.y + g * dt, float(m["max_fall"]))
	return v


func _physics_process(delta: float) -> void:
	if frozen:
		return
	kit.tick(delta)
	var x := 0.0 if kit.movement_locked() else _axis()
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = float(move["coyote_time"])
	else:
		_coyote -= delta
	if _pressed(&"jump") and not kit.jump_locked():
		_buffer = float(move["jump_buffer"])
	else:
		_buffer -= delta

	# Down + Jump on a ledge drops through it instead of jumping.
	_drop_time -= delta
	if on_floor and _held(&"down") and _pressed(&"jump") and not kit.jump_locked() and on_ledge():
		_drop_time = DROP_TIME
		_buffer = 0.0
		_coyote = 0.0
		on_floor = false
	set_collision_mask_value(2, _drop_time <= 0.0)

	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = float(move["jump_velocity"])
		_buffer = 0.0
		_coyote = 0.0
		on_floor = false

	var released := _was_jump_held and not _held(&"jump")
	velocity = step_motion(velocity, x, on_floor, _held(&"jump"), move, delta, released)
	velocity = kit.override_velocity(velocity)
	if velocity.y < 0.0:
		_nudge_around_ceiling_corner(delta)
	var fall_speed := velocity.y
	move_and_slide()
	if is_on_floor() and not _was_on_floor:
		landed.emit(fall_speed)
		if fall_speed > float(move["hard_landing_speed"]):
			_dust()
	_was_jump_held = _held(&"jump")
	if absf(x) > 0.01 and kit.state == "free":
		facing = 1 if x > 0 else -1
	_was_on_floor = on_floor
	_animate(delta, x)


var _was_jump_held := false


## True when he's standing on a one-way ledge (layer 2) rather than solid ground.
func on_ledge() -> bool:
	var down := Vector2(0, 2)
	if not test_move(global_transform, down):
		return false
	var mask := collision_mask
	collision_mask = 1
	var solid := test_move(global_transform, down)
	collision_mask = mask
	return not solid


## Clipping a ceiling corner by a few pixels shouldn't kill a jump: slide
## sideways (up to `corner_nudge` px) to the side that's free and keep rising.
func _nudge_around_ceiling_corner(delta: float) -> void:
	var up := Vector2(0, velocity.y * delta)
	if not test_move(global_transform, up):
		return
	for d in range(1, int(move["corner_nudge"]) + 1):
		for s in [1, -1]:
			var side := Vector2(d * s, 0)
			if not test_move(global_transform, side) and \
					not test_move(global_transform.translated(side), up):
				position.x += d * s
				return


func _dust() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(5, 1)
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 40.0
	p.gravity = Vector2(0, 90)
	p.color = Color(0.85, 0.88, 0.95, 0.8)
	p.global_position = global_position
	get_parent().add_child(p)
	p.finished.connect(p.queue_free)


func _animate(delta: float, x: float) -> void:
	var want := kit.anim_override()     # attacking, dodging, parrying, playing...
	if want == "":
		if not is_on_floor():
			want = "jump" if velocity.y < 0.0 else "fall"
		elif absf(velocity.x) > 8.0:
			want = "run"
		else:
			want = "idle"
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


## Public input queries, so the world (Hearths, menus) reads the same
## keyboard, gamepad or scripted controls as Orpheus does.
func just_pressed(action: StringName) -> bool:
	return _pressed(action)


func pressed(action: StringName) -> bool:
	return _pressed(action)


func held(action: StringName) -> bool:
	return _held(action)


func input_x() -> float:
	return _axis()


## The rectangle enemies and venom have to touch to hurt him.
func hurtbox() -> Rect2:
	return Rect2(global_position + Vector2(-5, -30), Vector2(10, 30))


## Start the current animation over (each swing replays the swing).
func restart_anim() -> void:
	anim = ""


func _axis() -> float:
	return controls.axis() if controls else Input.get_axis(&"move_left", &"move_right")


func _held(action: StringName) -> bool:
	return controls.held(action) if controls else Input.is_action_pressed(action)


func _pressed(action: StringName) -> bool:
	return controls.pressed(action) if controls else Input.is_action_just_pressed(action)
