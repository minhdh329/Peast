extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_capture_biome_repeat_limit():
		return
	if not _test_responsive_terrain_fit():
		return
	if ProceduralTerrain.RANDOM_BIOMES.size() != 5 or not ProceduralTerrain.RANDOM_BIOMES.has(ProceduralTerrain.Biome.CITY):
		_fail("The random biome pool must include City.")
		return
	var seen_biomes: Dictionary = {}
	var biome_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed: int in range(128):
		biome_rng.seed = seed
		var biome_index: int = biome_rng.randi_range(0, ProceduralTerrain.RANDOM_BIOMES.size() - 1)
		seen_biomes[ProceduralTerrain.RANDOM_BIOMES[biome_index]] = true
	if not seen_biomes.has(ProceduralTerrain.Biome.CITY):
		_fail("City should be reachable from random biome selection.")
		return
	var scenery_valid: bool = await _test_biome_scenery()
	if not scenery_valid:
		return
	if not await _test_forest_climb():
		return
	if not await _test_volcano_climb():
		return
	if not await _test_ocean_platforms():
		return
	if not await _test_player_platforms():
		return
	if not await _test_sky_fall():
		return
	var city_scene: PackedScene = load("res://scenes/CityMap.tscn")
	var city: Node2D = city_scene.instantiate() as Node2D
	root.add_child(city)
	current_scene = city
	for frame_index: int in range(8):
		await physics_frame
	var terrain: ProceduralTerrain = city.get_node("Terrain") as ProceduralTerrain
	if terrain.biome != ProceduralTerrain.Biome.CITY or terrain.randomize_biome_on_spawn:
		_fail("CityMap should always load the CITY biome.")
		return
	if terrain._get_biome_texture() != ProceduralTerrain.CITY_TEXTURE or terrain.get_node_or_null("CityBackground") == null:
		_fail("City terrain and background textures should be present.")
		return
	if terrain.get_cell_source_id(Vector2i(3, terrain.floor_row)) != 0 or terrain.get_cell_source_id(Vector2i(10, terrain.floor_row - 3)) != 0:
		_fail("City streets and rooftop platforms should contain solid tiles.")
		return
	var player: CharacterBody2D = city.get_node("Player") as CharacterBody2D
	if not player.is_on_floor():
		_fail("Player should spawn on the city street.")
		return
	var monsters: Array[Node] = get_nodes_in_group("monsters")
	if monsters.size() != 3:
		_fail("City should spawn three Monsters.")
		return
	var species: Array[String] = []
	for monster_node: Node in monsters:
		var monster: Monster = monster_node as Monster
		species.append(monster.charge_style)
		if not monster.is_on_floor() or not monster.scene_file_path in ["res://scenes/monsters/city_cat.tscn", "res://scenes/monsters/city_car.tscn"]:
			_fail("City Monsters should stand on tiles and belong to the city pool.")
			return
	if not species.has("Cat") or not species.has("Car"):
		_fail("Every city should spawn both a cat and a car.")
		return
	if not await _test_city_underpasses(terrain, player, monsters):
		return
	if not _test_city_passives(city):
		return
	for monster_node: Node in monsters:
		monster_node.queue_free()
	await process_frame
	terrain._process(0.0)
	if terrain._exit_portal == null:
		_fail("Clearing city Monsters should open the exit portal.")
		return
	player.velocity = Vector2.ZERO
	player.global_position = terrain._exit_portal.global_position
	for physics_frame_index: int in range(5):
		await physics_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/capture_rewards.tscn":
		_fail("Entering the victory portal should open the post-battle capture screen.")
		return
	current_scene.call("_finish")
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/main_menu.tscn":
		_fail("Finishing without capturing should return to the menu.")
		return
	print("City biome smoke test passed.")
	quit(0)


func _test_city_underpasses(terrain: ProceduralTerrain, player: CharacterBody2D, monsters: Array[Node]) -> bool:
	var building_columns: Array[int] = [int(terrain.map_width_cells * 0.32), int(terrain.map_width_cells * 0.65)]
	for building_column: int in building_columns:
		for column: int in range(building_column, building_column + 4):
			for row: int in range(terrain.floor_row - 2, terrain.floor_row):
				if terrain.get_cell_source_id(Vector2i(column, row)) != -1:
					_fail("City buildings should leave a two-block-high ground passage underneath.")
					return false
	var monster_positions: Array[Vector2] = []
	for monster_node: Node in monsters:
		var monster: Node2D = monster_node as Node2D
		monster_positions.append(monster.global_position)
		monster.set_physics_process(false)
		monster.global_position = Vector2(-1000.0, -1000.0)
	var was_physics_processing: bool = player.is_physics_processing()
	player.set_physics_process(false)
	player.global_position = Vector2(4.5 * terrain.TILE_SIZE.x, terrain.floor_row * terrain.TILE_SIZE.y - 22.0)
	player.velocity = Vector2.ZERO
	var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
	for frame_index: int in range(240):
		await physics_frame
		if not player.is_on_floor():
			player.velocity.y += gravity * player.get_physics_process_delta_time()
		else:
			player.velocity.y = 0.0
		player.velocity.x = 200.0
		player.move_and_slide()
	var passed_both_buildings: bool = player.is_on_floor() and player.global_position.x > 25.5 * terrain.TILE_SIZE.x
	for monster_index: int in range(monsters.size()):
		var monster: Node2D = monsters[monster_index] as Node2D
		monster.global_position = monster_positions[monster_index]
		monster.set_physics_process(true)
	player.velocity = Vector2.ZERO
	player.set_physics_process(was_physics_processing)
	if not passed_both_buildings:
		_fail("Player should move horizontally on the ground under both city buildings.")
		return false
	return true


func _test_capture_biome_repeat_limit() -> bool:
	var storage: Node = (load("res://scripts/pet_storage.gd") as Script).new() as Node
	var save_path: String = "user://biome_selection_smoke_test.json"
	storage.set("save_path", save_path)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261020
	var previous: int = -1
	var streak: int = 0
	var seen: Dictionary = {}
	var failure: String = ""
	for draw_index: int in range(256):
		var selected: int = int(storage.call("select_capture_biome", ProceduralTerrain.RANDOM_BIOMES, rng))
		streak = streak + 1 if selected == previous else 1
		if not ProceduralTerrain.RANDOM_BIOMES.has(selected) or streak > 2:
			failure = "Random capture maps must stay in the pool and never repeat more than twice."
			break
		previous = selected
		seen[selected] = true
		storage.call("load_data")
		if int(storage.get("last_capture_biome")) != selected or int(storage.get("capture_biome_streak")) != streak:
			failure = "Map repeat history must survive restarting or reloading the save."
			break
	if failure.is_empty() and seen.size() != ProceduralTerrain.RANDOM_BIOMES.size():
		failure = "Every map should remain reachable with the repeat limiter enabled."
	for blocked: int in ProceduralTerrain.RANDOM_BIOMES:
		for seed_value: int in range(32):
			storage.set("last_capture_biome", blocked)
			storage.set("capture_biome_streak", 2)
			rng.seed = seed_value
			var selected: int = int(storage.call("select_capture_biome", ProceduralTerrain.RANDOM_BIOMES, rng))
			if selected == blocked or int(storage.get("capture_biome_streak")) != 1:
				failure = "After two repeats, the next capture map must differ and start a new streak."
	var second_repeat_allowed: bool = false
	for seed_value: int in range(32):
		storage.set("last_capture_biome", ProceduralTerrain.Biome.OCEAN)
		storage.set("capture_biome_streak", 1)
		rng.seed = seed_value
		var selected: int = int(storage.call("select_capture_biome", ProceduralTerrain.RANDOM_BIOMES, rng))
		if selected == ProceduralTerrain.Biome.OCEAN:
			second_repeat_allowed = true
	if not second_repeat_allowed:
		failure = "A second consecutive visit should still be permitted by the random picker."
	var legacy_file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"collection": [], "team": []}))
	legacy_file.close()
	storage.call("load_data")
	if int(storage.get("last_capture_biome")) != -1 or int(storage.get("capture_biome_streak")) != 0:
		failure = "Legacy saves should start without a previous map streak."
	storage.set("last_capture_biome", ProceduralTerrain.Biome.OCEAN)
	storage.set("capture_biome_streak", 2)
	storage.call("reset_progress")
	if int(storage.get("last_capture_biome")) != -1 or int(storage.get("capture_biome_streak")) != 0:
		failure = "Resetting progress should also clear capture map history."
	storage.free()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if not failure.is_empty():
		_fail(failure)
		return false
	return true


func _test_responsive_terrain_fit() -> bool:
	for viewport_size: Vector2 in [Vector2(960.0, 540.0), Vector2(1280.0, 720.0), Vector2(1440.0, 600.0), Vector2(960.0, 960.0)]:
		var terrain: ProceduralTerrain = ProceduralTerrain.new()
		terrain._fit_layout_to_viewport(viewport_size)
		var floor_y: float = terrain.floor_row * ProceduralTerrain.TILE_SIZE.y
		if terrain.map_width_cells * ProceduralTerrain.TILE_SIZE.x < viewport_size.x or floor_y < viewport_size.y - ProceduralTerrain.TILE_SIZE.y * 2.0:
			_fail("Terrain should fill viewport %s and keep the floor visible." % viewport_size)
			return false
		if terrain.fall_death_y <= floor_y or not is_equal_approx(floor_y - terrain.water_surface_y, 128.0):
			_fail("Fall bounds and Ocean depth should follow the responsive floor at viewport %s." % viewport_size)
			return false
		terrain.free()
	return true


func _test_biome_scenery() -> bool:
	var required_nodes: Dictionary = {
		ProceduralTerrain.Biome.FOREST: "ForestBackground",
		ProceduralTerrain.Biome.VOLCANO: "VolcanoBackground",
		ProceduralTerrain.Biome.OCEAN: "OceanBackground",
		ProceduralTerrain.Biome.SKY_ISLANDS: "SkyBackground",
		ProceduralTerrain.Biome.CITY: "CityBackground",
	}
	for biome_value: int in range(5):
		var terrain: ProceduralTerrain = ProceduralTerrain.new()
		terrain.randomize_biome_on_spawn = false
		terrain.spawn_monsters_on_ready = false
		terrain.biome = biome_value as ProceduralTerrain.Biome
		root.add_child(terrain)
		await physics_frame
		if not _test_thin_platform_tiles(terrain):
			return false
		if biome_value == ProceduralTerrain.Biome.VOLCANO and not _test_volcano_mountain(terrain):
			return false
		if terrain.get_node_or_null(required_nodes[biome_value]) == null:
			_fail("Every biome should have its distinctive background scenery.")
			return false
		if terrain.get_node_or_null("MapBoundaries") == null:
			_fail("Every biome should have invisible side boundary collisions.")
			return false
		if biome_value == ProceduralTerrain.Biome.FOREST and (terrain.get_child_count() != 2 or terrain.find_child("ForestCanopy", true, false) != null):
			_fail("Forest should only add its background image, without procedural scenery nodes.")
			return false
		if biome_value == ProceduralTerrain.Biome.FOREST:
			var background: Sprite2D = terrain.get_node("ForestBackground") as Sprite2D
			if background.texture.resource_path != "res://assets/Gemini_Generated_Image_qwu7kjqwu7kjqwu7.png" or background.z_index >= -6 or background.scale.x <= 0.0 or background.scale.y <= 0.0:
				_fail("Forest should use the original image as its full-size background.")
				return false
		if biome_value == ProceduralTerrain.Biome.VOLCANO:
			var background: Sprite2D = terrain.get_node("VolcanoBackground") as Sprite2D
			if background.texture.resource_path != "res://assets/ABF30583-BCA8-4478-AD4C-F9A178D7BC59.jpeg" or background.z_index >= -6 or not is_equal_approx(background.scale.x, background.scale.y):
				_fail("Volcano should use the original image as a proportionally scaled background.")
				return false
			if terrain.get_child_count() != 2 or terrain.find_child("VolcanoRidges", true, false) != null or terrain.find_child("DistantEmber", true, false) != null:
				_fail("Volcano should not add procedural scenery over its background image.")
				return false
		if biome_value == ProceduralTerrain.Biome.OCEAN:
			var background: Sprite2D = terrain.get_node("OceanBackground") as Sprite2D
			var horizon_y: float = background.position.y + ProceduralTerrain.OCEAN_BACKGROUND_HORIZON_Y * background.scale.y
			if background.texture.resource_path != "res://assets/25DDF2A9-E0A9-4B77-8CA1-E589A6FF390B.jpeg" or background.z_index >= -6 or not is_equal_approx(background.scale.x, background.scale.y) or absf(horizon_y - terrain.water_surface_y) > 1.0:
				_fail("Ocean should use the original image with its horizon aligned to the water surface.")
				return false
			if terrain.get_child_count() != 2 or terrain.find_child("OceanIslandsFar", true, false) != null or terrain.find_child("Coral", true, false) != null:
				_fail("Ocean should not add procedural scenery over its background image.")
				return false
		if biome_value == ProceduralTerrain.Biome.SKY_ISLANDS:
			var background: Sprite2D = terrain.get_node("SkyBackground") as Sprite2D
			if background.texture.resource_path != "res://assets/(n) 2.png" or background.z_index >= -6 or not is_equal_approx(background.scale.x, background.scale.y):
				_fail("Sky Islands should use the original image, proportionally scaled behind gameplay.")
				return false
			if terrain.get_child_count() != 2 or terrain.find_child("SceneryCloud", true, false) != null or terrain.find_child("SkyIslandsFar", true, false) != null:
				_fail("Sky Islands should not add procedural scenery over its background image.")
				return false
		if biome_value == ProceduralTerrain.Biome.CITY:
			var background: Sprite2D = terrain.get_node("CityBackground") as Sprite2D
			if background.texture.resource_path != "res://assets/c86a3be5-cbc3-4d74-8f0b-f4070d9e3eef.jpg" or background.z_index >= -6 or not is_equal_approx(background.scale.x, background.scale.y):
				_fail("City should use the original image, proportionally scaled behind gameplay.")
				return false
			if terrain.get_child_count() != 2 or terrain.find_child("StreetLamp", true, false) != null or terrain.find_child("OverheadWire", true, false) != null:
				_fail("City should not add procedural scenery over its background image.")
				return false
		if biome_value == ProceduralTerrain.Biome.SKY_ISLANDS and not await _test_sky_layout(terrain):
			return false
		terrain.queue_free()
		await process_frame
	return true


func _test_volcano_mountain(terrain: ProceduralTerrain) -> bool:
	var rows: Dictionary = {}
	for cell: Vector2i in terrain.get_used_cells():
		if terrain.get_cell_alternative_tile(cell) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
			continue
		if not rows.has(cell.y):
			rows[cell.y] = []
		rows[cell.y].append(cell.x)
		var mirrored_cell: Vector2i = Vector2i(terrain.map_width_cells - 1 - cell.x, cell.y)
		if terrain.get_cell_alternative_tile(mirrored_cell) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
			_fail("Volcano platform slopes should mirror each other around the central summit.")
			return false
	if rows.size() < 4:
		_fail("Volcano platforms should form several rising mountain tiers.")
		return false
	var previous_row: int = terrain.floor_row
	var left_edge: int = 0
	var right_edge: int = terrain.map_width_cells - 1
	for row: int in range(terrain.floor_row - 1, 1, -1):
		if not rows.has(row):
			continue
		var columns: Array = rows[row]
		columns.sort()
		if previous_row - row != 2 or columns.front() <= left_edge or columns.back() >= right_edge:
			_fail("Each volcano tier should rise 64 pixels and narrow toward the mountain peak.")
			return false
		previous_row = row
		left_edge = columns.front()
		right_edge = columns.back()
	if right_edge - left_edge != 3 or terrain._lava_areas.is_empty():
		_fail("The volcano should have a narrow summit and retain its lava hazards.")
		return false
	return true


func _test_thin_platform_tiles(terrain: ProceduralTerrain) -> bool:
	var atlas: TileSetAtlasSource = terrain.tile_set.get_source(0) as TileSetAtlasSource
	var image: Image = atlas.texture.get_image()
	var solid_tile_count: int = 2 if terrain.biome == ProceduralTerrain.Biome.VOLCANO else 1
	for atlas_x: int in range(solid_tile_count):
		var solid_color: Color = image.get_pixel(atlas_x * ProceduralTerrain.TILE_SIZE.x, 0)
		var detailed_pixel_count: int = 0
		for pixel_y: int in range(ProceduralTerrain.TILE_SIZE.y):
			for pixel_x: int in range(ProceduralTerrain.TILE_SIZE.x):
				var pixel: Color = image.get_pixel(atlas_x * ProceduralTerrain.TILE_SIZE.x + pixel_x, pixel_y)
				if pixel.a != 1.0 or (terrain.biome != ProceduralTerrain.Biome.VOLCANO or atlas_x == 0) and pixel != solid_color:
					_fail("Ground and wall tiles should form opaque seamless solid blocks in every biome.")
					return false
				if pixel != solid_color:
					detailed_pixel_count += 1
		if terrain.biome == ProceduralTerrain.Biome.VOLCANO and atlas_x == 1 and detailed_pixel_count < 20:
			_fail("Volcano lava blocks should show molten texture instead of a flat fill.")
			return false
	for cell: Vector2i in terrain.get_used_cells():
		if terrain.get_cell_alternative_tile(cell) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
			continue
		var atlas_coords: Vector2i = terrain.get_cell_atlas_coords(cell)
		var data: TileData = terrain.get_cell_tile_data(cell)
		if atlas_coords.y != 1 or data.z_index >= 0 or not data.is_collision_polygon_one_way(1, 0):
			_fail("Floating platforms should use thin tiles drawn behind characters and retain one-way collision.")
			return false
		for point: Vector2 in data.get_collision_polygon_points(1, 0):
			if point.y < -16.0 or point.y > -16.0 + ProceduralTerrain.PLATFORM_THICKNESS:
				_fail("Platform collision should match its thin visible surface.")
				return false
		var tile_origin: Vector2i = atlas_coords * ProceduralTerrain.TILE_SIZE
		for pixel_y: int in range(ProceduralTerrain.PLATFORM_THICKNESS):
			for pixel_x: int in range(ProceduralTerrain.TILE_SIZE.x):
				if image.get_pixel(tile_origin.x + pixel_x, tile_origin.y + pixel_y).a != 1.0:
					_fail("Thin platform surfaces should remain visible and opaque, including Ocean and Sky.")
					return false
		for pixel_y: int in range(ProceduralTerrain.PLATFORM_THICKNESS, ProceduralTerrain.TILE_SIZE.y):
			for pixel_x: int in range(ProceduralTerrain.TILE_SIZE.x):
				if image.get_pixel(tile_origin.x + pixel_x, tile_origin.y + pixel_y).a != 0.0:
					_fail("The space below each thin platform must be transparent.")
					return false
	return true


func _test_sky_layout(terrain: ProceduralTerrain) -> bool:
	var pit_start: int = int((terrain.map_width_cells - ProceduralTerrain.SKY_PIT_WIDTH) / 2)
	for column: int in range(terrain.map_width_cells):
		var in_pit: bool = column >= pit_start and column < pit_start + ProceduralTerrain.SKY_PIT_WIDTH
		for row: int in range(terrain.floor_row, terrain.floor_row + 4):
			var expected_source: int = 0 if not in_pit or row == terrain.floor_row else -1
			if terrain.get_cell_source_id(Vector2i(column, row)) != expected_source:
				_fail("Sky islands should bridge the central pit at ground height and leave the lower pit open.")
				return false
			if in_pit and row == terrain.floor_row and terrain.get_cell_alternative_tile(Vector2i(column, row)) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
				_fail("The horizontal route across the central pit should be a one-way bridge.")
				return false
	for column: int in [10, 20]:
		for row: int in range(terrain.floor_row):
			if terrain.get_cell_source_id(Vector2i(column, row)) != -1:
				_fail("Sky islands should leave open gaps down to the bottom floor.")
				return false
	var spawn_positions: Array[Vector2] = [terrain.get_player_spawn_position()]
	spawn_positions.append_array(terrain._monster_spawns)
	for spawn_position: Vector2 in spawn_positions:
		var support_cell: Vector2i = terrain.local_to_map(spawn_position + Vector2(0.0, 24.0))
		if terrain.get_cell_source_id(support_cell) != 0:
			_fail("Sky character spawns should be supported by island tiles.")
			return false
	var body: CharacterBody2D = CharacterBody2D.new()
	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(20.0, 36.0)
	collision_shape.shape = rectangle
	body.add_child(collision_shape)
	root.add_child(body)
	body.position = Vector2(10.5 * terrain.TILE_SIZE.x, (terrain.floor_row - 4) * terrain.TILE_SIZE.y)
	var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
	for frame_index: int in range(60):
		await physics_frame
		body.velocity.y += gravity * body.get_physics_process_delta_time()
		body.move_and_slide()
	if not body.is_on_floor() or absf(body.position.y - (terrain.floor_row * terrain.TILE_SIZE.y - 18.0)) > 1.0:
		body.queue_free()
		_fail("Falling through a sky gap should land on the bottom floor.")
		return false
	var start_x: float = body.position.x
	for frame_index: int in range(10):
		await physics_frame
		body.velocity = Vector2(-200.0, gravity * body.get_physics_process_delta_time())
		body.move_and_slide()
	var can_walk: bool = body.is_on_floor() and body.position.x < start_x - 20.0
	if not can_walk:
		body.queue_free()
		_fail("Characters should be able to walk along the bottom after falling.")
		return false
	body.position = Vector2((pit_start - 0.5) * terrain.TILE_SIZE.x, terrain.floor_row * terrain.TILE_SIZE.y - 18.0)
	body.collision_mask = 1 | ProceduralTerrain.PLATFORM_COLLISION_MASK
	body.velocity = Vector2.ZERO
	for frame_index: int in range(12):
		await physics_frame
	for frame_index: int in range(90):
		await physics_frame
		body.velocity = Vector2(200.0, gravity * body.get_physics_process_delta_time())
		body.move_and_slide()
	var crossed_pit: bool = body.is_on_floor() and body.position.x > (pit_start + ProceduralTerrain.SKY_PIT_WIDTH + 0.5) * terrain.TILE_SIZE.x
	body.queue_free()
	if not crossed_pit:
		_fail("The ground-level one-way route should let characters cross the sky pit horizontally.")
		return false
	return true


func _test_sky_fall() -> bool:
	var game_scene: PackedScene = load("res://main.tscn")
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	terrain.biome = ProceduralTerrain.Biome.SKY_ISLANDS
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
	var pit_start: int = int((terrain.map_width_cells - ProceduralTerrain.SKY_PIT_WIDTH) / 2)
	var fall_x: float = (pit_start + 6.5) * terrain.TILE_SIZE.x
	player.position = Vector2(fall_x, terrain.floor_row * terrain.TILE_SIZE.y - 22.0)
	player.velocity = Vector2.ZERO
	player.current_hp = 63
	var pet_scene: PackedScene = load("res://scenes/pet.tscn")
	var pet: Pet = pet_scene.instantiate() as Pet
	scene.add_child(pet)
	pet.set_follow_target(player)
	pet.set_physics_process(false)
	pet.attack_timer.stop()
	player.active_pet = pet
	var appeared_above: bool = false
	var requested_drop: bool = false
	for frame_index: int in range(140):
		await physics_frame
		if current_scene != scene:
			_fail("Falling through the sky pit must not kill the Player or leave the scene.")
			return false
		if player.is_on_floor() and not requested_drop:
			Input.action_press("move_down")
			await physics_frame
			Input.action_release("move_down")
			requested_drop = true
		if player.position.y < 0.0:
			appeared_above = true
			break
	if not appeared_above or not is_equal_approx(player.position.x, fall_x) or player.current_hp != 63 or player.active_pet != pet or player._is_dead:
		_fail("Sky pit falls should reappear overhead at the same X without healing, killing or recalling pets.")
		return false
	var top_y: float = player.position.y
	for frame_index: int in range(12):
		await physics_frame
	if player.position.y <= top_y or player.velocity.y <= 0.0:
		_fail("After reappearing in the sky, the Player should continue falling under gravity.")
		return false
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var screenshot_path: String = OS.get_cache_dir().path_join("peast-sky-pit.png")
		image.save_png(screenshot_path)
		print("Screenshot: ", screenshot_path)
	player.set_physics_process(false)
	terrain.biome = ProceduralTerrain.Biome.FOREST
	player.position.y = terrain.fall_death_y + 1.0
	if terrain.wrap_sky_fall(player):
		_fail("Other biomes must not gain the sky fall loop.")
		return false
	scene.queue_free()
	await process_frame
	return true


func _test_forest_climb() -> bool:
	var game_scene: PackedScene = load("res://main.tscn")
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	terrain.biome = ProceduralTerrain.Biome.FOREST
	root.add_child(scene)
	current_scene = scene
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		for frame_index: int in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var screenshot_path: String = OS.get_cache_dir().path_join("peast-forest-background.png")
		image.save_png(screenshot_path)
		print("Screenshot: ", screenshot_path)
	var rows: Dictionary = {}
	var platform_cells: int = 0
	for cell: Vector2i in terrain.get_used_cells():
		if terrain.get_cell_alternative_tile(cell) == ProceduralTerrain.PLATFORM_ALTERNATIVE:
			rows[cell.y] = true
			platform_cells += 1
	var route_starts: Array[int] = []
	for route_start: int in range(3, terrain.map_width_cells - 6, 9):
		route_starts.append(route_start)
	var skipped_route_count: int = int(route_starts.size() / 3)
	var active_route_count: int = route_starts.size() - skipped_route_count
	var tier_count: int = mini(6, int((terrain.floor_row - 2) / 2))
	if platform_cells < active_route_count * tier_count * 3 or platform_cells > active_route_count * tier_count * 5 or rows.size() < 6:
		_fail("Forest should reduce platform routes by one third while retaining six reachable heights.")
		return false
	for column: int in range(terrain.map_width_cells):
		if terrain.get_cell_alternative_tile(Vector2i(column, terrain.floor_row)) != 0:
			_fail("Forest should retain its continuous solid ground route.")
			return false
	for route_index: int in range(route_starts.size()):
		var skipped_before: int = roundi(float(route_index) * skipped_route_count / route_starts.size())
		var skipped_after: int = roundi(float(route_index + 1) * skipped_route_count / route_starts.size())
		if skipped_after > skipped_before:
			var skipped_start: int = route_starts[route_index]
			if terrain.get_cell_alternative_tile(Vector2i(skipped_start + 2, terrain.floor_row - 2)) == ProceduralTerrain.PLATFORM_ALTERNATIVE:
				_fail("The middle forest climbing route should be the one removed.")
				return false
			continue
		var route_start: int = route_starts[route_index]
		var previous_row: int = terrain.floor_row
		var route_tiers: int = 0
		for row: int in range(terrain.floor_row - 1, 1, -1):
			if terrain.get_cell_alternative_tile(Vector2i(route_start + 2, row)) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
				continue
			if previous_row - row > 2:
				_fail("Forest climbing routes should have no step higher than a single jump can reach.")
				return false
			previous_row = row
			route_tiers += 1
		if route_tiers < 6:
			_fail("Every forest climbing route should reach six platform tiers.")
			return false
	var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
	var climb_column: int = 5
	player.position = Vector2((climb_column + 0.5) * terrain.TILE_SIZE.x, terrain.floor_row * terrain.TILE_SIZE.y - 20.0)
	for frame_index: int in range(20):
		await physics_frame
	var feet_offset: float = terrain.floor_row * terrain.TILE_SIZE.y - player.position.y
	var current_row: int = terrain.floor_row
	var summit_row: int = terrain.floor_row
	for row: int in range(2, terrain.floor_row):
		if terrain.get_cell_alternative_tile(Vector2i(climb_column, row)) == ProceduralTerrain.PLATFORM_ALTERNATIVE:
			summit_row = mini(summit_row, row)
	for hop_index: int in range(6):
		if current_row == summit_row:
			break
		var next_row: int = current_row
		for row: int in range(maxi(current_row - 2, 2), current_row):
			if terrain.get_cell_alternative_tile(Vector2i(climb_column, row)) == ProceduralTerrain.PLATFORM_ALTERNATIVE:
				next_row = mini(next_row, row)
		Input.action_press("jump")
		await physics_frame
		await physics_frame
		Input.action_release("jump")
		for frame_index: int in range(55):
			await physics_frame
		if next_row == current_row or not player.is_on_floor() or absf(player.position.y - (next_row * terrain.TILE_SIZE.y - feet_offset)) > 1.0:
			_fail("Player should be able to climb the forest platforms using successive single jumps.")
			return false
		current_row = next_row
	if current_row != summit_row:
		_fail("The forest canopy platforms should be reachable from the ground.")
		return false
	scene.queue_free()
	await process_frame
	return true


func _test_volcano_climb() -> bool:
	var game_scene: PackedScene = load("res://main.tscn")
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	terrain.biome = ProceduralTerrain.Biome.VOLCANO
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
	var tiers: Dictionary = {}
	for cell: Vector2i in terrain.get_used_cells():
		if terrain.get_cell_alternative_tile(cell) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
			continue
		tiers[cell.y] = mini(int(tiers.get(cell.y, terrain.map_width_cells)), cell.x)
	var tier_rows: Array = tiers.keys()
	tier_rows.sort()
	tier_rows.reverse()
	for side: int in [1, -1]:
		var spawn_column: float = 3.5 if side > 0 else terrain.map_width_cells - 3.5
		player.respawn(Vector2(spawn_column * terrain.TILE_SIZE.x, terrain.floor_row * terrain.TILE_SIZE.y - 22.0))
		for frame_index: int in range(20):
			await physics_frame
		var feet_offset: float = terrain.floor_row * terrain.TILE_SIZE.y - player.position.y
		var move_action: String = "move_right" if side > 0 else "move_left"
		for row: int in tier_rows:
			var width: int = 4 if row == tier_rows.back() else 5
			var target_column: float = int(tiers[row]) + width * 0.5
			if side < 0:
				target_column = terrain.map_width_cells - target_column
			var target_x: float = target_column * terrain.TILE_SIZE.x
			Input.action_press("jump")
			for frame_index: int in range(55):
				if (target_x - player.position.x) * side > 3.0:
					Input.action_press(move_action)
				else:
					Input.action_release(move_action)
				await physics_frame
				if frame_index >= 1:
					Input.action_release("jump")
			Input.action_release(move_action)
			if not player.is_on_floor() or absf(player.position.y - (row * terrain.TILE_SIZE.y - feet_offset)) > 1.0:
				_fail("Both volcano slopes should be climbable to the summit with single jumps.")
				return false
		if player.current_hp != player.max_hp:
			_fail("The mountain route should keep the climbing Player above the lava.")
			return false
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var screenshot_path: String = OS.get_cache_dir().path_join("peast-volcano-platforms.png")
		image.save_png(screenshot_path)
		print("Screenshot: ", screenshot_path)
	scene.queue_free()
	await process_frame
	return true


func _test_ocean_platforms() -> bool:
	var game_scene: PackedScene = load("res://main.tscn")
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	terrain.biome = ProceduralTerrain.Biome.OCEAN
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
	for frame_index: int in range(20):
		await physics_frame
	if terrain.water_surface_y < 320.0 or terrain.floor_row * terrain.TILE_SIZE.y - terrain.water_surface_y > 160.0:
		_fail("Ocean should have a reduced water depth rather than filling most of the screen.")
		return false
	if not player.is_on_floor() or player.is_swimming or terrain.is_underwater(player.global_position):
		_fail("Ocean Player should spawn standing on a surface platform, not swimming.")
		return false
	var surface_tiles: int = 0
	var submerged_tiles: int = 0
	for cell: Vector2i in terrain.get_used_cells():
		if terrain.get_cell_alternative_tile(cell) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
			continue
		var platform_y: float = cell.y * terrain.TILE_SIZE.y
		if platform_y < terrain.water_surface_y:
			_fail("Ocean standing platforms should align with the water surface, not float above it.")
			return false
		if platform_y == terrain.water_surface_y:
			surface_tiles += 1
		else:
			submerged_tiles += 1
	if surface_tiles < 8 or surface_tiles > terrain.map_width_cells * 0.6 or submerged_tiles != 0:
		_fail("Ocean should retain spaced surface platforms but have no submerged platforms.")
		return false
	for spawn_position: Vector2 in terrain._monster_spawns:
		if not terrain.is_underwater(spawn_position):
			_fail("Ocean Monsters should still spawn in the reduced water area.")
			return false
		var support_cell: Vector2i = terrain.local_to_map(spawn_position + Vector2(0.0, 24.0))
		if support_cell.y != terrain.floor_row or terrain.get_cell_source_id(support_cell) != 0 or terrain.get_cell_alternative_tile(support_cell) != 0:
			_fail("Ocean Monsters should spawn over the solid seabed after submerged platforms are removed.")
			return false
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var screenshot_path: String = OS.get_cache_dir().path_join("peast-ocean-platforms.png")
		image.save_png(screenshot_path)
		print("Screenshot: ", screenshot_path)
	Input.action_press("move_down")
	await physics_frame
	await physics_frame
	Input.action_release("move_down")
	for frame_index: int in range(40):
		await physics_frame
	if not player.is_swimming or not terrain.is_underwater(player.global_position) or (player.collision_mask & ProceduralTerrain.PLATFORM_COLLISION_MASK) == 0:
		_fail("Player should be able to drop from a dry ocean platform and swim in the remaining water.")
		return false
	scene.queue_free()
	await process_frame
	return true


func _test_player_platforms() -> bool:
	var game_scene: PackedScene = load("res://main.tscn")
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	terrain.biome = ProceduralTerrain.Biome.SKY_ISLANDS
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
	player.position = Vector2(3.5 * terrain.TILE_SIZE.x, terrain.floor_row * terrain.TILE_SIZE.y - 20.0)
	for frame_index: int in range(20):
		await physics_frame
	if not player.is_on_floor():
		_fail("Player should stand on solid ground underneath a platform.")
		return false
	var ground_y: float = player.position.y
	var pet_scene: PackedScene = load("res://scenes/pet.tscn")
	var pet: Pet = pet_scene.instantiate() as Pet
	scene.add_child(pet)
	pet.set_follow_target(player)
	pet.set_physics_process(false)
	pet.attack_timer.stop()
	player.active_pet = pet
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	for frame_index: int in range(6):
		await physics_frame
	var first_jump_velocity: float = player.velocity.y
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	if player.jump_count != 1 or player.velocity.y <= first_jump_velocity:
		_fail("Summoning a pet must not allow a second jump in midair.")
		return false
	var highest_y: float = player.position.y
	for frame_index: int in range(60):
		await physics_frame
		highest_y = minf(highest_y, player.position.y)
		if player.is_on_ceiling():
			_fail("Jumping from directly below a platform must not hit its underside.")
			return false
	var platform_y: float = player.position.y
	if not player.is_on_floor() or highest_y >= (terrain.floor_row - 2) * terrain.TILE_SIZE.y - 10.0 or ground_y - platform_y < 48.0:
		_fail("A single jump should pass through a platform and land on top of it.")
		return false
	Input.action_press("move_down")
	await physics_frame
	await physics_frame
	Input.action_release("move_down")
	for frame_index: int in range(40):
		await physics_frame
	if not player.is_on_floor() or absf(player.position.y - ground_y) > 1.0 or (player.collision_mask & ProceduralTerrain.PLATFORM_COLLISION_MASK) == 0:
		_fail("Down should drop through a platform, land on solid ground and restore platform collisions.")
		return false
	Input.action_press("move_down")
	await physics_frame
	await physics_frame
	Input.action_release("move_down")
	for frame_index: int in range(10):
		await physics_frame
	if not player.is_on_floor() or absf(player.position.y - ground_y) > 1.0:
		_fail("Down must not drop through solid bottom terrain.")
		return false
	terrain._add_platform(3, terrain.floor_row - 4, 4, 0)
	player.position.y = (terrain.floor_row - 4) * terrain.TILE_SIZE.y - 24.0
	player.velocity = Vector2.ZERO
	for frame_index: int in range(20):
		await physics_frame
	Input.action_press("move_down")
	await physics_frame
	await physics_frame
	Input.action_release("move_down")
	for frame_index: int in range(40):
		await physics_frame
	if not player.is_on_floor() or absf(player.position.y - platform_y) > 1.0:
		_fail("Dropping through an upper platform should still land on the next lower platform.")
		return false
	scene.queue_free()
	await process_frame
	return true


func _test_city_passives(city: Node2D) -> bool:
	var pet_scene: PackedScene = load("res://scenes/pet.tscn")
	var cat_scene: PackedScene = load("res://scenes/monsters/city_cat.tscn")
	var car_scene: PackedScene = load("res://scenes/monsters/city_car.tscn")
	var cat: Monster = cat_scene.instantiate() as Monster
	var car: Monster = car_scene.instantiate() as Monster
	city.add_child(cat)
	city.add_child(car)
	cat.set_physics_process(false)
	car.set_physics_process(false)
	cat.set_arena_team("TeamEnemy")
	car.set_arena_team("TeamEnemy")
	cat.current_traits.clear()
	car.current_traits.clear()
	cat.global_position = Vector2(64.0, -1000.0)
	car.global_position = cat.global_position
	var targets: Array[Pet] = []
	for offset: float in [60.0, 120.0]:
		var target: Pet = pet_scene.instantiate() as Pet
		city.add_child(target)
		target.set_physics_process(false)
		target.attack_timer.stop()
		target.set_arena_team("TeamPlayer")
		target.max_hp = 1000
		target.current_hp = 1000
		target.global_position = cat.global_position + Vector2(offset, 0.0)
		targets.append(target)
	for attack_index: int in range(6):
		cat._attack_target(targets[0])
	if cat.city_charge.get("active") or cat.city_charge.get("trigger_count") != 6 or targets[0].status_effects.call("has_effect", "Stun"):
		_fail("Cat must not charge before seven attack/hit events.")
		return false
	cat.take_damage(1, targets[0].global_position)
	if not cat.city_charge.get("active"):
		_fail("A cat should charge after its seventh total attack/hit event.")
		return false
	cat.city_charge.call("_check_hits", cat.global_position, targets[0].global_position)
	if cat.city_charge.get("active") or not targets[0].status_effects.call("has_effect", "Stun"):
		_fail("Cat charge should stun its victim and stop on hit.")
		return false
	var first_hp: int = targets[0].current_hp
	var second_hp: int = targets[1].current_hp
	for attack_index: int in range(4):
		car._attack_target(targets[0])
	if car.city_charge.get("active") or car.city_charge.get("trigger_count") != 4:
		_fail("Car must not charge before its fifth attack.")
		return false
	car._attack_target(targets[0])
	if not car.city_charge.get("active"):
		_fail("Car should charge after its fifth attack.")
		return false
	first_hp = targets[0].current_hp
	second_hp = targets[1].current_hp
	var end_position: Vector2 = car.global_position + Vector2(130.0, 0.0)
	car.city_charge.call("_check_hits", car.global_position, end_position)
	car.city_charge.call("_check_hits", car.global_position, end_position)
	if targets[0].current_hp != first_hp - car.attack_damage or targets[1].current_hp != second_hp - car.attack_damage or not car.city_charge.get("active"):
		_fail("Car must pierce two enemies, damaging each exactly once per charge.")
		return false
	var start_x: float = car.global_position.x
	for step_index: int in range(65):
		car.city_charge.call("step", car.get_physics_process_delta_time())
	if car.city_charge.get("active") or not is_equal_approx(car.global_position.x - start_x, 480.0) or car.collision_mask != (3 | ProceduralTerrain.PLATFORM_COLLISION_MASK):
		_fail("Car must finish at half the map width and restore its collision mask.")
		return false
	var storage_script: Script = load("res://scripts/pet_storage.gd")
	var storage: Node = storage_script.new() as Node
	for source: Monster in [cat, car]:
		var saved: Dictionary = storage.call("_to_saved", source.get_pet_data())
		var collection: Array[Dictionary] = [saved]
		storage.set("collection", collection)
		var runtime: Dictionary = storage.call("get_runtime_pet", 0)
		var captured: Pet = pet_scene.instantiate() as Pet
		city.add_child(captured)
		captured.apply_pet_data(runtime)
		captured.set_physics_process(false)
		captured.attack_timer.stop()
		if captured.charge_style != source.charge_style or captured.charge_trigger_range != source.charge_trigger_range or captured.charge_speed != source.charge_speed:
			_fail("Captured city pets must retain charge passives through save/load.")
			return false
		captured.set_arena_team("TeamPlayer")
		captured.global_position = source.global_position - Vector2(20.0, 0.0)
		source.max_hp = 1000
		source.current_hp = 1000
		if source.charge_style == "Cat":
			for hit_index: int in range(6):
				captured.take_damage(1, source.global_position)
			if captured.city_charge.get("active") or captured.city_charge.get("trigger_count") != 6:
				_fail("Captured cat must not charge before the seventh received hit.")
				return false
			captured.take_damage(1, source.global_position)
			if not captured.city_charge.get("active"):
				_fail("Captured cat should charge on its seventh received hit.")
				return false
			captured.city_charge.call("finish")
		captured._target_monster = source
		var required_attacks: int = 6 if source.charge_style == "Cat" else 4
		for attack_index: int in range(required_attacks):
			captured.call("_on_attack_timer_timeout")
		if captured.city_charge.get("active"):
			_fail("Captured city Pet should wait for its configured charge threshold.")
			return false
		var source_hp_before_trigger: int = source.current_hp
		captured.call("_on_attack_timer_timeout")
		if not captured.city_charge.get("active"):
			_fail("Captured city Pet should charge at its configured attack threshold.")
			return false
		captured.city_charge.call("_check_hits", captured.global_position, source.global_position)
		if source.current_hp != source_hp_before_trigger - captured.attack_damage * 2:
			_fail("The trigger attack and city charge should both damage enemy Monsters.")
			return false
		if source.charge_style == "Cat" and (captured.city_charge.get("active") or not source.status_effects.call("has_effect", "Stun")):
			_fail("Captured cats must stun enemy Monsters and stop on hit.")
			return false
		if source.charge_style == "Car" and not captured.city_charge.get("active"):
			_fail("Captured cars must continue charging after hitting a Monster.")
			return false
		captured.city_charge.call("finish")
		captured.queue_free()
	storage.free()
	for target: Pet in targets:
		target.queue_free()
	cat.queue_free()
	car.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)