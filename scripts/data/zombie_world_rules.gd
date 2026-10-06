class_name ZombieWorldRules
extends Resource

## Orangeville MVP tuning. These are intentionally project defaults, not claimed
## to be undocumented Project Zomboid Build 42.21 constants.
## New worlds use this preset; the selected preset and realized total are saved.
@export_enum("Very Few", "Few", "Normal", "Many", "Very Many", "Extremely Many") var population_preset := "Normal"
@export_range(0.5, 30.0, 0.1) var sight_range := 4.8
@export_range(0.0, 10.0, 0.1) var peripheral_range := 1.25
@export_range(1.0, 179.0, 1.0) var sight_half_angle_degrees := 72.0
@export_range(0.1, 10.0, 0.1) var perception_interval_game_seconds := 1.5
@export_range(1.0, 600.0, 1.0) var visual_memory_game_seconds := 90.0
@export_range(1.0, 600.0, 1.0) var sound_memory_game_seconds := 55.0
@export_range(0.0, 10.0, 0.05) var hearing_threshold := 0.55
@export_range(1.0, 600.0, 1.0) var search_game_seconds := 35.0
@export_range(0.0, 60.0, 0.5) var stimulus_switch_lock_game_seconds := 6.0
@export_range(1.0, 1440.0, 1.0) var migration_interval_game_minutes := 30.0
@export_range(0.0, 30.0, 0.5) var migration_player_exclusion_radius := 7.0
@export_range(0.0, 20.0, 0.5) var convergence_radius := 4.5
@export_range(1, 30, 1) var maximum_loose_group_size := 5


func population_range(preset: String = "") -> Vector2i:
	match population_preset if preset.is_empty() else preset:
		"Very Few": return Vector2i(1, 3)
		"Few": return Vector2i(4, 6)
		"Many": return Vector2i(11, 16)
		"Very Many": return Vector2i(17, 24)
		"Extremely Many": return Vector2i(25, 32)
		_: return Vector2i(7, 10)
