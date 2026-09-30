class_name ZombieWorldRules
extends Resource

## Orangeville MVP tuning. These are intentionally project defaults, not claimed
## to be undocumented Project Zomboid Build 42.21 constants.
@export_range(0, 100, 1) var initial_population_cap := 7
@export_range(0.5, 30.0, 0.1) var sight_range := 4.8
@export_range(0.0, 10.0, 0.1) var peripheral_range := 1.25
@export_range(1.0, 179.0, 1.0) var sight_half_angle_degrees := 72.0
@export_range(0.1, 10.0, 0.1) var perception_interval_game_seconds := 1.5
@export_range(1.0, 600.0, 1.0) var visual_memory_game_seconds := 90.0
@export_range(1.0, 600.0, 1.0) var sound_memory_game_seconds := 55.0
@export_range(1.0, 600.0, 1.0) var search_game_seconds := 35.0
@export_range(0.0, 60.0, 0.5) var stimulus_switch_lock_game_seconds := 6.0
@export_range(1.0, 1440.0, 1.0) var migration_interval_game_minutes := 30.0
@export_range(0.0, 30.0, 0.5) var migration_player_exclusion_radius := 7.0
@export_range(0.0, 20.0, 0.5) var convergence_radius := 4.5
@export_range(1, 30, 1) var maximum_loose_group_size := 5
