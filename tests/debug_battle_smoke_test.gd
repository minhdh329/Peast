extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var storage: Node = root.get_node("PetStorage")
	var inventory_before: Array = storage.get("collection").duplicate(true)
	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	(menu.get_node("MenuCenter/VBoxContainer/DebugButton") as Button).pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/DebugBattle.tscn":
		_fail("Main menu DEBUG button should open the debug sandbox.")
		return
	var debug: Node2D = current_scene as Node2D
	if not _controls_fit(debug):
		_fail("DEBUG controls should fit inside the 960x540 viewport.")
		return
	if debug.find_children("*", "OptionButton", true, false).size() != 3:
		_fail("DEBUG should keep only map, Monster species and team selectors.")
		return
	var team_choice: OptionButton = debug.get("_team_choice")
	for team_index: int in range(2):
		debug.call("clear_battle")
		await process_frame
		team_choice.select(team_index)
		team_choice.item_selected.emit(team_index)
		(debug.get("_species_choice") as OptionButton).select(1)
		debug.call("_on_spawn_pressed")
		var tag: String = "TeamPlayer" if team_index == 0 else "TeamEnemy"
		var spawned: Node = get_nodes_in_group(tag)[0]
		if team_index == 0 and not spawned is Pet:
			_fail("TeamPlayer must spawn the selected species as a Pet.")
			return
		if team_index == 1 and not spawned is Monster:
			_fail("TeamEnemy must spawn the selected species as a Monster.")
			return
	debug.call("clear_battle")
	await process_frame
	for biome_index: int in range(5):
		(debug.get("_map_choice") as OptionButton).select(biome_index)
		debug.call("_load_map", biome_index)
		await process_frame
		var terrain: ProceduralTerrain = debug.get("terrain") as ProceduralTerrain
		if int(terrain.biome) != biome_index or terrain.spawn_monsters_on_ready or not debug.call("_actors").is_empty():
			_fail("DEBUG map should match the selection and start with no automatic spawns.")
			return
	for species_index: int in range(10):
		debug.call("clear_battle")
		await process_frame
		var monster: Monster = debug.call("spawn_unit", species_index, false, 1, Vector2(600.0, 300.0), false) as Monster
		var pet: Pet = debug.call("spawn_unit", species_index, true, 0, Vector2(300.0, 300.0), false) as Pet
		if monster == null or pet == null or not monster.is_in_group("TeamEnemy") or not pet.is_in_group("TeamPlayer"):
			_fail("DEBUG must spawn Monster/Pet with the selected teams for all ten species.")
			return
		if not monster.current_traits.is_empty() or not pet.current_traits.is_empty() or monster._arena_active or pet._arena_active:
			_fail("Baseline DEBUG actors should start idle without random traits.")
			return
		pet._refresh_nearest_target()
		if pet._target_monster != monster or monster._find_closest_target() != pet:
			_fail("DEBUG actors should select only the opposite team.")
			return
		debug.call("start_battle")
		if not debug.get("battle_running") or not pet._arena_active or not monster._arena_active:
			_fail("Start should activate both teams.")
			return
	debug.call("clear_battle")
	await process_frame
	var randomized: Monster = debug.call("spawn_unit", 0, false, 0, Vector2(200.0, 300.0), true) as Monster
	if randomized.current_traits.size() < 1 or randomized.current_traits.size() > 4:
		_fail("Random trait option should generate one to four traits.")
		return
	debug.call("clear_battle")
	await process_frame
	var left_pet: Pet = debug.call("spawn_unit", 1, true, 0, Vector2(300.0, 300.0), false) as Pet
	var right_pet: Pet = debug.call("spawn_unit", 1, true, 1, Vector2(340.0, 300.0), false) as Pet
	left_pet._refresh_nearest_target()
	if left_pet._target_monster != right_pet:
		_fail("Pet-vs-Pet targeting must work across teams.")
		return
	var fireball_scene: PackedScene = load("res://scenes/fireball.tscn")
	var shot: FireballProjectile = fireball_scene.instantiate() as FireballProjectile
	debug.add_child(shot)
	shot.arena_team = "TeamPlayer"
	shot.global_position = right_pet.global_position
	shot.effect_type = "Poison"
	shot._physics_process(0.0)
	if not right_pet.status_effects.call("has_effect", "Poison") or left_pet.status_effects.call("has_effect", "Poison"):
		_fail("Pet projectiles should poison opposite-team Pets, not allies.")
		return
	debug.call("start_battle")
	debug.call("_toggle_pause")
	if not paused:
		_fail("Pause should freeze simulation.")
		return
	debug.call("_toggle_pause")
	if paused:
		_fail("Resume should unpause simulation.")
		return
	right_pet.current_hp = 0
	debug.call("_process", 0.0)
	if debug.get("battle_running") or debug.get("_result") != "TeamPlayer thắng":
		_fail("DEBUG should report the remaining team as winner.")
		return
	debug.call("clear_battle")
	await process_frame
	if not debug.call("_actors").is_empty() or debug.get("battle_running"):
		_fail("Clear should remove all actors and reset battle state.")
		return
	if storage.get("collection") != inventory_before:
		_fail("DEBUG must not change the player's Pet inventory.")
		return
	debug.call("_return_to_menu")
	await process_frame
	await process_frame
	if current_scene.scene_file_path != "res://scenes/main_menu.tscn":
		_fail("DEBUG return button should open the main menu.")
		return
	print("Debug battle smoke test passed.")
	quit(0)


func _fail(message: String) -> void:
	paused = false
	push_error(message)
	quit(1)


func _controls_fit(node: Node) -> bool:
	if node is Control and (node is Button or node is SpinBox):
		var rect: Rect2 = (node as Control).get_global_rect()
		if rect.position.x < 0.0 or rect.end.x > 960.0 or rect.end.y > 540.0:
			return false
	for child: Node in node.get_children():
		if not _controls_fit(child):
			return false
	return true