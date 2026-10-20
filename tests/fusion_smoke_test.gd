extends SceneTree

const TEST_SAVE_PATH := "user://fusion_smoke_test.json"
var _storage: Node
var _live_storage: Node
var _original_live_save_path: String
const UI_SAVE_PATH := "user://fusion_ui_smoke_test.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_storage = (load("res://scripts/pet_storage.gd") as Script).new() as Node
	_storage.set("save_path", TEST_SAVE_PATH)
	seed(20261019)
	if not _test_validation() or not _test_trait_pools() or not _test_removal_and_save():
		_finish(1)
		return
	if not await _test_inventory_fusion_ui():
		_finish(1)
		return
	print("Fusion smoke test passed.")
	_finish(0)


func _make_pet(species: String, traits: Array[String]) -> Dictionary:
	return _storage.call("_to_saved", {
		"name": species,
		"type": species,
		"texture": load("res://assets/pet.png"),
		"sprite_scale": Vector2(2.0, 2.0),
		"max_hp": 100 * (2 if traits.has("DoubleHP") else 1),
		"attack_damage": 10 * (2 if traits.has("DoubleDamage") else 1),
		"current_traits": traits,
		"split_on_death": true,
	}) as Dictionary


func _test_validation() -> bool:
	var collection: Array[Dictionary] = [
		_make_pet("Slime", ["DoubleAttack"]),
		_make_pet("Bird", ["FastMovement"]),
	]
	_storage.set("collection", collection)
	_storage.call("save_data")
	var before: String = JSON.stringify(_storage.get("collection"))
	for indices: Vector2i in [Vector2i(0, 0), Vector2i(-1, 1), Vector2i(0, 2), Vector2i(0, 1)]:
		var result: Dictionary = _storage.call("CombinePets", indices.x, indices.y) as Dictionary
		if not result.is_empty() or JSON.stringify(_storage.get("collection")) != before:
			push_error("Invalid fusion must return an empty Dictionary without modifying inventory.")
			return false
	collection.assign([_make_pet("Slime", []), _make_pet("Slime", [])])
	_storage.set("collection", collection)
	before = JSON.stringify(collection)
	if not (_storage.call("CombinePets", 0, 1) as Dictionary).is_empty() or JSON.stringify(collection) != before:
		push_error("An empty trait pool must be rejected before removing either parent.")
		return false
	return true


func _test_trait_pools() -> bool:
	var all_traits: Array[String] = ["DoubleAttack", "FastMovement", "DoubleHP", "DoubleDamage", "Revive", "Lifesteal", "ExplodeOnDeath"]
	var large_pool_produced_fewer_than_three: bool = false
	for pool_size: int in range(1, all_traits.size() + 1):
		var allowed: Array[String] = []
		for trait_index: int in range(pool_size):
			allowed.append(all_traits[trait_index])
		for trial: int in range(4):
			var traits_a: Array[String] = []
			var traits_b: Array[String] = []
			for trait_index: int in range(pool_size):
				if trait_index % 2 == 0:
					traits_a.append(allowed[trait_index])
				else:
					traits_b.append(allowed[trait_index])
			traits_b.append(allowed[0])
			var parent_a: Dictionary = _make_pet("Slime", traits_a)
			var parent_b: Dictionary = _make_pet("Slime", traits_b)
			parent_a.erase("type")
			parent_b.erase("type")
			var original_parent: Dictionary = parent_a.duplicate(true)
			var collection: Array[Dictionary] = [parent_a, parent_b]
			_storage.set("collection", collection)
			var combined: Dictionary = _storage.call("CombinePets", 0, 1) as Dictionary
			var selected: Array = combined.get("current_traits", [])
			var maximum: int = mini(4, pool_size)
			if combined.is_empty() or selected.size() < 1 or selected.size() > maximum or collection.size() != 1:
				push_error("Fusion trait counts should follow the unique pool size, not the parents' raw trait count.")
				return false
			if pool_size >= 4 and selected.size() < 3:
				large_pool_produced_fewer_than_three = true
			var seen: Array[String] = []
			for trait_name: String in selected:
				if not allowed.has(trait_name) or seen.has(trait_name):
					push_error("Fusion may only choose unique traits from the two parents.")
					return false
				seen.append(trait_name)
			if int(combined["max_hp"]) != 100 * (2 if selected.has("DoubleHP") else 1) or int(combined["attack_damage"]) != 10 * (2 if selected.has("DoubleDamage") else 1):
				push_error("Fusion should remove old baked stat bonuses and apply only the selected DoubleHP/DoubleDamage bonuses.")
				return false
			if parent_a != original_parent or combined["sprite_scale"] != Vector2(2.0, 2.0) or not combined["split_on_death"]:
				push_error("Fusion should deep-copy parent A and preserve its scale and species passives.")
				return false
	if not large_pool_produced_fewer_than_three:
		push_error("Fusion should allow one or two traits even when the unique pool contains four or more.")
		return false
	return true


func _test_removal_and_save() -> bool:
	for reversed_order: bool in [false, true]:
		var collection: Array[Dictionary] = [
			_make_pet("Bird", ["DoubleAttack"]),
			_make_pet("Slime", ["DoubleHP", "Revive"]),
			_make_pet("Jelly", ["DoubleAttack"]),
			_make_pet("Slime", ["DoubleDamage", "FastMovement"]),
			_make_pet("Crab", ["DoubleAttack"]),
		]
		var team: Array[int] = [4]
		var arena: Array[int] = [3, 0, 4, 1, 2]
		_storage.set("collection", collection)
		_storage.set("team", team)
		_storage.set("arena_team_indices", arena)
		_storage.set("mount_pet_index", 2)
		_storage.set("gold", 19)
		var combined: Dictionary = _storage.call("CombinePets", 3 if reversed_order else 1, 1 if reversed_order else 3) as Dictionary
		if combined.is_empty() or collection.size() != 4 or collection[0]["name"] != "Bird" or collection[1]["name"] != "Jelly" or collection[2]["name"] != "Crab" or collection[3]["type"] != "Slime":
			push_error("Fusion must delete the greater parent index first and append the fused Pet last.")
			return false
		_storage.call("load_data")
		if _storage.get("team") != [2] or _storage.get("arena_team_indices") != [0, 2, 1] or int(_storage.get("mount_pet_index")) != 1 or int(_storage.get("gold")) != 19:
			push_error("Fusion should preserve valid loadouts, reindex survivors, and leave gold unchanged.")
			return false
		var loaded: Dictionary = _storage.call("get_runtime_pet", 3) as Dictionary
		if loaded["current_traits"] != combined["current_traits"] or loaded["max_hp"] != combined["max_hp"] or loaded["type"] != "Slime":
			push_error("The fused Pet must survive a save/reload with the same species, traits, and stats.")
			return false
	return true


func _test_inventory_fusion_ui() -> bool:
	_live_storage = root.get_node("PetStorage")
	_original_live_save_path = str(_live_storage.get("save_path"))
	_live_storage.set("save_path", UI_SAVE_PATH)
	_live_storage.call("reset_progress")
	var collection: Array[Dictionary] = [
		_make_pet("Slime", ["DoubleAttack", "Revive"]),
		_make_pet("Slime", ["FastMovement", "DoubleHP"]),
		_make_pet("Bird", ["DoubleDamage"]),
	]
	_live_storage.set("collection", collection)
	var menu: Control = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	menu.call("_open_inventory")
	var fusion_button: Button = menu.get_node("%FusionButton") as Button
	if not fusion_button.is_visible_in_tree():
		push_error("Inventory should provide a visible Fusion button.")
		return false
	fusion_button.pressed.emit()
	await process_frame
	await process_frame
	var screen: Control = menu.get("_fusion_screen") as Control
	if screen == null or screen.scene_file_path != "res://scenes/pet_fusion.tscn" or menu.get_node("%InventoryPanel").visible:
		push_error("The Fusion button should open the dedicated fusion screen.")
		return false
	var combine: Button = screen.get("_combine_button") as Button
	if not combine.disabled:
		push_error("Fusion should be disabled until two Pets are selected.")
		return false
	screen.call("_select_pet", 0)
	var pet_buttons: Array = screen.get("_pet_buttons")
	if not (pet_buttons[0] as Button).is_visible_in_tree() or not (pet_buttons[1] as Button).is_visible_in_tree() or (pet_buttons[2] as Button).is_visible_in_tree():
		push_error("Selecting a Slime should show only Slimes in the fusion roster.")
		return false
	screen.call("_remove_selection", 0)
	if not (pet_buttons[2] as Button).is_visible_in_tree():
		push_error("Clearing the selected slot should restore all species.")
		return false
	screen.call("_select_pet", 2)
	if (pet_buttons[0] as Button).is_visible_in_tree() or (pet_buttons[1] as Button).is_visible_in_tree() or not (pet_buttons[2] as Button).is_visible_in_tree():
		push_error("Selecting another species should update the visible fusion candidates.")
		return false
	screen.call("_select_pet", 2)
	for card: Button in pet_buttons:
		if not card.is_visible_in_tree():
			push_error("Deselecting the last Pet through its card should restore the full roster.")
			return false
	screen.call("_select_pet", 0)
	screen.call("_select_pet", 2)
	if (screen.get("_selected_indices") as Array).size() != 1:
		push_error("Fusion UI should reject selecting a second Pet of a different species.")
		return false
	screen.call("_toggle_details", 0)
	var details: Array = screen.get("_details_labels")
	if not (details[0] as Label).visible:
		push_error("The fusion screen should allow inspecting Pet details.")
		return false
	screen.call("_toggle_details", 0)
	screen.call("_select_pet", 1)
	if combine.disabled:
		push_error("Fusion should become available after selecting two same-species Pets.")
		return false
	await process_frame
	await process_frame
	if not root.get_visible_rect().encloses(combine.get_global_rect()):
		push_error("The fusion confirmation control should remain inside the viewport.")
		return false
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var screenshot_path: String = OS.get_cache_dir().path_join("peast-pet-fusion.png")
		root.get_texture().get_image().save_png(screenshot_path)
		print("Screenshot: ", screenshot_path)
	screen.call("_request_combine")
	var confirmation: ConfirmationDialog = screen.get("_confirm") as ConfirmationDialog
	if not confirmation.visible or (_live_storage.get("collection") as Array).size() != 3:
		push_error("Fusion should request confirmation before consuming either Pet.")
		return false
	screen.call("_back")
	if confirmation.visible or menu.get("_fusion_screen") != screen or (_live_storage.get("collection") as Array).size() != 3:
		push_error("Back from confirmation should cancel without closing fusion or consuming Pets.")
		return false
	screen.call("_request_combine")
	confirmation.hide()
	confirmation.confirmed.emit()
	confirmation.confirmed.emit()
	if (_live_storage.get("collection") as Array).size() != 2 or not (screen.get("_selected_indices") as Array).is_empty() or int(_live_storage.get("gold")) != 3:
		push_error("Confirmed fusion should run only once, reset selection, and leave gold unchanged.")
		return false
	var fused_pet: Dictionary = _live_storage.call("get_runtime_pet", 1) as Dictionary
	var result_screen: Control = screen.get("_result_screen") as Control
	var result_image: TextureRect = screen.get("_result_image") as TextureRect
	var result_details: RichTextLabel = screen.get("_result_details") as RichTextLabel
	var continue_button: Button = screen.get("_result_continue") as Button
	if not result_screen.visible or result_image.texture != fused_pet["texture"] or result_details.text != preload("res://scripts/pet_details.gd").build_tooltip(fused_pet):
		push_error("Successful fusion should show the actual new Monster image, stats, and selected traits on a separate result screen.")
		return false
	screen.call("_select_pet", 0)
	if not (screen.get("_selected_indices") as Array).is_empty():
		push_error("The fusion roster should not accept selections behind the success screen.")
		return false
	await process_frame
	await process_frame
	if not root.get_visible_rect().encloses(continue_button.get_global_rect()) or result_details.size.y <= 0.0:
		push_error("The result should keep Continue onscreen and leave readable scroll space for Monster stats.")
		return false
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var result_path: String = OS.get_cache_dir().path_join("peast-fusion-success.png")
		root.get_texture().get_image().save_png(result_path)
		print("Screenshot: ", result_path)
	continue_button.pressed.emit()
	if result_screen.visible or menu.get("_fusion_screen") != screen:
		push_error("Continue should return to fusion rather than leaving for Inventory.")
		return false
	screen.call("_show_result", fused_pet)
	screen.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if result_screen.visible or menu.get("_fusion_screen") != screen:
		push_error("Android Back should dismiss the success screen before closing fusion.")
		return false
	for card: Button in screen.get("_pet_buttons"):
		if not card.is_visible_in_tree():
			push_error("Completing fusion should clear the species filter for the next pair.")
			return false
	screen.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	await process_frame
	await process_frame
	var grid: GridContainer = menu.get_node("%CollectionGrid") as GridContainer
	if menu.get("_fusion_screen") != null or not menu.get_node("%InventoryPanel").visible or grid.get_child_count() != 2:
		push_error("Returning from fusion should reopen Inventory with the updated collection.")
		return false
	menu.call("_on_play_pressed")
	if fusion_button.visible:
		push_error("The Fusion button should not appear in Play formation.")
		return false
	menu.call("_on_arena_pressed")
	if fusion_button.visible:
		push_error("The Fusion button should not appear in Arena formation.")
		return false
	return true


func _finish(exit_code: int) -> void:
	if current_scene != null:
		current_scene.queue_free()
	if _live_storage != null:
		_live_storage.set("save_path", _original_live_save_path)
		_live_storage.call("load_data")
	if FileAccess.file_exists(UI_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UI_SAVE_PATH))
	_storage.free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	quit(exit_code)