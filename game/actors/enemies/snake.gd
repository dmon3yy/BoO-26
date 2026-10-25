class_name Snake
extends Enemy
## Coiled on a rock. Every few beats it rears back for one beat, spits venom
## on the next, and the venom arrives on the beat after that. Parry it ON the
## beat and it flies back.

var _rearing := false


func _on_beat(index: int) -> void:
	var p := player()
	if p == null or p.kit.is_dead() or p.global_position.distance_to(global_position) > float(spec["sight"]):
		play("idle")
		return
	face(p.global_position.x - global_position.x)
	var every := int(spec["spit_every_beats"])
	if posmod(index, every) == every - 1:
		_rearing = true
		play("spit")
	elif posmod(index, every) == 0 and _rearing:
		_rearing = false
		_spit()


func _act(_delta: float) -> void:
	velocity.x = 0.0
	if not _rearing and anim == "spit" and _anim_time > 0.6:
		play("idle")


func _interrupted() -> void:
	_rearing = false


## The venom is aimed to reach Orpheus exactly one beat after it's spat, so
## a parry on that beat is a perfect one.
func _spit() -> void:
	var v := Venom.new()
	var dist := absf(player().global_position.x - global_position.x) - 14.0
	var speed := clampf(dist / seconds_per_beat(), 50.0, float(spec["spit_speed"]) * 2.0)
	v.velocity = Vector2(facing * speed, 0)
	v.damage = int(spec["spit_damage"])
	get_parent().add_child(v)
	Sfx.hit("spit", -6.0)
	v.global_position = global_position + Vector2(facing * 14, -18)
