extends RefCounted

const INDEX = preload("res://scripts/world/spatial_query_index.gd")


static func run(game: MVPGameRoot, check: Callable) -> void:
	var map := game.world_map
	var navigation_signature := _navigation_signature(map)
	map._build_navigation()
	check.call(map._last_navigation_grid_entries_scanned == map._nav_grid_ids.size(),
		"navigation initialization scans each grid node once")
	check.call(_navigation_signature(map) == navigation_signature,
		"single-pass navigation initialization preserves graph nodes and edges")
	check.call(map.find_path(Vector2(13.5, 9.5), 0, Vector2(14.5, 6.5), 2).size() > 2,
		"single-pass navigation preserves multi-floor route")
	var nearest_matches := true
	var nearest_candidates := 0
	var nearest_full := 0
	var nearest_rng := RandomNumberGenerator.new()
	nearest_rng.seed = 72219
	for index in range(300):
		var level := index % 3
		var position := Vector2(nearest_rng.randf_range(0, 20), nearest_rng.randf_range(0, 15))
		nearest_matches = nearest_matches and map._nearest_nav(position, level) == _brute_nearest_nav(map, position, level)
		nearest_candidates += map._last_nearest_nav_candidates
		nearest_full += (map._floor_node_ids.get(level, []) as Array).size()
	check.call(nearest_matches, "local nearest-navigation lookup matches full floor scan")
	check.call(nearest_candidates < nearest_full, "local nearest-navigation lookup excludes remote floor nodes")
	var stair_link: StairLink = map.stairs["safehouse_0_1"]
	var stair_node := map._nearest_nav(stair_link.start, stair_link.from_floor)
	check.call(stair_node in map._stair_nav_ids[stair_link.from_floor], "nearest-navigation lookup keeps stair landing nodes eligible")
	var navigator := LocalNavigation.new()
	var nav_start := Vector2(13.5, 9.5)
	var nav_target := Vector2(14.5, 6.5)
	navigator.advance(map, nav_start, 0, "", nav_target, 2, 0.8, 0.1)
	var initial_builds := navigator._path_build_count
	for repeat in range(30):
		navigator.advance(map, nav_start, 0, "", nav_target, 2, 0.8, 0.1)
	check.call(initial_builds == 1 and navigator._path_build_count == 1,
		"unchanged active path does not rebuild every fixed interval")
	navigator.advance(map, nav_start, 0, "", nav_target + Vector2(1.0, 0.0), 2, 0.8, 0.1)
	check.call(navigator._path_build_count == 2, "meaningful target movement invalidates cached path")
	navigator.reset()
	navigator.advance(map, nav_start, 0, "", Vector2(1.5, 1.5), 2, 0.8, 0.1)
	var unreachable_builds := navigator._path_build_count
	for repeat in range(5): navigator.advance(map, nav_start, 0, "", Vector2(1.5, 1.5), 2, 0.8, 0.1)
	check.call(navigator._path_build_count == unreachable_builds,
		"unreachable path retries are throttled")
	var character_panel := game.hud.character_panel
	character_panel.refresh(game)
	var skill_root := character_panel.skill_tree.get_root()
	var original_health := game.player_state.health
	game.player_state.health = maxf(0.0, original_health - 1.0)
	character_panel.refresh(game)
	check.call(character_panel.skill_tree.get_root() == skill_root,
		"health refresh preserves cached skills and traits tree")
	game.player_state.health = original_health
	var hud := game.hud
	hud.refresh(game)
	var presentation_count := hud._presentation_refresh_count
	for repeat in range(30): hud.refresh(game)
	check.call(hud._presentation_refresh_count == presentation_count,
		"unchanged HUD frame reuses cached presentation")
	game.inventory.revision += 1
	hud.refresh(game)
	check.call(hud._presentation_refresh_count == presentation_count + 1,
		"inventory revision invalidates HUD carry presentation")

	var index := INDEX.new()
	index.insert(0, Rect2(Vector2(4, -8), Vector2(0, 24)), "long_wall")
	index.insert(0, Rect2(Vector2(-4, -4), Vector2(4, 4)), "negative_diagonal")
	index.insert(1, Rect2(Vector2(4, -8), Vector2(0, 24)), "upper_wall")
	for i in range(100):
		index.insert(0, Rect2(Vector2(100 + i * 8, 100), Vector2.ONE), i)
	var boundary := index.query(0, Rect2(Vector2(4, 4), Vector2.ZERO))
	check.call(boundary.has("long_wall") and not boundary.has("upper_wall"), "spatial bins preserve exact wall boundaries and floor isolation")
	var long_query := index.query(0, Rect2(Vector2(3.9, -4), Vector2(0.2, 16)))
	check.call(long_query.count("long_wall") == 1, "multi-bin wall is returned only once for sound attenuation")
	check.call(index.query(0, Rect2(Vector2(-2, -2), Vector2.ZERO)).has("negative_diagonal"), "spatial bins use floor division for negative coordinates")
	check.call(boundary.size() < 5, "local spatial query excludes remote city walls")
	index.clear()
	check.call(index.query(0, Rect2(Vector2.ZERO, Vector2(1000, 1000))).is_empty(), "spatial rebuild clears stale geometry")
	var isolated_map := WorldMap.new()
	var first_map := MapDefinition.new()
	var first_wall := MapWallEdgeDefinition.new()
	first_wall.start = Vector2(4, 0)
	first_wall.end = Vector2(4, 8)
	first_map.wall_edges.append(first_wall)
	isolated_map.load_definition(first_map, false)
	var old_face: Dictionary = isolated_map.wall_faces(0)[0]
	var second_map := MapDefinition.new()
	var second_wall := MapWallEdgeDefinition.new()
	second_wall.start = Vector2(40, 0)
	second_wall.end = Vector2(40, 8)
	second_map.wall_edges.append(second_wall)
	isolated_map.load_definition(second_map, false)
	check.call(not isolated_map.query_walls(0, Rect2(Vector2.ZERO, Vector2(80, 80))).has(old_face), "map reload removes previous map spatial entries")
	isolated_map._add_wall(Vector2(-4, 0), Vector2(-4, 8), "new", 0)
	var new_candidates := isolated_map.query_walls(0, Rect2(Vector2(-4, 4), Vector2.ZERO))
	check.call(new_candidates.has(isolated_map.wall_faces(0)[1]), "wall insertion invalidates the index before the next query")
	isolated_map.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = 983145
	var los_matches := true
	var sound_matches := true
	var body_matches := true
	var stair_matches := true
	var queries: Array = []
	var candidate_count := 0
	var full_count := 0
	for i in range(300):
		var level := i % 3
		var from := Vector2(rng.randf_range(0, 20), rng.randf_range(0, 15))
		var to := from + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		los_matches = los_matches and map.has_line_of_sight(from, to, level) == _brute_los(map, from, to, level)
		var actual_sound := map.sound_cost(from, level, to, level)
		var expected_sound := _brute_sound(map, from, to, level)
		sound_matches = sound_matches and ((is_inf(actual_sound) and is_inf(expected_sound)) or is_equal_approx(actual_sound, expected_sound))
		body_matches = body_matches and map.can_stand(from, level) == _brute_can_stand(map, from, level)
		stair_matches = stair_matches and map._inside_stair_body(from, level, 0.22) == _brute_stair_body(map, from, level, 0.22)
		queries.append([from, to, level])
		candidate_count += map.query_walls(level, Rect2(from, Vector2.ZERO).expand(to)).size()
		full_count += map.wall_faces(level).size()
	check.call(los_matches, "indexed LOS matches full wall scan on 300 deterministic queries")
	check.call(sound_matches, "indexed sound attenuation matches full wall scan")
	check.call(body_matches and stair_matches, "indexed body clearance and stair support match full scans")
	var vis := VisibilitySystem.new()
	vis.setup(map)
	var rays_match := true
	for level in range(3):
		vis.viewer_floor = level
		vis.viewer_position = Vector2(11.5, 6.5)
		vis.vision_radius = 6.6
		vis.half_fov_radians = deg_to_rad(68)
		var polygon := vis._build_visibility_polygon()
		for i in range(VisibilitySystem.FOV_RAY_COUNT):
			var direction := Vector2.from_angle(TAU * float(i) / float(VisibilitySystem.FOV_RAY_COUNT))
			var angle := absf(wrapf(direction.angle() - vis.facing_direction.angle(), -PI, PI))
			var radius := vis.vision_radius if angle <= vis.half_fov_radians else VisibilitySystem.SELF_VISION_RADIUS
			var expected := vis._ray_endpoint(direction, radius, map.wall_faces(level))
			rays_match = rays_match and polygon[i].is_equal_approx(expected)
	check.call(rays_match, "indexed FOV matches full scan for all 768 rays across three floors")
	vis.free()
	var start := Time.get_ticks_usec()
	for repeat in range(4):
		for q in queries: _brute_los(map, q[0], q[1], q[2])
	var brute_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for repeat in range(4):
		for q in queries: map.has_line_of_sight(q[0], q[1], q[2])
	var indexed_us := Time.get_ticks_usec() - start
	print("Spatial query sample: candidates %d/%d; 1200 LOS queries full=%dus indexed=%dus (CPU microbenchmark, not FPS)." % [candidate_count, full_count, brute_us, indexed_us])


static func _brute_los(map: WorldMap, from: Vector2, to: Vector2, level: int) -> bool:
	if map.get_tile(from, level) == null or map.get_tile(to, level) == null: return false
	for wall in map.wall_faces(level):
		if Geometry2D.segment_intersects_segment(from, to, wall["start"], wall["end"]) != null: return false
	return true


static func _navigation_signature(map: WorldMap) -> Dictionary:
	var edges: Array[String] = []
	for id in range(map._navigation.get_point_count()):
		var neighbours: Array[int] = []
		for connected in map._navigation.get_point_connections(id):
			neighbours.append(connected)
		neighbours.sort()
		edges.append("%d:%s" % [id, neighbours])
	return {"points": map._navigation.get_point_count(), "edges": edges}


static func _brute_nearest_nav(map: WorldMap, position: Vector2, level: int) -> int:
	var nearest := -1
	var distance := INF
	for id: int in map._floor_node_ids.get(level, []):
		var target: Vector2 = map._nav_points[id]["position"]
		var squared := target.distance_squared_to(position)
		if squared < distance and squared < 2.26 and map._segment_walkable(position, target, level):
			nearest = id
			distance = squared
	return nearest


static func _brute_sound(map: WorldMap, from: Vector2, to: Vector2, level: int) -> float:
	if map.get_tile(from, level) == null or map.get_tile(to, level) == null: return INF
	var cost := from.distance_to(to)
	for wall in map.wall_faces(level):
		if Geometry2D.segment_intersects_segment(from, to, wall["start"], wall["end"]) != null: cost += 2.5
	return cost


static func _brute_stair_body(map: WorldMap, pos: Vector2, level: int, margin: float) -> bool:
	for link: StairLink in map.stairs.values():
		if level not in [link.from_floor, link.to_floor]: continue
		var offset := pos - link.start
		var along := offset.dot(link.direction())
		if along > StairLink.LANDING_LENGTH and along < link.length() - StairLink.LANDING_LENGTH and absf(offset.cross(link.direction())) < link.width * 0.5 + margin: return true
	return false


static func _brute_can_stand(map: WorldMap, pos: Vector2, level: int) -> bool:
	var tile := map.get_tile(pos, level)
	if tile == null or not tile.walkable or _brute_stair_body(map, pos, level, WorldMap.ACTOR_RADIUS): return false
	for offset in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		tile = map.get_tile(pos + offset * WorldMap.ACTOR_RADIUS, level)
		if tile == null or not tile.walkable: return false
	for wall in map.wall_faces(level):
		if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, wall["start"], wall["end"])) < WorldMap.ACTOR_RADIUS: return false
	return true
