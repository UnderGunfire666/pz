class_name ItemStack
extends RefCounted

var definition: ItemDefinition
var quantity: int


func _init(p_definition: ItemDefinition, p_quantity: int = 1) -> void:
	definition = p_definition
	quantity = max(1, p_quantity)


func total_weight() -> float:
	return definition.unit_weight * quantity


func label() -> String:
	if quantity == 1:
		return definition.display_name
	return "%s x%d" % [definition.display_name, quantity]
