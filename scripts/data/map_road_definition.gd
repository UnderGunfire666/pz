@tool
class_name MapRoadDefinition
extends Resource

## Source curve is canonical. Terrain paints are applied after roads as explicit
## hand-authored overrides, so rebuilding a road never destroys edits.
@export var id := ""
@export var level := 0
@export var centerline := PackedVector2Array()
@export_range(0.5, 16.0, 0.1) var width := 1.0
@export var terrain: MapTerrainDefinition
