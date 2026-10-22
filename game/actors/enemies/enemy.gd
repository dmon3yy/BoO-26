class_name Enemy
extends CharacterBody2D
## What every enemy shares: health, getting hit, staggering, being charmed by
## a song, touching Orpheus, and animating from a baked rig sheet.
##
## Enemies move whenever they like but ATTACK ON THE BEAT. Each one hears
## `_on_beat(index)` once per beat of the music (or of a steady 100 bpm pulse
## when nothing is playing), and starts and lands its attacks there. That's
## the rhythm game hiding inside the action game: the music tells you when
## to dodge, and when to parry for a perfect one.
##
## The numbers for each kind live in content/enemies.json.

const GRAVITY := 900.0
const MAX_FALL := 320.0
const QUIET_BPM := 100.0          # the pulse enemies follow when no music plays
const HITSTUN := 0.25

var kind := ""
var spec: Dictionary
var hp := 1
var facing := -1
var size := Vector2(12, 12)
var home := Vector2.ZERO
var anim := ""
var sprite: Sprite2D

var _anims: Dictionary
var _frame_w := 32
var _origin := Vector2.ZERO
var _anim_time := 0.0
var _stagger := 0.0
var _charm := 0.0
var _flash := 0.0
var _knock := 0.0
var _last_beat := -1
var _quiet_time := 0.0


## Build the enemy for a kind from content/enemies.json ("satyr", "bat", ...).
static func create(enemy_kind: String) -> Enemy:
	var e: Enemy
	match enemy_kind:
		"satyr": e = Satyr.new()
		"bat": e = Bat.new()
		"snake": e = Snake.new()
		_: return null
	e.kind = enemy_kind
	return e


func _ready() -> void:
	spec = ContentDB.json("enemies")[kind]
	hp = int(spec["hp"])
	size = Vector2(spec["size"][0], spec["size"][1])
	home = global_position
	add_to_group(&"enemies")
	collision_layer = Layers.ENEMY
	collision_mask = Layers.SOLID | Layers.LEDGE
	z_index = 4
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = Vector2(0, -size.y * 0.5)
	add_child(shape)

	var base := "res://game/art/characters/" + String(spec["rig"])
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	_anims = meta["anims"]
	_frame_w = int(meta["frame_size"][0])
	_origin = Vector2(meta["origin"][0], meta["origin"][1])
	sprite = Sprite2D.new()
	sprite.texture = ContentDB.lit_texture(base)
	sprite.hframes = int(meta["frames"])
	sprite.centered = false
	add_child(sprite)
	play(_anims.keys()[0])


# --- what the kit and songs call --------------------------------------------------

## The rectangle Orpheus's club has to touch.
func hurtbox() -> Rect2:
	return Rect2(global_position - Vector2(size.x * 0.5, size.y), size)


func take_hit(damage: int, dir: int, knockback: float, _on_beat: bool) -> void:
	hp -= damage
	_flash = 0.12
	_charm = 0.0
	_knock = dir * knockback
	_stagger = maxf(_stagger, HITSTUN)
	_interrupted()
	if hp <= 0:
		_die()


## A perfect parry knocks the enemy off balance: it can't attack or hurt.
func stagger(seconds: float) -> void:
	_stagger = maxf(_stagger, seconds)
	_interrupted()


## The Song of Charming: it sways, harmless, until the song wears off or it's hit.
func charm(seconds: float) -> void:
	_charm = seconds
	_interrupted()


func is_harmless() -> bool:
	return _stagger > 0.0 or _charm > 0.0


# --- for subclasses ------------------------------------------------------------------

## Called once per beat. Start wind-ups and land attacks here.
func _on_beat(_index: int) -> void:
	pass


## Called every physics tick while the enemy is free to act.
func _act(_delta: float) -> void:
	pass


## An attack in progress was cut short (hit, staggered or charmed).
func _interrupted() -> void:
	pass


func player() -> Orpheus:
	return get_tree().get_first_node_in_group(&"player") as Orpheus


## Where the music is, in beats (a steady pulse if there's no music).
func beat_clock() -> float:
	if Music.is_playing():
		return Music.beat_position()
	return _quiet_time * QUIET_BPM / 60.0


func seconds_per_beat() -> float:
	return Music.seconds_per_beat() if Music.is_playing() else 60.0 / QUIET_BPM


func play(name_: String) -> void:
	if name_ != anim and _anims.has(name_):
		anim = name_
		_anim_time = 0.0


func face(dir: float) -> void:
	if absf(dir) > 0.01:
		facing = 1 if dir > 0.0 else -1


func uses_gravity() -> bool:
	return true


# --- the shared tick -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_quiet_time += delta
	_stagger = maxf(0.0, _stagger - delta)
	_charm = maxf(0.0, _charm - delta)
	_flash = maxf(0.0, _flash - delta)

	var b := floori(beat_clock())
	if b != _last_beat:
		_last_beat = b
		if not is_harmless():
			_on_beat(b)

	if is_harmless():
		velocity.x = _knock
		_knock = move_toward(_knock, 0.0, 500.0 * delta)
	else:
		_act(delta)
	if uses_gravity():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
		move_and_slide()
	_touch_player()
	_animate(delta)


func _touch_player() -> void:
	if is_harmless():
		return
	var p := player()
	if p and p.kit and hurtbox().intersects(p.hurtbox()):
		p.kit.take_hit(int(spec["contact_damage"]), global_position, self)


func _animate(delta: float) -> void:
	if _stagger > HITSTUN and _anims.has("stagger"):
		play("stagger")
	_anim_time += delta
	var a: Dictionary = _anims[anim]
	var idx := int(_anim_time * float(a["fps"]))
	idx = idx % int(a["count"]) if a.get("loop", true) else mini(idx, int(a["count"]) - 1)
	sprite.frame = int(a["start"]) + idx
	sprite.flip_h = facing < 0
	sprite.offset = -_origin
	if facing < 0:
		sprite.offset.x = -(_frame_w - _origin.x - 1)
	# Hit flash, then a soft pink while charmed.
	if _flash > 0.0:
		sprite.modulate = Color(1.0, 0.45, 0.4)
	elif _charm > 0.0:
		sprite.modulate = Color(1.0, 0.75, 0.9)
		sprite.position.y = sin(_quiet_time * 6.0) * 1.5
	else:
		sprite.modulate = Color.WHITE
		sprite.position.y = 0.0


func _die() -> void:
	Sfx.hit("enemy_die", -4.0)
	Burst.spawn(get_parent(), hurtbox().get_center(), Color(1.0, 0.9, 0.7), 18.0, 0.35)
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 14
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 80.0
	p.gravity = Vector2(0, 200)
	p.color = Color(0.9, 0.85, 0.75)
	get_parent().add_child(p)
	p.global_position = hurtbox().get_center()
	p.finished.connect(p.queue_free)
	queue_free()
