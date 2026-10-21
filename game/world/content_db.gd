class_name ContentDB
extends RefCounted
## Reads the plain-text files in content/ (cached), and loads generated art.

static var _json_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


static func json(name: String) -> Dictionary:
	if not _json_cache.has(name):
		var path := "res://content/%s.json" % name
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_json_cache[name] = parsed if parsed is Dictionary else {}
	return _json_cache[name]


static func room(id: String) -> RoomData:
	return RoomData.load_file("res://content/rooms/%s.room" % id)


static func texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


## A CanvasTexture pairs colour with its normal map so lights can shade it.
static func lit_texture(base: String) -> Texture2D:
	var key := base + "#lit"
	if not _tex_cache.has(key):
		var diffuse := texture(base + ".png")
		var normal := texture(base + "_n.png")
		if diffuse == null:
			_tex_cache[key] = null
		elif normal == null:
			_tex_cache[key] = diffuse
		else:
			var ct := CanvasTexture.new()
			ct.diffuse_texture = diffuse
			ct.normal_texture = normal
			_tex_cache[key] = ct
	return _tex_cache[key]


static func clear() -> void:
	_json_cache.clear()
	_tex_cache.clear()


## Drop every static cache (fonts, textures, shared materials) before quitting,
## so the engine doesn't report them as leaked.
static func release_all() -> void:
	clear()
	FxNodes._additive = null
	FxNodes._unshaded_mat = null
	UiKit._font = null
	RoomBuilder._fluid_shader = null
