extends SceneTree


class Target extends CharacterBody2D:
	var hp: int = 10000

	func take_damage(amount: int, source: Vector2, effect_type: String = "", effect_chance: float = 1.0, is_over_time: bool = false) -> void:
		hp -= amount

	func is_alive() -> bool:
		return hp > 0

	func body_radius() -> float:
		return 12.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	var terrain: ProceduralTerrain = ProceduralTerrain.new()
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	world.add_child(terrain)
	terrain.clear()
	terrain._generate_floor_and_walls(0)
	terrain._add_platform(3, terrain.floor_row - 2, 5, 0)
	var target: Target = Target.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	target.add_child(shape)
	target.collision_layer = 2
	target.collision_mask = 0
	target.add_to_group("player")
	world.add_child(target)
	target.position = Vector2(6.5 * terrain.TILE_SIZE.x, (terrain.floor_row - 2) * terrain.TILE_SIZE.y - 12.0)
	var monster_scene: PackedScene = load("res://scenes/monster.tscn")
	var monster: Monster = monster_scene.instantiate() as Monster
	world.add_child(monster)
	monster.current_traits.clear()
	monster.attack_style = "Melee"
	monster.position = Vector2(4.5 * terrain.TILE_SIZE.x, terrain.floor_row * terrain.TILE_SIZE.y - 18.0)
	var ground_y: float = monster.position.y
	var highest_y: float = ground_y
	for frame_index: int in range(180):
		await physics_frame
		highest_y = minf(highest_y, monster.position.y)
		if target.hp < 10000:
			break
	if highest_y > ground_y - 32.0 or target.hp == 10000:
		_fail("A grounded melee Monster should jump onto a platform to reach a detected enemy: state=%s, position=%s, highest_y=%s, hp=%s, target=%s." % [monster.state, monster.position, highest_y, target.hp, monster._find_closest_target()])
		return
	world.queue_free()
	await process_frame
	if not await _test_multi_level_chase(false):
		return
	if not await _test_multi_level_chase(true):
		return
	if not await _test_multi_level_chase(false, true):
		return
	if not await _test_low_obstacle():
		return
	if not await _test_city_routes():
		return
	if not await _test_city_routes(true):
		return
	print("Monster navigation smoke test passed.")
	quit(0)


func _make_target(world: Node2D, position: Vector2) -> Target:
	var target: Target = Target.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	target.add_child(shape)
	target.collision_layer = 2
	target.collision_mask = 0
	target.add_to_group("TeamEnemy")
	target.add_to_group("monsters")
	world.add_child(target)
	target.position = position
	return target


func _test_multi_level_chase(use_pet: bool, ranged: bool = false) -> bool:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	var terrain: ProceduralTerrain = ProceduralTerrain.new()
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	world.add_child(terrain)
	terrain.clear()
	terrain._generate_floor_and_walls(0)
	terrain._add_platform(3, terrain.floor_row - 2, 5, 0)
	terrain._add_platform(7, terrain.floor_row - 4, 5, 0)
	terrain._add_platform(11, terrain.floor_row - 6, 5, 0)
	var target: Target = _make_target(world, Vector2(14.5 * 32.0, (terrain.floor_row - 6) * 32.0 - 12.0))
	var distant: Target = _make_target(world, Vector2(28.5 * 32.0, terrain.floor_row * 32.0 - 12.0))
	var actor: CharacterBody2D
	if use_pet:
		var pet_scene: PackedScene = load("res://scenes/pet.tscn")
		var pet: Pet = pet_scene.instantiate() as Pet
		pet.set_arena_team("TeamPlayer")
		world.add_child(pet)
		pet.apply_pet_data({
			"attack_style": "Melee", "texture": load("res://assets/pet.png"),
			"sprite_scale": Vector2.ONE, "max_hp": 1000, "attack_damage": 5,
			"attack_interval": 0.15, "movement_mode": "Ground",
		})
		actor = pet
	else:
		var monster_scene: PackedScene = load("res://scenes/monster.tscn")
		var monster: Monster = monster_scene.instantiate() as Monster
		monster.set_arena_team("TeamPlayer")
		world.add_child(monster)
		monster.current_traits.clear()
		monster.attack_style = "Ranged" if ranged else "Melee"
		monster.ranged_attack_range = 32.0 if ranged else 200.0
		monster.state = Monster.State.CHASE
		monster.attack_interval = 0.15
		actor = monster
	actor.position = Vector2(4.5 * 32.0, terrain.floor_row * 32.0 - 18.0)
	var highest_y: float = actor.position.y
	for frame_index: int in range(600):
		await physics_frame
		highest_y = minf(highest_y, actor.position.y)
		if target.hp < 10000:
			break
	if target.hp == 10000 or highest_y > (terrain.floor_row - 6) * 32.0 or distant.hp != 10000:
		_fail("%s should route via three platform tiers to attack the nearest enemy: position=%s, highest_y=%s." % ["Pet" if use_pet else "Monster", actor.position, highest_y])
		return false
	target.position = Vector2(7.5 * 32.0, terrain.floor_row * 32.0 - 12.0)
	var previous_hp: int = target.hp
	var descended: bool = false
	for frame_index: int in range(420):
		await physics_frame
		if actor._ground_navigation.feet_for(actor).y > (terrain.floor_row - 1) * 32.0:
			descended = true
		if target.hp < previous_hp and descended and (actor.collision_mask & ProceduralTerrain.PLATFORM_COLLISION_MASK) != 0:
			break
	if not descended or target.hp == previous_hp or (actor.collision_mask & ProceduralTerrain.PLATFORM_COLLISION_MASK) == 0:
		_fail("%s should descend through platforms to follow a moved enemy and restore platform collisions: position=%s, hp=%s, previous_hp=%s, mask=%s, drop_y=%s, air_target=%s." % ["Pet" if use_pet else "Monster", actor.position, target.hp, previous_hp, actor.collision_mask, actor._ground_navigation._drop_y, actor._ground_navigation._air_target])
		return false
	target.position.x = 27.5 * 32.0
	distant.position = actor.position + Vector2(32.0, 0.0)
	for frame_index: int in range(90):
		await physics_frame
		if distant.hp < 10000:
			break
	if distant.hp == 10000:
		_fail("Grounded actors should retarget a closer living enemy as enemy positions change.")
		return false
	world.queue_free()
	await process_frame
	return true


func _test_low_obstacle() -> bool:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	var terrain: ProceduralTerrain = ProceduralTerrain.new()
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	world.add_child(terrain)
	terrain.clear()
	terrain._generate_floor_and_walls(0)
	for row: int in range(terrain.floor_row - 2, terrain.floor_row):
		terrain._add_platform(6, row, 2, 0, false)
	var target: Target = _make_target(world, Vector2(10.5 * 32.0, terrain.floor_row * 32.0 - 12.0))
	var monster_scene: PackedScene = load("res://scenes/monster.tscn")
	var monster: Monster = monster_scene.instantiate() as Monster
	monster.set_arena_team("TeamPlayer")
	world.add_child(monster)
	monster.current_traits.clear()
	monster.state = Monster.State.CHASE
	monster.position = Vector2(4.5 * 32.0, terrain.floor_row * 32.0 - 18.0)
	for frame_index: int in range(480):
		await physics_frame
		if target.hp < 10000:
			break
	if target.hp == 10000 or monster.position.x < 8 * 32.0:
		var navigator = monster._ground_navigation
		var start_id: int = navigator._graph.get_closest_point(navigator.feet_for(monster))
		var end_id: int = navigator._graph.get_closest_point(navigator.feet_for(target))
		_fail("A melee Monster should jump over a low solid obstacle rather than run into its wall: position=%s, speed=%s, path=%s." % [monster.position, monster.movement_speed, navigator._graph.get_id_path(start_id, end_id, true)])
		return false
	world.queue_free()
	await process_frame
	return true


func _test_city_routes(use_pet: bool = false) -> bool:
	var routes: Array[Array] = [
		[Vector2(4.5, 0), Vector2(10.5, -5)],
		[Vector2(10.5, -5), Vector2(20.5, -6)],
		[Vector2(28.5, 0), Vector2(20.5, -6)],
		[Vector2(20.5, -6), Vector2(4.5, 0)],
	]
	for route: Array in routes:
		var world: Node2D = Node2D.new()
		root.add_child(world)
		current_scene = world
		var terrain: ProceduralTerrain = ProceduralTerrain.new()
		terrain.randomize_biome_on_spawn = false
		terrain.spawn_monsters_on_ready = false
		terrain.biome = ProceduralTerrain.Biome.CITY
		world.add_child(terrain)
		var start_cell: Vector2 = route[0] as Vector2
		var target_cell: Vector2 = route[1] as Vector2
		var target_position: Vector2 = Vector2(target_cell.x * 32.0, (terrain.floor_row + int(target_cell.y)) * 32.0 - 12.0)
		var target: Target = _make_target(world, target_position)
		var actor: CharacterBody2D
		if use_pet:
			var pet_scene: PackedScene = load("res://scenes/pet.tscn")
			var pet: Pet = pet_scene.instantiate() as Pet
			pet.set_arena_team("TeamPlayer")
			world.add_child(pet)
			pet.apply_pet_data({
				"attack_style": "Melee", "texture": load("res://assets/pet.png"),
				"sprite_scale": Vector2.ONE, "max_hp": 1000, "attack_damage": 5,
				"attack_interval": 0.15, "movement_mode": "Ground",
			})
			pet.melee_move_speed = 70.0
			actor = pet
		else:
			var monster_scene: PackedScene = load("res://scenes/monster.tscn")
			var monster: Monster = monster_scene.instantiate() as Monster
			monster.set_arena_team("TeamPlayer")
			world.add_child(monster)
			monster.current_traits.clear()
			monster.movement_speed = 70.0
			monster.state = Monster.State.CHASE
			actor = monster
		actor.position = Vector2(start_cell.x * 32.0, (terrain.floor_row + int(start_cell.y)) * 32.0 - (12.0 if use_pet else 18.0))
		for frame_index: int in range(720):
			await physics_frame
			if target.hp < 10000:
				break
		if target.hp == 10000:
			var navigator = actor._ground_navigation
			var start_id: int = navigator._graph.get_closest_point(navigator.feet_for(actor))
			var end_id: int = navigator._graph.get_closest_point(navigator.feet_for(target))
			_fail("City %s should reach route %s: position=%s, path=%s, air_target=%s." % ["Pet" if use_pet else "Monster", route, actor.position, navigator._graph.get_id_path(start_id, end_id, true), navigator._air_target])
			return false
		world.queue_free()
		await process_frame
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)