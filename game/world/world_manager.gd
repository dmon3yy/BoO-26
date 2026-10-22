extends Node2D
## The seamless world: builds rooms on demand, moves the camera, and swaps
## rooms Super Metroid-style when Orpheus crosses an edge.
##
## Rooms are placed on the global grid from content/world.json. Crossing a
## room's edge freezes Orpheus for a moment while the camera glides into the
## next room; the room he left stays built so turning back is instant.
##
## It also owns what happens *in* the world rather than to Orpheus himself:
## resting at Hearths, dying on hazards and respawning, and the auto-map.

const VIEW := Vector2(480, 270)
const SCROLL_TIME := 0.38
const LOOK_AHEAD := 28.0
## The camera holds its height while Orpheus jumps, and only follows when he
## lands, climbs above this band, or falls below it.
const BAND_UP := 56.0
const BAND_DOWN := 20.0
const HEARTH_REACH := 20.0
const FADE_TIME := 0.3

var cell_px: Vector2
var room_cells: Dictionary = {}      # Vector2i grid cell -> room id
var room_origin: Dictionary = {}     # room id -> Vector2 world origin
var rooms: Dictionary = {}           # room id -> Room (built)
var current: Room
var player: Orpheus
var camera: Camera2D

var _bg_layer: CanvasLayer
var _bg_sprites: Array[Sprite2D] = []
var _bg_factors: Array[float] = []
var _modulate: CanvasModulate
var _sky: DirectionalLight2D
var _weather: CPUParticles2D
var _theme_id := ""
var _cam_pos := Vector2.ZERO
var _transitioning := false
var _anchor_y := 0.0
var _busy := false              # dying, respawning or resting
var _fade: ColorRect
var _prompt: Label
var _toast: Control
var _map: MapScreen


func _ready() -> void:
	var world := ContentDB.json("world")
	var cell: Array = world["cell"]
	cell_px = Vector2(cell[0], cell[1]) * RoomData.TILE
	for id in world["rooms"]:
		var at: Array = world["rooms"][id]
		var data := ContentDB.room(id)
		var span := Vector2i(maxi(1, data.width / int(cell[0])), maxi(1, data.height / int(cell[1])))
		room_origin[id] = Vector2(at[0], at[1]) * cell_px
		for dy in span.y:
			for dx in span.x:
				room_cells[Vector2i(at[0] + dx, at[1] + dy)] = id

	_modulate = CanvasModulate.new()
	add_child(_modulate)
	_sky = DirectionalLight2D.new()
	_sky.height = 0.45
	_sky.rotation_degrees = 35.0
	_sky.shadow_enabled = true
	_sky.shadow_filter = Light2D.SHADOW_FILTER_NONE
	add_child(_sky)
	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = -10
	add_child(_bg_layer)
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)

	var ui := CanvasLayer.new()
	ui.layer = 15
	add_child(ui)
	_prompt = UiKit.label("", Vector2.ZERO, UiKit.GOLD)
	_prompt.visible = false
	ui.add_child(_prompt)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = VIEW
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)
	_map = MapScreen.new()
	_map.world = self
	add_child(_map)


func start(room_id: String) -> void:
	if not room_origin.has(room_id):
		push_error("unknown room %s" % room_id)
		return
	_enter(room_id)
	player = Orpheus.new()
	player.name = "Orpheus"
	player.position = current.player_start if current.player_start != Vector2.ZERO \
		else current.rect.get_center()
	add_child(player)
	_snap_camera()
	camera.make_current()


## Put Orpheus at a world position (in the right room) with the camera on him.
func place_player(room_id: String, pos: Vector2) -> void:
	_enter(room_id)
	player.global_position = pos
	player.velocity = Vector2.ZERO
	_snap_camera()


func _snap_camera() -> void:
	_anchor_y = player.global_position.y
	_cam_pos = _camera_target()
	camera.position = _cam_pos.round()


func room_at(world_pos: Vector2) -> String:
	var c := Vector2i(floori(world_pos.x / cell_px.x), floori(world_pos.y / cell_px.y))
	return room_cells.get(c, "")


func _enter(room_id: String) -> void:
	if not rooms.has(room_id):
		var data := ContentDB.room(room_id)
		for e in data.errors:
			push_error("%s: %s" % [room_id, e])
		var room := RoomBuilder.build(data, room_origin[room_id])
		rooms[room_id] = room
		add_child(room)
	current = rooms[room_id]
	GameState.room_id = room_id
	GameState.visited_rooms[room_id] = true
	_apply_theme(current.data.header.get("theme", ""))
	Events.room_entered.emit(room_id)
	_apply_debug(current)
	# Keep only this room and its direct neighbours built.
	for id in rooms.keys():
		if id != room_id and not _touches(rooms[id].rect, current.rect):
			rooms[id].queue_free()
			rooms.erase(id)


func _touches(a: Rect2, b: Rect2) -> bool:
	return a.grow(1.0).intersects(b)


func _apply_theme(theme_id: String) -> void:
	if theme_id == _theme_id:
		return
	_theme_id = theme_id
	var theme: Dictionary = ContentDB.json("themes").get(theme_id, {})
	var amb: Array = theme.get("ambient", [1, 1, 1])
	_modulate.color = Color(amb[0], amb[1], amb[2])
	var sky: Dictionary = theme.get("sky_light", {})
	var sc: Array = sky.get("color", [1, 1, 1])
	_sky.color = Color(sc[0], sc[1], sc[2])
	_sky.energy = float(sky.get("energy", 0.0))
	_sky.visible = _sky.energy > 0.0
	for s in _bg_sprites:
		s.queue_free()
	_bg_sprites.clear()
	_bg_factors.clear()
	for layer in theme.get("backgrounds", []):
		for key in ["tex", "glow"]:
			if not layer.has(key):
				continue
			var s := Sprite2D.new()
			s.texture = ContentDB.texture("res://game/art/backgrounds/%s.png" % layer[key])
			s.centered = false
			s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			s.region_enabled = true
			s.region_rect = Rect2(0, 0, VIEW.x, VIEW.y)
			_bg_layer.add_child(s)
			_bg_sprites.append(s)
			_bg_factors.append(float(layer["factor"]))
	for h in theme.get("halos", []):
		var halo := FxNodes.halo(Vector2(h[0], h[1]), Color(h[3][0], h[3][1], h[3][2], h[3][3]), h[2])
		_bg_layer.add_child(halo)
		_bg_sprites.append(halo)
		_bg_factors.append(-1.0)
	_set_weather(theme.get("particles", ""))
	Music.play_theme(theme.get("music", ""))


func _set_weather(kind: String) -> void:
	if _weather:
		_weather.queue_free()
		_weather = null
	if kind == "":
		return
	var p := CPUParticles2D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(VIEW.x * 0.65, 4)
	if kind == "snow":
		p.texture = ContentDB.texture("res://game/art/fx/snowflake.png")
		p.amount = 90
		p.lifetime = 7.0
		p.direction = Vector2(-0.35, 1)
		p.spread = 12.0
		p.gravity = Vector2(0, 6)
		p.initial_velocity_min = 14.0
		p.initial_velocity_max = 30.0
		p.scale_amount_min = 0.34
		p.scale_amount_max = 1.0
		p.color = Color(0.9, 0.95, 1.0, 0.85)
		p.position = Vector2(30, -VIEW.y * 0.6)
	else:
		p.texture = ContentDB.texture("res://game/art/fx/ember.png")
		p.amount = 50
		p.lifetime = 5.0
		p.direction = Vector2(0.15, -1)
		p.spread = 25.0
		p.gravity = Vector2(0, -8)
		p.initial_velocity_min = 8.0
		p.initial_velocity_max = 22.0
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		p.color = Color(1.0, 0.6, 0.25, 0.9)
		p.material = FxNodes.unshaded()
		p.position = Vector2(0, VIEW.y * 0.6)
	p.preprocess = p.lifetime
	camera.add_child(p)
	_weather = p


func _camera_target() -> Vector2:
	var p := player.global_position
	if player.is_on_floor():
		_anchor_y = p.y
	else:
		_anchor_y = clampf(_anchor_y, p.y - BAND_DOWN, p.y + BAND_UP)
	var focus := Vector2(p.x + player.facing * LOOK_AHEAD, _anchor_y - 24)
	return _clamp_to(current.rect, focus)


func _clamp_to(r: Rect2, p: Vector2) -> Vector2:
	var half := VIEW * 0.5
	var lo := r.position + half
	var hi := r.end - half
	return Vector2(
		r.get_center().x if lo.x > hi.x else clampf(p.x, lo.x, hi.x),
		r.get_center().y if lo.y > hi.y else clampf(p.y, lo.y, hi.y))


func _physics_process(delta: float) -> void:
	_update_camera(delta)
	if player == null or _transitioning or _busy:
		return
	if _touching_hazard() or _fell_out_of_world():
		die()
		return
	_update_hearth_prompt()
	if not current.rect.has_point(player.global_position + Vector2(0, -8)):
		var next := room_at(player.global_position + Vector2(0, -8))
		if next != "" and next != current.data.id:
			_transition(next)


# --- Hazards, death and respawn ---------------------------------------------

## The map character under a world position ("" outside every room).
func char_at(world_pos: Vector2) -> String:
	var id := room_at(world_pos)
	if id == "":
		return ""
	var local: Vector2 = (world_pos - room_origin[id]) / RoomData.TILE
	return ContentDB.room(id).char_at(floori(local.x), floori(local.y))


func _touching_hazard() -> bool:
	var p := player.global_position
	for probe in [p + Vector2(-4, -2), p + Vector2(4, -2), p + Vector2(0, -16)]:
		if char_at(probe) in ["^", "~"]:
			return true
	return false


func _fell_out_of_world() -> bool:
	var p := player.global_position
	return p.y > current.rect.end.y + 8 and room_at(p) == ""


## Souls-lite death: half the olives stay here, Orpheus wakes at his Hearth.
func die() -> void:
	if _busy:
		return
	_busy = true
	player.frozen = true
	var at := player.global_position
	GameState.drop_olives_on_death(current.data.id, at)
	Events.player_died.emit(at, current.data.id)
	# A beat of stillness so the hit registers before the screen goes dark.
	Hitstop.freeze(get_tree(), 0.12)
	while Hitstop.active():
		await get_tree().process_frame
	await _fade_to(1.0)
	var spawn := respawn_point()
	place_player(spawn[0], spawn[1])
	await get_tree().create_timer(0.25).timeout
	await _fade_to(0.0)
	player.frozen = false
	_busy = false


## [room_id, world position] of the last Hearth rested at, or the start.
func respawn_point() -> Array:
	var hid := GameState.hearth_id
	if hid != "" and hid.contains(":hearth_"):
		var room_id := hid.get_slice(":", 0)
		var xy := hid.get_slice(":hearth_", 1).split("_")
		if room_origin.has(room_id) and xy.size() == 2:
			return [room_id, room_origin[room_id] + _foot(int(xy[0]), int(xy[1]))]
	var start := "arcadia_01"
	var data := ContentDB.room(start)
	for y in data.height:
		var x := data.map_rows[y].find("P")
		if x >= 0:
			return [start, room_origin[start] + _foot(x, y)]
	return [start, room_origin[start] + data.size_px() * 0.5]


func _foot(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * RoomData.TILE, (y + 1) * RoomData.TILE)


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tw.finished


# --- Hearths -----------------------------------------------------------------

func _nearest_hearth() -> Vector2:
	for h in current.hearths:
		if player.global_position.distance_to(h) <= HEARTH_REACH and player.is_on_floor():
			return h
	return Vector2.INF


func _update_hearth_prompt() -> void:
	var h := _nearest_hearth()
	_prompt.visible = h != Vector2.INF and not is_instance_valid(_toast)
	if not _prompt.visible:
		return
	_prompt.text = "UP: rest"
	_prompt.position = (h - camera.position + VIEW * 0.5 + Vector2(-14, -44)).round()
	if player.just_pressed(&"up"):
		rest_at(h)


## Kneel at a Hearth of Hestia: this becomes the respawn point, the game is
## saved, and Hestia speaks your Word (the save as a code you can copy).
func rest_at(h: Vector2) -> void:
	_busy = true
	_prompt.visible = false
	player.frozen = true
	player.velocity = Vector2.ZERO
	var local: Vector2 = (h - room_origin[current.data.id]) / RoomData.TILE
	GameState.hearth_id = "%s:hearth_%d_%d" % [current.data.id, floori(local.x), floori(local.y) - 1]
	GameState.room_id = current.data.id
	Save.save_game(0)
	Events.hearth_rested.emit(GameState.hearth_id)
	_show_word(Save.make_word())
	await get_tree().create_timer(0.6).timeout
	player.frozen = false
	_busy = false


func _show_word(word: String) -> void:
	if is_instance_valid(_toast):
		_toast.queue_free()
	# Spaces between the groups let the Word wrap; reading a Word ignores them.
	var shown := word.replace("-", " ")
	var box := Rect2(40, 20, 400, 0)
	var text := UiKit.label(shown, Vector2(8, 18), UiKit.INK, box.size.x - 16)
	var per_line := floori((box.size.x - 16) / 30.0) * 5      # whole 5-character groups
	box.size.y = 40 + ceili(shown.length() / float(per_line)) * 10
	_toast = UiKit.panel(box)
	_toast.add_child(UiKit.label("Hestia's Hearth. Rested and saved. Your Word:", Vector2(8, 5), UiKit.GOLD))
	_toast.add_child(text)
	_toast.add_child(UiKit.label("Jump or Esc: close", Vector2(8, box.size.y - 13), UiKit.GOLD.darkened(0.3)))
	_prompt.get_parent().add_child(_toast)
	var toast := _toast
	var shown_at := Time.get_ticks_msec()
	# Stays until dismissed, or until you walk away from the Hearth.
	var hearth := player.global_position
	while is_instance_valid(toast):
		await get_tree().process_frame
		if Time.get_ticks_msec() - shown_at < 300:
			continue     # don't let the button that started it also close it
		if player.just_pressed(&"jump") or player.just_pressed(&"pause") \
				or player.global_position.distance_to(hearth) > 48.0:
			toast.queue_free()


func _transition(next: String) -> void:
	_transitioning = true
	player.frozen = true
	var from := _cam_pos
	_enter(next)
	var to := _camera_target()
	var tw := create_tween()
	tw.tween_method(func(p: Vector2): _cam_pos = p, from, to, SCROLL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	player.frozen = false
	_transitioning = false


func _process(_delta: float) -> void:
	pass


func _update_camera(delta: float) -> void:
	if player == null:
		return
	if not _transitioning:
		_cam_pos = _cam_pos.lerp(_camera_target(), 1.0 - exp(-delta * 8.0))
	camera.position = _cam_pos.round()
	var top_left := camera.position - VIEW * 0.5
	for i in _bg_sprites.size():
		var f := _bg_factors[i]
		if f < 0.0:
			continue
		var s := _bg_sprites[i]
		s.region_rect.position.x = top_left.x * f
		s.position.y = -clampf((top_left.y - current.rect.position.y) * f * 0.3, 0.0, 40.0)


## BOO_DEBUG="noshadow,nomod,nosky,nolights" switches pieces off for lighting reviews.
func _apply_debug(room: Node) -> void:
	var flags := OS.get_environment("BOO_DEBUG")
	if flags == "":
		return
	_modulate.visible = not flags.contains("nomod")
	if flags.contains("nosky"):
		_sky.visible = false
	for n in room.find_children("*", "PointLight2D", true, false):
		if flags.contains("noshadow"):
			n.shadow_enabled = false
		if flags.contains("nolights"):
			n.visible = false
