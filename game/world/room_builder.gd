class_name RoomBuilder
extends RefCounted
## Turns a RoomData into a Room node: tile layers, seamless collision,
## shadow-casting occluders, ledges, fluids, props and their lights.
##
## Used by the game, the editor preview and the screenshot tool, so a room
## always looks the same everywhere and never needs re-importing.

const T := RoomData.TILE
const TILES := "res://game/art/tiles/"
const PROPS := "res://game/art/props/"

const FLUID_SHADER := """
shader_type canvas_item;
uniform vec4 deep : source_color;
uniform vec4 mid : source_color;
uniform vec4 crest : source_color;
uniform vec2 size_px;
uniform float speed = 1.0;
void fragment() {
	vec2 p = floor(UV * size_px);
	float t = TIME * speed;
	float wave = sin(p.x * 0.35 + t * 2.0) + sin(p.x * 0.13 - t * 1.3) * 0.8;
	float n = sin(p.x * 0.9 + p.y * 1.7 + t * 3.0) * 0.5 + 0.5;
	vec4 c = deep;
	if (p.y < 2.0 + wave * 0.6) { c = crest; }
	else if (n > 0.72 - p.y * 0.02) { c = mid; }
	COLOR = c;
}
"""

static var _fluid_shader: Shader


static func build(data: RoomData, world_origin: Vector2) -> Room:
	var room := Room.new()
	room.name = data.id
	room.data = data
	room.position = world_origin
	room.rect = Rect2(world_origin, data.size_px())
	var themes := ContentDB.json("themes")
	room.theme = themes.get(data.header.get("theme", ""), {})
	var cell_origin := Vector2i(world_origin / T)

	_build_back(room, data, cell_origin)
	_build_solids(room, data, cell_origin)
	_build_collision_and_shadows(room, data)
	_build_ledges(room, data)
	_build_fluids(room, data)
	_build_spikes(room, data)
	_build_entities(room, data)
	return room


## '^' cells: a row of shards from the theme ("spikes" in themes.json). They
## have no collision; the WorldManager kills Orpheus when he touches one.
static func _build_spikes(room: Room, data: RoomData) -> void:
	var tex := ContentDB.lit_texture(PROPS + str(room.theme.get("spikes", "spikes_ice")))
	if tex == null:
		return
	for y in data.height:
		for x in data.width:
			if data.char_at(x, y) == "^":
				var s := Sprite2D.new()
				s.texture = tex
				s.centered = false
				s.position = Vector2(x, y) * T
				room.add_child(s)


# --- layers ------------------------------------------------------------------

static func _tile_layer(material: String, emissive: bool = false) -> TileMapLayer:
	var layer := TileMapLayer.new()
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(T, T)
	if emissive:
		src.texture = ContentDB.texture(TILES + material + "_e.png")
		layer.material = FxNodes.additive()
	else:
		src.texture = ContentDB.lit_texture(TILES + material)
	ts.add_source(src, 0)
	layer.tile_set = ts
	layer.name = material + ("_glow" if emissive else "")
	return layer


static func _place(layer: TileMapLayer, cell: Vector2i, atlas: Vector2i) -> void:
	var src := layer.tile_set.get_source(0) as TileSetAtlasSource
	if not src.has_tile(atlas):
		src.create_tile(atlas)
	layer.set_cell(cell, 0, atlas)


static func _build_solids(room: Room, data: RoomData, cell_origin: Vector2i) -> void:
	var materials: Dictionary = room.theme.get("solid", {})
	var glow_chance := float(room.theme.get("glow_chance", 1.0))
	var layers := {}
	var glow_layers := {}
	var is_solid := func(c: Vector2i) -> bool:
		return _is_solid_char(data.char_at(clampi(c.x, 0, data.width - 1), clampi(c.y, 0, data.height - 1)))
	for y in data.height:
		for x in data.width:
			var ch := data.char_at(x, y)
			if not materials.has(ch):
				continue
			var mat: String = materials[ch]
			if not layers.has(mat):
				layers[mat] = _tile_layer(mat)
				room.add_child(layers[mat])
				if ContentDB.texture(TILES + mat + "_e.png") != null:
					glow_layers[mat] = _tile_layer(mat, true)
			var mask := Autotiler.mask_at(Vector2i(x, y), is_solid)
			var atlas := Autotiler.atlas_coords(mask, cell_origin + Vector2i(x, y))
			_place(layers[mat], Vector2i(x, y), atlas)
			if glow_layers.has(mat) and _glows(cell_origin + Vector2i(x, y), glow_chance):
				_place(glow_layers[mat], Vector2i(x, y), atlas)
	for mat in glow_layers:
		room.add_child(glow_layers[mat])


static func _build_back(room: Room, data: RoomData, cell_origin: Vector2i) -> void:
	var backs: Dictionary = room.theme.get("back", {})
	if data.back_rows.is_empty() or backs.is_empty():
		return
	var layers := {}
	for y in data.height:
		for x in data.width:
			var ch := data.back_at(x, y)
			if not backs.has(ch):
				continue
			var mat: String = backs[ch]
			if not layers.has(mat):
				var layer := _tile_layer(mat)
				layer.z_index = -5
				layer.modulate = Color(0.78, 0.78, 0.82)
				layers[mat] = layer
				room.add_child(layer)
				if ContentDB.texture(TILES + mat + "_e.png") != null:
					var glow := _tile_layer(mat, true)
					glow.z_index = -4
					layers[mat + "#glow"] = glow
					room.add_child(glow)
			var same := func(c: Vector2i) -> bool:
				return data.back_at(clampi(c.x, 0, data.width - 1), clampi(c.y, 0, data.height - 1)) == ch
			var atlas := Autotiler.atlas_coords(Autotiler.mask_at(Vector2i(x, y), same), cell_origin + Vector2i(x, y))
			_place(layers[mat], Vector2i(x, y), atlas)
			if layers.has(mat + "#glow"):
				_place(layers[mat + "#glow"], Vector2i(x, y), atlas)


## Deterministic per-cell coin flip, so glowing seams scatter without repeating.
static func _glows(cell: Vector2i, chance: float) -> bool:
	if chance >= 1.0:
		return true
	var h := hash(cell.x * 73856093 ^ cell.y * 19349663)
	return float(h % 1000) / 1000.0 < chance


static func _is_solid_char(ch: String) -> bool:
	return ch == "#" or ch == "%"


# --- collision + shadows -------------------------------------------------------

static func _build_collision_and_shadows(room: Room, data: RoomData) -> void:
	var solid := func(c: Vector2i) -> bool:
		return _is_solid_char(data.char_at(c.x, c.y))
	var surfaces := TileOutline.trace(Vector2i(data.width, data.height), solid, T)
	var body := StaticBody2D.new()
	body.name = "Solid"
	body.collision_layer = 1
	room.add_child(body)
	for surf in surfaces:
		var pts: PackedVector2Array = surf["points"]
		if pts.size() < 2:
			continue
		# Explicit segment pairs: an open surface must not be closed into a loop.
		var segs := PackedVector2Array()
		var n := pts.size()
		for i in (n if surf["closed"] else n - 1):
			segs.append(pts[i])
			segs.append(pts[(i + 1) % n])
		var concave := ConcavePolygonShape2D.new()
		concave.segments = segs
		var shape := CollisionShape2D.new()
		shape.shape = concave
		body.add_child(shape)
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		poly.polygon = pts
		poly.closed = surf["closed"]
		poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
		occ.occluder = poly
		room.add_child(occ)


static func _build_ledges(room: Room, data: RoomData) -> void:
	var ledge_mat: String = room.theme.get("ledge", "")
	if ledge_mat == "":
		return
	var tex := ContentDB.lit_texture(TILES + ledge_mat)
	for y in data.height:
		var x := 0
		while x < data.width:
			if data.char_at(x, y) != "=":
				x += 1
				continue
			var start := x
			while x < data.width and data.char_at(x, y) == "=":
				x += 1
			var length := x - start
			for i in length:
				var s := Sprite2D.new()
				s.texture = tex
				s.centered = false
				s.region_enabled = true
				var kind := 0 if length == 1 else (1 if i == 0 else (3 if i == length - 1 else 2))
				s.region_rect = Rect2(kind * T, 0, T, T)
				s.position = Vector2((start + i) * T, y * T)
				room.add_child(s)
			var body := StaticBody2D.new()
			body.collision_layer = 2
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(length * T, 4)
			shape.shape = rect
			shape.one_way_collision = true
			shape.position = Vector2((start + length * 0.5) * T, y * T + 2)
			body.add_child(shape)
			room.add_child(body)


static func _build_fluids(room: Room, data: RoomData) -> void:
	var kind: String = room.theme.get("fluid", "")
	for y in data.height:
		var x := 0
		while x < data.width:
			if data.char_at(x, y) != "~":
				x += 1
				continue
			var start := x
			while x < data.width and data.char_at(x, y) == "~":
				x += 1
			var r := ColorRect.new()
			r.position = Vector2(start * T, y * T + 4)
			r.size = Vector2((x - start) * T, T - 4)
			var mat := ShaderMaterial.new()
			if _fluid_shader == null:
				_fluid_shader = Shader.new()
				_fluid_shader.code = FLUID_SHADER
			mat.shader = _fluid_shader
			mat.set_shader_parameter("size_px", r.size)
			if kind == "molten":
				mat.set_shader_parameter("deep", Color("e2461a"))
				mat.set_shader_parameter("mid", Color("ff8a2a"))
				mat.set_shader_parameter("crest", Color("ffd36a"))
				r.material = mat
				r.z_index = 1
				var mid := Vector2((start + x) * 0.5 * T, y * T + 2)
				room.add_child(FxNodes.light(mid, {"color": [1.0, 0.5, 0.2], "energy": 1.3,
					"scale": maxf(1.2, (x - start) * 0.25), "flicker": 0.1, "shadow": true}))
				room.add_child(FxNodes.halo(mid + Vector2(0, 6), Color(1.0, 0.45, 0.15, 0.55), (x - start) * T * 0.6))
			else:
				mat.set_shader_parameter("deep", Color(0.16, 0.28, 0.42, 0.85))
				mat.set_shader_parameter("mid", Color(0.3, 0.5, 0.68, 0.85))
				mat.set_shader_parameter("crest", Color(0.75, 0.88, 0.98, 0.95))
				mat.set_shader_parameter("speed", 0.4)
				r.material = mat
			room.add_child(r)


# --- entities ------------------------------------------------------------------

static func _build_entities(room: Room, data: RoomData) -> void:
	var legend := ContentDB.json("legend")
	var entity_kinds: Dictionary = legend.get("entities", {})
	var props := ContentDB.json("props")
	var enemies := ContentDB.json("enemies")
	var npcs := ContentDB.json("npcs")
	for y in data.height:
		for x in data.width:
			var ch := data.char_at(x, y)
			var kind := ""
			if data.legend.has(ch):
				kind = data.legend[ch]["kind"]
			elif entity_kinds.has(ch):
				kind = entity_kinds[ch]
			if kind == "":
				continue
			var foot := Vector2((x + 0.5) * T, (y + 1) * T)
			match kind:
				"player_start":
					room.player_start = room.position + foot
				_ when enemies.has(kind):
					var flag: String = enemies[kind].get("defeat_flag", "")
					if flag != "" and GameState.has(flag):
						continue     # a guardian stays beaten
					var e := Enemy.create(kind)
					e.position = foot
					room.add_child(e)
				_ when npcs.has(kind):
					var npc := Npc.new()
					npc.who = kind
					npc.position = foot
					room.add_child(npc)
					room.npcs.append(npc)
				_:
					if kind == "hearth":
						room.hearths.append(room.position + foot)
					var entity_id := "%s:%s_%d_%d" % [data.id, kind, x, y]
					var params: Dictionary = data.legend[ch]["params"] if data.legend.has(ch) else {}
					if GameState.collected.has(entity_id):
						continue     # sung open, picked up
					if kind == "pickup" and GameState.has(params.get("ability", "")):
						continue
					if kind == "gate" and GameState.has(params.get("needs", "")):
						continue     # already open
					var look: String = params.get("look", kind)
					if kind == "pickup" and not params.has("look"):
						look = "item_" + String(params.get("ability", "")).replace("song:", "song_")
					if props.has(look):
						var made := _spawn_prop(room, props[look], foot, entity_id)
						match kind:
							"song_seal":
								room.seals[entity_id] = {"song": params.get("song", ""), "at": room.position + foot,
									"nodes": made}
							"gate":
								room.gates[entity_id] = {"needs": params.get("needs", ""), "nodes": made}
							_ when props[look].has("pickup") or kind == "pickup":
								room.pickups[entity_id] = {"kind": kind, "params": params,
									"at": room.position + foot, "nodes": made}


## Builds a prop and returns every node it made (so a seal can be removed).
static func _spawn_prop(room: Room, spec: Dictionary, foot: Vector2, entity_id: String) -> Array[Node]:
	var made: Array[Node] = []
	var base: String = PROPS + spec["texture"]
	var sprite: Sprite2D = BobSprite.new() if spec.get("bob", false) else Sprite2D.new()
	sprite.texture = ContentDB.lit_texture(base)
	if sprite.texture == null:
		return made
	var size := sprite.texture.get_size()
	var anchor := foot
	if spec.get("hang", false):
		anchor = foot + Vector2(0, -T)   # hangs from the tile above, bottom at mid-tile
	elif spec.get("drip", false):
		anchor = foot + Vector2(0, size.y - T)   # top edge against the ceiling above
	sprite.position = anchor + Vector2(0, -size.y / 2.0)
	sprite.z_index = int(spec.get("z", 0))
	sprite.set_meta("entity_id", entity_id)
	room.add_child(sprite)
	made.append(sprite)
	if spec.get("emissive", false):
		var glow := Sprite2D.new()
		glow.texture = ContentDB.texture(base + "_e.png")
		glow.material = FxNodes.additive()
		glow.position = sprite.position
		glow.z_index = sprite.z_index
		room.add_child(glow)
		made.append(glow)
	for f in spec.get("flame", []):
		var fl := FxNodes.flame(anchor + Vector2(f[0], f[1]))
		fl.z_index = sprite.z_index + 1
		room.add_child(fl)
		made.append(fl)
	for l in spec.get("lights", []):
		var at: Vector2 = anchor + Vector2(l["offset"][0], l["offset"][1])
		var light := FxNodes.light(at, l)
		room.add_child(light)
		var c: Array = l.get("color", [1, 1, 1])
		var halo := FxNodes.halo(at, Color(c[0], c[1], c[2], 0.7), float(l.get("halo", 28.0 * float(l.get("scale", 1.0)))))
		room.add_child(halo)
		made.append_array([light, halo])
	if spec.get("solid", false):
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		body.position = sprite.position
		body.add_child(shape)
		room.add_child(body)
		made.append(body)
	return made


class BobSprite:
	extends Sprite2D
	## Pickups float gently so they read as collectable.
	func _ready() -> void:
		var tw := create_tween().set_loops()
		tw.tween_property(self, "position:y", position.y - 2, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "position:y", position.y, 0.6).set_trans(Tween.TRANS_SINE)
