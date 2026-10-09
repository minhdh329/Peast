extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager_script: Script = load("res://scripts/arena_manager.gd") as Script
	var manager: Node2D = manager_script.new() as Node2D
	manager.set("arena_team", [
		_make_pet_data("Pet 1"),
		_make_pet_data("Pet 2"),
		_make_pet_data("Pet 3"),
	])
	root.add_child(manager)
	await process_frame

	var player_team: Array[Node] = get_nodes_in_group("TeamPlayer")
	var enemy_team: Array[Node] = get_nodes_in_group("TeamEnemy")
	if player_team.size() != 3 or enemy_team.size() != 3:
		_fail("ArenaManager should spawn exactly three members on each team.")
		return
	for pet_node: Node in player_team:
		var pet: Pet = pet_node as Pet
		if pet == null or pet._arena_active:
			_fail("Player pets should start idle.")
			return
		pet._refresh_nearest_target()
		if not is_instance_valid(pet._target_monster) or not pet._target_monster.is_in_group("TeamEnemy"):
			_fail("Player pets should only select enemy-team monsters.")
			return
	for monster_node: Node in enemy_team:
		var monster: Monster = monster_node as Monster
		if monster == null or monster._arena_active:
			_fail("Enemy monsters should start idle.")
			return
		if not monster._find_closest_target().is_in_group("TeamPlayer"):
			_fail("Enemy monsters should only select the player team.")
			return
	var fireball_scene: PackedScene = load("res://scenes/fireball.tscn")
	for team_tag: String in ["TeamPlayer", "TeamEnemy"]:
		var shot: FireballProjectile = fireball_scene.instantiate() as FireballProjectile
		root.add_child(shot)
		shot.arena_team = team_tag
		for ally: Node in get_nodes_in_group(team_tag):
			var hp_before: int = int(ally.get("current_hp"))
			shot._on_body_entered(ally as Node2D)
			shot.global_position = (ally as Node2D).global_position
			shot._check_hostile_hit()
			if int(ally.get("current_hp")) != hp_before or shot.is_queued_for_deletion():
				_fail("Allied projectiles must pass through without damage or consumption.")
				return
		shot.free()

	await create_timer(2.1).timeout
	if not manager.get("battle_has_started") or manager.get("activated_combatant_count") != 6:
		_fail("ArenaManager should activate all six combatants after two seconds.")
		return
	var result_overlay: Control = manager.get("_result_overlay")
	var result_label: Label = manager.get("_result_label")
	if result_overlay.visible:
		_fail("Results should remain hidden while both teams are alive.")
		return
	var reviving_pet: Pet = player_team[0] as Pet
	for pet_index: int in range(1, player_team.size()):
		(player_team[pet_index] as Pet).current_hp = 0
	reviving_pet.current_traits = [Monster.TRAIT_REVIVE]
	reviving_pet.current_hp = 1
	reviving_pet.take_damage(1, Vector2.ZERO)
	manager.call("_process", 0.0)
	if not manager.get("_battle_started") or result_overlay.visible:
		_fail("Arena should not decide the result while the Player's last Pet is reviving.")
		return
	reviving_pet.set("_is_reviving", false)
	reviving_pet._revive_available = false
	for pet_node: Node in player_team:
		(pet_node as Pet).current_hp = 100
	var reviving_monster: Monster = enemy_team[0] as Monster
	for monster_index: int in range(1, enemy_team.size()):
		(enemy_team[monster_index] as Monster).current_hp = 0
	reviving_monster.current_traits = [Monster.TRAIT_REVIVE]
	reviving_monster.current_hp = 1
	reviving_monster.take_damage(1, Vector2.ZERO)
	manager.call("_process", 0.0)
	if not manager.get("_battle_started") or result_overlay.visible:
		_fail("Arena should not decide the result while the Enemy's last Monster is reviving.")
		return
	reviving_monster.set("_is_reviving", false)
	reviving_monster.set("_revive_available", false)
	for monster_node: Node in enemy_team:
		(monster_node as Monster).current_hp = 100
	for enemy: Node in enemy_team:
		enemy.set("current_hp", 0)
	manager.call("_process", 0.0)
	if not result_overlay.visible or result_label.text != "CHIẾN THẮNG!":
		_fail("Eliminating the enemy team should display victory.")
		return
	for enemy: Node in enemy_team:
		enemy.set("current_hp", 100)
	for player_pet: Node in player_team:
		player_pet.set("current_hp", 0)
	manager.set("_battle_started", true)
	manager.set("_battle_finished", false)
	manager.call("_process", 0.0)
	if result_label.text != "THUA":
		_fail("Eliminating the player team should display defeat.")
		return
	for enemy: Node in enemy_team:
		enemy.set("current_hp", 0)
	manager.set("_battle_started", true)
	manager.set("_battle_finished", false)
	manager.call("_process", 0.0)
	if result_label.text != "HÒA":
		_fail("Eliminating both teams should display a draw.")
		return
	current_scene = manager
	var return_button: Button = manager.get("_return_button")
	return_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/main_menu.tscn":
		_fail("The return button should open the main menu.")
		return
	print("Arena smoke test passed.")
	quit(0)


func _make_pet_data(pet_name: String) -> Dictionary:
	return {
		"name": pet_name,
		"attack_style": "Melee",
		"texture": load("res://assets/pet.png"),
		"sprite_scale": Vector2.ONE,
		"max_hp": 100,
		"attack_damage": 10,
		"attack_interval": 1.0,
		"attack_range": 38.0,
		"movement_mode": "Ground",
	}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)