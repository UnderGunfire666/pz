@tool
class_name MapCellDefinition
extends Resource

## A fixed logical authoring cell. It is not a runtime streaming chunk.
@export var id := ""
@export var cell_coordinate := Vector2i.ZERO
@export var size := Vector2i(64, 64)
@export var levels: Array[MapLevelDefinition] = []
