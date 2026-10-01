@tool
class_name MapStairDefinition
extends Resource

@export var id := ""
@export var building_id := ""
@export var start := Vector2.ZERO
@export var end := Vector2.ONE
@export var from_floor := 0
@export var to_floor := 1
@export_range(0.1, 4.0, 0.01) var width := 0.8
## Non-destructive opening mask. Removing this stair reveals the original slab,
## including any floor/heat edits made after stair placement.
@export var opening_cells: Array[Vector2i] = []
