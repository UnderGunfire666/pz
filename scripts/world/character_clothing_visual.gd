class_name CharacterClothingVisual
extends Node3D

## Inventory owns equipment. This projection only changes when equipment IDs
## change; durability and unrelated bag transfers do not rebuild the outfit.
var inventory: InventoryGrid
var character: MixamoCharacterVisual
var body_type := "male"
var garments: Dictionary = {}
var hair_meshes: Array[MeshInstance3D] = []
var _body_meshes: Array[MeshInstance3D] = []
var _originals: Array[Mesh] = []
var _skin: Skin
var _revision := -1
var _signature := "!"
static var _meshes: Dictionary = {}
static var _body_cache: Dictionary = {}

func setup(model: MixamoCharacterVisual, source: InventoryGrid, kind: String) -> void:
	name = "ClothingVisual"
	character = model
	inventory = source
	body_type = kind
	_skin = Skin.new()
	for i in character.skeleton.get_bone_count():
		_skin.add_named_bind(character.skeleton.get_bone_name(i), character.skeleton.get_bone_global_rest(i).affine_inverse())
	for mesh in character.meshes:
		_body_meshes.append(mesh)
		_originals.append(mesh.mesh)

func refresh() -> void:
	if _revision == inventory.revision: return
	_revision = inventory.revision
	var equipped := {}
	var signature := ""
	for slot: String in InventoryGrid.CLOTHING_SLOTS:
		var items := inventory.contents(slot)
		if items.is_empty(): continue
		var id := ClothingCatalog.visual_id(items[0].definition.id)
		equipped[slot] = id
		signature += slot + ":" + id + ";"
	if signature == _signature: return
	_signature = signature
	for slot: String in garments.keys():
		if not equipped.has(slot) or garments[slot].get_meta("item_id") != equipped[slot]:
			garments[slot].free()
			garments.erase(slot)
	var covered := {}
	for slot: String in equipped:
		if not garments.has(slot):
			var mesh := _load_mesh(ClothingCatalog.mesh_path(equipped[slot], body_type))
			if mesh == null: continue
			var instance := _attach(mesh, slot)
			instance.set_meta("item_id", equipped[slot])
			garments[slot] = instance
		var garment: MeshInstance3D = garments[slot]
		garment.visible = not _occluded(slot, equipped)
		if garment.visible:
			var masks: Dictionary = garment.mesh.get_meta("body_masks", {})
			for key: String in masks:
				if not covered.has(key): covered[key] = {}
				for triangle: int in masks[key]: covered[key][triangle] = true
	for hair in hair_meshes: hair.visible = not equipped.has("hat")
	_apply_body_masks(covered, body_type + ":" + signature)

func _occluded(slot: String, equipped: Dictionary) -> bool:
	if slot == "inner_top": return equipped.has("outer_top")
	if slot == "underwear_top": return equipped.has("inner_top") or equipped.has("outer_top")
	if slot == "inner_bottom": return equipped.has("outer_bottom")
	if slot == "underwear_bottom": return equipped.has("inner_bottom") or equipped.has("outer_bottom")
	return false

static func _load_mesh(path: String) -> ArrayMesh:
	if not _meshes.has(path):
		if not ResourceLoader.exists(path):
			push_warning("Missing clothing bake: " + path)
			return null
		_meshes[path] = load(path)
	return _meshes[path] as ArrayMesh

func _attach(mesh: ArrayMesh, label: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.skin = _skin
	instance.skeleton = NodePath("..")
	instance.extra_cull_margin = 0.5
	character.skeleton.add_child(instance)
	return instance

func add_hair(hair: String) -> void:
	var mesh := _load_mesh(ClothingCatalog.BAKED + body_type + "/" + hair + ".res")
	if mesh != null: hair_meshes.append(_attach(mesh, "Hair"))

func _apply_body_masks(masks: Dictionary, cache_key: String) -> void:
	if not _body_cache.has(cache_key):
		var results: Array[Mesh] = []
		for index in _body_meshes.size():
			var original := _originals[index]
			var output := ArrayMesh.new()
			var changed := false
			for surface in original.get_surface_count():
				var arrays := original.surface_get_arrays(surface)
				var mask: Dictionary = masks.get(String(_body_meshes[index].name) + ":" + str(surface), {})
				if not mask.is_empty():
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					var kept := PackedInt32Array()
					for triangle in indices.size() / 3:
						if mask.has(triangle): continue
						kept.append(indices[triangle * 3])
						kept.append(indices[triangle * 3 + 1])
						kept.append(indices[triangle * 3 + 2])
					arrays[Mesh.ARRAY_INDEX] = kept
					changed = true
					if kept.is_empty(): continue
				output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, original.surface_get_format(surface))
				output.surface_set_material(output.get_surface_count() - 1, original.surface_get_material(surface))
			results.append(output if changed else original)
		# Bound combination caching while living instances retain their resources.
		if _body_cache.size() >= 48: _body_cache.erase(_body_cache.keys()[0])
		_body_cache[cache_key] = results
	var cached: Array = _body_cache[cache_key]
	for index in _body_meshes.size():
		_body_meshes[index].mesh = cached[index]
		_body_meshes[index].visible = cached[index].get_surface_count() > 0
