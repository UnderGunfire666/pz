class_name ClothingSystem
extends RefCounted

const BODY_REGIONS := ["Head", "Torso", "Left Arm", "Right Arm", "Left Hand", "Right Hand",
	"Left Leg", "Right Leg", "Left Foot", "Right Foot"]
const OUTER_SLOTS := ["outer_top", "outer_bottom"]
const NON_PROTECTIVE_SLOTS := ["glasses", "mask"]

var inventory: InventoryGrid
var rng := RandomNumberGenerator.new()

func _init(p_inventory: InventoryGrid = null) -> void:
	inventory = p_inventory
	rng.randomize()

## Shared immediate commands for NPCs/zombies. Player interactions schedule
## these same inventory transitions through the existing timed action queue.
func wear(uid: String) -> bool:
	if inventory == null: return false
	var found := inventory.find_unit(uid)
	if found.is_empty(): return false
	var slot: String = found["stack"].definition.clothing_slot
	if slot not in InventoryGrid.CLOTHING_SLOTS or found["owner"] == slot: return false
	var moves: Array = []
	if not inventory.contents(slot).is_empty():
		moves.append({"uid": inventory.contents(slot)[0].units[0]["uid"], "destination": "loose"})
	moves.append({"uid": uid, "destination": slot})
	if not inventory.preview_moves(moves): return false
	for move: Dictionary in moves:
		if not inventory.move_unit(move["uid"], move["destination"]): return false
	return true

func remove(slot: String) -> bool:
	if inventory == null or slot not in InventoryGrid.CLOTHING_SLOTS or inventory.contents(slot).is_empty(): return false
	return inventory.move_unit(inventory.contents(slot)[0].units[0]["uid"], "loose")

static func rag_definition() -> ItemDefinition:
	return ItemDefinition.new("rag", "Rag", Vector3(15, 10, 1), 0.05, ["rag", "repair_material"])

func worn_for_region(region: String, protective_only: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if inventory == null: return result
	for slot in InventoryGrid.CLOTHING_SLOTS:
		if protective_only and slot in NON_PROTECTIVE_SLOTS: continue
		for stack: ItemStack in inventory.contents(slot):
			var item := stack.definition
			if region in item.clothing_regions and float(stack.units[0].get("clothing_durability", {}).get(region, 0.0)) > 0:
				result.append({"slot": slot, "stack": stack, "unit": stack.units[0]})
	return result

func protection_percent(region: String) -> float:
	var total := 0.0
	for entry in worn_for_region(region, true):
		total += float(entry["stack"].definition.clothing_protection.get(region, 0.0))
	return clampf(total, 0.0, 100.0)

func warmth_by_region() -> Dictionary:
	var result := {}
	for region in BODY_REGIONS:
		var total := 0.0
		for entry in worn_for_region(region):
			total += float(entry["stack"].definition.clothing_warmth.get(region, 0.0))
		result[region] = total
	return result

func total_warmth() -> float:
	var total := 0.0
	for value in warmth_by_region().values(): total += float(value)
	return total / BODY_REGIONS.size()

## forced_roll is a deterministic 0..1 test hook. A failed protection roll does not damage clothing.
func resolve_hit(region: String, damage: float, forced_roll: float = -1.0) -> Dictionary:
	var result := {"region": region, "incoming": damage, "protected": false, "absorbed": 0.0,
		"player_damage": maxf(0.0, damage), "destroyed": [], "rag_count": 0}
	if region not in BODY_REGIONS or damage <= 0 or inventory == null: return result
	var garments := worn_for_region(region, true)
	var chance := protection_percent(region) / 100.0
	var roll := rng.randf() if forced_roll < 0 else clampf(forced_roll, 0.0, 1.0)
	if garments.is_empty() or chance <= 0.0 or (chance < 1.0 and roll >= chance): return result
	result["protected"] = true
	var remaining := damage
	var active := garments.duplicate()
	while remaining > 0.000001 and not active.is_empty():
		var total_weight := 0.0
		for entry in active: total_weight += 2.0 if entry["slot"] in OUTER_SLOTS else 1.0
		var budget := remaining
		var consumed := 0.0
		var exhausted: Array = []
		for entry in active:
			var share := budget * (2.0 if entry["slot"] in OUTER_SLOTS else 1.0) / total_weight
			var durability: Dictionary = entry["unit"]["clothing_durability"]
			var absorbed := minf(share, float(durability[region]))
			durability[region] = float(durability[region]) - absorbed
			consumed += absorbed
			if float(durability[region]) <= 0.000001:
				durability[region] = 0.0
				exhausted.append(entry)
		remaining -= consumed
		for entry in exhausted: active.erase(entry)
		if consumed <= 0.000001: break
	result["absorbed"] = damage - remaining
	result["player_damage"] = remaining
	for entry in garments:
		if float(entry["unit"]["clothing_durability"][region]) > 0: continue
		var uid: String = entry["unit"]["uid"]
		result["destroyed"].append(uid)
		result["rag_count"] += entry["stack"].definition.rag_yield
		inventory.remove_unit(uid)
	if result["destroyed"].is_empty(): inventory.revision += 1
	return result
