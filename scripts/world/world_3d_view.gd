class_name World3DView
extends Node3D

## First-person presentation. Simulation owns collision, combat and AI sensing.
var world_map: WorldMap
var player: PlayerController
var actor_layer: Node2D
var interactions: InteractionSystem
var camera: Camera3D
var view_rig: PlayerViewRig
var chunk_builder := WorldChunkBuilder.new()
var streamer := WorldChunkStreamer.new()
var actor_visuals: Dictionary = {}
var interaction_markers: Array[Dictionary] = []
var _marker_index: Dictionary = {}
var _marker_nodes: Dictionary = {}
var _marker_revision := -1
var _environment: Environment
var _sun: DirectionalLight3D
var _last_lighting_daylight := -1.0
var _active_building_id := ""
var _display_floor := -1
signal player_building_changed(previous_id: String, current_id: String)
signal player_display_floor_changed(floor_index: int)
var _player_material := _material(Color("d8e7f3"))
var _player_accent_material := _material(Color("416a92"))
var _zombie_material := _material(Color("a54646"))
var _zombie_flash_material := _material(Color("f06a58"))
var _npc_material := _material(Color("76a878"))
var _door_material := _material(Color("936d43"))
var _health_back_material := _material(Color("261c1a"))
var _health_fill_material := _material(Color("ed655c"))
var _swing_material := _material(Color(1.0, 0.86, 0.53, 0.72), true)


func setup(p_world_map: WorldMap, p_player: PlayerController,
		p_actor_layer: Node2D, p_interactions: InteractionSystem) -> void:
	world_map = p_world_map
	player = p_player
	actor_layer = p_actor_layer
	interactions = p_interactions
	_build_environment()
	view_rig = PlayerViewRig.new()
	view_rig.name = "PlayerViewRig"
	add_child(view_rig)
	camera = view_rig.camera
	camera.make_current()
	sync_view_to_player()
	chunk_builder.setup(world_map)
	streamer.name = "WorldChunks"
	add_child(streamer)
	streamer.setup(chunk_builder, camera)
	world_map.barrier_changed.connect(streamer.barrier_changed)
	interactions.points_changed.connect(_refresh_interaction_markers)
	_refresh_interaction_markers()
	player.world_view = self


func _process(delta: float) -> void:
	if player == null: return
	_update_camera(delta)
	streamer.advance()
	_update_location()
	_update_lighting()
	_update_interaction_markers()
	_update_actors()


func orbit_camera(mouse_delta: Vector2) -> void:
	view_rig.look_delta(mouse_delta)
	player.facing_direction = view_rig.facing_direction()
	_update_camera(0.0)


func input_to_logical(screen_input: Vector2) -> Vector2:
	return view_rig.movement_direction(screen_input)


func sync_view_to_player() -> void:
	view_rig.align_to_facing(player.facing_direction)
	_update_camera(0.0)


func _update_camera(_delta: float) -> void:
	var height := world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
	view_rig.update_pose(Vector3(player.logical_position.x, height, player.logical_position.y))


func refresh_after_load() -> void:
	sync_view_to_player()
	streamer.refresh(true)
	streamer.flush_pending()
	_update_location()
	_refresh_interaction_markers()
	_update_actors()


func _update_location() -> void:
	var tile := world_map.get_tile(player.logical_position, player.floor_level)
	var building := tile.building_id if tile != null else ""
	if not player.stair_id.is_empty(): building = world_map.stairs[player.stair_id].building_id
	if building != _active_building_id:
		var previous := _active_building_id
		_active_building_id = building
		player_building_changed.emit(previous, building)
	var floor_index := world_map.display_floor_at(player.logical_position, player.floor_level, player.stair_id)
	if floor_index != _display_floor:
		_display_floor = floor_index
		player_display_floor_changed.emit(floor_index)


func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("a5b7c7")
	environment_node.environment = _environment
	add_child(environment_node)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	_sun.shadow_enabled = false
	add_child(_sun)
	_update_lighting()


func _update_lighting() -> void:
	var daylight := world_map.ambient_light()
	if absf(daylight - _last_lighting_daylight) < 0.001: return
	_last_lighting_daylight = daylight
	_environment.ambient_light_energy = lerpf(0.12, 0.65, daylight)
	_environment.background_color = Color("101a28").lerp(Color("424e59"), daylight)
	_sun.light_energy = lerpf(0.08, 1.1, daylight)
	_sun.light_color = Color("8cadd5").lerp(Color("ffe4b8"), daylight)


func _refresh_interaction_markers() -> void:
	for marker in interaction_markers: (marker["node"] as Node3D).queue_free()
	interaction_markers.clear()
	_marker_nodes.clear()
	_marker_index.clear()
	for point: Dictionary in interactions.points:
		var key := WorldChunkStreamer.cell_at(point["position"])
		if not _marker_index.has(key): _marker_index[key] = []
		_marker_index[key].append(point)
	_marker_revision = -1
	_update_interaction_markers()


func _update_interaction_markers() -> void:
	if _marker_revision != streamer.revision:
		_marker_revision = streamer.revision
		var needed: Dictionary = {}
		for key: Vector2i in streamer.desired:
			if not streamer.resident.has(key): continue
			for point: Dictionary in _marker_index.get(key, []):
				var id := String(point["id"])
				needed[id] = true
				if not _marker_nodes.has(id):
					var node := _create_interaction_marker(point)
					var entry := {"node": node, "point": point}
					_marker_nodes[id] = entry
					interaction_markers.append(entry)
		for id: String in _marker_nodes.keys():
			if needed.has(id): continue
			var entry: Dictionary = _marker_nodes[id]
			(entry["node"] as Node3D).queue_free()
			interaction_markers.erase(entry)
			_marker_nodes.erase(id)
	for marker: Dictionary in interaction_markers:
		var point: Dictionary = marker["point"]
		(marker["node"] as Node3D).visible = not (point["kind"] == "hazard" and point.get("triggered", false))

func _create_interaction_marker(point: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mesh := TorusMesh.new()
	if point.get("furniture", false):
		var cabinet := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 1.0, 0.5)
		cabinet.mesh = box
		cabinet.position.y = 0.5
		cabinet.material_override = _material(Color("d9d9d2"))
		root.add_child(cabinet)
	mesh.inner_radius = 0.27
	mesh.outer_radius = 0.34
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.position.y = 0.045
	root.add_child(ring)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.045
	beacon_mesh.bottom_radius = 0.08
	beacon_mesh.height = 0.42
	beacon.mesh = beacon_mesh
	beacon.position.y = 0.24
	root.add_child(beacon)
	var color := Color("6dcae8")
	match String(point["kind"]):
		"bed":
			color = Color("baa7ea")
		"hazard":
			color = Color("e37a52")
	var material := _material(color)
	material.emission_enabled = true
	material.emission = color * 0.16
	ring.material_override = material
	beacon.material_override = material
	var logical_position: Vector2 = point["position"]
	var floor_level := int(point.get("floor", 0))
	root.position = Vector3(logical_position.x, float(floor_level) * world_map.floor_height, logical_position.y)
	add_child(root)
	return root


func _update_actors() -> void:
	var alive_ids: Dictionary = {}
	for actor in actor_layer.get_children():
		if not actor is PlayerController and not actor is ZombieActor and not actor is SurvivorNPC:
			continue
		var node := actor as Node2D
		var actor_id := node.get_instance_id()
		if node.is_queued_for_deletion():
			continue
		alive_ids[actor_id] = true
		var logical_position: Vector2 = node.get("logical_position")
		var actor_floor := int(node.get("floor_level"))
		var stair_id := String(node.get("stair_id"))
		var visible := _actor_is_visible(node, actor_id, logical_position, actor_floor, stair_id)
		var visual: Dictionary = actor_visuals.get(actor_id, {})
		if not visible:
			if not visual.is_empty():
				_remove_actor_visual(actor_id, visual)

			continue
		if visual.is_empty():
			visual = _create_actor_visual(node)
			actor_visuals[actor_id] = visual
		var model: Node3D = visual["root"]
		model.visible = node != player or view_rig.shows_local_body()
		if bool(visual["has_health"]):
			(visual["health_bar"] as Node3D).visible = true
		model.position = Vector3(logical_position.x, world_map.elevation_at(logical_position, actor_floor, stair_id), logical_position.y)
		if node == player:
			model.rotation.y = atan2(-player.facing_direction.x, -player.facing_direction.y)
			(visual["equipment_visual"] as PlayerEquipmentVisual).refresh()
			var swing: Node3D = visual["swing"]
			swing.visible = player._attack_flash_left > 0.0
			swing.rotation.y = lerpf(-0.9, 0.9, 1.0 - clampf(player._attack_flash_left / 0.18, 0.0, 1.0))
		elif node is ZombieActor:
			var zombie := node as ZombieActor
			var direction := zombie.facing_direction
			if direction.length_squared() > 0.001:
				model.rotation.y = atan2(-direction.x, -direction.y)
			_update_health_bar(visual, zombie.health, ZombieActor.MAX_HEALTH)
			var flash := _zombie_flash_material if zombie._damage_flash_left > 0.0 else _zombie_material
			(visual["body"] as MeshInstance3D).material_override = flash
			(visual["head"] as MeshInstance3D).material_override = flash
		elif node is SurvivorNPC:
			var direction: Vector2 = node.facing_direction
			model.rotation.y = atan2(-direction.x, -direction.y)
		if bool(visual["has_health"]):
			var bar: Node3D = visual["health_bar"]
			bar.global_position = model.global_position + Vector3(0.0, 2.05, 0.0)
			bar.look_at(camera.global_position, Vector3.UP)
	for actor_id in actor_visuals.keys():
		if not alive_ids.has(actor_id):
			_remove_actor_visual(actor_id, actor_visuals[actor_id])


func _actor_is_visible(node: Node2D, _actor_id: int, logical_position: Vector2,
		_actor_floor: int, _stair_id: String) -> bool:
	if node == player: return true
	# No gameplay FOV, LOS, floor slice or exploration gate. The depth buffer
	# and camera frustum perform normal 3D occlusion for every resident actor.
	return streamer.resident.has(WorldChunkStreamer.cell_at(logical_position)) and streamer.desired.has(WorldChunkStreamer.cell_at(logical_position))

func _create_actor_visual(actor: Node2D) -> Dictionary:
	var root := Node3D.new()
	root.name = "PlayerVisual" if actor == player else "ActorVisual"
	add_child(root)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var lower_body: MeshInstance3D = null
	if actor == player:
		var torso_mesh := CylinderMesh.new()
		torso_mesh.top_radius = 0.22
		torso_mesh.bottom_radius = 0.25
		torso_mesh.height = 0.72
		torso_mesh.radial_segments = 8
		body.mesh = torso_mesh
		body.position.y = 1.06
		lower_body = MeshInstance3D.new()
		lower_body.name = "LowerBody"
		var lower_mesh := CylinderMesh.new()
		lower_mesh.top_radius = 0.22
		lower_mesh.bottom_radius = 0.17
		lower_mesh.height = 0.7
		lower_mesh.radial_segments = 8
		lower_body.mesh = lower_mesh
		lower_body.position.y = 0.35
		root.add_child(lower_body)
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.26
		capsule.height = 1.42
		body.mesh = capsule
		body.position.y = 0.76
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.23
	head_mesh.height = 0.46
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.62, -0.04)
	root.add_child(head)
	var has_health := actor is ZombieActor
	var material := _zombie_material if has_health else (_npc_material if actor is SurvivorNPC else _player_material)
	body.material_override = material
	if lower_body != null: lower_body.material_override = material
	head.material_override = _player_accent_material if actor == player else material
	if has_health:
		head.position.z = -0.2
	var direction_marker := MeshInstance3D.new()
	direction_marker.name = "DirectionMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.07, 0.07, 0.42)
	direction_marker.mesh = marker_mesh
	direction_marker.position = Vector3(0.0, 0.85, -0.42)
	direction_marker.material_override = _door_material
	root.add_child(direction_marker)
	var visual := {"root": root, "body": body, "head": head, "lower_body": lower_body, "has_health": has_health}
	if actor == player:
		var equipment_visual := PlayerEquipmentVisual.new()
		root.add_child(equipment_visual)
		equipment_visual.setup(player.state.inventory)
		visual["equipment_visual"] = equipment_visual
		visual["swing"] = _create_swing_visual(root)
	if has_health:
		visual["health_bar"] = _create_health_bar()
		var actor_id := actor.get_instance_id()
		(actor as ZombieActor).died.connect(
			func(_zombie: ZombieActor) -> void: _remove_actor_visual(actor_id, visual),
			CONNECT_ONE_SHOT
		)
	return visual


func _create_swing_visual(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "AttackSwing"
	parent.add_child(root)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(12):
		var a := lerpf(-0.45, 0.45, float(index) / 12.0)
		var b := lerpf(-0.45, 0.45, float(index + 1) / 12.0)
		for point in [Vector2(sin(a), -cos(a)) * 0.72, Vector2(sin(a), -cos(a)) * 1.22, Vector2(sin(b), -cos(b)) * 1.22,
			Vector2(sin(a), -cos(a)) * 0.72, Vector2(sin(b), -cos(b)) * 1.22, Vector2(sin(b), -cos(b)) * 0.72]:
			surface.add_vertex(Vector3(point.x, 0.85, point.y))
	var arc := MeshInstance3D.new()
	arc.mesh = surface.commit()
	arc.material_override = _swing_material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arc)
	root.visible = false
	return root


func _remove_actor_visual(actor_id: int, visual: Dictionary) -> void:
	for key in ["root", "health_bar"]:
		var node := visual.get(key) as Node3D
		if is_instance_valid(node):
			node.visible = false
			node.queue_free()
	actor_visuals.erase(actor_id)


func _create_health_bar() -> Node3D:
	var bar := Node3D.new()
	add_child(bar)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.8, 0.1, 0.04)
	back.mesh = back_mesh
	back.material_override = _health_back_material
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(back)
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.72, 0.055, 0.06)
	fill.mesh = fill_mesh
	fill.position.z = -0.035
	fill.material_override = _health_fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(fill)
	bar.visible = false
	return bar


func _update_health_bar(visual: Dictionary, health: int, max_health: int) -> void:
	var bar: Node3D = visual["health_bar"]
	var fill := bar.get_child(1) as MeshInstance3D
	var ratio := clampf(float(health) / float(maxi(1, max_health)), 0.0, 1.0)
	fill.scale.x = maxf(0.001, ratio)
	fill.position.x = -0.36 * (1.0 - ratio)


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
