extends Node
## One-shot sound effects from a small pool of players.

const POOL_SIZE := 12

var _pool: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


## Play one of the built sound effects by name: Sfx.hit("club_hit").
func hit(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	play("res://game/audio/sfx/%s.wav" % sound, volume_db, pitch)


func play(path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _cache.has(path):
		if not ResourceLoader.exists(path):
			return
		_cache[path] = load(path)
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _cache[path]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
