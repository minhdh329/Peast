extends SceneTree

const PET_SAVE_PATH := "user://arena_smoke_test.json"
var _original_save_path: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var storage: Node = root.get_node("PetStorage")
	_original_save_path = str(storage.get("save_path"))
	storage.set("save_path", PET_SAVE_PATH)
	var arena_map: Node2D = (load("res://scenes/ArenaTest.tscn") as PackedScene).instantiate() as Node2D
	var background: TextureRect = arena_map.get_node("BackgroundLayer/Background") as TextureRect
	var map_name: Label = arena_map.get_node("MapUI/MapName") as Label
	var valid_map: bool = map_name.text == "Đấu trường" and background.texture.resource_path == "res://assets/Gemini_Generated_Image_hkpyxthkpyxthkpy.png" and background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED and background.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and background.anchor_right == 1.0 and background.anchor_bottom == 1.0 and not (arena_map.get_node("FloorVisual") as Polygon2D).visible and not (arena_map.get_node("CenterLine") as Polygon2D).visible
	arena_map.free()
	if not valid_map:
		_fail("Arena should display the Dau truong map name and a full-viewport image background without old overlays.")
		return
	if not await _test_saved_arena_roster():
		return
	if not await _test_play_formation_flow():
		return
	if not await _test_arena_formation_ui():
		return
	if not await _test_auto_assignment():
		return
	var manager_script: Script = load("res://scripts/arena_manager.gd") as Script
	var manager: Node2D = manager_script.new() as Node2D
	var test_team: Array[Dictionary] = [
		_make_pet_data("Pet 1"),
		_make_pet_data("Pet 2"),
		_make_pet_data("Pet 3"),
		_make_pet_data("Pet 4"),
		_make_pet_data("Pet 5"),
	]
	manager.set("arena_team", test_team)
	root.add_child(manager)
	await process_frame

	var player_team: Array[Node] = get_nodes_in_group("TeamPlayer")
	var enemy_team: Array[Node] = get_nodes_in_group("TeamEnemy")
	if player_team.size() != 5 or enemy_team.size() != 5:
		_fail("ArenaManager should spawn exactly five members on each team.")
		return
	for slot_index: int in range(5):
		var player_body: CharacterBody2D = player_team[slot_index] as CharacterBody2D
		var enemy_body: CharacterBody2D = enemy_team[slot_index] as CharacterBody2D
		var player_feet: Vector2 = preload("res://scripts/ground_navigation.gd").feet_for(player_body)
		var enemy_feet: Vector2 = preload("res://scripts/ground_navigation.gd").feet_for(enemy_body)
		if absf(player_feet.y - 448.0) > 0.1 or absf(enemy_feet.y - 448.0) > 0.1:
			_fail("Every Arena Pet and Monster should spawn with its collider feet on the ground.")
			return
		if player_body.position.x >= 480.0 or enemy_body.position.x <= 480.0:
			_fail("Arena teams should spawn on opposite sides of the center line.")
			return
		if slot_index > 0:
			var previous_player: Node2D = player_team[slot_index - 1] as Node2D
			var previous_enemy: Node2D = enemy_team[slot_index - 1] as Node2D
			if player_body.position.x <= previous_player.position.x or enemy_body.position.x >= previous_enemy.position.x:
				_fail("Arena slot 5 should be closest to the opponents and slot 1 furthest away on both teams.")
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
	if not manager.get("battle_has_started") or manager.get("activated_combatant_count") != 10:
		_fail("ArenaManager should activate all ten combatants after two seconds.")
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
	var pet_storage: Node = root.get_node("PetStorage")
	var saved_team_before: Array[int] = []
	saved_team_before.assign(pet_storage.get("team"))
	current_scene = manager
	var return_button: Button = manager.get("_return_button")
	return_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/main_menu.tscn":
		_fail("The return button should open the main menu.")
		return
	var save_file: FileAccess = FileAccess.open(PET_SAVE_PATH, FileAccess.READ)
	if save_file == null:
		_fail("Returning from Arena should persist the regular Pet team.")
		return
	var saved_data: Variant = JSON.parse_string(save_file.get_as_text())
	var saved_team: Array[int] = []
	if saved_data is Dictionary:
		for index: Variant in saved_data.get("team", []):
			saved_team.append(int(index))
	if saved_team != saved_team_before:
		_fail("Arena should save the previous regular team, not replace it with its five-member lineup.")
		return
	print("Arena smoke test passed.")
	_restore_save()
	quit(0)


func _test_saved_arena_roster() -> bool:
	var storage: Node = root.get_node("PetStorage")
	var saved_collection: Array[Dictionary] = []
	saved_collection.assign(storage.get("collection"))
	var saved_team: Array[int] = []
	saved_team.assign(storage.get("team"))
	var saved_arena: Array[int] = []
	saved_arena.assign(storage.get("arena_team_indices"))
	var saved_mount: int = int(storage.get("mount_pet_index"))
	var saved_gold: int = int(storage.get("gold"))
	var collection: Array[Dictionary] = []
	for pet_index: int in range(6):
		collection.append(storage.call("_to_saved", _make_pet_data("Saved Arena %d" % pet_index)) as Dictionary)
	var normal_team: Array[int] = [1]
	var chosen_team: Array[int] = [5, 3, 0, 4, 2]
	storage.set("collection", collection)
	storage.set("team", normal_team)
	storage.set("mount_pet_index", 0)
	var menu: Control = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	menu.call("_on_arena_pressed")
	menu.set("_arena_team_indices", chosen_team)
	menu.call("_start_arena")
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/ArenaTest.tscn":
		_fail("Starting a selected Arena roster should open the Arena scene.")
		return false
	var manager: Node = current_scene.get_node("ArenaManager")
	manager.set("_battle_finished", true)
	if storage.get("arena_team_indices") != chosen_team:
		_fail("Starting Arena should save all five selected collection indices in order.")
		return false
	manager.call("_return_to_main_menu")
	await process_frame
	await process_frame
	storage.call("load_data")
	menu = current_scene as Control
	menu.call("_on_arena_pressed")
	await process_frame
	if menu.get("_arena_team_indices") != chosen_team or storage.get("team") != normal_team or int(storage.get("mount_pet_index")) != 0:
		_fail("Reopening Arena after a save reload should restore the exact roster without changing the fighter or mount.")
		return false
	storage.call("release_pet", 3)
	storage.call("load_data")
	var adjusted_team: Array[int] = [4, 0, 3, 2]
	if storage.get("arena_team_indices") != adjusted_team:
		_fail("Releasing a Pet should remove it from the saved Arena roster and reindex remaining members.")
		return false
	menu.call("_on_arena_pressed")
	var repaired_team: Array[int] = [4, 0, 3, 2, 1]
	if menu.get("_arena_team_indices") != repaired_team:
		_fail("Arena should preserve surviving roster order and fill only the missing slot.")
		return false
	menu.queue_free()
	await process_frame
	storage.set("collection", saved_collection)
	storage.set("team", saved_team)
	storage.set("arena_team_indices", saved_arena)
	storage.set("mount_pet_index", saved_mount)
	storage.set("gold", saved_gold)
	storage.call("save_data")
	return true


func _test_play_formation_flow() -> bool:
	var pet_storage: Node = root.get_node("PetStorage")
	var saved_collection: Array[Dictionary] = []
	saved_collection.assign(pet_storage.get("collection"))
	var saved_team: Array[int] = []
	saved_team.assign(pet_storage.get("team"))
	var saved_mount_index: int = int(pet_storage.get("mount_pet_index"))
	var collection: Array[Dictionary] = []
	for pet_index: int in range(4):
		collection.append(pet_storage.call("_to_saved", _make_pet_data("Play %d" % (pet_index + 1))) as Dictionary)
	var team: Array[int] = [2]
	pet_storage.set("collection", collection)
	pet_storage.set("team", team)
	pet_storage.set("mount_pet_index", 3)

	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn") as PackedScene
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	await process_frame
	menu.call("_open_inventory")
	var team_row: HBoxContainer = menu.get_node("%TeamRow") as HBoxContainer
	var mount_row: HBoxContainer = menu.get_node("%MountRow") as HBoxContainer
	if team_row.visible or mount_row.visible:
		_fail("Inventory should not display team formation controls.")
		return false
	menu.call("_on_collection_card_pressed", 1)
	if pet_storage.get("team") != team:
		_fail("Choosing a collection card in Inventory should not modify the saved team.")
		return false
	menu.call("_close_inventory")
	menu.call("_on_play_pressed")
	await process_frame
	await process_frame
	await process_frame
	var play_start_button: Button = menu.get_node("%PlayStartButton") as Button
	var selected_indices: Array[int] = []
	selected_indices.assign(menu.get("_play_team_indices"))
	if not menu.get_node("%InventoryPanel").visible or not team_row.visible or team_row.get_child_count() != 1 or not mount_row.visible or mount_row.get_child_count() != 1 or not play_start_button.visible:
		_fail("Choosing Play should open separate one-fighter and one-mount slots.")
		return false
	if selected_indices != team or int(menu.get("_play_mount_index")) != 3:
		_fail("The Play screen should restore the saved fighter and mount selections.")
		return false
	var fighter_rect: Rect2 = team_row.get_global_rect()
	var mount_rect: Rect2 = mount_row.get_global_rect()
	var collection_scroll: ScrollContainer = menu.get_node("%CollectionGrid").get_parent() as ScrollContainer
	if absf(fighter_rect.position.y - mount_rect.position.y) > 1.0 or fighter_rect.end.x > mount_rect.position.x or collection_scroll.size.y <= 0.0:
		_fail("Play fighter and mount slots should share one row without overlap and leave space for the collection.")
		return false
	menu.call("_on_collection_card_pressed", 1)
	await process_frame
	selected_indices.assign(menu.get("_play_team_indices"))
	menu.call("_on_mount_card_pressed", 0)
	if selected_indices != [1] or int(menu.get("_play_mount_index")) != 0 or pet_storage.get("team") != team or pet_storage.get("mount_pet_index") != 3:
		_fail("The fighter and distinct mount selections should stay separate and temporary until Play starts.")
		return false
	menu.free()
	await process_frame
	pet_storage.set("collection", saved_collection)
	pet_storage.set("team", saved_team)
	pet_storage.set("mount_pet_index", saved_mount_index)
	return true


func _test_arena_formation_ui() -> bool:
	var pet_storage: Node = root.get_node("PetStorage")
	var saved_arena: Array[int] = []
	saved_arena.assign(pet_storage.get("arena_team_indices"))
	var empty_arena: Array[int] = []
	pet_storage.set("arena_team_indices", empty_arena)
	var saved_collection: Array[Dictionary] = []
	saved_collection.assign(pet_storage.get("collection"))
	var saved_team: Array[int] = []
	saved_team.assign(pet_storage.get("team"))
	var collection: Array[Dictionary] = []
	for pet_index: int in range(6):
		collection.append(pet_storage.call("_to_saved", _make_pet_data("Formation %d" % (pet_index + 1))) as Dictionary)
	var team: Array[int] = [4, 1, 5]
	pet_storage.set("collection", collection)
	pet_storage.set("team", team)

	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn") as PackedScene
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	await process_frame
	menu.call("_on_arena_pressed")
	await process_frame
	var start_button: Button = menu.get_node("%ArenaStartButton") as Button
	var team_row: HBoxContainer = menu.get_node("%TeamRow") as HBoxContainer
	var selected_indices: Array[int] = []
	selected_indices.assign(menu.get("_arena_team_indices"))
	if not menu.get_node("%InventoryPanel").visible or team_row.get_child_count() != 5 or start_button.disabled:
		_fail("Arena 5v5 should open a formation screen with five selected Pet and an enabled start button.")
		return false
	if selected_indices != [4, 1, 5, 0, 2]:
		_fail("Arena formation should seed from the saved team and fill remaining slots from the collection.")
		return false
	for slot_index: int in range(5):
		var card: Button = team_row.get_child(slot_index).get_child(0) as Button
		if card.text.begins_with("%d. " % (slot_index + 1)):
			_fail("Arena formation cards should not display slot numbers.")
			return false
	var first_slot_arrows: HBoxContainer = team_row.get_child(0).get_child(1) as HBoxContainer
	(first_slot_arrows.get_child(1) as Button).pressed.emit()
	selected_indices.assign(menu.get("_arena_team_indices"))
	if selected_indices != [1, 4, 5, 0, 2]:
		_fail("Arena formation arrows should change the combat order.")
		return false
	menu.call("_on_collection_card_pressed", 0)
	if not start_button.disabled:
		_fail("Arena should require five selected Pet before enabling the start button.")
		return false
	var empty_slot: Control = menu.call("_create_team_slot", 4) as Control
	var empty_text: String = (empty_slot.get_child(0) as Button).text
	empty_slot.free()
	if empty_text != "(trống)":
		_fail("Empty formation slots should not display slot numbers.")
		return false
	menu.call("_on_collection_card_pressed", 3)
	selected_indices.assign(menu.get("_arena_team_indices"))
	if selected_indices != [1, 4, 5, 2, 3] or start_button.disabled or pet_storage.get("team") != team:
		_fail("Arena selection should allow changing the lineup without changing the saved regular team.")
		return false

	menu.free()
	var arena_lineup: Array[Dictionary] = []
	for collection_index: int in selected_indices:
		arena_lineup.append(pet_storage.call("get_runtime_pet", collection_index) as Dictionary)
	pet_storage.set("arena_lineup", arena_lineup)
	var manager_script: Script = load("res://scripts/arena_manager.gd") as Script
	var manager: Node2D = manager_script.new() as Node2D
	root.add_child(manager)
	await process_frame
	var assigned_names: Array[String] = []
	for pet_data: Dictionary in manager.get("arena_team"):
		assigned_names.append(str(pet_data["name"]))
	if assigned_names != ["Formation 2", "Formation 5", "Formation 6", "Formation 3", "Formation 4"] or not (pet_storage.get("arena_lineup") as Array).is_empty():
		_fail("ArenaManager should consume the selected lineup in order without leaving stale selection data.")
		return false
	manager.queue_free()
	await process_frame
	pet_storage.set("collection", saved_collection)
	pet_storage.set("team", saved_team)
	pet_storage.set("arena_team_indices", saved_arena)
	return true


func _test_auto_assignment() -> bool:
	var pet_storage: Node = root.get_node("PetStorage")
	var saved_collection: Array[Dictionary] = []
	saved_collection.assign(pet_storage.get("collection"))
	var saved_team: Array[int] = []
	saved_team.assign(pet_storage.get("team"))
	var collection: Array[Dictionary] = []
	var team: Array[int] = []
	for pet_index: int in range(6):
		var pet_data: Dictionary = _make_pet_data("Roster %d" % (pet_index + 1))
		collection.append(pet_storage.call("_to_saved", pet_data) as Dictionary)
	pet_storage.set("collection", collection)
	team.assign([4, 1, 5])
	pet_storage.set("team", team)
	var manager_script: Script = load("res://scripts/arena_manager.gd") as Script
	var automatic_manager: Node2D = manager_script.new() as Node2D
	root.add_child(automatic_manager)
	await process_frame
	var expected_names: Array[String] = ["Roster 5", "Roster 2", "Roster 6", "Roster 1", "Roster 3"]
	var assigned_names: Array[String] = []
	for pet_data: Dictionary in automatic_manager.get("arena_team"):
		assigned_names.append(str(pet_data["name"]))
	if assigned_names != expected_names or get_nodes_in_group("TeamPlayer").size() != 5 or get_nodes_in_group("TeamEnemy").size() != 5:
		_fail("Entering Arena should preserve the selected lineup and automatically fill five distinct pets from the collection.")
		return false
	automatic_manager.queue_free()
	await process_frame
	collection = []
	team = []
	for pet_index: int in range(4):
		var pet_data: Dictionary = _make_pet_data("Incomplete %d" % (pet_index + 1))
		collection.append(pet_storage.call("_to_saved", pet_data) as Dictionary)
	pet_storage.set("collection", collection)
	team.assign([0, 1, 2])
	pet_storage.set("team", team)
	var incomplete_manager: Node2D = manager_script.new() as Node2D
	root.add_child(incomplete_manager)
	await process_frame
	var incomplete_overlay: Control = incomplete_manager.get("_result_overlay") as Control
	var incomplete_label: Label = incomplete_manager.get("_result_label") as Label
	if incomplete_manager.get("_battle_started") or not incomplete_overlay.visible or not incomplete_label.text.contains("5") or not get_nodes_in_group("TeamPlayer").is_empty():
		_fail("Arena should explain that five captured pets are required instead of starting an incomplete match.")
		return false
	incomplete_manager.queue_free()
	await process_frame
	pet_storage.set("collection", saved_collection)
	pet_storage.set("team", saved_team)
	return true


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
	_restore_save()
	quit(1)


func _restore_save() -> void:
	var storage: Node = root.get_node("PetStorage")
	storage.set("save_path", _original_save_path)
	storage.call("load_data")
	if FileAccess.file_exists(PET_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PET_SAVE_PATH))