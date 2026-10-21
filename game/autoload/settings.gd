extends Node
## Player settings: controls, rhythm calibration and accessibility.
##
## Default bindings are created in code (not stored in project.godot) so that
## remapping is just "replace the events on an action" and reset is trivial.

const PATH := "user://settings.cfg"

## Calibration, in seconds. Positive audio_offset means "the speakers are late".
var audio_offset := 0.0
var visual_offset := 0.0
var input_offset := 0.0
var rhythm_assist := false
var screen_shake := true
var flashes := true

const KEYS := {
	&"move_left": [KEY_LEFT, KEY_A],
	&"move_right": [KEY_RIGHT, KEY_D],
	&"up": [KEY_UP, KEY_W],
	&"down": [KEY_DOWN, KEY_S],
	&"jump": [KEY_SPACE, KEY_Z],
	&"attack": [KEY_X, KEY_J],
	&"dodge": [KEY_C, KEY_K],
	&"parry": [KEY_V, KEY_L],
	&"lyre": [KEY_SHIFT, KEY_I],
	&"item": [KEY_Q],
	&"pause": [KEY_ESCAPE, KEY_ENTER],
	&"debug_next_room": [KEY_F2],
	&"debug_beat_lab": [KEY_F3],
	&"debug_dialogue": [KEY_F4],
	&"debug_capture": [KEY_F12],
}

const PAD_BUTTONS := {
	&"move_left": [JOY_BUTTON_DPAD_LEFT],
	&"move_right": [JOY_BUTTON_DPAD_RIGHT],
	&"up": [JOY_BUTTON_DPAD_UP],
	&"down": [JOY_BUTTON_DPAD_DOWN],
	&"jump": [JOY_BUTTON_A],
	&"attack": [JOY_BUTTON_X],
	&"dodge": [JOY_BUTTON_B],
	&"parry": [JOY_BUTTON_RIGHT_SHOULDER],
	&"lyre": [JOY_BUTTON_LEFT_SHOULDER],
	&"item": [JOY_BUTTON_Y],
	&"pause": [JOY_BUTTON_START],
}

const PAD_AXES := {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"up": [JOY_AXIS_LEFT_Y, -1.0],
	&"down": [JOY_AXIS_LEFT_Y, 1.0],
}


func _ready() -> void:
	install_default_bindings()
	load_settings()


func install_default_bindings() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.35)
		for keycode in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		for button in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	audio_offset = cfg.get_value("rhythm", "audio_offset", audio_offset)
	visual_offset = cfg.get_value("rhythm", "visual_offset", visual_offset)
	input_offset = cfg.get_value("rhythm", "input_offset", input_offset)
	rhythm_assist = cfg.get_value("rhythm", "assist", rhythm_assist)
	screen_shake = cfg.get_value("comfort", "screen_shake", screen_shake)
	flashes = cfg.get_value("comfort", "flashes", flashes)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("rhythm", "audio_offset", audio_offset)
	cfg.set_value("rhythm", "visual_offset", visual_offset)
	cfg.set_value("rhythm", "input_offset", input_offset)
	cfg.set_value("rhythm", "assist", rhythm_assist)
	cfg.set_value("comfort", "screen_shake", screen_shake)
	cfg.set_value("comfort", "flashes", flashes)
	cfg.save(PATH)
