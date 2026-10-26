class_name OrpheusKit
extends Node
## Orpheus's fighting kit: the club, the dodge, the parry, his health, the
## Muse meter and the lyre. Movement stays in orpheus.gd; this node tells it
## when to hold still, and takes over his velocity while dodging or reeling.
##
## Everything that can be timed to the music asks the conductor for a grade
## (Music.grade_now). GOOD or PERFECT counts as "on the beat": the club hits
## harder, a parry becomes a perfect parry, and Muse fills. Nothing requires
## the beat. All the numbers live in content/combat.json.

const NOTES := {&"up": "up", &"down": "down", &"move_left": "left", &"move_right": "right", &"jump": "middle"}
const NOTE_SFX := {"up": "up", "down": "down", "left": "left", "right": "right", "middle": "center"}

var c: Dictionary                 # content/combat.json
var songs: Dictionary             # content/songs.json
var player: Orpheus

var hp := 12
var muse := 0.0
## free | attack | dodge | parry | hurt | lyre
var state := "free"
var notes: Array = []             # [{"note": String, "on_beat": bool}], newest last

var _t := 0.0                     # seconds in the current state
var _on_beat := false             # the current swing or parry was on the beat
var low := false                  # the current swing is a crouch strike
var _hit := {}                    # enemies this swing already hit
var _invulnerable := 0.0
var _cooldown := {"dodge": 0.0, "parry": 0.0}
var _dodge_dir := 1
var _air_dodged := false
var _knock := Vector2.ZERO


func _init(owner_player: Orpheus) -> void:
	player = owner_player
	c = ContentDB.json("combat")
	songs = ContentDB.json("songs")
	name = "Kit"


func _ready() -> void:
	restore()


## Full health and an empty Muse meter: a new life, or a rest at a Hearth.
func restore(keep_muse: bool = false) -> void:
	hp = GameState.max_hp
	if not keep_muse:
		muse = 0.0
	state = "free"
	_invulnerable = 0.0
	Events.player_hp_changed.emit(hp, GameState.max_hp)
	Events.muse_changed.emit(muse, max_muse())


func max_muse() -> float:
	return float(c["muse_max"])


func add_muse(amount: float) -> void:
	muse = clampf(muse + amount, 0.0, max_muse())
	Events.muse_changed.emit(muse, max_muse())


func is_dead() -> bool:
	return hp <= 0


# --- what orpheus.gd asks ------------------------------------------------------

## Left/right input is ignored (attacking on the ground, parrying, playing).
func movement_locked() -> bool:
	return state in ["parry", "lyre", "hurt", "dodge"] or (state == "attack" and player.is_on_floor())


func jump_locked() -> bool:
	return state in ["parry", "lyre", "hurt", "dodge"]


## Dodging and being knocked back take over Orpheus's velocity.
func override_velocity(v: Vector2) -> Vector2:
	if state == "dodge":
		return Vector2(_dodge_dir * float(c["dodge"]["speed"]), 0.0)
	if state == "hurt":
		_knock.x = move_toward(_knock.x, 0.0, 600.0 * get_physics_process_delta_time())
		return Vector2(_knock.x, v.y)
	return v


func anim_override() -> String:
	match state:
		"attack": return "crouch_attack" if low else "attack"
		"dodge": return "dodge"
		"parry": return "parry"
		"hurt": return "hurt"
		"lyre": return "play"
	return ""


# --- the per-tick update -------------------------------------------------------

func tick(delta: float) -> void:
	_t += delta
	_invulnerable = maxf(0.0, _invulnerable - delta)
	for k in _cooldown:
		_cooldown[k] = maxf(0.0, _cooldown[k] - delta)
	if player.is_on_floor():
		_air_dodged = false
	# Blink while invulnerable after a hit.
	player.sprite.modulate.a = 0.35 if (_invulnerable > 0.0 and state != "dodge" and int(_t * 16.0) % 2 == 0) else 1.0

	match state:
		"free":
			_from_free()
		"attack":
			var club: Dictionary = c["club"]
			var start := float(club["startup"])
			if _t >= start and _t < start + float(club["active"]):
				_swing_hits()
			if _t >= start + float(club["active"]) + float(club["recovery"]):
				state = "free"
		"dodge":
			if _t >= float(c["dodge"]["time"]):
				state = "free"
		"parry":
			if _t >= float(c["parry"]["window"]):
				state = "free"
		"hurt":
			if _t >= float(c["hurt"]["stun"]):
				state = "free"
		"lyre":
			if not player.held(&"lyre"):
				notes.clear()
				state = "free"
			else:
				_listen_for_notes()


func _from_free() -> void:
	if player.pressed(&"attack") and GameState.has_ability(&"club"):
		_start(&"attack")
	elif player.pressed(&"dodge") and _cooldown["dodge"] <= 0.0 and not (_air_dodged and not player.is_on_floor()):
		_start(&"dodge")
	elif player.pressed(&"parry") and _cooldown["parry"] <= 0.0 and GameState.has_ability(&"shield"):
		_start(&"parry")
	elif player.held(&"lyre") and player.is_on_floor() and GameState.has_ability(&"lyre"):
		_start(&"lyre")


func _start(what: StringName) -> void:
	state = String(what)
	_t = 0.0
	match what:
		&"attack":
			low = player.crouching
			_on_beat = _grade("swing")
			_hit.clear()
			Sfx.hit("club_swing", -6.0, randf_range(0.95, 1.08))
			player.restart_anim()
		&"dodge":
			_dodge_dir = player.facing
			var x := player.input_x()
			if absf(x) > 0.3:
				_dodge_dir = 1 if x > 0.0 else -1
				player.facing = _dodge_dir
			_invulnerable = maxf(_invulnerable, float(c["dodge"]["invulnerable"]))
			_cooldown["dodge"] = float(c["dodge"]["time"]) + float(c["dodge"]["cooldown"])
			if not player.is_on_floor():
				_air_dodged = true
		&"parry":
			_on_beat = _grade("parry")
			_cooldown["parry"] = float(c["parry"]["window"]) + float(c["parry"]["cooldown"])
		&"lyre":
			notes.clear()


## Ask the conductor how close to the beat this input is. True = on the beat.
func _grade(what: String) -> bool:
	if not Music.is_playing():
		return false
	var g: int = Music.grade_now()["grade"]
	Events.beat_graded.emit(g, what)
	return g != Music.Grade.MISS


# --- the club ------------------------------------------------------------------

## Where the club can hit right now: chest height, or along the floor for a
## crouch strike (the only way to reach a scorpion).
func club_box() -> Rect2:
	var club: Dictionary = c["club_low"] if low else c["club"]
	var size := Vector2(club["reach"][0], club["reach"][1])
	var centre := player.global_position + Vector2(float(club["offset"][0]) * player.facing, float(club["offset"][1]))
	return Rect2(centre - size * 0.5, size)


static func club_damage(base: float, on_beat: bool, combat: Dictionary) -> int:
	return int(round(base * (float(combat["on_beat"]["damage_multiplier"]) if on_beat else 1.0)))


func _swing_hits() -> void:
	var box := club_box()
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if _hit.has(e) or not e.hurtbox().intersects(box):
			continue
		_hit[e] = true
		var dmg := club_damage(float(c["club"]["damage"]), _on_beat, c)
		e.take_hit(dmg, player.facing, float(c["club"]["knockback"]), _on_beat)
		Burst.spawn(player.get_parent(), e.hurtbox().get_center(), UiKit.GOLD if _on_beat else Color.WHITE)
		Sfx.hit("club_hit_beat" if _on_beat else "club_hit")
		if _on_beat:
			add_muse(float(c["on_beat"]["muse_hit"]))
		Hitstop.freeze(get_tree(), float(c["on_beat"]["hitstop"]) if _on_beat else float(c["club"]["hitstop"]))


# --- getting hit ---------------------------------------------------------------

## Something hurts Orpheus. Returns what happened: "ignored" (dodging or still
## blinking), "perfect" (an on-beat parry: the attacker staggers), "blocked"
## (a parry), or "hit".
func take_hit(damage: int, from: Vector2, attacker: Node = null) -> String:
	if is_dead() or _invulnerable > 0.0:
		return "ignored"
	var from_front := signf(from.x - player.global_position.x) == float(player.facing) \
		or absf(from.x - player.global_position.x) < 2.0
	if state == "parry" and from_front:
		var p: Dictionary = c["parry"]
		if _on_beat:
			add_muse(float(c["on_beat"]["muse_parry"]))
			if attacker and attacker.has_method("stagger"):
				attacker.stagger(float(p["stagger"]))
			Burst.spawn(player.get_parent(), player.global_position + Vector2(10 * player.facing, -16), UiKit.GOLD, 20.0)
			Hitstop.freeze(get_tree(), float(c["on_beat"]["hitstop"]))
			Sfx.hit("parry_perfect")
			return "perfect"
		player.velocity.x = -player.facing * float(p["block_knockback"])
		Burst.spawn(player.get_parent(), player.global_position + Vector2(10 * player.facing, -16), Color(0.7, 0.85, 1.0), 16.0)
		Sfx.hit("parry", -3.0)
		return "blocked"
	hp = maxi(0, hp - damage)
	Events.player_hp_changed.emit(hp, GameState.max_hp)
	var h: Dictionary = c["hurt"]
	var away := -1.0 if from.x > player.global_position.x else 1.0
	_knock = Vector2(away * float(h["knockback"][0]), 0.0)
	player.velocity.y = float(h["knockback"][1])
	player.facing = int(-away)
	state = "hurt"
	_t = 0.0
	notes.clear()
	_invulnerable = float(h["invulnerable"])
	player.restart_anim()
	Hitstop.freeze(get_tree(), float(h["hitstop"]))
	Sfx.hit("hurt", -2.0)
	return "hit"


# --- the lyre --------------------------------------------------------------------

func _listen_for_notes() -> void:
	for action in NOTES:
		if player.pressed(action):
			play_note(NOTES[action])


func play_note(note: String) -> void:
	var on_beat := _grade("note")
	Sfx.play("res://game/audio/sfx/lyre_%s.wav" % NOTE_SFX[note], -4.0)
	Burst.spawn(player.get_parent(), player.global_position + Vector2(8 * player.facing, -22),
		UiKit.GOLD if on_beat else Color(0.8, 0.85, 1.0), 8.0, 0.3)
	notes.append({"note": note, "on_beat": on_beat})
	if notes.size() > 8:
		notes.pop_front()
	var id := match_song(notes, songs)
	if id != "":
		_perform(id)


## The song (if any) whose notes the most recent notes spell out, among the
## songs Orpheus knows.
static func match_song(played: Array, song_book: Dictionary) -> String:
	for id in song_book:
		if id.begins_with("_") or not GameState.has_ability(StringName("song:" + id)):
			continue
		var want: Array = song_book[id]["notes"]
		if played.size() < want.size():
			continue
		var tail := played.slice(played.size() - want.size())
		var ok := true
		for i in want.size():
			if tail[i]["note"] != want[i]:
				ok = false
				break
		if ok:
			return id
	return ""


## Muse a song costs right now: combat songs cost Muse, half if every note
## was on the beat.
static func song_cost(song: Dictionary, played: Array) -> float:
	if song.get("kind", "") != "combat":
		return 0.0
	var cost := float(song.get("cost", 0))
	var tail := played.slice(maxi(0, played.size() - (song["notes"] as Array).size()))
	if tail.all(func(n): return n["on_beat"]):
		cost *= 0.5
	return cost


func _perform(id: String) -> void:
	var song: Dictionary = songs[id]
	var cost := song_cost(song, notes)
	notes.clear()
	if muse < cost:
		Events.beat_graded.emit(Music.Grade.MISS, "song_failed")
		return
	add_muse(-cost)
	var at := player.global_position + Vector2(0, -16)
	match song.get("effect", ""):
		"charm":
			for e in get_tree().get_nodes_in_group(&"enemies"):
				if e.global_position.distance_to(at) <= float(song.get("range", 200)):
					e.charm(float(song.get("seconds", 4.0)))
		"heal":
			hp = mini(GameState.max_hp, hp + int(song.get("amount", 4)))
			Events.player_hp_changed.emit(hp, GameState.max_hp)
	Burst.spawn(player.get_parent(), at, UiKit.GOLD, float(song.get("range", 48)), 0.5)
	Events.song_played.emit(id, at)
