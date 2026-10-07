class_name InventoryGrid
extends RefCounted

## Legacy class name retained for callers; capacity is exclusively volume based.
var loose: Array[ItemStack] = []
var equipment: Array[ItemStack] = []
const HANDS := ["left_hand", "right_hand", "two_hands"]
const CLOTHING_SLOTS := ["inner_top", "outer_top", "inner_bottom", "outer_bottom", "hat", "glasses", "mask", "shoes", "gloves", "underwear_top", "underwear_bottom", "socks", "belt", "neck", "badge", "medical_support"]
const BODY_REGIONS := ["Head", "Torso", "Left Arm", "Right Arm", "Left Hand", "Right Hand", "Left Leg", "Right Leg", "Left Foot", "Right Foot"]
const ROOTS := ["loose", "equipment", "left_hand", "right_hand", "two_hands",
	"inner_top", "outer_top", "inner_bottom", "outer_bottom", "hat", "glasses", "mask", "shoes", "gloves", "underwear_top", "underwear_bottom", "socks", "belt", "neck", "badge", "medical_support"]
var hands := {"left_hand": [], "right_hand": [], "two_hands": []}
var clothing := {"inner_top": [], "outer_top": [], "inner_bottom": [], "outer_bottom": [],
	"hat": [], "glasses": [], "mask": [], "shoes": [], "gloves": [],
	"underwear_top": [], "underwear_bottom": [], "socks": [], "belt": [], "neck": [], "badge": [], "medical_support": []}
var wearer_gender := "male"
var strength := 0
var world: Dictionary = {}
var penalty_limit := 12.0
var absolute_limit := 30.0
var use_context: Dictionary = {}
var last_error := ""
var revision := 0
var _item_state_accumulator := 0.0
var equipped: ItemStack:
	get: return equipment[0] if not equipment.is_empty() else null

func _init(starter_pack: bool = false, creation_strength: int = 0) -> void:
	strength = maxi(0, creation_strength)
	if starter_pack:
		equipment.append(ItemStack.new(ItemCatalog.backpack_definitions()["small_backpack"]))

func current_weight() -> float:
	var weight := 0.0
	for root in ROOTS:
		for stack: ItemStack in contents(root): weight += effective_weight(stack)
	return weight

## Physical mass never includes reduction. Only this inventory's equipped slot
## changes effective carried weight; nested containers always retain full mass.
func effective_weight(stack: ItemStack) -> float:
	var weight := stack.total_weight()
	if equipped != null and stack.quantity == 1 and stack.units[0]["uid"] == equipped.units[0]["uid"]:
		weight = stack.definition.unit_weight + (weight - stack.definition.unit_weight) * (1.0 - stack.definition.weight_reduction)
	return weight

## Validate a sequence on detached inventory data before committing its first step.
## In particular, a failed backpack replacement must not displace the old pack.
func preview_moves(moves: Array) -> bool:
	var trial := InventoryGrid.new(false)
	trial.absolute_limit = absolute_limit
	trial.strength = strength
	trial.wearer_gender = wearer_gender
	for root in ROOTS:
		for stack: ItemStack in contents(root): trial.contents(root).append(InventoryCodec.unpack(InventoryCodec.pack(stack)))
	for id in world:
		var container := ContainerData.new(id, world[id].display_name)
		container.capacity = world[id].capacity
		for stack: ItemStack in world[id].contents:
			container.contents.append(InventoryCodec.unpack(InventoryCodec.pack(stack)))
		trial.world[id] = container
	trial.world["preview_ground"] = ContainerData.new("preview_ground", "Ground")
	for move: Dictionary in moves:
		var destination: String = move["destination"]
		if destination == "ground": destination = "preview_ground"
		if not trial.move_unit(move["uid"], destination):
			last_error = trial.last_error
			return false
	last_error = ""
	return true

func encumbrance() -> float:
	return maxf(0.0, current_weight() - penalty_limit) / maxf(1.0, absolute_limit - penalty_limit)

func default_destination() -> String:
	return equipped.units[0]["uid"] if equipped != null else "loose"

func contents(id: String) -> Array:
	if id == "loose": return loose
	if id == "equipment": return equipment
	if hands.has(id): return hands[id]
	if clothing.has(id): return clothing[id]
	if world.has(id): return world[id].contents
	var found := find_unit(id)
	if not found.is_empty() and found["stack"].definition.capacity() > 0:
		return found["unit"]["contents"]
	return []

func has_container(id: String) -> bool:
	if id in ROOTS or world.has(id): return true
	var found := find_unit(id)
	return not found.is_empty() and found["stack"].definition.capacity() > 0

func find_unit(uid: String) -> Dictionary:
	for id in ROOTS:
		var found := _find(contents(id), uid, id)
		if not found.is_empty(): return found
	for id in world:
		var found := _find(world[id].contents, uid, id)
		if not found.is_empty(): return found
	return {}

func _find(items: Array, uid: String, owner: String) -> Dictionary:
	for stack: ItemStack in items:
		for unit in stack.units:
			if unit["uid"] == uid:
				return {"stack": stack, "unit": unit, "owner": owner}
			var found := _find(unit["contents"], uid, unit["uid"])
			if not found.is_empty(): return found
	return {}

func carried(uid: String) -> bool:
	for root in ROOTS:
		if not _find(contents(root), uid, root).is_empty(): return true
	return false

func has_free_hand() -> bool:
	return hands["two_hands"].is_empty() and (hands["left_hand"].is_empty() or hands["right_hand"].is_empty())

func hand_cap(two: bool = false) -> float:
	return (50.0 if two else 25.0) * (1.0 + minf(0.5, strength * 0.05))

func one_handed(stack: ItemStack) -> bool:
	var size := stack.unit_dimensions(stack.units[0])
	return size.x <= 5 and size.y <= 5 and size.z < 100 and not stack.definition.requires_two_hands and stack.total_weight() <= hand_cap()

func hands_error() -> String:
	if not hands["two_hands"].is_empty() and (not hands["left_hand"].is_empty() or not hands["right_hand"].is_empty()): return "Both hands are occupied."
	for slot in HANDS:
		var items: Array = hands[slot]
		if items.size() > 1: return "Hand slot already occupied."
		if items.is_empty(): continue
		var stack: ItemStack = items[0]
		if stack.quantity != 1: return "A hand slot holds one item."
		if stack.total_weight() > hand_cap(slot == "two_hands"): return "Hand weight limit exceeded."
		if slot != "two_hands" and not one_handed(stack): return "Item requires two hands."
	return ""

func pickup_plan(uid: String) -> Array[Dictionary]:
	last_error = ""
	var found := find_unit(uid)
	if found.is_empty():
		last_error = "Item unavailable."
		return []
	if found["owner"] in HANDS: return []
	var single := ItemStack.from_unit(found["stack"].definition, found["unit"])
	if single.total_weight() > hand_cap(true):
		last_error = "Hand weight limit exceeded."
		return []
	var slot := "two_hands"
	var displace: Array = []
	if one_handed(single):
		slot = "right_hand" if hands["right_hand"].is_empty() or not hands["left_hand"].is_empty() else "left_hand"
		displace = ["two_hands", slot]
	else: displace = HANDS
	var plan: Array[Dictionary] = []
	for hand in displace:
		for held: ItemStack in hands[hand]: plan.append({"step": "move", "uid": held.units[0]["uid"], "destination": "ground", "displace": true})
	plan.append({"step": "move", "uid": uid, "destination": slot, "pickup": true})
	if not preview_moves(plan): return []
	return plan

func held_weapon() -> ItemStack:
	for slot in ["two_hands", "right_hand", "left_hand"]:
		for stack: ItemStack in hands[slot]:
			if "weapon" in stack.definition.tags: return stack
	return null

func held_tag(tag: String) -> bool:
	for slot in HANDS:
		for stack: ItemStack in hands[slot]:
			if tag in stack.definition.tags: return true
	return false

func attack_damage() -> int:
	var weapon := held_weapon()
	return maxi(1, weapon.definition.weapon_damage) if weapon != null else 1

func attack_type() -> String:
	var weapon := held_weapon()
	return weapon.definition.weapon_attack_type if weapon != null and not weapon.definition.weapon_attack_type.is_empty() else "shove"

func held_switchable() -> Dictionary:
	for slot in ["two_hands", "right_hand", "left_hand"]:
		for stack: ItemStack in hands[slot]:
			if stack.definition.switchable:
				return {"stack": stack, "unit": stack.units[0], "owner": slot}
	return {}

func toggle_switchable(uid: String) -> bool:
	var found := find_unit(uid)
	if found.is_empty() or not found["owner"] in HANDS or not found["stack"].definition.switchable:
		last_error = "Switchable equipment must be held."
		return false
	found["unit"]["switched_on"] = not bool(found["unit"].get("switched_on", false))
	revision += 1
	return true

func remove_unit(uid: String) -> Dictionary:
	var found := find_unit(uid)
	if found.is_empty(): return {}
	var stack: ItemStack = found["stack"]
	var unit: Dictionary = found["unit"]
	var owner: String = found["owner"]
	stack.units.erase(unit)
	if stack.quantity == 0: contents(owner).erase(stack)
	revision += 1
	return found

func can_wear(item: ItemDefinition) -> bool:
	return item.clothing_gender.is_empty() or item.clothing_gender == wearer_gender

func move_unit(uid: String, destination: String) -> bool:
	last_error = ""
	var found := find_unit(uid)
	if found.is_empty() or not has_container(destination):
		last_error = "Item or destination is unavailable."
		return false
	var source: String = found["owner"]
	if source == destination:
		last_error = "Item is already there."
		return false
	var stack: ItemStack = found["stack"]
	var unit: Dictionary = found["unit"]
	if destination == uid or not _find(unit["contents"], destination, uid).is_empty():
		last_error = "A container cannot contain itself."
		return false
	if destination == "equipment" and (not equipment.is_empty() or not "backpack" in stack.definition.tags or float(unit["durability"]) <= 0):
		last_error = "Equip one undamaged backpack at a time."
		return false
	if destination in CLOTHING_SLOTS and (not clothing[destination].is_empty() or stack.definition.clothing_slot != destination):
		last_error = "Clothing is incompatible with that slot."
		return false
	if destination in CLOTHING_SLOTS and not can_wear(stack.definition):
		last_error = "This underwear is fitted for %s characters." % stack.definition.clothing_gender
		return false
	var target := contents(destination)
	if world.has(destination):
		if world[destination].used_volume() + ItemStack.from_unit(stack.definition, unit).total_volume() > world[destination].capacity + 0.000001:
			last_error = "Container full."
			return false
	elif not destination in ROOTS:
		var parent := find_unit(destination)
		var used := 0.0
		for child: ItemStack in target: used += child.total_volume()
		if used + ItemStack.from_unit(stack.definition, unit).total_volume() > parent["stack"].definition.capacity() + 0.000001:
			last_error = "Not enough container volume."
			return false
	var origin := contents(source)
	var stack_index := origin.find(stack)
	var unit_index := stack.units.find(unit)
	stack.units.remove_at(unit_index)
	if stack.quantity == 0: origin.remove_at(stack_index)
	var moved := ItemStack.from_unit(stack.definition, unit)
	target.append(moved)
	var error := hands_error()
	if current_weight() > absolute_limit + 0.000001: error = "Player hard carry limit exceeded."
	if not error.is_empty():
		target.erase(moved)
		if stack.quantity == 0: origin.insert(stack_index, stack)
		stack.units.insert(unit_index, unit)
		last_error = error
		return false
	revision += 1
	return true

func add_item(stack: ItemStack) -> bool:
	# Import newly created loot, never copy an already owned instance.
	for unit in stack.units:
		if not find_unit(unit["uid"]).is_empty(): return false
	var destination := default_destination()
	var target := contents(destination)
	var used := 0.0
	for child: ItemStack in target: used += child.total_volume()
	if equipped != null and used + stack.total_volume() > equipped.definition.capacity() + 0.000001: return false
	target.append(stack)
	if current_weight() > absolute_limit:
		target.erase(stack)
		return false
	revision += 1
	return true

func first_with_tag(tag: String) -> String:
	for root in ROOTS:
		var uid := _first_tag(contents(root), tag)
		if not uid.is_empty(): return uid
	return ""

func first_medical_action(action: String) -> String:
	for root in ROOTS:
		var uid := _first_medical(contents(root), action)
		if not uid.is_empty(): return uid
	return ""

func _first_medical(items: Array, action: String) -> String:
	for stack: ItemStack in items:
		if stack.definition.medical_action == action and not stack.units.is_empty(): return stack.units[0]["uid"]
		for unit in stack.units:
			var uid := _first_medical(unit["contents"], action)
			if not uid.is_empty(): return uid
	return ""

func _first_tag(items: Array, tag: String) -> String:
	for stack: ItemStack in items:
		for unit in stack.units:
			if tag in stack.definition.tags:
				if tag != "water" or stack.definition.capacity() == 0 or not unit["contents"].is_empty():
					return unit["uid"]
			var result := _first_tag(unit["contents"], tag)
			if not result.is_empty(): return result
	return ""

func sort_items() -> void:
	contents(default_destination()).sort_custom(func(a: ItemStack, b: ItemStack) -> bool: return a.definition.display_name < b.definition.display_name)
	revision += 1

## Item simulation is batched by game minute so large inventories do not create a
## per-frame traversal cost. Definitions are static; only units are mutated.
func advance_item_states(game_seconds: float) -> void:
	if game_seconds <= 0.0: return
	_item_state_accumulator += game_seconds
	if _item_state_accumulator < 60.0: return
	var elapsed := _item_state_accumulator
	_item_state_accumulator = 0.0
	var ambient := StatusConfig.ambient_temperature_at(GameTime.elapsed_game_seconds)
	var changed := false
	for root in ROOTS:
		changed = _advance_stack_states(contents(root), elapsed, ambient) or changed
	for container: ContainerData in world.values():
		var target := container.temperature_target if is_finite(container.temperature_target) else ambient
		changed = _advance_stack_states(container.contents, elapsed, target) or changed
	if changed: revision += 1

func _advance_stack_states(items: Array, game_seconds: float, environment_temperature: float) -> bool:
	var changed := false
	for stack: ItemStack in items:
		for unit in stack.units:
			var item := stack.definition
			if "food" in item.tags or "water" in item.tags or "liquid" in item.tags:
				var previous_temperature := float(unit.get("temperature", environment_temperature))
				var rate := maxf(0.0, 1.0 + environment_temperature * 0.02)
				var temperature := move_toward(previous_temperature, environment_temperature, rate * game_seconds / 3600.0)
				if not is_equal_approx(temperature, previous_temperature):
					unit["temperature"] = temperature
					changed = true
				if item.freshness_lifetime_days > 0.0 and (not item.requires_opening or bool(unit.get("opened", false))):
					var previous_freshness := float(unit.get("freshness", 100.0))
					var multiplier := pow(2.0, (temperature - 20.0) / 10.0)
					var freshness := maxf(0.0, previous_freshness - game_seconds / (item.freshness_lifetime_days * 86400.0) * 100.0 * multiplier)
					if not is_equal_approx(freshness, previous_freshness):
						unit["freshness"] = freshness
						changed = true
			changed = _advance_stack_states(unit["contents"], game_seconds, environment_temperature) or changed
	return changed

func summary() -> String:
	var labels: Array[String] = []
	for stack: ItemStack in contents(default_destination()): labels.append(stack.label())
	return ", ".join(labels) if not labels.is_empty() else "Empty"

func all_valid() -> bool:
	if wearer_gender not in ["male", "female"]: return false
	if strength < 0 or not hands_error().is_empty(): return false
	for slot in CLOTHING_SLOTS:
		if clothing[slot].size() > 1: return false
		if not clothing[slot].is_empty():
			var garment: ItemStack = clothing[slot][0]
			if garment.quantity != 1 or garment.definition.clothing_slot != slot or not can_wear(garment.definition): return false
	if equipment.size() > 1: return false
	if equipped != null and (equipped.quantity != 1 or not "backpack" in equipped.definition.tags or equipped.units[0]["durability"] <= 0): return false
	var ids := {}
	for root in ROOTS:
		if not _valid_tree(contents(root), ids, 0): return false
	for container: ContainerData in world.values():
		if container.used_volume() > container.capacity + 0.000001: return false
		if not _valid_tree(container.contents, ids, 0): return false
	if current_weight() > absolute_limit + 0.000001: return false
	if not use_context.is_empty():
		if not use_context.get("uid") is String or not use_context.get("origin") is String or not use_context.get("used") is bool: return false
		if not use_context.get("return_after", true) is bool: return false
		var found := find_unit(use_context["uid"])
		if found.is_empty() or not found["owner"] in HANDS or not has_container(use_context["origin"]): return false
	return true

func _valid_tree(items: Array, ids: Dictionary, depth: int) -> bool:
	if depth > 16 or ids.size() > 4096: return false
	for stack: ItemStack in items:
		var item := stack.definition
		if stack.quantity <= 0 or not item.dimensions.is_finite() or item.dimensions.x <= 0 or item.dimensions.y <= 0 or item.dimensions.z <= 0: return false
		if not is_finite(item.unit_weight) or item.unit_weight < 0 or not is_finite(item.weight_reduction) or item.weight_reduction < 0 or item.weight_reduction > 1: return false
		if not item.capacity_dimensions.is_finite() or item.capacity_dimensions.x < 0 or item.capacity_dimensions.y < 0 or item.capacity_dimensions.z < 0: return false
		if item.capacity_dimensions != Vector3.ZERO and item.capacity() <= 0: return false
		if not is_finite(item.volume()) or not is_finite(item.capacity()): return false
		if "backpack" in item.tags and item.capacity() <= 0: return false
		if not item.clothing_slot.is_empty():
			if item.clothing_slot not in CLOTHING_SLOTS or "clothing" not in item.tags or item.clothing_regions.is_empty(): return false
			if item.rag_yield != (2 if item.clothing_slot in ["outer_top", "outer_bottom"] else 1): return false
			for region in item.clothing_regions:
				if region not in BODY_REGIONS or not item.clothing_max_durability.has(region): return false
				for values in [item.clothing_protection, item.clothing_warmth, item.clothing_max_durability]:
					var value: Variant = values.get(region, 0.0)
					if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0: return false
		for unit in stack.units:
			var fraction := float(unit.get("remaining", 1.0))
			if not is_finite(fraction) or fraction <= 0 or fraction > 1: return false
			if fraction != 1.0 and (item.capacity() > 0 or not ("food" in item.tags or "liquid" in item.tags or "water" in item.tags)): return false
			if not is_finite(float(unit.get("acquired", 0.0))) or float(unit.get("acquired", 0.0)) < 0: return false
			if ids.has(unit["uid"]) or String(unit["uid"]).is_empty() or unit["uid"] in ROOTS or unit["uid"] in ["ground", "nearby_all", "preview_ground"] or world.has(unit["uid"]): return false
			ids[unit["uid"]] = true
			if not is_finite(float(unit["durability"])) or unit["durability"] < 0 or unit["durability"] > 100: return false
			if not unit.get("switched_on", false) is bool or (unit.get("switched_on", false) and not item.switchable): return false
			for key in ["freshness", "temperature", "liquid_ml", "bandage_absorption"]:
				var state_value: Variant = unit.get(key, 100.0 if key == "freshness" else 0.0)
				if not (state_value is float or state_value is int) or not is_finite(float(state_value)): return false
			if float(unit.get("freshness", 100.0)) < 0.0 or float(unit.get("freshness", 100.0)) > 100.0 or float(unit.get("liquid_ml", 0.0)) < 0.0: return false
			if not unit.get("opened", true) is bool or not unit.get("bandage_disinfected", false) is bool or not unit.get("appearance", "default") is String or unit.get("cooking_state", "raw") not in ["raw", "cooked", "burnt"]: return false
			if not unit.get("clothing_durability", {}) is Dictionary: return false
			var region_durability: Dictionary = unit.get("clothing_durability", {})
			if not item.clothing_slot.is_empty():
				for region in item.clothing_regions:
					if not region_durability.has(region) or not (region_durability[region] is float or region_durability[region] is int) or not is_finite(float(region_durability[region])): return false
					if float(region_durability[region]) <= 0 or float(region_durability[region]) > float(item.clothing_max_durability.get(region, 0)): return false
			if not _valid_tree(unit["contents"], ids, depth + 1): return false
			var volume := 0.0
			for child: ItemStack in unit["contents"]: volume += child.total_volume()
			if volume > item.capacity() + 0.000001: return false
		if not is_finite(stack.total_weight()): return false
	return true
