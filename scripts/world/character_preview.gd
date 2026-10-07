extends Node3D

## F6 inspection scene; click a body region, B toggles authoritative volumes.
var camera: Camera3D
var boxes: Array[MeshInstance3D] = []
var actors: Array[Dictionary] = []
var label: Label
var frames := 0
var frame_times: Array[float] = []
var render_cpu: Array[float] = []
var render_gpu: Array[float] = []
var last_frame_usec := 0
var benchmark := false
var outfit_index := 0
var stripped := false

func _ready() -> void:
	benchmark = "--benchmark" in OS.get_cmdline_user_args()
	if benchmark: RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("25303b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 150, 0)
	add_child(light)
	camera = Camera3D.new()
	camera.fov = 43.0
	add_child(camera)
	camera.position = Vector3(0, 1.5, -6.4)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(40, 40)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("444d56")
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	if benchmark:
		camera.fov = 60.0
		camera.position = Vector3(0, 8, -14)
		camera.look_at(Vector3(0, 0.8, 5))
		for index in 64:
			add_model(ActorBody.ZOMBIE if index % 3 == 0 else ActorBody.PLAYER, Vector3((index % 8 - 3.5) * 0.9, 0, index / 8 * 1.0), "Zombie" if index % 3 == 0 else ("Female NPC" if index % 3 == 1 else "Player"))
	else:
		add_model(ActorBody.PLAYER, Vector3(-1.35, 0, 0), "Player")
		add_model(ActorBody.PLAYER, Vector3(0, 0, 0), "Female NPC")
		add_model(ActorBody.ZOMBIE, Vector3(1.35, 0, 0), "Zombie")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--close="):
			var x := float(argument.trim_prefix("--close="))
			camera.position = Vector3(x, 1.1, -3.1)
			camera.look_at(Vector3(x, 0.95, 0))
	label = Label.new()
	label.position = Vector2(20, 20)
	label.text = "Clothing preview | C: next outfit | R: remove / wear | B: hit volumes\nLeft: original zombie · centre: female NPC · right: male player | Click: body region"
	add_child(label)

func add_model(profile: CharacterBodyProfile, at: Vector3, title: String) -> void:
	var model := MixamoCharacterVisual.new()
	model.position = at
	add_child(model)
	var appearance := CharacterAppearance.new()
	if title == "Female NPC":
		appearance.gender = "female"
		appearance.hair = "Hair_Long"
	var inventory := InventoryGrid.new()
	inventory.wearer_gender = appearance.gender
	var rng := RandomNumberGenerator.new()
	rng.seed = actors.size() + 19
	ClothingCatalog.dress(inventory, rng, ["CasualWear", "Medical Lite", "Park Ranger"][actors.size() % 3])
	model.setup(profile if title == "Zombie" else appearance.model_profile())
	model.bind_clothing(inventory, appearance, title == "Zombie")
	actors.append({"position": at, "profile": profile, "name": title, "model": model, "inventory": inventory})
	if benchmark: return
	for region: String in profile.regions:
		var bounds: AABB = profile.regions[region]
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = bounds.size
		box.mesh = mesh
		box.position = at + bounds.get_center()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.2, 0.8, 1.0, 0.22)
		box.material_override = material
		box.visible = false
		add_child(box)
		boxes.append(box)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_C, KEY_R]:
		if event.keycode == KEY_C:
			outfit_index = (outfit_index + 1) % 3
			stripped = false
		else: stripped = not stripped
		for index in actors.size():
			var inventory: InventoryGrid = actors[index]["inventory"]
			for slot: String in InventoryGrid.ROOTS: inventory.contents(slot).clear()
			inventory.revision += 1
			if not stripped:
				var rng := RandomNumberGenerator.new()
				rng.seed = index + 19
				ClothingCatalog.dress(inventory, rng, ["CasualWear", "Medical Lite", "Park Ranger"][(index + outfit_index) % 3])
			actors[index]["model"].clothing_visual.refresh()
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		for box in boxes: box.visible = not box.visible
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var origin := camera.project_ray_origin(event.position)
		var direction := camera.project_ray_normal(event.position)
		var distance := INF
		var selected := "No hit"
		for actor: Dictionary in actors:
			for region: String in actor["profile"].regions:
				var hit := PlayerTargeting.ray_box(origin - actor["position"], direction, actor["profile"].regions[region], 20)
				if hit < distance:
					distance = hit
					selected = actor["name"] + ": " + region
		label.text = "B: hit volumes | Click: body region\n" + selected

func _process(delta: float) -> void:
	for actor: Dictionary in actors:
		var model := actor["model"] as MixamoCharacterVisual
		if "--static" in OS.get_cmdline_user_args():
			model.animation_player.stop()
			model.skeleton.reset_bone_poses()
		else:
			var animation_delta := 1.0 / 60.0 if "--capture" in OS.get_cmdline_user_args() else delta
			var interval := MixamoCharacterVisual.animation_interval_for_distance(camera.global_position.distance_to(model.global_position)) if benchmark else 0.0
			model.advance_animation_throttled(animation_delta, "attack" if actor["name"] == "Zombie" else "walk", 1.0, interval)
	frames += 1
	var now := Time.get_ticks_usec()
	if benchmark and frames > 30:
		frame_times.append(float(now - last_frame_usec) / 1000.0)
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	last_frame_usec = now
	if frames == 160 and benchmark:
		frame_times.sort()
		render_cpu.sort()
		render_gpu.sort()
		print("BODY BENCHMARK 64 instances: median frame ms=", frame_times[frame_times.size() / 2],
			" p95=", frame_times[int(frame_times.size() * 0.95)],
			" render CPU p95=", render_cpu[int(render_cpu.size() * 0.95)],
			" GPU p95=", render_gpu[int(render_gpu.size() * 0.95)],
			" draw calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			" video memory=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		get_tree().quit()
	if frames == 8 and "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/character-preview.png")
		get_tree().quit()
