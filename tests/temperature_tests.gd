extends Node

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	var fridge := ContainerData.new("fridge", "Fridge")
	fridge.temperature_target = 4.0
	var freezer := ContainerData.new("freezer", "Freezer")
	freezer.temperature_target = -18.0
	check(fridge.effective_temperature(-7.5) == -7.5, "Cold room must not make fridge a heater")
	check(fridge.effective_temperature(30.0) == 4.0, "Warm room retains refrigeration")
	check(freezer.effective_temperature(-25.0) == -25.0, "Freezer cannot heat an even colder room")
	check(is_equal_approx(StatusConfig.item_temperature_after(-10.0, 30.0, 3600.0), -8.4), "30 C warming is 1.6 C/hour")
	check(is_equal_approx(StatusConfig.item_temperature_after(-10.0, 4.0, 3600.0), -8.92), "Refrigerated thawing is 1.08 C/hour")
	check(is_equal_approx(StatusConfig.item_temperature_after(-10.0, -7.5, 3600.0), -9.15), "Subzero warming keeps agreed 2 percent reduction")
	check(StatusConfig.item_temperature_after(20.0, -18.0, 3600.0) < StatusConfig.item_temperature_after(20.0, 4.0, 3600.0), "Freezer cools faster than fridge")
	check(StatusConfig.item_temperature_after(20.0, -18.0, 864000.0) == -18.0, "Cooling cannot overshoot")
	check(StatusConfig.item_temperature_after(-18.0, 4.0, 864000.0) == 4.0, "Warming cannot overshoot")
	var inventory := InventoryGrid.new()
	var apple := ItemStack.new(ItemCatalog.food_definitions()["apple"])
	apple.units[0]["temperature"] = -7.5
	fridge.contents.append(apple)
	inventory.world[fridge.id] = fridge
	inventory._advance_item_minute(-7.5)
	check(apple.units[0]["temperature"] == -7.5, "Reproduced winter fridge case stays cold")
	var pack := ItemStack.new(ItemCatalog.backpack_definitions()["small_backpack"])
	fridge.contents.erase(apple)
	pack.units[0]["contents"].append(apple)
	freezer.contents.append(pack)
	inventory.world[freezer.id] = freezer
	inventory._advance_item_minute(-7.5)
	check(apple.units[0]["temperature"] < -7.5, "Nested food inherits freezer environment")
	check(inventory.move_unit(apple.units[0]["uid"], "loose"), "Food can be removed from freezer")
	apple = inventory.loose[0]
	var cold: float = apple.units[0]["temperature"]
	inventory._advance_item_minute(20.0)
	check(apple.units[0]["temperature"] > cold, "Removed food warms in room")
	var restored := InventoryCodec.unpack(InventoryCodec.pack(apple))
	check(restored.units[0]["temperature"] == apple.units[0]["temperature"], "Save codec preserves food temperature")
	var batch := InventoryGrid.new()
	var ticks := InventoryGrid.new()
	var one := ItemStack.new(ItemCatalog.food_definitions()["apple"])
	one.units[0]["temperature"] = 20.0
	batch.loose.append(one)
	ticks.loose.append(InventoryCodec.unpack(InventoryCodec.pack(one)))
	GameTime.elapsed_game_seconds = 3600.0
	batch.advance_item_states(3600.0)
	for minute in range(1, 61):
		GameTime.elapsed_game_seconds = minute * 60.0
		ticks.advance_item_states(60.0)
	check(is_equal_approx(one.units[0]["temperature"], ticks.loose[0].units[0]["temperature"]), "Fast forward matches minute ticks")
	check(is_equal_approx(one.units[0]["freshness"], ticks.loose[0].units[0]["freshness"]), "Fast forward freshness matches minute ticks")
	var before: float = one.units[0]["temperature"]
	batch.advance_item_states(0.0)
	check(one.units[0]["temperature"] == before, "Paused simulation does not change temperature")
	print("Temperature regression failures: ", failures)
	get_tree().quit(1 if failures else 0)
