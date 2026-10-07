extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as MVPGameRoot
	add_child(game)
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	game.set_process(false)
	game.player.set_process(false)
	game.npc.set_process(false)
	game.zombie_spawner.set_process(false)
	for zombie in game.zombie_spawner.active_zombies: zombie.set_process(false)
	game.world_3d_view._process(0.0)
	var baseline := QuickSave.snapshot(game)
	check(QuickSave.validate(baseline, game), "New game outfits produce a valid save")
	check(game.player.appearance.gender == "male" and game.player.appearance.hair == "original", "Player keeps the male base character and original hairstyle")
	check(ClothingCatalog.SOURCES.size() == 35, "All 35 unique garments/accessories are catalogued")
	var wardrobe_ids := {}
	for stack: ItemStack in game.inventory.world["wardrobe"].contents: wardrobe_ids[stack.definition.id] = true
	for id: String in ClothingCatalog.SOURCES:
		check(wardrobe_ids.has(id), "Wardrobe contains " + id)
		var definition := ClothingCatalog.definition(id)
		check(definition.clothing_slot in InventoryGrid.CLOTHING_SLOTS, "Garment has a supported slot: " + id)
		check(definition.clothing_gender.is_empty() or String(ClothingCatalog.SOURCES[id][0]).contains("/" + definition.clothing_gender.capitalize() + "/"), "Only gender-labelled underwear is restricted: " + id)
		for kind: String in ["male", "female", "zombie"]:
			if not definition.clothing_gender.is_empty() and definition.clothing_gender != ("male" if kind == "zombie" else kind): continue
			var mesh := load(ClothingCatalog.mesh_path(id, kind)) as ArrayMesh
			check(mesh != null and mesh.get_surface_count() > 0, "Bound garment exists: " + kind + "/" + id)
			if mesh == null: continue
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var valid := weights.size() == vertices.size() * 4
				for v in vertices.size():
					valid = valid and vertices[v].is_finite() and absf(weights[v * 4] + weights[v * 4 + 1] + weights[v * 4 + 2] + weights[v * 4 + 3] - 1.0) < 0.001
				check(valid, "All garment vertices have finite positions and normalized weights: " + kind + "/" + id)
	_gender_rules()
	var player_model: MixamoCharacterVisual = game.world_3d_view.actor_visuals[game.player.get_instance_id()]["character_model"]
	check(player_model._profile.model_path == CharacterAppearance.MALE, "Player renders the new male body")
	_exercise_visual(player_model, game.inventory, "player")
	var npc_model: MixamoCharacterVisual = game.world_3d_view.actor_visuals[game.npc.get_instance_id()]["character_model"]
	check(npc_model._profile.model_path == (CharacterAppearance.MALE if game.npc.appearance.gender == "male" else CharacterAppearance.FEMALE), "NPC model follows its persisted gender")
	_exercise_visual(npc_model, game.npc.inventory, "NPC")
	var zombie := game.zombie_spawner.active_zombies[0]
	var zombie_model := MixamoCharacterVisual.new()
	add_child(zombie_model)
	zombie_model.setup(ActorBody.ZOMBIE)
	zombie_model.bind_clothing(zombie.inventory, zombie.appearance, true)
	check(zombie_model._profile.model_path.ends_with("Zombie/Zombie.fbx"), "Zombie retains its original model")
	_exercise_visual(zombie_model, zombie.inventory, "zombie")
	zombie_model.free()
	_save_and_migrate(game)
	_layers_and_hair()
	QuickSave.restore(game, baseline)
	check(QuickSave.validate(QuickSave.snapshot(game), game), "Restored baseline remains valid")
	print("WARDROBE TESTS: %d checks, %d failures" % [checks, failures.size()])
	game.free()
	get_tree().quit(0 if failures.is_empty() else 1)

func _gender_rules() -> void:
	var inventory := InventoryGrid.new()
	var clothes := ClothingSystem.new(inventory)
	var male := ItemStack.new(ClothingCatalog.definition("male_boxers"))
	var female := ItemStack.new(ClothingCatalog.definition("female_boyshorts"))
	var male_uid: String = male.units[0]["uid"]
	var female_uid: String = female.units[0]["uid"]
	inventory.loose.append_array([male, female])
	check(clothes.wear(male_uid), "Male underwear can be worn by male characters")
	check(not clothes.wear(female_uid) and inventory.contents("underwear_bottom")[0].units[0]["uid"] == male_uid, "Rejected underwear replacement keeps the old item equipped")
	check(clothes.remove("underwear_bottom"), "Underwear can be removed into inventory")
	inventory.wearer_gender = "female"
	check(clothes.wear(female_uid), "Female underwear can be worn by female characters")
	check(not inventory.move_unit(male_uid, "underwear_bottom"), "Direct inventory moves cannot bypass underwear restrictions")
	for id: String in ["casual_jeans", "underwear_tshirt", "ranger_shirt"]:
		var garment := ItemStack.new(ClothingCatalog.definition(id))
		inventory.loose.append(garment)
		check(clothes.wear(garment.units[0]["uid"]), "Unisex garment fits female character: " + id)
	check(inventory.all_valid(), "Layered female outfit preserves inventory invariants")

func _exercise_visual(model: MixamoCharacterVisual, inventory: InventoryGrid, label: String) -> void:
	var clothes := ClothingSystem.new(inventory)
	var item := ItemStack.new(ClothingCatalog.definition("medical_mask"))
	inventory.loose.append(item)
	check(clothes.wear(item.units[0]["uid"]), label + " can equip a garment")
	model.clothing_visual.refresh()
	var visible_mesh: MeshInstance3D = model.clothing_visual.garments["mask"]
	check(visible_mesh.get_node(visible_mesh.skeleton) == model.skeleton and visible_mesh.visible, label + " clothing uses the animated body skeleton")
	var mesh_id := visible_mesh.get_instance_id()
	inventory.revision += 1
	model.clothing_visual.refresh()
	check(model.clothing_visual.garments["mask"].get_instance_id() == mesh_id, label + " unrelated inventory changes reuse the existing mesh")
	model.advance_animation(0.4, "walk")
	check(clothes.remove("mask"), label + " can remove a garment")
	model.clothing_visual.refresh()
	check(not model.clothing_visual.garments.has("mask"), label + " removal immediately removes the 3D garment")

func _save_and_migrate(game: MVPGameRoot) -> void:
	game.npc.appearance.hair = "Hair_Buns"
	var snapshot := QuickSave.snapshot(game)
	check(QuickSave.validate(snapshot, game), "Changed outfits and hairstyle validate before saving")
	game.npc.appearance.hair = "original"
	for slot: String in InventoryGrid.CLOTHING_SLOTS: game.npc.inventory.contents(slot).clear()
	game.npc.inventory.revision += 1
	QuickSave.restore(game, snapshot)
	check(game.npc.appearance.hair == "Hair_Buns", "Loading preserves NPC hairstyle")
	check(QuickSave.snapshot(game)["npc"]["wardrobe"] == snapshot["npc"]["wardrobe"], "Loading preserves exact NPC clothing instances and slots")
	check(QuickSave.snapshot(game)["zombies"][0]["wardrobe"] == snapshot["zombies"][0]["wardrobe"], "Loading preserves zombie clothing instances and slots")
	var invalid := snapshot.duplicate(true)
	invalid["npc"]["appearance"]["hair"] = "not_a_resource"
	check(not QuickSave.validate(invalid, game), "Corrupt appearance is rejected before live state changes")
	var legacy := snapshot.duplicate(true)
	legacy["version"] = 12
	legacy["player"].erase("appearance")
	legacy["npc"].erase("appearance")
	legacy["npc"].erase("wardrobe")
	for entry in legacy["zombies"]:
		entry.erase("appearance")
		entry.erase("wardrobe")
	for slot: String in ["underwear_top", "underwear_bottom", "socks", "belt", "neck", "badge", "medical_support"]: legacy["inventory"].erase(slot)
	var preserved := legacy.duplicate(true)
	check(QuickSave.validate(legacy, game), "Version-12 save migrates to clothing-aware actors")
	check(legacy == preserved, "Migration leaves the original save data untouched")
	legacy["inventory"].erase("loose")
	check(not QuickSave.validate(legacy, game), "Migration rejects missing historical inventory instead of inventing empty data")

func _layers_and_hair() -> void:
	var appearance := CharacterAppearance.new()
	appearance.gender = "female"
	appearance.hair = "Hair_Buns"
	var inventory := InventoryGrid.new()
	inventory.wearer_gender = "female"
	var clothes := ClothingSystem.new(inventory)
	var model := MixamoCharacterVisual.new()
	add_child(model)
	model.setup(appearance.model_profile())
	model.bind_clothing(inventory, appearance)
	for id: String in ["female_tubebra", "underwear_tshirt", "medical_shirt", "medical_cap"]:
		var item := ItemStack.new(ClothingCatalog.definition(id))
		inventory.loose.append(item)
		clothes.wear(item.units[0]["uid"])
	model.clothing_visual.refresh()
	var visual := model.clothing_visual
	check(not visual.garments["underwear_top"].visible and not visual.garments["inner_top"].visible and visual.garments["outer_top"].visible, "Outer clothing visually covers inner layers without removing their inventory items")
	check(not visual.hair_meshes.is_empty() and not visual.hair_meshes[0].visible, "Hat hides the selected hairstyle")
	clothes.remove("hat")
	clothes.remove("outer_top")
	visual.refresh()
	check(visual.hair_meshes[0].visible and visual.garments["inner_top"].visible, "Removing hat and outer clothing restores hair and the inner shirt")
	for slot: String in InventoryGrid.CLOTHING_SLOTS: clothes.remove(slot)
	visual.refresh()
	var original := true
	for i in model.meshes.size(): original = original and model.meshes[i].mesh == visual._originals[i]
	check(original and visual.garments.is_empty(), "Removing every garment restores the complete original body meshes")
	model.free()
