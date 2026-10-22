extends Node
## Music: the conductor.
##
## Keeps an exact song clock, emits `beat` and `bar` signals, and grades
## player inputs against the nearest beat.
##
## Why not just read the audio position? Audio position only updates when the
## mixer hands over a chunk (and on the web, every 128 samples via a message),
## so it jumps in steps. We run a smooth clock from the engine's frame time and
## steer it gently toward the audio position, snapping only if they drift far
## apart. (Frame time, not wall time: it stays exact when frames stall and in
## Movie Maker recordings, which the A/V sync test relies on.)

signal beat(index: int)
signal bar(index: int)
signal song_started(song_id: String)

enum Grade { MISS, GOOD, PERFECT }

const PERFECT_WINDOW := 0.050   # seconds either side of a beat
const GOOD_WINDOW := 0.100
const ASSIST_SCALE := 1.6       # rhythm assist widens both windows
const STEER := 0.1              # fraction of clock error corrected per frame
const SNAP := 0.25              # beyond this error, jump straight to audio

var song_id := ""
var bpm := 120.0
var beats_per_bar := 4
var offset := 0.0               # seconds from stream start to beat 0
var loop_length := 0.0          # seconds; 0 = no loop

var _stems: Array[AudioStreamPlayer] = []
var _stem_names: Array[String] = []     # "melody", "harmony", "percussion"
var _mix_target: Dictionary = {}       # stem name -> 0..1
var _mix_now: Dictionary = {}
var _playing := false
var _clock := 0.0               # smoothed song time, seconds since stream start
var _laps := 0                  # completed loops, so beat indices keep rising
var _last_beat := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Play a song by id (game/audio/music/<id>.json); does nothing if it's already playing.
func play_theme(id: String) -> void:
	if id == song_id and _playing:
		return
	var path := "res://game/audio/music/%s.json" % id
	if not FileAccess.file_exists(path):
		stop()
		return
	var beat_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	play_song(id, beat_map["stems"], beat_map)


## Load a song built by tools/build_audio.py: stems plus a beat map.
func play_song(id: String, stem_paths: Array, beat_map: Dictionary) -> void:
	stop()
	song_id = id
	bpm = float(beat_map.get("bpm", 120.0))
	beats_per_bar = int(beat_map.get("beats_per_bar", 4))
	offset = float(beat_map.get("offset", 0.0))
	loop_length = float(beat_map.get("loop_seconds", 0.0))
	_stem_names.clear()
	for path in stem_paths:
		_stem_names.append(String(path).get_file().get_basename().get_slice("_", 1))
		var p := AudioStreamPlayer.new()
		var stream: AudioStream = load(path)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		p.stream = stream
		p.bus = &"Master"
		# Mixed by Godot (not handed to the browser as a sample), so loops are
		# gapless and the playback position is exact on the web too.
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(p)
		_stems.append(p)
	for p in _stems:
		p.play()
	_clock = 0.0
	_laps = 0
	_last_beat = -1
	_playing = true
	song_started.emit(id)


func stop() -> void:
	for p in _stems:
		p.stop()
		p.queue_free()
	_stems.clear()
	_playing = false


func _exit_tree() -> void:
	# Release streams before shutdown, or the audio thread keeps them alive.
	for p in _stems:
		p.stop()
		p.stream = null
	_stems.clear()


func set_stem_volume(index: int, linear: float) -> void:
	if index < _stems.size():
		_stems[index].volume_db = linear_to_db(maxf(linear, 0.0001))


## Stem layering: fade each stem toward a level, e.g.
## mix({"percussion": 1.0, "melody": 0.4}). Stems not named keep their level.
## The world calls this every frame: drums come in when a fight starts, and
## the melody steps back while Orpheus plays his lyre.
func mix(levels: Dictionary) -> void:
	_mix_target.merge(levels, true)


const MIX_RATE := 1.5          # how fast stems fade, in full volume per second


func _fade_stems(delta: float) -> void:
	for i in _stems.size():
		var stem := _stem_names[i]
		if not _mix_target.has(stem):
			continue
		var now: float = _mix_now.get(stem, 1.0)
		now = move_toward(now, float(_mix_target[stem]), MIX_RATE * delta)
		_mix_now[stem] = now
		set_stem_volume(i, now)


func is_playing() -> bool:
	return _playing


func seconds_per_beat() -> float:
	return 60.0 / bpm


## Song time as heard by the player: our clock minus extra speaker latency.
func song_time() -> float:
	return _clock + _laps * loop_length - Settings.audio_offset


## Continuous beat position (2.5 = halfway between beats 2 and 3).
func beat_position(at_time: float = song_time()) -> float:
	return (at_time - offset) / seconds_per_beat()


## Grade an input made right now. Returns {"grade": Grade, "delta": seconds}.
func grade_now() -> Dictionary:
	var t := song_time() - Settings.input_offset
	var delta := nearest_beat_delta(t, bpm, offset)
	return {"grade": grade_delta(delta, Settings.rhythm_assist), "delta": delta}


## 0..1 pulse for HUD beat indicators; 1.0 exactly on the beat.
func pulse() -> float:
	var t := song_time() - Settings.visual_offset
	var phase := fposmod(beat_position(t), 1.0)
	return pow(1.0 - phase, 3.0)


static func nearest_beat_delta(t: float, tempo: float, beat_offset: float) -> float:
	var spb := 60.0 / tempo
	var pos := (t - beat_offset) / spb
	return (pos - roundf(pos)) * spb


static func grade_delta(delta: float, assist: bool) -> Grade:
	var scale := ASSIST_SCALE if assist else 1.0
	var d := absf(delta)
	if d <= PERFECT_WINDOW * scale:
		return Grade.PERFECT
	if d <= GOOD_WINDOW * scale:
		return Grade.GOOD
	return Grade.MISS


func _process(delta: float) -> void:
	if not _playing:
		return
	_fade_stems(delta)
	_clock += delta
	var audio := _audio_position()
	if audio >= 0.0:
		var err := audio - _clock
		if loop_length > 0.0 and err < -loop_length * 0.5:
			# The audio wrapped around to the loop start before our clock did.
			_laps += 1
			_clock -= loop_length
			err = audio - _clock
		if absf(err) > SNAP:
			_clock = audio
		else:
			_clock += err * STEER
	_emit_beats()


func _audio_position() -> float:
	if _stems.is_empty() or not _stems[0].playing:
		return -1.0
	return _stems[0].get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()


func _emit_beats() -> void:
	var current := floori(beat_position())
	while _last_beat < current:
		_last_beat += 1
		beat.emit(_last_beat)
		if _last_beat % beats_per_bar == 0:
			bar.emit(_last_beat / beats_per_bar)
