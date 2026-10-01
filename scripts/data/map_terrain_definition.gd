@tool
class_name MapTerrainDefinition
extends Resource

## Immutable authoring definition. Runtime tiles copy these values so gameplay
## never depends on a mesh or material.
@export var id := ""
@export var display_name := ""
@export_enum("grass", "dirt", "gravel", "asphalt", "concrete", "water", "indoor_floor") var category := "grass"
@export var passable := true
@export_range(0.01, 10.0, 0.01) var movement_cost := 1.0
@export var blocks_line_of_sight := false
@export_range(0.0, 1.0, 0.01) var sound_attenuation := 0.0
@export var supports_floor := true
@export var visual_recipe := "grass"
