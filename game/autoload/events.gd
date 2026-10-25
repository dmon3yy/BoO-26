extends Node
## Global signal bus.
##
## Systems announce what happened here instead of holding references to each
## other. A HUD can listen for `olives_changed` without knowing the economy
## code exists, so either piece can change without breaking the other.

signal room_entered(room_id: String)
signal player_died(at: Vector2, room_id: String)
signal olives_changed(total: int)
signal ability_gained(ability: StringName)
signal flag_set(flag: StringName)
signal hearth_rested(hearth_id: String)
signal song_played(song_id: String, at: Vector2)
signal player_hp_changed(hp: int, max_hp: int)
signal muse_changed(muse: float, max_muse: float)
## Every graded action (swing, parry, note), so the HUD can show the beat.
signal beat_graded(grade: int, what: String)
## An enemy was defeated at `at` (world position), dropping `olives`.
signal enemy_defeated(kind: String, at: Vector2, olives: int)
## Hermes has something to say (see content/narration.json).
signal narrate(key: String)
signal journal_added(entry_id: String)
## Shake the screen for a moment (if Pause > Screen shake is on).
signal shake(seconds: float)
