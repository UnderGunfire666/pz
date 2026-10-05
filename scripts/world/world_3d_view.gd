class_name World3DView
extends Node3D

## Third-person presentation. Simulation owns collision, combat and AI sensing.
var world_map: WorldMap
var player: PlayerController
var actor_layer: Node2D
var interactions: InteractionSystem
var camera: Camera3D
var view_rig: PlayerViewRig
var third_person_equipment: FirstPersonHands
var chunk_builder := WorldChunkBuilder.new()
var streamer := WorldChunkStreamer.new()
var actor_visuals: Dictionary = {}
var interaction_markers: Array[Dictionary] = []
var _camera_shake_left := 0.0
var _camera_shake_duration := 0.0
var _camera_shake_strength := 0.0
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
var _npc_material := _material(Color("76a878"))
var _door_material := _material(Color("936d43"))
var _health_back_material := _material(Color("261c1a"))
var _health_fill_material := _material(Color("ed655c"))


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
	third_person_equipment = FirstPersonHands.new()
	camera.add_child(third_person_equipment)
	third_person_equipment.setup(player.state.inventory)
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
	_update_actors(delta)
	third_person_equipment.advance(delta, player)


func orbit_camera(mouse_delta: Vector2) -> void:
	view_rig.look_delta(mouse_delta)
	player.facing_direction = view_rig.facing_direction()
	player.look_pitch = view_rig.pitch
	_update_camera(0.0)


func input_to_logical(screen_input: Vector2) -> Vector2:
	return view_rig.movement_direction(screen_input)


func sync_view_to_player() -> void:
	view_rig.align_to_facing(player.facing_direction)
	view_rig.pitch = player.look_pitch
	_update_camera(0.0)


func _update_camera(delta: float) -> void:
	var height := world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
	view_rig.update_pose(Vector3(player.logical_position.x, height, player.logical_position.y), world_map)
	if _camera_shake_left <= 0.0:
		return
	var elapsed := _camera_shake_duration - _camera_shake_left
	var fade := _camera_shake_left / maxf(0.001, _camera_shake_duration)
	var phase := elapsed * 92.0
	# This only offsets the rendered camera after its collision-clamped pose has
	# been calculated; player aim, LOS, collision and combat remain authoritative.
	camera.position += Vector3(sin(phase) * _camera_shake_strength * fade,
		cos(phase * 1.37) * _camera_shake_strength * 0.62 * fade, 0.0)
	_camera_shake_left = maxf(0.0, _camera_shake_left - delta)


func play_hit_camera_shake(strength: float = 0.035, duration: float = 0.11) -> void:
	_camera_shake_strength = maxf(_camera_shake_strength, strength)
	_camera_shake_duration = maxf(_camera_shake_duration, duration)
	_camera_shake_left = maxf(_camera_shake_left, duration)


func refresh_after_load() -> void:
	sync_view_to_player()
	third_person_equipment.reset_motion()
	streamer.refresh(true)
	streamer.flush_pending()
	_update_location()
	_refresh_interaction_markers()
	_update_actors()
	third_person_equipment.advance(0.0, player)


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
		if point.get("furniture", false):
			var cabinet := (marker["node"] as Node3D).get_node("Cabinet") as MeshInstance3D
			var opened := (point["container"] as ContainerData).is_open
			if not cabinet.has_meta("opened") or cabinet.get_meta("opened") != opened:
				cabinet.set_meta("opened", opened)
				cabinet.material_override = _material(ContainerData.OPEN_COLOR if opened else ContainerData.CLOSED_COLOR)

func _create_interaction_marker(point: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mesh := TorusMesh.new()
	if point.get("furniture", false):
		var cabinet := MeshInstance3D.new()
		cabinet.name = "Cabinet"
		var box := BoxMesh.new()
		box.size = ContainerData.CABINET_SIZE
		cabinet.mesh = box
		cabinet.position.y = 0.5
		cabinet.material_override = _material(ContainerData.OPEN_COLOR if (point["container"] as ContainerData).is_open else ContainerData.CLOSED_COLOR)
		root.add_child(cabinet)
	mesh.inner_radius = 0.27
	mesh.outer_radius = 0.34
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.visible = not point.get("furniture", false)
	ring.position.y = 0.045
	root.add_child(ring)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 0.045
	beacon_mesh.bottom_radius = 0.08
	beacon_mesh.height = 0.42
	beacon.mesh = beacon_mesh
	beacon.visible = not point.get("furniture", false)
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


func _update_actors(delta: float = 0.0) -> void:
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
			model.position = ActorBody.transform_for(player).origin
			model.rotation.y = atan2(-player.facing_direction.x, -player.facing_direction.y)
			var player_character := visual["character_model"] as MixamoCharacterVisual
			var held_id := _player_held_item_id()
			var equipment_changed: bool = String(visual.get("held_item_id", held_id)) != held_id
			visual["held_item_id"] = held_id
			if player.aim_mode:
				var upper := "armed_idle"
				var restart_upper_attack := false
				if int(visual.get("attack_id", 0)) != player.visual_attack_id:
					visual["attack_id"] = player.visual_attack_id
					upper = "attack"
					restart_upper_attack = true
				elif player.visual_attack_remaining > 0.0 and player_character.upper_animation_player.is_playing() and player_character.upper_animation_player.get_current_animation() == "attack":
					upper = "attack"
				player_character.advance_split_animation(delta, _player_animation(), _player_animation_speed(), upper, restart_upper_attack,
					PlayerController.ATTACK_ANIMATION_SPEED if upper == "attack" else 1.0)
			else:
				# Leaving right-click preparation immediately removes both partial layers.
				# An already committed attack continues as one full-body clip.
				var full_body := "attack" if player.visual_attack_remaining > 0.0 else _player_animation()
				var full_speed := PlayerController.ATTACK_ANIMATION_SPEED if full_body == "attack" else _player_animation_speed()
				player_character.advance_animation(delta, full_body, full_speed)
			player_character.set_region_flash(player.visual_hit_region, player.visual_damage_remaining)
		elif node is ZombieActor:
			var zombie := node as ZombieActor
			var direction := zombie.facing_direction
			if direction.length_squared() > 0.001:
				model.rotation.y = atan2(-direction.x, -direction.y)
			_update_health_bar(visual, zombie.health, ZombieActor.MAX_HEALTH)
			var previous: Vector3 = visual.get("last_render_position", model.position)
			var motion_speed := previous.distance_to(model.position) / delta if delta > 0.00001 else 0.0
			visual["last_render_position"] = model.position
			var character := visual["character_model"] as MixamoCharacterVisual
			character.set_region_flash(zombie.last_hit_region, zombie._damage_flash_left)
			if zombie.visual_attack_remaining > 0.0:
				if int(visual.get("attack_id", 0)) != zombie.visual_attack_id:
					character.play_animation("attack", 0.0, 1.0, true)
					visual["attack_id"] = zombie.visual_attack_id
				character.advance_animation(delta, "attack", 1.0)
			elif motion_speed > 0.04:
				var chasing := zombie.awareness in [ZombieActor.Awareness.VISUAL, ZombieActor.Awareness.VISUAL_MEMORY]
				character.advance_animation(delta, "run" if chasing else "walk", clampf(motion_speed / 0.58, 0.65, 1.5))
			else:
				character.advance_animation(delta, "idle", 1.0)
		elif node is SurvivorNPC:
			var direction: Vector2 = node.facing_direction
			model.rotation.y = atan2(-direction.x, -direction.y)
			var npc_character := visual["character_model"] as MixamoCharacterVisual
			npc_character.set_region_flash(node.visual_hit_region, node.visual_damage_remaining)
			if node.visual_attack_remaining > 0.0:
				if int(visual.get("attack_id", 0)) != node.visual_attack_id:
					npc_character.play_animation("attack", 0.0, 1.0, true)
					visual["attack_id"] = node.visual_attack_id
				npc_character.advance_animation(delta, "attack", 1.0)
			elif node.visual_velocity.length() > 0.04:
				npc_character.advance_animation(delta, "walk", clampf(node.visual_velocity.length() / SurvivorNPC.MOVE_SPEED, 0.65, 1.35))
			else:
				npc_character.advance_animation(delta, "idle", 1.0)
		if bool(visual["has_health"]):
			var bar: Node3D = visual["health_bar"]
			bar.global_position = model.global_position + Vector3(0.0, 2.05, 0.0)
			bar.look_at(camera.global_position, Vector3.UP)
	for actor_id in actor_visuals.keys():
		if not alive_ids.has(actor_id):
			_remove_actor_visual(actor_id, actor_visuals[actor_id])


func _player_animation() -> String:
	var speed := player.visual_velocity.length()
	if speed < 0.04: return "idle"
	var facing := player.facing_direction
	var right := Vector2(-facing.y, facing.x)
	if player.visual_velocity.dot(facing) < -absf(player.visual_velocity.dot(right)) * 0.85:
		return "back_run" if speed > PlayerController.WALK_SPEED * PlayerController.BACKWARD_MOVE_MULTIPLIER * 1.18 else "back_walk"
	if absf(player.visual_velocity.dot(right)) > absf(player.visual_velocity.dot(facing)) * 1.15:
		return "strafe_right" if player.visual_velocity.dot(right) > 0.0 else "strafe_left"
	if speed > PlayerController.WALK_SPEED * 1.18:
		return "run"
	return "walk"


func _player_animation_speed() -> float:
	var speed := player.visual_velocity.length()
	if speed < 0.04: return 1.0
	var animation := _player_animation()
	var reference := PlayerController.WALK_SPEED * (PlayerController.SPRINT_MULTIPLIER if animation in ["run", "armed_run", "back_run"] else 1.0)
	if animation in ["back_walk", "back_run"]: reference *= PlayerController.BACKWARD_MOVE_MULTIPLIER
	return clampf(speed / reference, 0.65, 1.35)


func _player_held_item_id() -> String:
	if player.state.inventory == null: return ""
	for slot: String in ["right_hand", "left_hand", "two_hands"]:
		var contents := player.state.inventory.contents(slot)
		if not contents.is_empty(): return contents[0].definition.id
	return ""


func _actor_is_visible(node: Node2D, _actor_id: int, logical_position: Vector2,
		_actor_floor: int, _stair_id: String) -> bool:
	if node is SurvivorNPC and node.health <= 0: return false
	if node == player: return true
	# No gameplay FOV, LOS, floor slice or exploration gate. The depth buffer
	# and camera frustum perform normal 3D occlusion for every resident actor.
	return streamer.resident.has(WorldChunkStreamer.cell_at(logical_position)) and streamer.desired.has(WorldChunkStreamer.cell_at(logical_position))

func _create_actor_visual(actor: Node2D) -> Dictionary:
	var root := Node3D.new()
	root.name = "PlayerVisual" if actor == player else "ActorVisual"
	add_child(root)
	var has_health := actor is ZombieActor
	var visual := {"root": root, "has_health": has_health}
	if actor == player or has_health or actor is SurvivorNPC:
		var imported := MixamoCharacterVisual.new()
		imported.name = "CharacterModel"
		root.add_child(imported)
		imported.setup(ActorBody.profile(actor), actor == player)
		visual["character_model"] = imported
		if actor == player: third_person_equipment.bind_body(imported)
	else:
		# NPC appearance is still a placeholder; only Player/Zombie assets exist.
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.26
		capsule.height = 1.42
		body.mesh = capsule
		body.position.y = 0.76
		body.material_override = _npc_material
		root.add_child(body)
		var head := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.23
		sphere.height = 0.46
		head.mesh = sphere
		head.position.y = 1.62
		head.material_override = _npc_material
		root.add_child(head)
	if has_health:
		visual["health_bar"] = _create_health_bar()
		var actor_id := actor.get_instance_id()
		(actor as ZombieActor).died.connect(
			func(_zombie: ZombieActor) -> void: _remove_actor_visual(actor_id, visual),
			CONNECT_ONE_SHOT
		)
	return visual

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
