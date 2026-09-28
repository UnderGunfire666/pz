class_name ItemDefinition
extends RefCounted

## Immutable item data. A production game would load this from .tres or JSON data.
var id: String
var display_name: String
var grid_size: Vector2i
var unit_weight: float
var tags: Array[String]


func _init(
		p_id: String,
		p_display_name: String,
		p_grid_size: Vector2i,
		p_unit_weight: float,
		p_tags: Array[String] = []
	) -> void:
	id = p_id
	display_name = p_display_name
	grid_size = p_grid_size
	unit_weight = p_unit_weight
	tags = p_tags
