class_name InventoryUpgradeTests
extends RefCounted

static func run(game: MVPGameRoot, check: Callable) -> void:
	var inv := InventoryGrid.new(false, 10)
	inv.absolute_limit = 200
	check.call(is_equal_approx(inv.hand_cap(), 37.5) and is_equal_approx(inv.hand_cap(true), 75), "Strength ten gives capped fifty percent hand bonus")
	check.call(is_equal_approx(InventoryGrid.new(false, 99).hand_cap(), 37.5), "Strength bonus cannot exceed fifty percent")
	var small := ItemStack.new(ItemDefinition.new("small", "Small", Vector3(5, 5, 99), 1))
	var uid: String = small.units[0]["uid"]
	inv.loose.append(small)
	check.call(inv.one_handed(small) and inv.pickup_plan(uid)[-1]["destination"] == "right_hand", "one-hand inclusive width and exclusive height boundary prefers right")
	check.call(inv.move_unit(uid, "right_hand"), "first pickup enters right hand")
	var second := ItemStack.new(ItemDefinition.new("second", "Second", Vector3.ONE, 1))
	var second_uid: String = second.units[0]["uid"]
	inv.loose.append(second)
	check.call(inv.pickup_plan(second_uid)[-1]["destination"] == "left_hand", "occupied right hand selects free left hand")
	inv.move_unit(second_uid, "left_hand")
	check.call(not inv.has_free_hand(), "two one-hand items block free-hand operations")
	var tall := ItemStack.new(ItemDefinition.new("tall", "Tall", Vector3(5, 5, 100), 1))
	inv.loose.append(tall)
	var plan := inv.pickup_plan(tall.units[0]["uid"])
	check.call(plan.size() == 3 and plan[-1]["destination"] == "two_hands", "height one hundred requires both hands and plans both drops")
	check.call(inv.contents("right_hand").size() == 1 and inv.contents("left_hand").size() == 1, "pickup preview never mutates held items")
	var dense := ItemStack.new(ItemDefinition.new("dense", "Dense", Vector3.ONE, 40))
	check.call(not inv.one_handed(dense), "small item exceeding one-hand weight needs both hands")
	dense.definition.requires_two_hands = true
	dense.definition.unit_weight = 1
	check.call(not inv.one_handed(dense), "explicit two-hand flag overrides small dimensions")
	var container := ContainerData.new("cabinet", "Cabinet")
	container.capacity = 250000
	inv.world[container.id] = container
	var huge := ItemStack.new(ItemDefinition.new("huge", "Huge", Vector3(100, 100, 100), 1))
	inv.loose.append(huge)
	check.call(not inv.move_unit(huge.units[0]["uid"], "cabinet") and container.contents.is_empty(), "fixed cabinet capacity rejects oversize atomically")
	var baseline := QuickSave.snapshot(game)
	var actions := game.interactions
	actions.interrupt_action()
	for root in InventoryGrid.ROOTS: game.inventory.contents(root).clear()
	game.inventory.use_context = {}
	game.player.logical_position = Vector2(3.1, 3.0)
	game.inventory.world["test_cabinet_0"].is_open = true
	game.inventory.world["test_cabinet_1"].is_open = true
	game.player.floor_level = 0
	game.player.stair_id = ""
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	var nearby := actions.nearby_containers()
	var nearby_ids: Array = []
	for point in nearby: nearby_ids.append(point["id"])
	check.call("test_cabinet_0" in nearby_ids and "test_cabinet_1" in nearby_ids, "near and farther clear cabinets are visible within common circular radius")
	check.call(not "test_cabinet_2" in nearby_ids and not "test_cabinet_3" in nearby_ids, "wall-blocked and out-of-radius cabinets are excluded")
	check.call(nearby_ids.find("test_cabinet_0") < nearby_ids.find("test_cabinet_1"), "cabinet sources ordered nearest first")
	for index in range(4):
		check.call(is_equal_approx(game.inventory.world["test_cabinet_%d" % index].capacity, 250000), "whitebox cabinet %d uses shared fixed capacity" % index)
	var model := InventoryPresentation.new()
	check.call(model.sides[0]["selected"] == "all_carried" and model.containers(game, 0)[0]["id"] == "all_carried", "All carried is the first and default player container tab")
	var player_tabs := model.containers(game, 0)
	var player_tab_ids: Array = player_tabs.map(func(entry: Dictionary) -> String: return entry["id"])
	check.call(game.inventory.equipped == null and not "equipped" in player_tab_ids,
		"new player has no backpack and therefore no backpack container tab")
	check.call("worn_clothing" in player_tab_ids and not player_tab_ids.any(
		func(id: String) -> bool: return id in InventoryGrid.CLOTHING_SLOTS),
		"player inventory exposes one clothing aggregate without body-part container tabs")
	var ui_pack := ItemStack.new(ItemDefinition.backpack("ui_pack", "UI test backpack", Vector3(2, 2, 2), 0.5, 0.1))
	game.inventory.equipment.append(ui_pack)
	check.call(model.containers(game, 0).any(func(entry: Dictionary) -> bool: return entry["id"] == "equipped"),
		"backpack container tab appears after a backpack is equipped")
	model.sides[0]["selected"] = "worn_clothing"
	var equipped_groups := model.groups(game, 0)
	check.call(equipped_groups.size() == 1 and equipped_groups[0]["ids"] == [ui_pack.units[0]["uid"]],
		"clothing tab includes the currently equipped backpack for interaction")
	model.sides[0]["selected"] = model.container_tab_for(game, ui_pack.units[0]["uid"])
	var equipped_tabs := model.containers(game, 0)
	check.call(model.sides[0]["selected"] == "equipped" and equipped_tabs.filter(
		func(entry: Dictionary) -> bool: return entry["id"] == "equipped").size() == 1,
		"opening the equipped backpack selects its existing tab without creating another")
	game.inventory.equipment.clear()
	check.call(not model.containers(game, 0).any(func(entry: Dictionary) -> bool: return entry["id"] == "equipped"),
		"backpack container tab disappears after the backpack is unequipped")
	model.sides[1]["selected"] = "nearby_all"
	var groups := model.groups(game, 1)
	var snacks: Dictionary = {}
	for group in groups:
		if group["name"] == "Trail snack": snacks = group
	check.call(snacks.get("ids", []).size() == 6, "Nearby All merges matching types and different flavors across cabinets")
	var transfer_ids: Array = snacks["transfer_ids"]
	check.call(game.inventory.find_unit(transfer_ids[0])["owner"] == "test_cabinet_0" and game.inventory.find_unit(transfer_ids[3])["owner"] == "test_cabinet_1", "aggregate transfer resolves each real source in container list order")
	var weight_before := game.inventory.current_weight()
	model.split(1, snacks["ids"], 2)
	var sizes: Array = []
	for group in model.groups(game, 1):
		if group["name"] == "Trail snack": sizes.append(group["ids"].size())
	sizes.sort()
	check.call(sizes == [2, 4] and is_equal_approx(weight_before, game.inventory.current_weight()), "UI stack splitting changes groups without changing ownership or weight")
	model.sides[0]["sort"] = "weight"
	model.sides[0]["descending"] = false
	model.sides[1]["expanded"]["cabinet_snack:"] = true
	var pref_path := OS.get_temp_dir().path_join("pz-ui-%d.cfg" % Time.get_ticks_usec())
	check.call(model.save_preferences(pref_path) == OK, "UI preference file saves")
	var loaded := InventoryPresentation.new()
	loaded.load_preferences(pref_path)
	check.call(loaded.sides == model.sides, "both selections independent sort expansion and split preferences survive restart")
	DirAccess.remove_absolute(pref_path)
	model.sides[1]["selected"] = "test_cabinet_3"
	model.containers(game, 1)
	check.call(model.sides[1]["selected"] == "ground", "unreachable selected cabinet falls back to Ground")
	check.call(model.containers(game, 0).size() == 3, "empty hands and no backpack leave All, Carried, and Clothing tabs only")
	game.hud.pack_panel.presentation.sides[1]["selected"] = "test_cabinet_0"
	game.hud.pack_panel.last_signature = ""
	game.hud.pack_panel.refresh(game)
	game.hud.details.show()
	var inventory_center := game.hud.details.get_global_rect().get_center()
	check.call(game.hud.pointer_over_page(inventory_center), "inventory page captures wheel input inside its visible bounds")
	var zoom_before := game.world_3d_view.camera.fov
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_event.pressed = true
	wheel_event.position = inventory_center
	game._unhandled_input(wheel_event)
	check.call(is_equal_approx(game.world_3d_view.camera.fov, zoom_before),
		"wheel input over inventory page never reaches world camera zoom")
	game.hud.details.hide()
	var hammer_row: TreeItem = null
	var snack_row: TreeItem = null
	for row in game.hud.pack_panel.trees[1].get_root().get_children():
		if row.get_text(0) == "Hammer": hammer_row = row
		if row.get_text(0) == "Trail snack": snack_row = row
	check.call(hammer_row != null and hammer_row.get_first_child() == null, "single item is a leaf row without an acquisition-time dropdown")
	check.call(snack_row != null and snack_row.get_first_child() != null, "only a true stack exposes expandable individual rows")
	check.call(game.hud.pack_panel.tab_bars[1].get_child_count() == model.containers(game, 1).size(), "right-side container labels replace the container dropdown")
	var cabinet: ContainerData = game.inventory.world["test_cabinet_0"]
	var snack_uid: String = cabinet.contents[0].units[0]["uid"]
	game.player_state.survival.hunger = 99
	actions.request_use(snack_uid)
	check.call(game.inventory.find_unit(snack_uid)["owner"] == cabinet.id, "furniture food stays at source until timed pickup commits")
	actions._update_active_action(100)
	check.call(game.inventory.find_unit(snack_uid)["owner"] == "right_hand" and game.inventory.use_context.is_empty(), "furniture food is partially eaten and surviving item stays held")
	check.call(is_equal_approx(game.player_state.survival.hunger, 100), "furniture eating stops at satisfied hunger")
	var hammer_uid: String = cabinet.contents[1].units[0]["uid"]
	actions.request_pickup(hammer_uid)
	actions._update_active_action(100)
	check.call(game.inventory.find_unit(hammer_uid)["owner"] == "left_hand" and game.inventory.held_weapon() != null, "second pickup fills left hand and selects weapon attack")
	var plank_uid := ""
	for stack: ItemStack in cabinet.contents:
		if stack.definition.id == "cabinet_plank": plank_uid = stack.units[0]["uid"]
	check.call(not plank_uid.is_empty(), "cabinet retains long two-hand test item after other pickups")
	var too_heavy := ItemStack.new(ItemDefinition.new("overweight_test", "Overweight", Vector3(5, 5, 10), 31))
	cabinet.contents.append(too_heavy)
	var point_count := actions.points.size()
	actions.request_pickup(too_heavy.units[0]["uid"])
	check.call(actions.active_action.is_empty() and actions.points.size() == point_count and game.inventory.find_unit(hammer_uid)["owner"] == "left_hand", "hard carry rejection occurs before displaced item drops")
	var over_hand := ItemStack.new(ItemDefinition.new("overhand_test", "Over hand", Vector3.ONE, 51))
	cabinet.contents.append(over_hand)
	actions.request_pickup(over_hand.units[0]["uid"])
	check.call(actions.active_action.is_empty() and actions.points.size() == point_count, "hand cap rejects overweight pickup without side effects")
	actions.request_transfer(plank_uid, "loose")
	check.call(actions.active_action.is_empty(), "both occupied hands block container transfers")
	actions.request_pickup(plank_uid)
	var first_drop: String = actions.active_action["payload"]["uid"]
	actions._update_active_action(float(actions.active_action["remaining"]) / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	actions.interrupt_action()
	check.call(game.inventory.find_unit(first_drop)["owner"].begins_with("dropped_") and game.inventory.find_unit(plank_uid)["owner"] == cabinet.id, "interrupted displacement preserves completed ground drop and new item source")
	actions.request_pickup(plank_uid)
	actions._update_active_action(100)
	check.call(game.inventory.find_unit(plank_uid)["owner"] == "two_hands" and not game.inventory.has_free_hand(), "two-hand pickup occupies both hands exclusively")
	check.call(game.inventory.held_weapon() == null, "ordinary two-hand item leaves default shove available")
	var path := OS.get_temp_dir().path_join("pz-hands-%d.save" % Time.get_ticks_usec())
	check.call(QuickSave.save_game(game, path) and QuickSave.load_game(game, path), "save/load preserves hand slots and cabinet contents")
	check.call(game.inventory.find_unit(plank_uid)["owner"] == "two_hands" and game.inventory.all_valid(), "restored hand inventory satisfies global identities and limits")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	actions.request_units([plank_uid], "ground", false)
	check.call(not actions.active_action.is_empty(), "dropping held item is allowed without a free hand")
	actions._update_active_action(100)
	check.call(game.inventory.has_free_hand() and game.inventory.find_unit(plank_uid)["owner"].begins_with("dropped_"), "held item drop restores free hands")
	DirAccess.remove_absolute(path)
	QuickSave.restore(game, baseline)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
