class_name BackpackTests
extends RefCounted

static func run(game: MVPGameRoot, check: Callable) -> void:
	var inv := InventoryGrid.new(false)
	var pack := ItemStack.new(ItemDefinition.backpack("test_pack", "Pack", Vector3(3, 3, 3), 2, 0.1))
	inv.equipment.append(pack)
	check.call(is_equal_approx(pack.definition.volume(), 64.0), "3 cubed backpack has 4 cubed external dimensions")
	var rod := ItemStack.new(ItemDefinition.new("rod", "Long rod", Vector3(27, 1, 1), 1))
	check.call(inv.add_item(rod) and is_equal_approx(pack.used_volume(), 27), "volume boundary accepts long item without orientation constraints")
	check.call(not inv.add_item(ItemStack.new(ItemDefinition.new("extra", "Extra", Vector3.ONE, 1))), "capacity rejects one unit above exact volume")
	inv.contents(inv.default_destination()).clear()
	var inner := ItemStack.new(ItemDefinition.backpack("inner", "Inner", Vector3.ONE, 1, 0.5))
	inner.units[0]["contents"].append(ItemStack.new(ItemDefinition.new("dense", "Dense", Vector3.ONE, 10)))
	check.call(inv.add_item(inner), "nested backpack consumes external rather than internal volume")
	check.call(is_equal_approx(inv.current_weight(), 2 + (1 + 10) * 0.9), "only equipped outer backpack reduces full contents weight")
	check.call(is_equal_approx(inner.total_weight(), 11), "nested backpack has unreduced physical mass")
	check.call(is_equal_approx(inv.effective_weight(ItemStack.from_unit(pack.definition, pack.units[0])), inv.current_weight()), "equipped row displays effective weight by unit identity")
	var weight := inner.total_weight()
	inner.units[0]["durability"] = 0
	check.call(is_equal_approx(inner.total_weight(), weight) and is_equal_approx(inner.definition.volume(), 8), "damage changes neither weight nor volume")
	check.call(not inv.move_unit(pack.units[0]["uid"], inner.units[0]["uid"]), "ancestor cannot be moved into its own descendant")
	var bottle_def := ItemDefinition.new("bottle", "Bottle", Vector3(1, 1, 2), 0.2, ["water"])
	bottle_def.capacity_dimensions = Vector3.ONE
	var water_def := ItemDefinition.new("water", "Water", Vector3(0.5, 1, 1), 0.5, ["liquid", "water"])
	var bottle := ItemStack.new(bottle_def)
	bottle.units[0]["contents"].append(ItemStack.new(water_def))
	check.call(is_equal_approx(bottle.total_volume(), 2) and is_equal_approx(bottle.total_weight(), 0.7), "liquid adds weight but no volume beyond bottle exterior")
	var limit_inv := InventoryGrid.new(false)
	limit_inv.absolute_limit = 5
	check.call(limit_inv.add_item(ItemStack.new(ItemDefinition.new("limit", "Limit", Vector3.ONE, 5))), "absolute weight boundary accepted")
	check.call(not limit_inv.add_item(ItemStack.new(ItemDefinition.new("over", "Over", Vector3.ONE, 0.01))) and is_equal_approx(limit_inv.current_weight(), 5), "absolute weight overflow rejected atomically")
	var reduced := InventoryGrid.new(false)
	reduced.absolute_limit = 5
	var heavy_pack := ItemStack.new(ItemDefinition.backpack("reduced", "Reduced", Vector3(2, 2, 2), 1, 0.9))
	var heavy_unit := ItemStack.new(ItemDefinition.new("heavy", "Heavy", Vector3.ONE, 20))
	heavy_pack.units[0]["contents"].append(heavy_unit)
	reduced.equipment.append(heavy_pack)
	var heavy_uid: String = heavy_unit.units[0]["uid"]
	check.call(not reduced.move_unit(heavy_uid, "loose") and reduced.find_unit(heavy_uid)["owner"] == heavy_pack.units[0]["uid"],
		"taking out reduced-weight item cannot transiently exceed absolute limit")
	var state := PlayerState.new()
	state.inventory = limit_inv
	limit_inv.penalty_limit = 3
	check.call(state.movement_multiplier() < 1 and state.exertion_multiplier() > 1, "encumbrance slows movement and increases stamina/fatigue exertion")

	var baseline := QuickSave.snapshot(game)
	check.call(QuickSave.validate(baseline, game), "pre-backpack test world snapshot valid")
	var actions := game.interactions
	actions.interrupt_action()
	game.player.logical_position = Vector2(4.5, 7)
	game.player.floor_level = 0
	game.player.stair_id = ""
	game.inventory.loose.clear()
	game.inventory.equipment.clear()
	for hand in InventoryGrid.HANDS: game.inventory.contents(hand).clear()
	game.inventory.use_context.clear()
	game.inventory.equipment.append(ItemStack.new(ItemDefinition.backpack("tiny", "Tiny", Vector3(1, 1, 2), 0.5, 0.1)))
	var destination := game.inventory.default_destination()
	var source := actions._ground_container()
	var first_pile_count := actions.points.size()
	check.call(actions._ground_container() == source and actions.points.size() == first_pile_count,
		"repeated drops at one floor position reuse a single ground pile")
	var ground_position := game.player.logical_position
	game.player.floor_level = 1
	game.player.logical_position = Vector2(4.5, 3.5)
	check.call(actions._ground_container() != source, "same position on another floor receives an independent ground pile")
	game.player.floor_level = 0
	game.player.logical_position = ground_position
	var cans := ItemStack.new(ItemDefinition.new("can", "Can", Vector3.ONE, 1, ["food"]), 3)
	cans.units[0]["flavor"] = "Peach"
	cans.units[1]["flavor"] = "Pear"
	cans.units[2]["flavor"] = "Plum"
	var first_uid: String = cans.units[0]["uid"]
	game.inventory.world[source].contents.append(cans)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	actions.request_batch(source, destination)
	GameTime.set_speed(GameTime.SpeedMode.FAST)
	check.call(is_equal_approx(actions.active_action["duration"], 0.01), "transfer duration uses full kg times cm cubed divided by 100")
	actions._update_active_action(float(actions.active_action["remaining"]) / (GameTime.GAME_SECONDS_PER_REAL_SECOND * 3.0))
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	actions.interrupt_action("Test")
	check.call(cans.quantity == 2 and game.inventory.find_unit(first_uid)["owner"] == destination, "batch interruption preserves first committed unit and remainder in source")
	check.call(game.inventory.find_unit(first_uid)["unit"]["flavor"] == "Peach", "split stack retains exact identity and flavor")
	actions.request_batch(source, destination)
	actions._update_active_action(100)
	check.call(cans.quantity == 1 and game.inventory.contents(destination).size() == 2 and actions.active_action.is_empty(), "batch stops at first unit that does not fit")
	check.call(game.inventory.all_valid(), "partial batch leaves valid unique containment tree")
	var old_pack := game.inventory.equipped
	var old_uid: String = old_pack.units[0]["uid"]
	var replacement := ItemStack.new(ItemDefinition.backpack("replacement", "Replacement", Vector3(4, 4, 4), 1, 0.25))
	var replacement_uid: String = replacement.units[0]["uid"]
	game.inventory.world[source].contents.append(replacement)
	actions.request_equip(replacement_uid)
	check.call(is_equal_approx(actions.active_action["duration"], 2.0 * (old_pack.total_weight() / 100.0 + 1.0)), "unequip duration uses full backpack mass")
	actions._update_active_action(float(actions.active_action["remaining"]) / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	actions.interrupt_action("Test")
	check.call(game.inventory.equipped == null and game.inventory.find_unit(old_uid)["owner"].begins_with("dropped_"), "interrupted backpack change leaves old pack safely on ground")
	check.call(game.inventory.find_unit(old_uid)["unit"]["contents"].size() == 2, "set-down backpack retains all contents")
	actions.request_equip(replacement_uid)
	actions._update_active_action(100)
	check.call(game.inventory.equipped.units[0]["uid"] == replacement_uid and game.inventory.equipment.size() == 1, "backpack change equips exactly one replacement")
	var broken := ItemStack.new(ItemDefinition.backpack("broken", "Broken", Vector3.ONE, 1, 0.3))
	broken.units[0]["durability"] = 0
	game.inventory.world[source].contents.append(broken)
	actions.request_equip(broken.units[0]["uid"])
	check.call(actions.active_action.is_empty() and game.inventory.equipped.units[0]["uid"] == replacement_uid, "zero durability backpack cannot replace equipped pack")
	check.call(game.inventory.add_item(bottle), "bottle fits replacement backpack")
	var bottle_uid: String = bottle.units[0]["uid"]
	var pack_uid := game.inventory.default_destination()
	game.player_state.survival.thirst = 20
	actions.request_use(bottle_uid)
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	actions._update_active_action(100)
	check.call(game.inventory.find_unit(bottle_uid)["owner"] == pack_uid, "paused item action commits no step")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	actions._update_active_action(float(actions.active_action["remaining"]) / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	check.call(game.inventory.find_unit(bottle_uid)["owner"] == "right_hand" and not game.inventory.use_context["used"], "take-out step commits bottle to explicit right-hand ownership")
	actions.interrupt_action("Test")
	check.call(is_equal_approx(game.player_state.survival.thirst, 20), "interrupting before drink preserves liquid and hydration")
	actions.request_use(bottle_uid)
	var path := "/tmp/pz-backpack-%d.save" % Time.get_ticks_usec()
	check.call(QuickSave.save_game(game, path), "save captures timed use and held bottle")
	var data := QuickSave.snapshot(game)
	check.call(QuickSave.validate(data, game), "nested inventory and action snapshot validates")
	var bad := data.duplicate(true)
	bad["inventory"]["right_hand"][0]["units"][0]["uid"] = bad["inventory"]["equipment"][0]["units"][0]["uid"]
	check.call(not QuickSave.validate(bad, game), "duplicate item identity rejected before load")
	bad = data.duplicate(true)
	bad["inventory"]["right_hand"][0]["capacity"] = Vector3(0.1, 0.1, 0.1)
	check.call(not QuickSave.validate(bad, game), "overfilled nested bottle rejected before load")
	bad = data.duplicate(true)
	bad["inventory"]["right_hand"][0]["weight"] = 10000.0
	check.call(not QuickSave.validate(bad, game), "overweight save rejected before load")
	var before := game.inventory.current_weight()
	QuickSave.restore(game, bad)
	check.call(is_equal_approx(game.inventory.current_weight(), before), "invalid restore leaves valid live inventory untouched")
	check.call(QuickSave.load_game(game, path) and game.interactions.active_action.get("kind") == "pack", "load restores paused in-progress action")
	check.call(game.inventory.find_unit(old_uid)["unit"]["contents"].size() == 2
		and game.inventory.find_unit(broken.units[0]["uid"])["unit"]["durability"] == 0,
		"save/load preserves ground backpack contents and damaged backpack durability")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	game.interactions._update_active_action(float(game.interactions.active_action["remaining"]) / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	check.call(game.inventory.use_context.get("used", false) and game.inventory.find_unit(bottle_uid)["unit"]["contents"].is_empty(), "drink commits liquid consumption before return")
	game.interactions.interrupt_action("Test")
	var thirst := game.player_state.survival.thirst
	game.interactions.request_use(bottle_uid)
	game.interactions._update_active_action(100)
	check.call(is_equal_approx(thirst, game.player_state.survival.thirst) and game.inventory.find_unit(bottle_uid)["owner"] == pack_uid, "resume after drink returns same bottle without consuming twice")
	check.call(game.inventory.use_context.is_empty() and game.inventory.all_valid(), "completed use leaves no ambiguous held state")
	var food := ItemStack.new(ItemDefinition.new("partial_food", "Partial food", Vector3(4, 4, 4), 0.1, ["food"]))
	var food_uid: String = food.units[0]["uid"]
	game.inventory.loose.append(food)
	game.player_state.survival.hunger = 20
	actions.request_use(food_uid)
	actions._update_active_action(float(actions.active_action["remaining"]) / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	actions._update_active_action(2.0 / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	food = game.inventory.find_unit(food_uid)["stack"]
	actions.interrupt_action("Partial food test")
	check.call(is_equal_approx(food.total_weight(), 0.08) and is_equal_approx(game.player_state.survival.hunger, 24.8), "two game seconds consume twenty grams and proportional nutrition")
	check.call(food.unit_dimensions(food.units[0]).is_equal_approx(Vector3(4, 4, 3.2)), "longest dimension tie shrinks height first")
	check.call(is_equal_approx(food.total_volume(), 51.2), "partial independent food volume shrinks with remaining mass")
	check.call(QuickSave.save_game(game, path) and QuickSave.load_game(game, path), "partial consumption survives save/load")
	check.call(is_equal_approx(float(game.inventory.find_unit(food_uid)["unit"]["remaining"]), 0.8), "save retains exact remaining fraction and identity")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	game.player_state.survival.hunger = 99
	actions.request_use(food_uid)
	actions._update_active_action(100)
	check.call(is_equal_approx(game.player_state.survival.hunger, 100) and not game.inventory.find_unit(food_uid).is_empty(), "eating stops at satiety and preserves uneaten food")
	var invalid_pack := ItemStack.new(ItemDefinition.backpack("overweight_pack", "Too heavy", Vector3.ONE, 100, 0))
	game.inventory.world[source].contents.append(invalid_pack)
	var equipped_before: String = game.inventory.equipped.units[0]["uid"]
	var point_count := actions.points.size()
	actions.request_equip(invalid_pack.units[0]["uid"])
	check.call(actions.active_action.is_empty() and game.inventory.equipped.units[0]["uid"] == equipped_before and actions.points.size() == point_count, "invalid replacement rejects before dropping old pack or creating ground pile")
	actions.request_transfer(food_uid, source)
	check.call(not actions.active_action.is_empty(), "valid transfer starts timed action")
	var action_before := actions.active_action.duplicate(true)
	actions.request_sorting()
	check.call(actions.active_action == action_before, "UI sorting consumes no time and does not interrupt action")
	actions.interrupt_action()
	check.call(is_equal_approx(actions.pack_step_duration({"step": "move", "uid": food_uid, "destination": "ground"}) * 2,
		actions.pack_step_duration({"step": "move", "uid": food_uid, "destination": "loose"})), "ground drop takes half transfer time")
	var large_bottle_def := ItemDefinition.new("measured_bottle", "Measured bottle", Vector3(5, 5, 22), 0.2, ["water"])
	large_bottle_def.capacity_dimensions = Vector3(5, 5, 20)
	var measured_bottle := ItemStack.new(large_bottle_def)
	measured_bottle.units[0]["contents"].append(ItemStack.new(ItemDefinition.new("measured_water", "Water", Vector3(5, 5, 20), 0.5, ["water", "liquid"])))
	game.inventory.loose.append(measured_bottle)
	game.player_state.survival.thirst = 20
	actions.request_use(measured_bottle.units[0]["uid"])
	actions._update_active_action(float(actions.active_action["remaining"]) / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	actions._update_active_action(2.0 / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	measured_bottle = game.inventory.find_unit(game.inventory.use_context["uid"])["stack"]
	check.call(is_equal_approx(measured_bottle.total_weight(), 0.6) and is_equal_approx(measured_bottle.total_volume(), 550), "two seconds drink one hundred mL without shrinking bottle exterior")
	check.call(is_equal_approx(game.player_state.survival.thirst, 26.4), "partial drinking applies proportional hydration")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	game.hud.details.visible = false
	game._input(tab)
	game.hud.refresh(game)
	check.call(game.hud.details.visible and game.hud.action_row.visible and not actions.active_action.is_empty(), "Tab opens inventory without stopping timed use and HUD shows progress")
	game._input(tab)
	game.hud.refresh(game)
	check.call(not game.hud.details.visible and game.hud.action_row.visible and GameTime.speed_mode == GameTime.SpeedMode.NORMAL, "Tab hides inventory without pausing or hiding action progress")
	actions.request_transfer(food_uid, source)
	check.call(actions.active_action.get("payload", {}).get("uid") == food_uid and is_equal_approx(measured_bottle.total_weight(), 0.6), "another timed action cancels consumption while retaining partial bottle")
	actions.interrupt_action()
	DirAccess.remove_absolute(path)
	QuickSave.restore(game, baseline)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
