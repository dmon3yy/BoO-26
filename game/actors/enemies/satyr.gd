class_name Satyr
extends Enemy
## Paces its patch of woods. When it sees Orpheus it rears up on a beat and
## charges on the next one, so dodge (or parry) on that next beat.

var mode := "patrol"            # patrol | windup | charge | rest
var _beats_left := 0
var _charge_t := 0.0


func _on_beat(_index: int) -> void:
	match mode:
		"patrol":
			if _sees_player():
				mode = "windup"
				_beats_left = int(spec["windup_beats"])
				face(player().global_position.x - global_position.x)
				play("windup")
		"windup":
			_beats_left -= 1
			if _beats_left <= 0:
				mode = "charge"
				_charge_t = 0.0
				play("charge")
		"rest":
			_beats_left -= 1
			if _beats_left <= 0:
				mode = "patrol"


func _act(delta: float) -> void:
	match mode:
		"patrol":
			if is_on_wall() or not _floor_ahead() or absf(global_position.x - home.x) > 48.0 \
					and signf(global_position.x - home.x) == float(facing):
				facing = -facing
			velocity.x = facing * float(spec["walk_speed"])
			play("walk")
		"windup":
			velocity.x = 0.0
		"charge":
			_charge_t += delta
			velocity.x = facing * float(spec["charge_speed"])
			if _charge_t >= float(spec["charge_time"]) or is_on_wall() or not _floor_ahead():
				_end_charge()
		"rest":
			velocity.x = 0.0
			play("idle")


func _interrupted() -> void:
	if mode != "patrol":
		mode = "rest"
		_beats_left = int(spec["rest_beats"])
	play("stagger")


func _end_charge() -> void:
	mode = "rest"
	velocity.x = 0.0
	_beats_left = int(spec["rest_beats"])


func _sees_player() -> bool:
	var p := player()
	if p == null or p.kit.is_dead():
		return false
	var d := p.global_position - global_position
	return absf(d.x) < float(spec["sight"][0]) and absf(d.y) < float(spec["sight"][1])


## Is there floor one step ahead? Satyrs don't walk (or charge) off ledges.
func _floor_ahead() -> bool:
	if not is_on_floor():
		return true
	var ahead := global_transform.translated(Vector2(facing * (size.x * 0.5 + 4.0), 0))
	return test_move(ahead, Vector2(0, 6))
