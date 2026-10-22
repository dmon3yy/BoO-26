extends GutTest
## M2 combat: the club, the dodge, the parry, getting hurt, enemies and songs.
## A tiny arena (one floor) is built for each test; inputs come from a fake pad.

var arena: Node2D
var orpheus: Orpheus
var pad: Pad


class Pad:
	extends RefCounted
	var x := 0.0
	var down := {}
	var tapped := {}

	func axis() -> float:
		return x

	func held(action: StringName) -> bool:
		return down.has(action) or tapped.has(action)

	func pressed(action: StringName) -> bool:
		return tapped.has(action)

	## Press for exactly one physics tick.
	func tap(action: StringName) -> void:
		tapped[action] = true


func before_each() -> void:
	GameState.reset()
	Music.stop()
	arena = Node2D.new()
	add_child_autofree(arena)
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000, 32)
	shape.shape = rect
	floor_body.position = Vector2(0, 16)
	floor_body.add_child(shape)
	arena.add_child(floor_body)
	orpheus = Orpheus.new()
	pad = Pad.new()
	orpheus.controls = pad
	arena.add_child(orpheus)
	orpheus.global_position = Vector2(0, 0)
	await wait_physics_frames(3)


func _tick(frames: int = 1) -> void:
	for i in frames:
		await wait_physics_frames(1)
		pad.tapped.clear()


func _enemy(kind: String, at: Vector2) -> Enemy:
	var e := Enemy.create(kind)
	arena.add_child(e)
	e.global_position = at
	e.home = at
	return e


# --- pure rules ------------------------------------------------------------------

func test_on_beat_swings_hit_half_again_as_hard() -> void:
	var c := ContentDB.json("combat")
	assert_eq(OrpheusKit.club_damage(2.0, false, c), 2)
	assert_eq(OrpheusKit.club_damage(2.0, true, c), 3)


func test_songs_match_the_last_notes_played() -> void:
	var book := ContentDB.json("songs")
	var played := [{"note": "down", "on_beat": false}]
	for n in book["zeus"]["notes"]:
		played.append({"note": n, "on_beat": false})
	assert_eq(OrpheusKit.match_song(played, book), "zeus")
	assert_eq(OrpheusKit.match_song(played.slice(0, 3), book), "")


func test_unknown_songs_do_nothing() -> void:
	GameState.revoke_ability(&"song:zeus")
	var played := []
	for n in ContentDB.json("songs")["zeus"]["notes"]:
		played.append({"note": n, "on_beat": false})
	assert_eq(OrpheusKit.match_song(played, ContentDB.json("songs")), "")


func test_combat_songs_cost_half_when_played_on_the_beat() -> void:
	var charm: Dictionary = ContentDB.json("songs")["charm"]
	var sloppy := []
	var tight := []
	for n in charm["notes"]:
		sloppy.append({"note": n, "on_beat": false})
		tight.append({"note": n, "on_beat": true})
	assert_eq(OrpheusKit.song_cost(charm, sloppy), float(charm["cost"]))
	assert_eq(OrpheusKit.song_cost(charm, tight), float(charm["cost"]) / 2.0)
	assert_eq(OrpheusKit.song_cost(ContentDB.json("songs")["zeus"], sloppy), 0.0, "traversal songs are free")


# --- in the arena -------------------------------------------------------------------

func test_the_club_hurts_an_enemy_in_front() -> void:
	var snake := _enemy("snake", Vector2(18, 0))
	var before := snake.hp
	pad.tap(&"attack")
	await _tick(12)
	assert_lt(snake.hp, before, "the swing landed")


func test_the_club_misses_an_enemy_behind() -> void:
	var snake := _enemy("snake", Vector2(-30, 0))
	var before := snake.hp
	pad.tap(&"attack")
	await _tick(12)
	assert_eq(snake.hp, before)


func test_getting_hit_costs_health_then_blinks() -> void:
	var kit := orpheus.kit
	assert_eq(kit.take_hit(2, Vector2(20, 0)), "hit")
	assert_eq(kit.hp, GameState.max_hp - 2)
	assert_eq(kit.take_hit(2, Vector2(20, 0)), "ignored", "invulnerable right after a hit")


func test_dodging_is_invulnerable() -> void:
	pad.tap(&"dodge")
	await _tick(2)
	assert_eq(orpheus.kit.state, "dodge")
	assert_eq(orpheus.kit.take_hit(2, Vector2(20, 0)), "ignored")
	assert_gt(absf(orpheus.velocity.x), 100.0, "the dodge carries him")


func test_a_parry_blocks_from_the_front_only() -> void:
	pad.tap(&"parry")
	await _tick(1)
	assert_eq(orpheus.kit.take_hit(2, Vector2(20, 0)), "blocked")
	assert_eq(orpheus.kit.take_hit(2, Vector2(-20, 0)), "hit", "not from behind")


func test_an_on_beat_parry_staggers_the_attacker() -> void:
	var satyr := _enemy("satyr", Vector2(60, 0))
	pad.tap(&"parry")
	await _tick(1)
	orpheus.kit._on_beat = true      # as if Music graded the parry GOOD
	assert_eq(orpheus.kit.take_hit(2, satyr.global_position, satyr), "perfect")
	assert_true(satyr.is_harmless(), "staggered")
	assert_gt(orpheus.kit.muse, 0.0, "a perfect parry earns Muse")


func test_a_perfect_parry_sends_venom_back() -> void:
	var v := Venom.new()
	v.velocity = Vector2(-100, 0)
	arena.add_child(v)
	v.stagger(1.0)
	assert_false(v.hostile)
	assert_gt(v.velocity.x, 0.0)


func test_charmed_enemies_are_harmless() -> void:
	var satyr := _enemy("satyr", Vector2(8, 0))
	satyr.charm(2.0)
	await _tick(5)
	assert_eq(orpheus.kit.hp, GameState.max_hp, "touching a charmed satyr doesn't hurt")


func test_the_hymn_heals_for_muse() -> void:
	var kit := orpheus.kit
	kit.take_hit(6, Vector2(20, 0))
	kit.add_muse(100)
	for n in ContentDB.json("songs")["hymn"]["notes"]:
		kit.notes.append({"note": n, "on_beat": false})
	kit.notes.pop_back()
	kit.play_note(ContentDB.json("songs")["hymn"]["notes"][-1])
	assert_eq(kit.hp, GameState.max_hp - 6 + 4)
	assert_eq(kit.muse, 100.0 - 40.0)
