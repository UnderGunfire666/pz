class_name InventoryDropSurface
extends Control

var panel: BackpackPanel

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return panel != null and panel.accepts_drag(data)

func _drop_data(_position: Vector2, data: Variant) -> void:
	panel.drop_payload(data, "ground")
