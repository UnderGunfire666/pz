class_name ClothingCatalog
extends RefCounted

## Stable item IDs, source mesh names and outfit groups. Alternate FBX/glTF
## exports of the same garment are one item, not duplicate loot.
const ROOT := "res://assets/Clothes/"
const BAKED := "res://resources/clothing/"
const SOURCES := {
	"casual_socks": ["CasualWear/AnkleSocks_Socks.gltf", "AnkleSocks", "socks", "Ankle socks", "CasualWear"],
	"casual_bonnet": ["CasualWear/HearBonnet_ACC.fbx", "HairBonnet", "hat", "Hair bonnet", "CasualWear"],
	"casual_jeans": ["CasualWear/Jeans_Pants.gltf", "Jeans", "outer_bottom", "Jeans", "CasualWear"],
	"casual_shoes": ["CasualWear/TennisShoes_Shoes.fbx", "TennisSHoes", "shoes", "Tennis shoes", "CasualWear"],
	"casual_thighhighs": ["CasualWear/ThighHighs_Socks.gltf", "ThighHighs", "socks", "Thigh-high socks", "CasualWear"],
	"ranger_bonnet": ["Law Enforcement Lite/Park Ranger/HearBonnet_ACC.fbx.gltf", "HairBonnet", "hat", "Ranger hair bonnet", "Park Ranger"],
	"ranger_hat": ["Law Enforcement Lite/Park Ranger/ParkRangerFullOutfitKit.gltf", "Park Ranger Hat", "hat", "Ranger hat", "Park Ranger"],
	"ranger_pants": ["Law Enforcement Lite/Park Ranger/ParkRangerFullOutfitKit.gltf", "Khakis", "outer_bottom", "Ranger khakis", "Park Ranger"],
	"ranger_belt": ["Law Enforcement Lite/Park Ranger/ParkRangerFullOutfitKit.gltf", "Belt", "belt", "Ranger belt", "Park Ranger"],
	"ranger_shirt": ["Law Enforcement Lite/Park Ranger/ParkRangerFullOutfitKit.gltf", "ParkRanger SHirt", "outer_top", "Ranger shirt", "Park Ranger"],
	"ranger_badges": ["Law Enforcement Lite/Park Ranger/ParkRangerFullOutfitKit.gltf", "OfficerShirt_Badges", "badge", "Ranger badges", "Park Ranger"],
	"ranger_boots": ["Law Enforcement Lite/Park Ranger/ParkRangerFullOutfitKit.gltf", "LeatherBoots", "shoes", "Leather boots", "Park Ranger"],
	"medical_shirt": ["Medical Lite/MedicalOutfitKit.gltf", "Scrub_Shirt", "outer_top", "Scrub shirt", "Medical Lite"],
	"medical_mask": ["Medical Lite/MedicalOutfitKit.gltf", "SurgicalMask", "mask", "Surgical mask", "Medical Lite"],
	"medical_pants": ["Medical Lite/MedicalOutfitKit.gltf", "Scrub_Pants", "outer_bottom", "Scrub pants", "Medical Lite"],
	"medical_cap": ["Medical Lite/MedicalOutfitKit.gltf", "SurgicalCap", "hat", "Surgical cap", "Medical Lite"],
	"medical_gloves": ["Medical Lite/MedicalOutfitKit.gltf", "Scrub_Gloves", "gloves", "Surgical gloves", "Medical Lite"],
	"medical_stethoscope": ["Medical Lite/MedicalOutfitKit.gltf", "stethoscope", "neck", "Stethoscope", "Medical Lite"],
	"medical_neckbrace": ["Medical Lite/MedicalOutfitKit.gltf", "Neck Brace", "neck", "Neck brace", "Medical Lite"],
	"medical_crutch": ["Medical Lite/MedicalOutfitKit.gltf", "Crutch", "medical_support", "Crutch", "Medical Lite"],
	"medical_cast": ["Medical Lite/MedicalOutfitKit.gltf", "FootCast", "shoes", "Foot cast", "Medical Lite"],
	"medical_footbrace": ["Medical Lite/MedicalOutfitKit.gltf", "FootBrace", "shoes", "Foot braces", "Medical Lite"],
	"underwear_tshirt": ["Underwear 2025/2025 Version/TShirt.fbx", "T-Shirt", "inner_top", "T-shirt", "Underwear 2025"],
	"underwear_tanktop": ["Underwear 2025/2025 Version/TankTop.fbx", "TankTop", "inner_top", "Tank top", "Underwear 2025"],
	"male_boxers": ["Underwear 2025/2025 Version/Male/M_UnderwearAllMeshes.gltf", "Boxers", "underwear_bottom", "Boxers", "Underwear 2025"],
	"male_briefs": ["Underwear 2025/2025 Version/Male/M_UnderwearAllMeshes.gltf", "Briefs", "underwear_bottom", "Briefs", "Underwear 2025"],
	"male_boxerbriefs": ["Underwear 2025/2025 Version/Male/M_UnderwearAllMeshes.gltf", "BoxerBriefs", "underwear_bottom", "Boxer briefs", "Underwear 2025"],
	"female_boyshorts": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "BoyShorts", "underwear_bottom", "Boy shorts", "Underwear 2025"],
	"female_gstring": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "GString", "underwear_bottom", "G-string", "Underwear 2025"],
	"female_highcut": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "HightCut", "underwear_bottom", "High-cut briefs", "Underwear 2025"],
	"female_thong": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "Thong", "underwear_bottom", "Thong", "Underwear 2025"],
	"female_seamless": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "ThongSeamless", "underwear_bottom", "Seamless thong", "Underwear 2025"],
	"female_tubebra": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "TubeBra", "underwear_top", "Tube bra", "Underwear 2025"],
	"female_paddedbra": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "PaddedBra", "underwear_top", "Padded bra", "Underwear 2025"],
	"female_tribra": ["Underwear 2025/2025 Version/Female/F_UnderwearFull.gltf", "TriBra", "underwear_top", "Triangle bra", "Underwear 2025"],
}
const LEGACY_VISUALS := {"shirt": "underwear_tshirt", "jacket": "ranger_shirt", "trousers": "casual_jeans", "overpants": "ranger_pants", "cap": "ranger_hat", "mask": "medical_mask", "boots": "ranger_boots", "gloves": "medical_gloves"}
static var _definitions: Dictionary = {}

static func visual_id(id: String) -> String:
	return String(LEGACY_VISUALS.get(id, id))

static func definition(id: String) -> ItemDefinition:
	if _definitions.has(id): return _definitions[id]
	if not SOURCES.has(id): return null
	var row: Array = SOURCES[id]
	var slot: String = row[2]
	var regions: Array[String] = ["Torso"]
	match slot:
		"hat", "mask": regions = ["Head"]
		"inner_top", "outer_top": regions = ["Torso", "Left Arm", "Right Arm"]
		"underwear_bottom", "inner_bottom", "outer_bottom": regions = ["Left Leg", "Right Leg"]
		"socks", "shoes": regions = ["Left Foot", "Right Foot"]
		"gloves": regions = ["Left Hand", "Right Hand"]
	var protection := {}
	var warmth := {}
	var durability := {}
	for region in regions:
		protection[region] = 5.0 if slot in ["outer_top", "outer_bottom", "shoes"] else 0.0
		warmth[region] = 5.0 if slot in ["outer_top", "outer_bottom", "inner_top"] else 1.0
		durability[region] = 40.0
	var item := ItemDefinition.clothing(id, row[3], slot, regions, protection, warmth, durability,
		0.5 if slot in ["outer_top", "outer_bottom", "shoes"] else 0.15, Vector3(15, 10, 3), 1)
	item.clothing_gender = "male" if id.begins_with("male_") else ("female" if id.begins_with("female_") else "")
	item.outfit_group = row[4]
	_definitions[id] = item
	return item

static func all_items() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for id: String in SOURCES: result.append(ItemStack.new(definition(id)))
	return result

static func starter_outfit(inventory: InventoryGrid) -> void:
	for id: String in ["underwear_tshirt", "casual_jeans", "casual_shoes", "casual_socks", "male_boxers"]:
		var stack := ItemStack.new(definition(id))
		inventory.loose.append(stack)
		inventory.move_unit(stack.units[0]["uid"], stack.definition.clothing_slot)

static func dress(inventory: InventoryGrid, rng: RandomNumberGenerator, group: String = "") -> void:
	if group.is_empty(): group = ["CasualWear", "Park Ranger", "Medical Lite"][rng.randi_range(0, 2)]
	var by_slot := {}
	for id: String in SOURCES:
		var item := definition(id)
		if not inventory.can_wear(item): continue
		if item.outfit_group != group and item.clothing_slot not in ["underwear_bottom", "underwear_top"]: continue
		# Medical supports are available loot, not part of a healthy starter outfit.
		if id in ["medical_crutch", "medical_cast", "medical_footbrace", "medical_neckbrace", "ranger_bonnet"]: continue
		if not by_slot.has(item.clothing_slot): by_slot[item.clothing_slot] = []
		by_slot[item.clothing_slot].append(item)
	if not by_slot.has("outer_top"):
		by_slot["inner_top"] = [definition("underwear_tshirt"), definition("underwear_tanktop")]
	if group == "Medical Lite": by_slot["shoes"] = [definition("casual_shoes")]
	for slot: String in by_slot:
		if not inventory.contents(slot).is_empty(): continue
		var choices: Array = by_slot[slot]
		var stack := ItemStack.new(choices[rng.randi_range(0, choices.size() - 1)])
		inventory.loose.append(stack)
		inventory.move_unit(stack.units[0]["uid"], slot)

static func mesh_path(id: String, body: String) -> String:
	return BAKED + body + "/" + visual_id(id) + ".res"
