@tool
class_name MapRoadDefinition
extends Resource

## Source curve is canonical. Terrain paints are applied after roads as explicit
## hand-authored overrides, so rebuilding a road never destroys edits.
@export var id := ""
@export var level := 0
@export var centerline := PackedVector2Array()
## Road authoring is grid based.  Whole-cell widths avoid ambiguous half-road
## occupancy and make water clipping deterministic.
@export_range(1.0, 16.0, 1.0) var width := 1.0
@export var terrain: MapTerrainDefinition
## New brush strokes save exact grid coverage, including even widths.
@export var grid_cells: Array[Vector2i] = []
