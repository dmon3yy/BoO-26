extends Node2D
## The seamless world: builds rooms on demand, moves the camera, and swaps
## rooms Super Metroid-style when Orpheus crosses an edge.
##
## Rooms are placed on the global grid from content/world.json. Crossing a
## room's edge freezes Orpheus for a moment while the camera glides into the
## next room; the room he left stays built so turning back is instant.

const VIEW := Vector2(480, 270)
const SCROLL_TIME := 0.38
const LOOK_AHEAD := 28.0

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
	_cam_pos = _camera_target()
	camera.position = _cam_pos.round()
	camera.make_current()


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
	var focus := player.global_position + Vector2(player.facing * LOOK_AHEAD, -24)
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
	if player == null or _transitioning:
		return
	if not current.rect.has_point(player.global_position + Vector2(0, -8)):
		var next := room_at(player.global_position + Vector2(0, -8))
		if next != "" and next != current.data.id:
			_transition(next)


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
