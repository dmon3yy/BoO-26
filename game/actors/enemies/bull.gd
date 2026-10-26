class_name Bull
extends Enemy
## The Colchis Bull, guardian of Arcadia: a bronze machine that breathes
## fire. Hephaestus built the first ones; these are copies, and nobody on
## the surface knows who's making them.
##
## Its armoured front shrugs off the club. Everything it does is on the beat:
##   pace   walks at you for a couple of beats
##   paw    scrapes the ground for ONE beat: the warning
##   charge on the next beat it charges. Dodge through it, or jump to a ledge.
##          If it hits a wall it's dazed for a few beats: hit it anywhere.
##   flame  (once it's hurt) it draws breath for a beat, then breathes a low
##          jet of fire along the floor for a beat. Jump it.
## Strike its back whenever you can get behind it.

signal defeated

var mode := "asleep"            # asleep | pace | paw | charge | dazed | inhale | flame | dead
var max_hp := 24
var _beats_left := 0
var _charge_t := 0.0
var _flame: Node2D
var _steam := 0.0


func _ready() -> void:
	super()
	max_hp = hp
	add_to_group(&"boss")
	z_index = 4


func display_name() -> String:
	return String(spec.get("name", "Guardian"))


func awake() -> bool:
	return mode != "asleep" and mode != "dead"


func angry() -> bool:
	return hp <= int(spec["flame_from_hp"])


# --- on the beat ----------------------------------------------------------------------

func _on_beat(_index: int) -> void:
	var p := player()
	if p == null or p.kit.is_dead():
		return
	var dx := p.global_position.x - global_position.x
	match mode:
		"asleep":
			if absf(dx) < float(spec["wake_range"]):
				mode = "pace"
				_beats_left = 2
				Sfx.hit("bull_roar", -2.0)
				Events.narrate.emit("bull_wakes")
		"pace":
			face(dx)
			_beats_left -= 1
			if _beats_left > 0:
				return
			if angry() and absf(dx) < float(spec["flame_range"]) and randf() < 0.6:
				mode = "inhale"
				play("inhale")
				Sfx.hit("bull_inhale", -4.0)
			else:
				mode = "paw"
				play("paw")
				Sfx.hit("bull_paw", -3.0)
		"paw":
			mode = "charge"
			_charge_t = 0.0
			play("charge")
			Sfx.hit("bull_charge", -2.0)
		"inhale":
			mode = "flame"
			_breathe_fire()
		"flame":
			_end_flame()
			_rest(2)
		"dazed":
			_beats_left -= 1
			if _beats_left <= 0:
				_rest(1)


func _rest(beats: int) -> void:
	mode = "pace"
	_beats_left = beats
	play("walk")


func _act(delta: float) -> void:
	_steam -= delta
	match mode:
		"asleep", "paw", "inhale", "flame", "dazed", "dead":
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			if mode == "asleep":
				play("idle")
		"pace":
			# Plod towards him, but don't grind against a wall or stand on his toes.
			var p := player()
			var close := p != null and absf(p.global_position.x - global_position.x) < size.x * 0.4
			if is_on_wall() and get_wall_normal().x * facing < 0.0 or close:
				velocity.x = 0.0
				play("idle")
			else:
				velocity.x = facing * float(spec["walk_speed"])
				play("walk")
		"charge":
			_charge_t += delta
			var speed := float(spec["charge_speed"]) * (1.2 if angry() else 1.0)
			velocity.x = facing * speed
			if _steam <= 0.0:
				_steam = 0.06
				_puff(Vector2(-facing * size.x * 0.4, -size.y * 0.85))
			if is_on_wall():
				_hit_wall()
			elif _charge_t > float(spec["charge_max"]):
				_rest(1)


func _hit_wall() -> void:
	mode = "dazed"
	_beats_left = int(spec["stun_beats"])
	velocity.x = -facing * 90.0     # it rebounds off the wall rather than sinking into it
	play("dazed")
	Sfx.hit("bull_crash")
	Hitstop.freeze(get_tree(), 0.08)
	Events.shake.emit(0.25)
	for i in 3:
		Burst.spawn(get_parent(), global_position + Vector2(facing * size.x * 0.5, -size.y * 0.4 - i * 8), Color(1.0, 0.8, 0.4), 10.0 + i * 4)


# --- fire -------------------------------------------------------------------------------

func _breathe_fire() -> void:
	play("flame")
	Sfx.hit("bull_flame", -2.0)
	_flame = BullFlame.new()
	_flame.facing = facing
	_flame.damage = int(spec["flame_damage"])
	_flame.length = float(spec["flame_range"])
	_flame.owner_bull = self
	get_parent().add_child(_flame)
	_flame.global_position = global_position + Vector2(facing * size.x * 0.5, -6)


func _end_flame() -> void:
	if is_instance_valid(_flame):
		_flame.queue_free()


# --- getting hit ----------------------------------------------------------------------

## Only blows to its back, or anything while it's dazed, get through the bronze.
func take_hit(damage: int, dir: int, _knockback: float, _on_beat: bool) -> void:
	if not awake():
		mode = "pace"
		_beats_left = 1
	var from_behind := dir == facing
	if mode != "dazed" and not from_behind:
		Sfx.hit("parry", -2.0, 0.7)
		Burst.spawn(get_parent(), hurtbox().get_center() + Vector2(facing * size.x * 0.4, 0), Color(1.0, 0.85, 0.5), 8.0)
		return
	hp -= damage
	_flash = 0.12
	Sfx.hit("bull_clang", -2.0)
	if hp <= 0:
		_end_flame()
		_defeat()


func stagger(_seconds: float) -> void:
	pass       # nothing staggers it but a wall


func charm(_seconds: float) -> void:
	pass       # it's a machine: it has no music in it


func is_harmless() -> bool:
	return mode in ["asleep", "dazed", "dead"]


func _touch_player() -> void:
	if is_harmless():
		return
	var p := player()
	if p and p.kit and hurtbox().intersects(p.hurtbox()):
		var dmg := int(spec["charge_damage"]) if mode == "charge" else int(spec["contact_damage"])
		p.kit.take_hit(dmg, global_position, self)


func _defeat() -> void:
	mode = "dead"
	GameState.set_flag(StringName(spec["defeat_flag"]))
	defeated.emit()
	Events.enemy_defeated.emit(kind, hurtbox().get_center(), int(spec.get("olives", 0)))
	Sfx.hit("bull_crash", 0.0, 0.7)
	for i in 6:
		Burst.spawn(get_parent(), hurtbox().get_center() + Vector2(randf_range(-40, 40), randf_range(-20, 12)),
			Color(1.0, 0.7, 0.35), 12.0 + i * 3, 0.5 + i * 0.08)
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)


func _puff(offset: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 3
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 24.0
	p.gravity = Vector2(0, -20)
	p.color = Color(0.85, 0.85, 0.9, 0.6)
	get_parent().add_child(p)
	p.global_position = global_position + offset
	p.finished.connect(p.queue_free)


class BullFlame:
	extends Node2D
	## A low jet of fire along the floor, one beat long. Jump over it.
	var facing := 1
	var damage := 2
	var length := 96.0
	var owner_bull: Node
	var _t := 0.0
	var _light: PointLight2D

	func _ready() -> void:
		z_index = 6
		material = FxNodes.unshaded()
		_light = FxNodes.light(Vector2(facing * length * 0.5, -6), {"color": [1.0, 0.55, 0.2], "energy": 1.6,
			"scale": 2.0, "flicker": 0.2, "shadow": false})
		add_child(_light)

	func _physics_process(delta: float) -> void:
		_t += delta
		queue_redraw()
		var reach := minf(1.0, _t / 0.15) * length
		var box := Rect2(global_position + Vector2(0 if facing > 0 else -reach, -12), Vector2(reach, 12))
		var p := get_tree().get_first_node_in_group(&"player") as Orpheus
		if p and box.intersects(p.hurtbox()):
			p.kit.take_hit(damage, global_position, owner_bull)

	func _draw() -> void:
		var reach := minf(1.0, _t / 0.15) * length
		for i in int(reach / 5.0):
			var x := i * 5.0 * facing
			var h := 4.0 + 6.0 * sin(i * 1.3 + _t * 30.0) * 0.5 + 3.0 * (1.0 - i * 5.0 / length)
			var c := Color(1.0, 0.85, 0.35).lerp(Color(1.0, 0.35, 0.1), i * 5.0 / length)
			draw_rect(Rect2(x - 3, -h - 2, 6, h + 2), c)
			draw_rect(Rect2(x - 1, -h * 0.6 - 2, 3, h * 0.6), Color(1.0, 0.95, 0.7))
