class_name TraitSet
extends RefCounted

## Shared player/NPC trait framework. Values are intentionally stable modifiers;
## a later major-experience system may change them through set_value().
var values: Dictionary = {}


func set_value(trait_id: String, value: float) -> void:
	values[trait_id] = clampf(value, -1.0, 1.0)


func value(trait_id: String, fallback: float = 0.0) -> float:
	return float(values.get(trait_id, fallback))


func to_save_data() -> Dictionary:
	return values.duplicate()


func load_save_data(data: Dictionary) -> void:
	values = data.duplicate()
