class_name Scorpion
extends Enemy
## Low and armoured: a standing swing passes right over it, so crouch (hold
## Down) and strike low. It creeps along the floor; when Orpheus is close in
## front it raises its tail on one beat and stings on the next.

var mode := "creep"            # creep | raise | rest
var _beats_left := 0
var _lunge := 0.0


func _on_beat(_index: int) -> void:
	match mode:
		"creep":
			var p := player()
			if p and not p.kit.is_dead() and absf(p.global_position.y - global_position.y) < 20.0 \
					and absf(p.global_position.x - global_position.x) < float(spec["sight"]):
				face(p.global_position.x - global_position.x)
				mode = "raise"
				play("raise")
		"raise":
			_sting()
			mode = "rest"
			_beats_left = int(spec["rest_beats"])
		"rest":
			_beats_left -= 1
			if _beats_left <= 0:
				mode = "creep"


func _act(delta: float) -> void:
	_lunge = maxf(0.0, _lunge - delta)
	match mode:
		"creep":
			if is_on_wall() or not _floor_ahead() or absf(global_position.x - home.x) > 40.0 \
					and signf(global_position.x - home.x) == float(facing):
				facing = -facing
			velocity.x = facing * float(spec["walk_speed"])
			play("walk")
		_:
			velocity.x = facing * 90.0 if _lunge > 0.0 else 0.0
			if mode == "rest" and _lunge <= 0.0:
				play("idle")


func _interrupted() -> void:
	mode = "rest"
	_beats_left = int(spec["rest_beats"])
	_lunge = 0.0


## The sting: a short lunge, and anything in reach of the tail is hit.
func _sting() -> void:
	play("sting")
	_lunge = 0.12
	var p := player()
	if p == null:
		return
	var reach := Rect2(global_position + Vector2(-4 if facing > 0 else -float(spec["sting_reach"]) + 4, -18),
		Vector2(float(spec["sting_reach"]), 18))
	if reach.intersects(p.hurtbox()):
		p.kit.take_hit(int(spec["sting_damage"]), global_position, self)


func _floor_ahead() -> bool:
	if not is_on_floor():
		return true
	var ahead := global_transform.translated(Vector2(facing * (size.x * 0.5 + 3.0), 0))
	return test_move(ahead, Vector2(0, 6))
