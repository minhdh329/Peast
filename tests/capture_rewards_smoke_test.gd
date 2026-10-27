extends SceneTree

const TEST_SAVE_PATH := "user://capture_rewards_smoke_test.json"
var _storage: Node
var _original_save_path: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_storage = root.get_node("PetStorage")
	_original_save_path = str(_storage.get("save_path"))
	_storage.set("save_path", TEST_SAVE_PATH)
	_storage.call("reset_progress")
	_storage.set("gold", 2)
	if float(_storage.get("CAPTURE_SUCCESS_CHANCE")) != 0.5:
		_fail("Capture chance must be fixed at 50%.")
		return
	var scene: Node2D = (load("res://main.tscn") as PackedScene).instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	root.add_child(scene)
	current_scene = scene
	var player: Node2D = scene.get_node("Player") as Node2D
	var slime_scene: PackedScene = load("res://scenes/monsters/forest_slime.tscn")
	var bird_scene: PackedScene = load("res://scenes/monsters/sky_bird.tscn")
	var monsters: Array[Monster] = []
	for monster_scene: PackedScene in [slime_scene, slime_scene, bird_scene]:
		var monster: Monster = terrain.spawn_random_monster(Vector2(700.0, 350.0), monster_scene) as Monster
		monster.set_physics_process(false)
		monsters.append(monster)
	terrain.register_capture_candidate(monsters[0])
	var candidates: Array[Dictionary] = terrain.get("_capture_candidates")
	if candidates.size() != 3:
		_fail("Every actual Monster should be listed once, including separate instances of the same species.")
		return
	var expected_pet: Dictionary = monsters[1].get_pet_data().duplicate(true)
	monsters[0].current_traits.clear()
	monsters[0].die()
	monsters.remove_at(0)
	await process_frame
	var offspring_count: int = 0
	for monster_node: Node in get_nodes_in_group("monsters"):
		var offspring: Monster = monster_node as Monster
		if offspring.split_count == 0:
			continue
		offspring.set_physics_process(false)
		monsters.append(offspring)
		offspring_count += 1
		terrain.register_capture_candidate(offspring)
	if offspring_count != 2 or (terrain.get("_capture_candidates") as Array).size() != 3:
		_fail("Split slime offspring must remain in combat without adding capture options.")
		return
	for candidate: Dictionary in terrain.get("_capture_candidates"):
		if int(candidate.get("split_count", 0)) != 0:
			_fail("Capture candidates must include original Monsters only, never split offspring.")
			return
	if not (_storage.get("collection") as Array).is_empty():
		_fail("Encountered Monsters should not enter the collection before post-battle capture.")
		return
	terrain.set("_monsters_spawned", true)
	terrain.complete_stage(player)
	if bool(terrain.get("_stage_completed")):
		_fail("Capture rewards must not open while Monsters remain in the stage.")
		return
	for monster: Monster in monsters:
		monster.queue_free()
	await process_frame
	player.set("current_hp", 0)
	terrain.complete_stage(player)
	if bool(terrain.get("_stage_completed")):
		_fail("A defeated Player must not unlock the capture screen.")
		return
	player.set("current_hp", 100)
	terrain.complete_stage(player)
	terrain.complete_stage(player)
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/capture_rewards.tscn":
		_fail("Winning a stage should open its capture rewards.")
		return
	var rewards: Node = current_scene
	if (rewards.get("_candidates") as Array).size() != 3 or not (_storage.get("pending_capture_candidates") as Array).is_empty():
		_fail("The reward screen should consume only this stage's encountered Monsters.")
		return
	if (rewards.get("_capture_buttons") as Array).size() != 3:
		_fail("Capture rewards must offer only the original Monsters, not the two split slimes.")
		return
	await process_frame
	await process_frame
	var finish_button: Button = rewards.get("_finish_button") as Button
	if not root.get_visible_rect().encloses(finish_button.get_global_rect()):
		_fail("Finish must remain visible and reachable on the capture screen.")
		return
	var info_buttons: Array = rewards.get("_info_buttons")
	(info_buttons[1] as Button).pressed.emit()
	await process_frame
	var info_overlay: Control = rewards.get("_info_overlay") as Control
	var info_text: RichTextLabel = rewards.get("_info_text") as RichTextLabel
	var expected_details: String = preload("res://scripts/pet_details.gd").build_tooltip(expected_pet)
	if not info_overlay.visible or info_text.text != expected_details:
		_fail("Each Monster's info button should show its full stats and trait descriptions.")
		return
	rewards.call("_try_capture", 1)
	if int(_storage.get("gold")) != 2 or (rewards.get("_attempted") as Array).has(true):
		_fail("Viewing Monster details must not spend gold or allow accidental capture behind the modal.")
		return
	var close_button: Button = rewards.get("_info_close_button") as Button
	if not root.get_visible_rect().encloses(close_button.get_global_rect()) or info_text.size.y <= 0.0:
		_fail("Monster details must leave readable scroll space and an onscreen close button.")
		return
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var info_image: Image = root.get_texture().get_image()
		var info_path: String = OS.get_cache_dir().path_join("peast-capture-monster-info.png")
		info_image.save_png(info_path)
		print("Screenshot: ", info_path)
	rewards.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if info_overlay.visible or current_scene != rewards or bool(rewards.get("_finished")):
		_fail("Android Back should close Monster details without leaving capture rewards.")
		return
	if "--capture-screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var screenshot_path: String = OS.get_cache_dir().path_join("peast-capture-rewards.png")
		image.save_png(screenshot_path)
		print("Screenshot: ", screenshot_path)
	var rng: RandomNumberGenerator = rewards.get("_capture_rng") as RandomNumberGenerator
	rng.seed = _find_seed(false)
	rewards.call("_try_capture", 0)
	rewards.call("_try_capture", 0)
	if int(_storage.get("gold")) != 1 or not (_storage.get("collection") as Array).is_empty():
		_fail("A failed capture must cost one gold and never allow another attempt on that Monster.")
		return
	var capture_buttons: Array = rewards.get("_capture_buttons")
	if (capture_buttons[1] as Button).disabled or not (capture_buttons[1] as Button).text.contains("1 vàng"):
		_fail("One gold should enable an unattempted capture and display its one-gold cost.")
		return
	if not (capture_buttons[0] as Button).disabled:
		_fail("A failed Monster's capture button must stay disabled.")
		return
	(info_buttons[0] as Button).pressed.emit()
	if not info_overlay.visible:
		_fail("Monster information should remain available after a failed capture.")
		return
	close_button.pressed.emit()
	rng.seed = _find_seed(true)
	rewards.call("_try_capture", 1)
	rewards.call("_try_capture", 1)
	if int(_storage.get("gold")) != 0 or (_storage.get("collection") as Array).size() != 1:
		_fail("A successful capture must cost one gold and save that Monster exactly once.")
		return
	var saved_pet: Dictionary = _storage.call("get_runtime_pet", 0) as Dictionary
	for field: String in ["name", "max_hp", "attack_damage", "mount_type", "current_traits", "split_on_death"]:
		if saved_pet.get(field) != expected_pet.get(field):
			_fail("Captured Monster data should retain %s from its actual encounter." % field)
			return
	rewards.call("_try_capture", 2)
	var attempts: Array = rewards.get("_attempted")
	if int(_storage.get("gold")) != 0 or bool(attempts[2]) or not (capture_buttons[2] as Button).disabled:
		_fail("Insufficient gold must not spend money or consume a Monster's capture attempt.")
		return
	_storage.call("load_data")
	if int(_storage.get("gold")) != 0 or (_storage.get("collection") as Array).size() != 1:
		_fail("Gold spent and successful captures should survive reloading the save.")
		return
	rewards.call("_finish")
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/main_menu.tscn":
		_fail("Finish should return to the menu even with unattempted Monsters remaining.")
		return
	_finish(0)


func _find_seed(success: bool) -> int:
	var probe: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(1000):
		probe.seed = seed_value
		if (probe.randf() < 0.5) == success:
			return seed_value
	return 0


func _fail(message: String) -> void:
	push_error(message)
	_finish(1)


func _finish(exit_code: int) -> void:
	if current_scene != null:
		current_scene.queue_free()
	_storage.set("save_path", _original_save_path)
	_storage.call("load_data")
	_storage.set("pending_capture_candidates", [] as Array[Dictionary])
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	if exit_code == 0:
		print("Capture rewards smoke test passed.")
	quit(exit_code)