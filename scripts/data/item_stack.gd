class_name ItemStack
extends RefCounted

## One definition, distinct identity/contents for every physical unit.
var definition: ItemDefinition
var units: Array[Dictionary] = []
var quantity: int:
	get: return units.size()
	set(value):
		while units.size() > maxi(0, value):
			units.pop_back()
		while units.size() < value:
			units.append({"uid": new_uid(), "flavor": "", "durability": 100.0, "contents": [],
				"remaining": 1.0, "acquired": GameTime.elapsed_game_seconds,
				"clothing_durability": definition.clothing_max_durability.duplicate(true), "switched_on": false})

static func new_uid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _init(p_definition: ItemDefinition, p_quantity: int = 1) -> void:
	definition = p_definition
	quantity = maxi(0, p_quantity)

static func from_unit(item: ItemDefinition, unit: Dictionary) -> ItemStack:
	var stack := ItemStack.new(item, 0)
	stack.units.append(unit)
	return stack

func total_weight() -> float:
	var result := 0.0
	for unit in units:
		var contents_weight := 0.0
		for child: ItemStack in unit["contents"]:
			contents_weight += child.total_weight()
		result += definition.unit_weight * float(unit.get("remaining", 1.0)) + contents_weight
	return result

func total_volume() -> float:
	var result := 0.0
	for unit in units:
		var size := unit_dimensions(unit)
		result += size.x * size.y * size.z
	return result

func unit_dimensions(unit: Dictionary) -> Vector3:
	var size := definition.capacity_dimensions + Vector3.ONE if "backpack" in definition.tags else definition.dimensions
	if definition.capacity() == 0 and ("food" in definition.tags or "liquid" in definition.tags or "water" in definition.tags):
		var fraction := float(unit.get("remaining", 1.0))
		if size.z >= size.x and size.z >= size.y: size.z *= fraction
		elif size.x >= size.y: size.x *= fraction
		else: size.y *= fraction
	return size

func used_volume(index: int = 0) -> float:
	var result := 0.0
	for child: ItemStack in units[index]["contents"]:
		result += child.total_volume()
	return result

func label() -> String:
	return definition.display_name if quantity == 1 else "%s x%d" % [definition.display_name, quantity]
