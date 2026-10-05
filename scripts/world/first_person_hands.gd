class_name FirstPersonHands
extends Node3D

## Presentation only; equipment comes from InventoryGrid and never deals damage.
var inventory: InventoryGrid
var hands: Array[Node3D] = []
var held_ids: Array[String] = []
var revision := -1
var hurt_remaining := 0.0
var sleeve_color := Color("c99c7c")
var _last_feet := Vector3.INF
var _walk_phase := 0.0
var _walk_blend := 0.0


func setup(source: InventoryGrid) -> void:
	inventory = source
	name = "FirstPersonHands"
	refresh()


func refresh() -> void:
	if revision == inventory.revision: return
	revision = inventory.revision
	for hand in hands:
		remove_child(hand)
		hand.queue_free()
	hands.clear()
	held_ids.clear()
	sleeve_color = Color("52616b") if not inventory.contents("outer_top").is_empty() else (Color("c0c7cc") if not inventory.contents("inner_top").is_empty() else Color("c99c7c"))
	var skin := Color("685747") if not inventory.contents("gloves").is_empty() else Color("c99c7c")
	for slot: String in ["left_hand", "right_hand"]:
		var hand := Node3D.new()
		hand.name = slot
		add_child(hand)
		hands.append(hand)
		_box(hand, Vector3(0, -0.04, 0.15), Vector3(0.105, 0.11, 0.36), sleeve_color)
		_box(hand, Vector3.ZERO, Vector3(0.12, 0.12, 0.14), skin)
		var contents := inventory.contents(slot)
		if slot == "right_hand" and not inventory.contents("two_hands").is_empty(): contents = inventory.contents("two_hands")
		held_ids.append("" if contents.is_empty() else contents[0].definition.id)
		if contents.is_empty(): continue
		var stack: ItemStack = contents[0]
		if stack.definition.id.contains("hammer"):
			_box(hand, Vector3(0, 0.13, -0.025), Vector3(0.045, 0.3, 0.045), Color("8c623f"))
			_box(hand, Vector3(0, 0.29, -0.025), Vector3(0.22, 0.085, 0.085), Color("8b939a"))
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
	var strike := sin(clampf(1.0 - player._attack_flash_left / 0.18, 0, 1) * PI) if player._attack_flash_left > 0 else 0.0
	var shove := inventory.held_weapon() == null
	for i in hands.size():
		var side := -1.0 if i == 0 else 1.0
		var hand := hands[i]
		var weapon := inventory.held_weapon()
		var active := shove or (weapon != null and held_ids[i] == weapon.definition.id) or not inventory.contents("two_hands").is_empty()
		var amount := strike if active else 0.0
		hand.position = Vector3(side * (0.22 if player.aim_mode else 0.29), -0.29 + amount * 0.08, -0.48 - amount * 0.18)
		hand.position += Vector3(cos(_walk_phase) * 0.006, sin(_walk_phase * 2) * 0.008, sin(_walk_phase) * side * 0.008) * _walk_blend
		hand.rotation = Vector3(-amount * 0.65, -side * amount * 0.5, side * hurt_remaining * 1.8)
	# Pull the hands back near walls, so held geometry does not visibly cross them.
	var eye := ActorPerception.point(player.world_map, player.logical_position, player.floor_level, player.stair_id, ActorPerception.EYE_HEIGHT)
	position.z = 0.22 if not player.world_map.has_spatial_line_of_sight(eye, eye + player.look_direction() * 0.85) else 0.0


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
