class_name PlayerEquipmentVisual
extends Node3D

## Render-only projection of authoritative InventoryGrid clothing slots.
## The cached revision avoids rebuilding meshes every frame; inventory remains the
## sole source of what is equipped.
var inventory: InventoryGrid
var torso_anchor: Node3D
var outer_top_root: Node3D
var _last_revision := -1
var _shown_outer_top_uid := ""


func setup(p_inventory: InventoryGrid) -> void:
	inventory = p_inventory
	name = "EquipmentVisual"
	torso_anchor = Node3D.new()
	torso_anchor.name = "TorsoAnchor"
	add_child(torso_anchor)
	outer_top_root = _create_work_jacket()
	outer_top_root.name = "OuterTop"
	torso_anchor.add_child(outer_top_root)
	refresh(true)


func refresh(force: bool = false) -> void:
	if inventory == null: return
	if not force and _last_revision == inventory.revision: return
	_last_revision = inventory.revision
	var worn: Array = inventory.contents("outer_top")
	var uid := ""
	var supported := false
	if not worn.is_empty():
		var stack: ItemStack = worn[0]
		uid = stack.units[0]["uid"]
		supported = stack.definition.id == "jacket"
	_shown_outer_top_uid = uid if supported else ""
	outer_top_root.visible = supported


func _create_work_jacket() -> Node3D:
	var root := Node3D.new()
	var jacket_material := _material(Color("52616b"))
	var trim_material := _material(Color("34434d"))

	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh := CylinderMesh.new()
	torso_mesh.top_radius = 0.31
	torso_mesh.bottom_radius = 0.34
	torso_mesh.height = 0.72
	torso_mesh.radial_segments = 8
	torso_mesh.rings = 1
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 1.08, 0.0)
	torso.material_override = jacket_material
	root.add_child(torso)

	for side in [-1.0, 1.0]:
		var sleeve := MeshInstance3D.new()
		sleeve.name = "LeftSleeve" if side < 0 else "RightSleeve"
		var sleeve_mesh := CylinderMesh.new()
		sleeve_mesh.top_radius = 0.105
		sleeve_mesh.bottom_radius = 0.09
		sleeve_mesh.height = 0.62
		sleeve_mesh.radial_segments = 8
		sleeve.mesh = sleeve_mesh
		sleeve.position = Vector3(0.34 * side, 1.04, 0.0)
		sleeve.rotation.z = deg_to_rad(-8.0 * side)
		sleeve.material_override = jacket_material
		root.add_child(sleeve)

	var collar := MeshInstance3D.new()
	collar.name = "Collar"
	var collar_mesh := TorusMesh.new()
	collar_mesh.inner_radius = 0.155
	collar_mesh.outer_radius = 0.235
	collar_mesh.rings = 8
	collar_mesh.ring_segments = 6
	collar.mesh = collar_mesh
	collar.position = Vector3(0.0, 1.45, 0.0)
	collar.material_override = trim_material
	root.add_child(collar)

	var closure := MeshInstance3D.new()
	closure.name = "FrontClosure"
	var closure_mesh := BoxMesh.new()
	closure_mesh.size = Vector3(0.035, 0.58, 0.025)
	closure.mesh = closure_mesh
	closure.position = Vector3(0.0, 1.07, -0.342)
	closure.material_override = trim_material
	root.add_child(closure)
	return root


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
