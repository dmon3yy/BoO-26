class_name Bat
extends Enemy
## Hangs from the ceiling. When Orpheus comes near it drops on a beat and
## swoops through where he was standing, arriving there on the very next
## beat, then flutters home. Its whole flight is timed in beats, so it moves
## with the music.

var mode := "hang"              # hang | swoop | return
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _start_beat := 0.0


func uses_gravity() -> bool:
	return false


func _ready() -> void:
	super()
	collision_mask = 0
	# Perch under the ceiling above the spot it was placed.
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -2), global_position + Vector2(0, -200),
		Layers.SOLID)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		global_position = hit["position"] + Vector2(0, size.y + 1)
	home = global_position
	play("hang")


func _on_beat(index: int) -> void:
	if mode == "hang" and _near_player():
		mode = "swoop"
		_from = global_position
		_to = player().global_position + Vector2(0, -6)
		face(_to.x - _from.x)
		_start_beat = index
		play("fly")


func _act(_delta: float) -> void:
	var beats := float(spec["swoop_beats"])
	var u := (beat_clock() - _start_beat) / beats
	match mode:
		"swoop":
			if u >= 1.0:
				mode = "return"
				_from = global_position
				_start_beat = beat_clock()
			else:
				# A U-shaped scoop: down to where Orpheus stood exactly
				# halfway through (on a beat), then up and out the far side.
				global_position = Vector2(lerpf(_from.x, _to.x + (_to.x - _from.x), u),
					lerpf(_from.y, _to.y, sin(PI * u)))
		"return":
			var back := (beat_clock() - _start_beat) / float(spec["rest_beats"])
			face(home.x - global_position.x)
			if back >= 1.0:
				global_position = home
				mode = "hang"
				play("hang")
			else:
				global_position = _from.lerp(home, smoothstep(0.0, 1.0, back)) + Vector2(0, -8.0 * sin(PI * back))
	if mode == "hang":
		sprite.flip_v = true
		sprite.position.y = -size.y - 2
	else:
		sprite.flip_v = false


func _interrupted() -> void:
	if mode == "swoop":
		mode = "return"
		_from = global_position
		_start_beat = beat_clock()


func _near_player() -> bool:
	var p := player()
	return p != null and not p.kit.is_dead() and p.global_position.distance_to(global_position) < float(spec["sight"])
