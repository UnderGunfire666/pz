class_name ItemDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export var dimensions := Vector3.ONE
@export var unit_weight := 0.0
@export var tags: Array[String] = []
@export var capacity_dimensions := Vector3.ZERO
@export_range(0.0, 1.0) var weight_reduction := 0.0
@export var requires_two_hands := false
@export var clothing_slot := ""
@export var clothing_regions: Array[String] = []
@export var clothing_protection: Dictionary = {}
@export var clothing_warmth: Dictionary = {}
@export var clothing_max_durability: Dictionary = {}
@export var rag_yield := 0
@export var weapon_attack_type := ""
@export var weapon_damage := 0
@export var weapon_hitbox_size := Vector3.ZERO
@export var switchable := false
@export var hunger_restore := 0.0
@export var thirst_restore := 0.0
@export var happiness_effect := 0.0
@export var medical_action := ""

func _init(p_id: String = "", p_name: String = "", p_dimensions: Vector3 = Vector3.ONE,
		p_weight: float = 0.0, p_tags: Array[String] = []) -> void:
	id = p_id
	display_name = p_name
	dimensions = p_dimensions
	unit_weight = p_weight
	tags = p_tags

func volume() -> float:
	var size := capacity_dimensions + Vector3.ONE if "backpack" in tags else dimensions
	return size.x * size.y * size.z

func capacity() -> float:
	return capacity_dimensions.x * capacity_dimensions.y * capacity_dimensions.z

static func backpack(id_value: String, title: String, size: Vector3, weight: float, reduction: float) -> ItemDefinition:
	var item := ItemDefinition.new(id_value, title, size + Vector3.ONE, weight, ["backpack"])
	item.capacity_dimensions = size
	item.weight_reduction = reduction
	return item

static func clothing(id_value: String, title: String, slot: String, regions: Array[String],
		protection: Dictionary, warmth: Dictionary, durability: Dictionary,
		weight: float, size: Vector3, rags: int) -> ItemDefinition:
	var item := ItemDefinition.new(id_value, title, size, weight, ["clothing"])
	item.clothing_slot = slot
	item.clothing_regions = regions.duplicate()
	item.clothing_protection = protection.duplicate(true)
	item.clothing_warmth = warmth.duplicate(true)
	item.clothing_max_durability = durability.duplicate(true)
	item.rag_yield = 2 if slot in ["outer_top", "outer_bottom"] else 1
	return item


static func baseball_bat() -> ItemDefinition:
	var item := ItemDefinition.new("baseball_bat", "Baseball bat", Vector3(4, 4, 85), 1.05, ["weapon", "tool"])
	item.requires_two_hands = true
	item.weapon_attack_type = "bat swing"
	item.weapon_damage = 1
	# Metres, in the attack direction: a narrow cylinder approximation sampled
	# against the authoritative per-body-part hurtboxes.
	item.weapon_hitbox_size = Vector3(0.11, 0.11, 1.5)
	return item
