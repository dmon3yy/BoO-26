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
