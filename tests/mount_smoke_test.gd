extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not InputMap.has_action("interact"):
		_fail("The interact action should be configured for mounting.")
		return
	var interact_bound_to_r: bool = false
	for event: InputEvent in InputMap.action_get_events("interact"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_R:
			interact_bound_to_r = true
	if not interact_bound_to_r:
		_fail("The interact action should be bound to the R key.")
		return
	if not await _test_mount_metadata():
		return
	var game_scene: PackedScene = load("res://main.tscn") as PackedScene
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	root.add_child(scene)
	current_scene = scene
	var player: Node = scene.get_node("Player")
	var hotbar: Node = scene.get_node("HotBar")
	if hotbar.get("_slots").size() != 1:
		_fail("Normal gameplay should provide only one combat hotbar slot.")
		return
	for frame_index: int in range(20):
		await physics_frame

	if not await _test_mount_type(player, 0):
		return
	if not await _test_mount_type(player, 1):
		return
	if not await _test_mount_type(player, 2):
		return
	if not await _test_swim_mount_in_water(scene, terrain, player):
		return

	scene.queue_free()
	await process_frame
	print("Mount smoke test passed.")
	quit(0)


func _test_mount_metadata() -> bool:
	var fixtures: Array[Dictionary] = [
		{"path": "res://scenes/monsters/forest_slime.tscn", "mount_type": 0},
		{"path": "res://scenes/monsters/sky_bird.tscn", "mount_type": 1},
		{"path": "res://scenes/monsters/ocean_crab.tscn", "mount_type": 2},
	]
	var pet_storage: Node = root.get_node("PetStorage")
	var saved_collection: Array[Dictionary] = []
	saved_collection.assign(pet_storage.get("collection"))
	for fixture: Dictionary in fixtures:
		var monster: Monster = (load(str(fixture["path"])) as PackedScene).instantiate() as Monster
		root.add_child(monster)
		await process_frame
		var monster_data: Dictionary = monster.get_pet_data()
		if int(monster_data.get("mount_type", -1)) != int(fixture["mount_type"]):
			_fail("Monster data should expose the matching ground, fly, or swim mount type.")
			return false
		var saved_pet: Dictionary = pet_storage.call("_to_saved", monster_data) as Dictionary
		if int(saved_pet.get("mount_type", -1)) != int(fixture["mount_type"]):
			_fail("PetStorage should preserve mount_type when saving a captured Monster.")
			return false
		monster.queue_free()
		await process_frame

	var legacy_pet: Dictionary = pet_storage.call("_to_saved", _make_pet_data(1)) as Dictionary
	legacy_pet.erase("mount_type")
	var temporary_collection: Array[Dictionary] = [legacy_pet]
	pet_storage.set("collection", temporary_collection)
	var migrated_pet: Dictionary = pet_storage.call("get_runtime_pet", 0) as Dictionary
	pet_storage.set("collection", saved_collection)
	if int(migrated_pet.get("mount_type", -1)) != 1:
		_fail("Legacy Pet saves should infer their mount type from movement_mode.")
		return false
	return true


func _test_mount_type(player: Node, mount_type: int) -> bool:
	var pets: Array[Dictionary] = [_make_pet_data(0)]
	player.set("captured_pets", pets)
	player.set("mount_pet_data", _make_pet_data(mount_type))
	player.set("selected_pet_index", 0)
	player.call("_summon_pet", 0)
	await physics_frame
	var active_pet: Pet = player.get("active_pet") as Pet
	if active_pet == null:
		_fail("Player should summon a Pet before mounting.")
		return false
	player.call("_toggle_mount")
	if not bool(player.get("is_mounted")) or not active_pet.sprite.visible or not is_instance_valid(player.get("_mount_sprite")):
		_fail("Mounting should show a separate mount without hiding the combat Pet.")
		return false
	if int(player.get("_mounted_type")) != mount_type:
		_fail("Player should use the mount type stored in Pet data.")
		return false

	Input.action_press("move_right")
	if mount_type == 1:
		Input.action_press("move_up")
	player.call("_process_mounted_movement", 1.0 / 60.0, false)
	Input.action_release("move_right")
	Input.action_release("move_up")
	var mounted_velocity: Vector2 = player.get("velocity")
	if mount_type == 0 and not is_equal_approx(mounted_velocity.x, float(player.get("SPEED")) * 1.5):
		_fail("Ground mounts should increase horizontal speed by 50%.")
		return false
	if mount_type == 1 and (mounted_velocity.y >= 0.0 or mounted_velocity.length() > float(player.get("SPEED")) * 1.5 + 0.1):
		_fail("Fly mounts should move freely in the selected direction without gravity.")
		return false
	if mount_type == 2 and not is_equal_approx(mounted_velocity.x, float(player.get("SPEED")) * 0.25):
		_fail("Swim mounts should move very slowly on land.")
		return false

	player.call("_dismount_mount")
	if bool(player.get("is_mounted")) or player.get("active_pet") != active_pet or player.get("_mount_sprite") != null:
		_fail("Dismounting should remove only the mount visual and preserve the combat Pet.")
		return false
	player.call("_recall_pet")
	await process_frame
	return true


func _test_swim_mount_in_water(scene: Node2D, terrain: ProceduralTerrain, player: Node) -> bool:
	var water_area: Area2D = Area2D.new()
	water_area.name = "TestWater"
	water_area.collision_layer = 8
	water_area.add_to_group("water")
	var water_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(160.0, 160.0)
	water_shape.shape = rectangle
	water_area.add_child(water_shape)
	scene.add_child(water_area)
	water_area.global_position = player.global_position
	for frame_index: int in range(3):
		await physics_frame
	if not bool(player.call("_is_in_water", terrain)):
		_fail("Player should detect Area2D nodes in the water group on collision layer 4.")
		return false
	player.set("is_swimming", true)
	player.set("mount_pet_data", _make_pet_data(2))
	player.call("_toggle_mount")
	Input.action_press("move_right")
	player.call("_process_mounted_movement", 1.0 / 60.0, false)
	Input.action_release("move_right")
	var mounted_velocity: Vector2 = player.get("velocity")
	if not bool(player.get("is_mounted")) or not is_equal_approx(mounted_velocity.x, float(player.get("SPEED")) * 1.5):
		_fail("Swim mounts should move faster with gravity disabled inside a water area.")
		return false
	player.call("_dismount_mount")
	return true


func _make_pet_data(mount_type: int) -> Dictionary:
	var movement_mode: String = "Ground"
	if mount_type == 1:
		movement_mode = "Fly"
	elif mount_type == 2:
		movement_mode = "Swim"
	return {
		"name": "Mount Test",
		"texture": load("res://assets/pet.png"),
		"sprite_scale": Vector2.ONE,
		"attack_style": "Melee",
		"max_hp": 100,
		"attack_damage": 10,
		"movement_mode": movement_mode,
		"mount_type": mount_type,
	}


func _fail(message: String) -> void:
	Input.action_release("interact")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	push_error(message)
	quit(1)