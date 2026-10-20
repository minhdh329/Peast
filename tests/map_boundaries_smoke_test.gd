extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for biome_value: int in range(5):
		var world: Node2D = Node2D.new()
		root.add_child(world)
		current_scene = world
		var terrain: ProceduralTerrain = ProceduralTerrain.new()
		terrain.randomize_biome_on_spawn = false
		terrain.spawn_monsters_on_ready = false
		terrain.biome = biome_value as ProceduralTerrain.Biome
		world.add_child(terrain)
		var width: float = terrain.map_width_cells * ProceduralTerrain.TILE_SIZE.x
		if terrain.get_node_or_null("MapBoundaries") == null:
			_fail("Every biome must have invisible side boundaries.")
			return
		for row: int in range(terrain.floor_row):
			if terrain.get_cell_source_id(Vector2i(0, row)) != -1 or terrain.get_cell_source_id(Vector2i(terrain.map_width_cells - 1, row)) != -1:
				_fail("Visible block walls must be removed from the biome edges.")
				return
		if not await _test_actor_edges(world, width):
			return
		world.queue_free()
		await process_frame

	var arena: Node2D = (load("res://scenes/ArenaTest.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	var manager: Node2D = arena.get_node("ArenaManager") as Node2D
	manager.set_process(false)
	manager.set("_battle_finished", true)
	for team: String in ["TeamPlayer", "TeamEnemy"]:
		for actor: Node in get_nodes_in_group(team):
			actor.queue_free()
	await process_frame
	if manager.get_node_or_null("MapBoundaries") == null or not await _test_actor_edges(arena, 960.0):
		_fail("Arena should prevent combatants escaping either edge.")
		return
	arena.queue_free()
	await process_frame
	print("Map boundaries smoke test passed.")
	quit(0)


func _test_actor_edges(world: Node2D, width: float) -> bool:
	var game: Node2D = (load("res://main.tscn") as PackedScene).instantiate() as Node2D
	var player: CharacterBody2D = game.get_node("Player") as CharacterBody2D
	game.remove_child(player)
	game.free()
	world.add_child(player)
	player.set_physics_process(false)
	var monster: Monster = (load("res://scenes/monsters/sky_bird.tscn") as PackedScene).instantiate() as Monster
	monster.set_arena_team("TeamEnemy")
	world.add_child(monster)
	monster.set_physics_process(false)
	var pet: Pet = (load("res://scenes/pet.tscn") as PackedScene).instantiate() as Pet
	pet.set_arena_team("TeamPlayer")
	world.add_child(pet)
	pet.apply_pet_data(monster.get_pet_data())
	pet.set_physics_process(false)
	pet.attack_timer.stop()
	var actors: Array[CharacterBody2D] = [player, monster, pet]
	await physics_frame
	await physics_frame
	for actor: CharacterBody2D in actors:
		for height: float in [-10000.0, -100.0, 300.0]:
			for direction: float in [-1.0, 1.0]:
				actor.global_position = Vector2(48.0 if direction < 0.0 else width - 48.0, height)
				actor.velocity = Vector2.ZERO
				var collision: KinematicCollision2D = actor.move_and_collide(Vector2(direction * 2000.0, 0.0))
				if collision == null or not collision.get_collider().name == "MapBoundaries":
					_fail("%s should physically collide with the invisible edge at height %s." % [actor.name, height])
					return false
				if actor.global_position.x <= 0.0 or actor.global_position.x >= width:
					_fail("Player, Monster, and Pet bodies must remain inside the map during fast movement.")
					return false
	for actor: CharacterBody2D in actors:
		actor.queue_free()
	await process_frame
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)