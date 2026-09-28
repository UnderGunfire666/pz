class_name InventoryGrid
extends RefCounted

## Grid-inspired placement gives MVP inventory meaningful size and weight pressure
## without building the final drag-and-drop UI yet.
var grid_size: Vector2i
var max_weight: float
var placements: Array[Dictionary] = []


func _init(p_grid_size: Vector2i = Vector2i(6, 4), p_max_weight: float = 12.0) -> void:
	grid_size = p_grid_size
	max_weight = p_max_weight


func current_weight() -> float:
	var total := 0.0
	for placement in placements:
		total += (placement["stack"] as ItemStack).total_weight()
	return total


func add_item(stack: ItemStack) -> bool:
	if stack == null or stack.quantity <= 0 or stack.definition.grid_size.x <= 0 or stack.definition.grid_size.y <= 0:
		return false
	if current_weight() + stack.total_weight() > max_weight:
		return false
	var slot := find_first_fit(stack.definition.grid_size)
	if slot.x < 0:
		return false
	placements.append({"stack": stack, "slot": slot})
	return true


func find_first_fit(item_size: Vector2i) -> Vector2i:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var candidate := Vector2i(x, y)
			if _fits(candidate, item_size):
				return candidate
	return Vector2i(-1, -1)


func _fits(origin: Vector2i, item_size: Vector2i) -> bool:
	if origin.x < 0 or origin.y < 0:
		return false
	if origin.x + item_size.x > grid_size.x or origin.y + item_size.y > grid_size.y:
		return false
	for placement in placements:
		var occupied_origin: Vector2i = placement["slot"]
		var occupied_size: Vector2i = (placement["stack"] as ItemStack).definition.grid_size
		var candidate_rect := Rect2i(origin, item_size)
		var occupied_rect := Rect2i(occupied_origin, occupied_size)
		if candidate_rect.intersects(occupied_rect):
			return false
	return true


func take_first_with_tag(tag: String) -> ItemStack:
	for index in range(placements.size()):
		var stack: ItemStack = placements[index]["stack"]
		if tag in stack.definition.tags:
			stack.quantity -= 1
			if stack.quantity <= 0:
				placements.remove_at(index)
			return ItemStack.new(stack.definition)
	return null


func sort_items() -> void:
	var previous := placements.duplicate()
	var old_stacks: Array[ItemStack] = []
	for placement in placements:
		old_stacks.append(placement["stack"])
	old_stacks.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		return a.definition.grid_size.x * a.definition.grid_size.y > b.definition.grid_size.x * b.definition.grid_size.y)
	placements.clear()
	for stack in old_stacks:
		if not add_item(stack):
			placements = previous
			return


func summary() -> String:
	if placements.is_empty():
		return "Empty"
	var labels: Array[String] = []
	for placement in placements:
		labels.append((placement["stack"] as ItemStack).label())
	return ", ".join(labels)
