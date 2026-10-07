class_name FirstPersonHands
extends Node3D

## Third-person held props follow the imported model's animated hand bones.
## Equipment comes from InventoryGrid and never deals damage.
var body_visual: MixamoCharacterVisual
var inventory: InventoryGrid
var hands: Array[Node3D] = []
var held_ids: Array[String] = []
var revision := -1
var hurt_remaining := 0.0
var sleeve_color := Color("c99c7c")
var _last_feet := Vector3.INF
var _walk_phase := 0.0
var _walk_blend := 0.0
const BAT_MODEL: PackedScene = preload("res://assets/Objects/bat/batclean_low.glb")


func setup(source: InventoryGrid) -> void:
	inventory = source
	name = "ThirdPersonEquipment"
	refresh()

func bind_body(model: MixamoCharacterVisual) -> void:
	body_visual = model


func refresh() -> void:
	if revision == inventory.revision: return
	revision = inventory.revision
	for hand in hands:
		remove_child(hand)
		hand.queue_free()
	hands.clear()
	held_ids.clear()
	sleeve_color = Color("52616b") if not inventory.contents("outer_top").is_empty() else (Color("c0c7cc") if not inventory.contents("inner_top").is_empty() else Color("c99c7c"))
	for slot: String in ["left_hand", "right_hand"]:
		var hand := Node3D.new()
		hand.name = slot
		add_child(hand)
		hands.append(hand)
		var contents := inventory.contents(slot)
		if slot == "right_hand" and not inventory.contents("two_hands").is_empty(): contents = inventory.contents("two_hands")
		held_ids.append("" if contents.is_empty() else contents[0].definition.id)
		if contents.is_empty(): continue
		var stack: ItemStack = contents[0]
		if stack.definition.id == "baseball_bat":
			var bat := BAT_MODEL.instantiate() as Node3D
			bat.name = "BaseballBat"
			# The grip is on the right animated hand; the two-hand Mixamo poses place
			# the left hand on the same prop during ready and attack animations.
			# The source mesh runs from its grip near local Y=0 to the barrel on
			# positive Y, matching the existing hand-prop convention.
			bat.position = Vector3(0.0, 0.10, 0.0)
			bat.rotation = Vector3.ZERO
			bat.scale = Vector3.ONE
			hand.add_child(bat)
		elif stack.definition.id.contains("hammer"):
			_box(hand, Vector3(0, 0.09, -0.075), Vector3(0.045, 0.3, 0.045), Color("8c623f"))
			_box(hand, Vector3(0, 0.25, -0.075), Vector3(0.22, 0.085, 0.085), Color("8b939a"))
		elif stack.definition.switchable:
			_box(hand, Vector3(0, 0.04, -0.12), Vector3(0.08, 0.08, 0.26), Color("35434a"))
			_box(hand, Vector3(0, 0.04, -0.255), Vector3(0.1, 0.1, 0.015), Color("fff3b0") if stack.units[0].get("switched_on", false) else Color("6c7880"))
		else:
			# Generic occupied-hand proxy for items without a dedicated model.
			_box(hand, Vector3(0, 0.08, -0.05), Vector3(0.10, 0.20, 0.13), Color("829879"))


func advance(delta: float, player: PlayerController) -> void:
	refresh()
	visible = not player.state.is_dead()
	var feet := ActorPerception.point(player.world_map, player.logical_position, player.floor_level, player.stair_id, 0.0)
	var travelled := feet.distance_to(_last_feet) if _last_feet.is_finite() else 0.0
	_last_feet = feet
	if travelled > 1.5: reset_motion()
	elif GameTime.simulation_scale() > 0.0:
		_walk_phase = fmod(_walk_phase + travelled * TAU / 1.5, TAU)
		_walk_blend = move_toward(_walk_blend, 1.0 if travelled > 0.0001 else 0.0, delta * GameTime.simulation_scale() * 8.0)
	hurt_remaining = maxf(0, hurt_remaining - delta * GameTime.simulation_scale())
	if is_instance_valid(body_visual):
		for i in hands.size():
			var wrist_index := MixamoCharacterVisual.bone(body_visual.skeleton, "LeftHand" if i == 0 else "RightHand")
			if wrist_index >= 0:
				# Props use the same animated wrist as the visible mesh.
				hands[i].global_transform = body_visual.skeleton.global_transform * body_visual.skeleton.get_bone_global_pose(wrist_index)


func reset_motion() -> void:
	_last_feet = Vector3.INF
	_walk_phase = 0.0
	_walk_blend = 0.0


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	parent.add_child(mesh)
