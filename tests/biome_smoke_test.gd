extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	if terrain._get_biome_texture() != ProceduralTerrain.CITY_TEXTURE or terrain.get_node_or_null("CitySkyline") == null:
		_fail("City terrain and skyline textures should be present.")
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
	if current_scene == null or current_scene.scene_file_path != "res://scenes/main_menu.tscn":
		_fail("Entering the exit portal should return the player to the main menu.")
		return
	print("City biome smoke test passed.")
	quit(0)


func _test_biome_scenery() -> bool:
	var required_nodes: Dictionary = {
		ProceduralTerrain.Biome.FOREST: "DistantMountains",
		ProceduralTerrain.Biome.VOLCANO: "VolcanoAshMountains",
		ProceduralTerrain.Biome.OCEAN: "OceanSky",
		ProceduralTerrain.Biome.SKY_ISLANDS: "SceneryCloud",
		ProceduralTerrain.Biome.CITY: "CitySkyline",
	}
	for biome_value: int in range(5):
		var terrain: ProceduralTerrain = ProceduralTerrain.new()
		terrain.randomize_biome_on_spawn = false
		terrain.spawn_monsters_on_ready = false
		terrain.biome = biome_value as ProceduralTerrain.Biome
		root.add_child(terrain)
		await physics_frame
		if terrain.get_node_or_null(required_nodes[biome_value]) == null:
			_fail("Every biome should have its distinctive background scenery.")
			return false
		if biome_value == ProceduralTerrain.Biome.FOREST and (terrain.find_child("ForestCanopy", true, false) == null or terrain.get_child_count() < 80):
			_fail("Forest scenery should contain foreground tree canopies.")
			return false
		if biome_value == ProceduralTerrain.Biome.CITY and (terrain.find_child("StreetLamp", true, false) == null or terrain.get_child_count() < 8):
			_fail("City scenery should contain street lamps.")
			return false
		terrain.queue_free()
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
	cat.global_position = Vector2(5000.0, -1000.0)
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
	if car.city_charge.get("active") or not is_equal_approx(car.global_position.x - start_x, 480.0) or car.collision_mask != 3:
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