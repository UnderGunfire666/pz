class_name InventoryItemTree
extends Tree

var panel: BackpackPanel
var side := 0

func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null: return null
	var data: Variant = item.get_metadata(0)
	if not data is Dictionary or data.get("ids", []).is_empty(): return null
	var payload: Dictionary = data.duplicate(true)
	payload["inventory_drag"] = true
	payload["side"] = side
	payload["split"] = Input.is_physical_key_pressed(KEY_CTRL)
	var preview := Label.new()
	preview.text = "%s × %d" % [item.get_text(0), payload["ids"].size()]
	set_drag_preview(preview)
	return payload

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return panel.game != null and panel.game.inventory.has_free_hand() and panel.accepts_drag(data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var destination := panel.presentation.destination(panel.game, side)
	var item := get_item_at_position(at_position)
	if item != null:
		var row: Dictionary = item.get_metadata(0)
		if row.get("ids", []).size() == 1:
			var found := panel.game.inventory.find_unit(row["ids"][0])
			if not found.is_empty() and found["stack"].definition.capacity() > 0:
				destination = row["ids"][0]
	panel.drop_payload(data, destination)
