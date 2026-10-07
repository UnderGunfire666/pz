class_name ItemCatalog
extends RefCounted

## Static content catalogue. A single definition is shared by all physical units;
## freshness, temperature, opening state and appearance belong to ItemStack units.

static func food(id: String, title: String, weight: float, hunger: float, calories: float,
		fresh_days: float = 0.0, tags: Array[String] = ["food"], happiness: float = 0.0) -> ItemDefinition:
	var item := ItemDefinition.new(id, title, Vector3(2, 2, 2), weight, tags)
	item.hunger_restore = hunger
	item.calories = calories
	item.happiness_effect = happiness
	item.freshness_lifetime_days = fresh_days
	return item

static func food_definitions() -> Dictionary:
	var items := {}
	# Fresh food: meat/fish use the agreed 2-day baseline; produce uses 5 days.
	items["egg"] = food("egg", "Egg", 0.05, 6, 72, 10.0)
	items["milk"] = food("milk", "Milk", 0.25, 8, 122, 5.0, ["food", "water"])
	items["chicken"] = food("chicken", "Chicken breast (100 g)", 0.10, 13, 120, 2.0)
	items["beef"] = food("beef", "Ground beef (100 g)", 0.10, 16, 254, 2.0)
	items["cod"] = food("cod", "Cod (100 g)", 0.10, 9, 82, 2.0)
	items["apple"] = food("apple", "Apple", 0.18, 10, 95, 5.0)
	items["berries"] = food("berries", "Berries", 0.15, 8, 72, 5.0)
	items["carrot"] = food("carrot", "Carrot", 0.06, 4, 25, 5.0)
	items["potato"] = food("potato", "Potato", 0.17, 10, 130, 5.0)
	items["cabbage"] = food("cabbage", "Cabbage portion", 0.09, 4, 22, 5.0)
	items["tomato"] = food("tomato", "Tomato", 0.12, 4, 22, 5.0)
	for id in ["egg", "chicken", "beef", "cod"]:
		items[id].consumption_rate_per_game_minute = 60.0
	for id in ["apple", "berries", "carrot", "potato", "cabbage", "tomato"]:
		items[id].consumption_rate_per_game_minute = 150.0
	items["milk"].consumption_rate_per_game_minute = 100.0
	for id in ["egg", "chicken", "beef", "cod", "potato", "apple", "berries", "carrot", "cabbage", "tomato"]:
		items[id].cooking_state_supported = true
	# Cans are stable until opened, then use the agreed 30-day reference life.
	var can_specs := [["canned_beans", "Canned beans", 0.42, 22, 350], ["canned_corn", "Canned corn", 0.40, 16, 190],
		["canned_tuna", "Canned tuna", 0.18, 14, 132], ["canned_sardines", "Canned sardines", 0.18, 15, 208],
		["canned_tomato", "Canned tomatoes", 0.40, 8, 80], ["canned_vegetable_soup", "Canned vegetable soup", 0.42, 12, 140],
		["canned_fruit_cocktail", "Canned fruit cocktail", 0.42, 14, 180]]
	for spec in can_specs:
		var canned: ItemDefinition = food(spec[0], spec[1], float(spec[2]), float(spec[3]), float(spec[4]), 30.0, ["food", "canned", "openable"])
		canned.requires_opening = true
		canned.cooking_state_supported = true
		canned.consumption_rate_per_game_minute = 120.0
		items[canned.id] = canned
	var ration := food("emergency_ration", "Emergency ration", 0.25, 30, 1200, 30.0, ["food", "ration", "openable"])
	ration.requires_opening = true
	ration.cooking_state_supported = true
	ration.default_cooking_state = "cooked"
	ration.consumption_rate_per_game_minute = 90.0
	items[ration.id] = ration
	for spec in [["chips", "Chips", 0.15, 18, 800, 10], ["biscuits", "Biscuits", 0.18, 16, 520, 8], ["granola_bar", "Granola bar", 0.04, 9, 190, 7], ["chocolate", "Chocolate bar", 0.10, 12, 535, 12]]:
		var snack := food(spec[0], spec[1], float(spec[2]), float(spec[3]), float(spec[4]), 30.0, ["food", "snack", "openable"], float(spec[5]))
		snack.requires_opening = true
		snack.consumption_rate_per_game_minute = 80.0
		items[snack.id] = snack
	var ice_cream := food("ice_cream", "Ice cream", 0.10, 10, 210, 5.0, ["food", "dessert"], 12)
	ice_cream.edible_frozen = true
	ice_cream.consumption_rate_per_game_minute = 70.0
	items[ice_cream.id] = ice_cream
	var ice_pop := food("ice_pop", "Ice pop", 0.08, 5, 90, 5.0, ["food", "dessert"], 8)
	ice_pop.edible_frozen = true
	ice_pop.consumption_rate_per_game_minute = 60.0
	items[ice_pop.id] = ice_pop
	return items

static func water_container(id: String, title: String, capacity_ml: float, weight: float, empty_id: String) -> ItemDefinition:
	var item := ItemDefinition.new(id, title, Vector3(2, 2, 5), weight, ["water", "container"])
	item.capacity_dimensions = Vector3(2, 2, 4)
	item.liquid_capacity_ml = capacity_ml
	item.empty_container_id = empty_id
	item.thirst_restore = capacity_ml * 0.032
	return item

static func liquid_definitions() -> Dictionary:
	var items := {}
	items["canned_water"] = water_container("canned_water", "Canned water", 355, 0.03, "empty_can")
	items["bottled_water"] = water_container("bottled_water", "Bottled water", 500, 0.02, "empty_bottle")
	var juice := water_container("juice", "Juice box", 250, 0.01, "empty_juice_box")
	juice.freshness_lifetime_days = 7.0
	juice.requires_opening = true
	juice.happiness_effect = 4.0
	items["juice"] = juice
	for spec in [["empty_can", "Empty can", 0.03], ["empty_bottle", "Empty bottle", 0.02], ["empty_juice_box", "Empty juice box", 0.01]]:
		var empty := ItemDefinition.new(spec[0], spec[1], Vector3(2, 2, 5), float(spec[2]), ["container"])
		if spec[0] != "empty_juice_box":
			empty.capacity_dimensions = Vector3(2, 2, 4)
			empty.liquid_capacity_ml = 355 if spec[0] == "empty_can" else 500
		items[empty.id] = empty
	return items

static func medical_definitions() -> Dictionary:
	var items := {}
	for spec in [["bandage", "Bandage", "bandage"], ["adhesive_bandage", "Adhesive bandage", "bandage"], ["disinfectant", "Disinfectant", "disinfectant"], ["alcohol_wipes", "Alcohol wipes", "disinfectant"], ["antibiotics", "Antibiotics", "antibiotic"], ["painkillers", "Painkillers", "painkiller"], ["splint", "Splint", "splint"], ["burn_dressing", "Burn dressing", "burn_dressing"], ["antidepressants", "Antidepressants", "antidepressant"], ["beta_blockers", "Beta blockers", "beta_blocker"], ["caffeine_pills", "Caffeine pills", "caffeine"], ["sleeping_pills", "Sleeping pills", "sleeping_pill"], ["tweezers", "Tweezers", "remove_glass"], ["forceps", "Hemostatic forceps", "remove_bullet"], ["suture_needle", "Suture needle", "suture"], ["suture_needle_holder", "Suture needle holder", ""], ["vitamins", "Vitamins", ""]]:
		var item := ItemDefinition.new(spec[0], spec[1], Vector3(1, 1, 1), 0.05, ["medical"])
		item.medical_action = spec[2]
		if spec[0] in ["bandage", "adhesive_bandage"]: item.tags.append("bandage")
		if spec[0] in ["tweezers", "forceps", "suture_needle"]: item.tags.append("tool")
		items[item.id] = item
	return items

static func tool_definitions() -> Dictionary:
	var opener := ItemDefinition.new("can_opener", "Can opener", Vector3(2, 1, 8), 0.12, ["tool", "can_opener"])
	var knife := ItemDefinition.new("knife", "Knife", Vector3(2, 1, 22), 0.18, ["tool", "knife", "weapon"])
	knife.weapon_attack_type = "stab"
	knife.weapon_damage = 1
	return {opener.id: opener, knife.id: knife}

static func backpack_definitions() -> Dictionary:
	# One definition per gameplay-identical bag. Colour, agency and travel variants
	# are physical-unit appearance values, rather than duplicate item definitions.
	var specs := [["big_hiking_backpack", "Big hiking backpack", Vector3(38, 24, 60), 2.2, 0.30],
		["cloth_gun_case", "Cloth gun case", Vector3(15, 12, 55), 1.0, 0.12], ["duffel_bag", "Duffel bag", Vector3(34, 18, 36), 1.1, 0.15],
		["fishing_basket", "Fishing basket", Vector3(22, 17, 25), 1.5, 0.10], ["simple_framepack", "Simple framepack", Vector3(32, 20, 48), 2.0, 0.20],
		["framepack", "Framepack", Vector3(38, 24, 60), 3.0, 0.25], ["large_framepack", "Large framepack", Vector3(42, 27, 66), 4.0, 0.22],
		["golf_bag", "Golf bag", Vector3(18, 16, 80), 1.2, 0.15], ["hide_sling_bag", "Hide sling bag", Vector3(24, 15, 32), 0.8, 0.12],
		["hiking_backpack", "Hiking backpack", Vector3(32, 20, 48), 1.2, 0.20], ["hydration_pack", "Hydration pack", Vector3(24, 16, 35), 1.0, 0.12],
		["military_backpack", "Military backpack", Vector3(40, 25, 62), 2.0, 0.32], ["sheet_sling_bag", "Sheet sling bag", Vector3(20, 15, 30), 0.8, 0.10],
		["small_backpack", "Small backpack", Vector3(25, 16, 38), 1.0, 0.14], ["small_leather_backpack", "Small leather backpack", Vector3(24, 16, 35), 1.0, 0.13],
		["small_simple_framepack", "Small simple framepack", Vector3(25, 17, 38), 1.5, 0.14], ["small_tarp_backpack", "Small tarp backpack", Vector3(24, 16, 35), 1.0, 0.12],
		["tarp_sling_bag", "Tarp sling bag", Vector3(22, 15, 32), 0.8, 0.11], ["trauma_bag", "Trauma bag", Vector3(34, 18, 36), 1.0, 0.15]]
	var appearances := {"big_hiking_backpack": ["standard", "travel"], "cloth_gun_case": ["rifle", "shotgun", "camo"],
		"duffel_bag": ["standard", "tinted", "baseball", "burglar", "food canned", "food snacks", "inmate", "money", "police", "sheriff", "swat", "tool", "weapon"],
		"hiking_backpack": ["standard", "travel"], "hydration_pack": ["standard", "camo"], "military_backpack": ["standard", "army", "desert camo", "survivor"],
		"small_backpack": ["standard", "kids", "medical", "patched", "travel"], "small_simple_framepack": ["simple", "tarp"]}
	var items := {}
	for spec in specs:
		var pack := ItemDefinition.backpack(spec[0], spec[1], spec[2], float(spec[3]), float(spec[4]))
		var variants: Array[String] = []
		variants.assign(appearances.get(spec[0], ["default"]))
		pack.appearance_variants = variants
		items[pack.id] = pack
	return items
