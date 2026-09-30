class_name ClothingTests
extends RefCounted

static func garment(id: String, slot: String, regions: Array[String], protection: Dictionary,
		durability: Dictionary, warmth: Dictionary = {}, rags: int = 1, weight: float = 1.0) -> ItemStack:
	return ItemStack.new(ItemDefinition.clothing(id, id.capitalize(), slot, regions, protection, warmth,
		durability, weight, Vector3(20, 15, 3), rags))

static func run(game: MVPGameRoot, check: Callable) -> void:
	var inv := InventoryGrid.new(false)
	inv.absolute_limit = 500
	var shirt := garment("shirt_test", "inner_top", ["Torso", "Left Arm"], {"Torso": 35, "Left Arm": 20},
		{"Torso": 30, "Left Arm": 20}, {"Torso": 120, "Left Arm": 80}, 1, 1.25)
	inv.loose.append(shirt)
	var uid: String = shirt.units[0]["uid"]
	check.call(not inv.move_unit(uid, "hat") and inv.find_unit(uid)["owner"] == "loose", "clothing rejects an incompatible wear slot atomically")
	check.call(inv.move_unit(uid, "inner_top") and is_equal_approx(inv.current_weight(), 1.25), "worn clothing remains authoritative carried weight")
	var clothing := ClothingSystem.new(inv)
	check.call(is_equal_approx(clothing.protection_percent("Torso"), 35), "regional protection aggregates worn garments")
	var shirt_unit: Dictionary = inv.find_unit(uid)["unit"]
	var before := float(shirt_unit["clothing_durability"]["Torso"])
	var failed := clothing.resolve_hit("Torso", 12, 0.9)
	check.call(not failed["protected"] and failed["player_damage"] == 12 and shirt_unit["clothing_durability"]["Torso"] == before,
		"failed protection roll passes full damage without clothing wear")
	var intermediate := clothing.resolve_hit("Torso", 3, 0.2)
	check.call(intermediate["protected"] and intermediate["player_damage"] == 0, "intermediate protection probability can deterministically succeed")
	check.call(shirt_unit["clothing_durability"]["Left Arm"] == 20, "a torso hit leaves other regional durability unchanged")
	var jacket := garment("jacket_test", "outer_top", ["Torso"], {"Torso": 80}, {"Torso": 4}, {"Torso": 40}, 2)
	inv.contents("outer_top").append(jacket)
	check.call(clothing.protection_percent("Torso") == 100, "aggregate regional protection is capped at one hundred percent")
	var protected := clothing.resolve_hit("Torso", 12, 0.0)
	check.call(protected["protected"] and is_equal_approx(protected["player_damage"], 0), "successful protection absorbs damage while durability remains")
	check.call(is_equal_approx(float(shirt_unit["clothing_durability"]["Torso"]), 19),
		"outer-to-inner two-to-one allocation reallocates exhausted outer capacity")
	check.call(protected["rag_count"] == 2 and inv.contents("outer_top").is_empty(), "zero regional durability destroys whole garment with configured rag yield")
	var weak := garment("weak_test", "outer_top", ["Torso"], {"Torso": 100}, {"Torso": 2})
	inv.contents("outer_top").append(weak)
	var pass_through := clothing.resolve_hit("Torso", 30, 0.0)
	check.call(pass_through["player_damage"] > 0 and pass_through["absorbed"] < 30, "damage exceeding all clothing durability passes through to player")
	check.call(pass_through["rag_count"] == 3, "one hit independently converts every destroyed layer to its correct rag count")
	var allocation_inv := InventoryGrid.new(false)
	allocation_inv.absolute_limit = 100
	var thin_inner := garment("thin_inner", "inner_top", ["Torso"], {"Torso": 50}, {"Torso": 1})
	var durable_outer := garment("durable_outer", "outer_top", ["Torso"], {"Torso": 50}, {"Torso": 30})
	var thin_unit: Dictionary = thin_inner.units[0]
	var durable_unit: Dictionary = durable_outer.units[0]
	allocation_inv.contents("inner_top").append(thin_inner)
	allocation_inv.contents("outer_top").append(durable_outer)
	ClothingSystem.new(allocation_inv).resolve_hit("Torso", 15, 0.0)
	check.call(thin_unit["clothing_durability"]["Torso"] == 0
		and durable_unit["clothing_durability"]["Torso"] == 16,
		"insufficient inner durability reallocates its share to the outer layer")
	var glasses := garment("glasses_test", "glasses", ["Head"], {"Head": 100}, {"Head": 10}, {"Head": 1250})
	inv.contents("glasses").append(glasses)
	check.call(clothing.protection_percent("Head") == 0, "glasses and masks never contribute hit protection")
	check.call(not clothing.resolve_hit("Head", 4, 0.0)["protected"], "zero effective protection always fails even at deterministic zero roll")
	var hat := garment("hat_test", "hat", ["Head"], {"Head": 100}, {"Head": 10})
	inv.contents("hat").append(hat)
	check.call(clothing.resolve_hit("Head", 1, 1.0)["protected"], "hat provides head protection and a hundred-percent chance always succeeds")
	check.call(clothing.warmth_by_region()["Head"] == 1250 and clothing.total_warmth() == 125,
		"warmth retains values above one hundred and averages all ten body regions")

	var baseline := QuickSave.snapshot(game)
	game.interactions.interrupt_action()
	for root in InventoryGrid.ROOTS: game.inventory.contents(root).clear()
	game.inventory.use_context = {}
	game.player.logical_position = Vector2(4.45, 6.65)
	game.player.floor_level = 0
	game.player.stair_id = ""
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	var old := garment("old_coat", "outer_top", ["Torso"], {"Torso": 40}, {"Torso": 40})
	var replacement := garment("jacket", "outer_top", ["Torso"], {"Torso": 50}, {"Torso": 50})
	game.inventory.contents("outer_top").append(old)
	game.inventory.loose.append(replacement)
	var old_uid: String = old.units[0]["uid"]
	var replacement_uid: String = replacement.units[0]["uid"]
	game.interactions.request_wear(replacement_uid)
	game.interactions._update_active_action(InteractionSystem.CLOTHING_CHANGE_GAME_SECONDS / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	game.interactions.interrupt_action()
	check.call(game.inventory.contents("outer_top").is_empty() and game.inventory.find_unit(old_uid)["owner"] == "loose"
		and game.inventory.find_unit(replacement_uid)["owner"] == "loose",
		"interrupted replacement keeps completed removal and does not commit pending wear")
	game.interactions.request_wear(replacement_uid)
	game.interactions._update_active_action(100)
	check.call(game.inventory.find_unit(replacement_uid)["owner"] == "outer_top", "timed wear commits the compatible clothing slot")
	var clothing_view := InventoryPresentation.new()
	clothing_view.sides[0]["selected"] = "worn_clothing"
	var clothing_groups := clothing_view.groups(game, 0)
	check.call(clothing_groups.size() == 1 and clothing_groups[0]["ids"] == [replacement_uid],
		"clothing inventory tab aggregates only garments currently worn by the player")
	game.world_3d_view._update_actors()
	var player_visual: Dictionary = game.world_3d_view.actor_visuals[game.player.get_instance_id()]
	var equipment_visual := player_visual["equipment_visual"] as PlayerEquipmentVisual
	check.call(equipment_visual.outer_top_root.visible and equipment_visual._shown_outer_top_uid == replacement_uid
		and equipment_visual.get_parent() == player_visual["root"],
		"outer-top visual reads the authoritative worn item and follows the player root")
	game.player._attack_flash_left = 0.1
	game.world_3d_view._update_actors()
	check.call(equipment_visual.outer_top_root.visible and (player_visual["swing"] as Node3D).visible,
		"worn jacket remains attached while the existing attack effect plays")
	game.player._attack_flash_left = 0.0
	game.inventory.move_unit(replacement_uid, "loose")
	game.world_3d_view._update_actors()
	check.call(not equipment_visual.outer_top_root.visible, "outer-top visual hides after the authoritative slot is cleared")
	game.inventory.move_unit(replacement_uid, "outer_top")
	game.world_3d_view._update_actors()
	check.call(equipment_visual.outer_top_root.visible, "outer-top visual returns after the same instance is worn again")
	game.hud.character_panel.refresh(game)
	var torso_status := game.hud.character_panel.region_data(game, "Torso")
	check.call(torso_status["protection"] == 50 and String(torso_status["worn"]).contains("Jacket"),
		"character status derives torso protection and worn clothing from authoritative slots")
	var was_visible := game.hud.character_panel.visible
	game.hud.toggle_character_panel()
	check.call(game.hud.character_panel.visible != was_visible and not game.hud.details.visible,
		"character panel opens independently and closes the inventory overlay")
	check.call(game.hud.pointer_over_page(game.hud.character_panel.get_global_rect().get_center()),
		"character page captures wheel input inside its visible bounds")
	var zoom_before := game.world_3d_view.camera_distance
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_event.pressed = true
	wheel_event.position = game.hud.character_panel.get_global_rect().get_center()
	game._unhandled_input(wheel_event)
	check.call(is_equal_approx(game.world_3d_view.camera_distance, zoom_before),
		"wheel input over character page never reaches world camera zoom")
	game.hud.toggle_character_panel()
	var needle := ItemStack.new(ItemDefinition.new("repair_needle", "Needle", Vector3.ONE, 0.01, ["needle", "tool"]))
	var thread := ItemStack.new(ItemDefinition.new("repair_thread", "Thread", Vector3.ONE, 0.02, ["thread", "tool"]))
	var rags := ItemStack.new(ClothingSystem.rag_definition(), 2)
	game.inventory.loose.append_array([needle, thread, rags])
	var replacement_unit: Dictionary = game.inventory.find_unit(replacement_uid)["unit"]
	replacement_unit["clothing_durability"]["Torso"] = 25.0
	game.interactions.request_repair(replacement_uid, "Torso")
	game.interactions._update_active_action(0.5 * InteractionSystem.CLOTHING_REPAIR_GAME_SECONDS / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	game.interactions.interrupt_action()
	check.call(rags.quantity == 2 and replacement_unit["clothing_durability"]["Torso"] == 25,
		"interrupted repair consumes nothing and changes no durability")
	game.interactions.request_repair(replacement_uid, "Torso")
	game.interactions._update_active_action(100)
	check.call(rags.quantity == 1 and replacement_unit["clothing_durability"]["Torso"] == 30
		and not game.inventory.find_unit(needle.units[0]["uid"]).is_empty() and not game.inventory.find_unit(thread.units[0]["uid"]).is_empty(),
		"sixty-second repair consumes one rag, preserves tools and restores ten percent max durability")
	replacement_unit["clothing_durability"]["Torso"] = 48.0
	game.interactions.request_repair(replacement_uid, "Torso")
	game.interactions._update_active_action(100)
	check.call(rags.quantity == 0 and replacement_unit["clothing_durability"]["Torso"] == 50
		and not game.interactions.repair_reason(replacement_uid, "Torso").is_empty(),
		"repair caps at regional maximum and rejects a fully repaired target")
	var flashlight_def := ItemDefinition.new("switch_test", "Flashlight", Vector3.ONE, 0.2, ["equipment"])
	flashlight_def.switchable = true
	var flashlight := ItemStack.new(flashlight_def)
	game.inventory.contents("right_hand").append(flashlight)
	var flashlight_uid: String = flashlight.units[0]["uid"]
	check.call(game.inventory.toggle_switchable(flashlight_uid) and flashlight.units[0]["switched_on"], "held switchable equipment stores authoritative on state")
	check.call(game.inventory.attack_type() == "shove" and game.inventory.attack_damage() == 1, "held non-weapon equipment preserves default shove")
	game.inventory.contents("right_hand").clear()
	var blade_def := ItemDefinition.new("blade_test", "Machete", Vector3(4, 1, 45), 0.9, ["weapon"])
	blade_def.weapon_attack_type = "machete swing"
	blade_def.weapon_damage = 4
	var blade := ItemStack.new(blade_def)
	game.inventory.contents("right_hand").append(blade)
	check.call(game.inventory.attack_type() == "machete swing" and game.inventory.attack_damage() == 4, "held weapon supplies minimal attack type and damage data")
	game.inventory.contents("right_hand").clear()
	game.inventory.contents("right_hand").append(flashlight)
	var saved := QuickSave.snapshot(game)
	check.call(QuickSave.validate(saved, game), "clothing durability, slots and equipment state produce a valid save")
	flashlight.units[0]["switched_on"] = false
	QuickSave.restore(game, saved)
	check.call(game.inventory.find_unit(flashlight_uid)["unit"]["switched_on"], "save/load preserves switch state and clothing instance data")
	var legacy := baseline.duplicate(true)
	legacy["version"] = 3
	for slot in InventoryGrid.CLOTHING_SLOTS: legacy["inventory"].erase(slot)
	check.call(QuickSave.validate(legacy, game), "version-three save migrates with all clothing slots empty")
	QuickSave.restore(game, baseline)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)

	var fragile := garment("fragile", "hat", ["Head"], {"Head": 100}, {"Head": 1}, {}, 1)
	game.inventory.contents("hat").append(fragile)
	var point_count := game.interactions.points.size()
	var health_before := game.player_state.health
	var hit := game.player_state.receive_hit("Test hit", "Head", 1, false, 0.0)
	var dropped_rag := false
	for point in game.interactions.points.slice(point_count):
		for stack: ItemStack in point["container"].contents:
			if stack.definition.id == "rag" and stack.definition.unit_weight == 0.05 and stack.definition.dimensions == Vector3(15, 10, 1): dropped_rag = true
	check.call(hit["player_damage"] == 0 and game.player_state.health == health_before and dropped_rag,
		"destroyed garment creates an independent rag pile at the player's feet")
	QuickSave.restore(game, baseline)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
