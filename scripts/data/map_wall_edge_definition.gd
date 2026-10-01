@tool
class_name MapWallEdgeDefinition
extends Resource

## Explicit authored edge. Walls occupy boundaries and never consume a full tile.
@export var id := ""
@export var start := Vector2.ZERO
@export var end := Vector2.RIGHT
@export var level := 0
@export var building_id := ""
@export_enum("wall", "door", "window") var kind := "wall"
@export var initially_open := false
@export var initially_intact := true
