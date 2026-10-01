@tool
class_name MapDecorationDefinition
extends Resource

## Static map dressing. It owns placement only; rendering selects the simple
## recipe so gameplay and save state never depend on scene nodes.
@export var id := ""
@export_enum("tree", "road_sign") var kind := "tree"
@export var position := Vector2.ZERO
@export var level := 0
