extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not preload("res://scripts/mobile_controls.gd").is_enabled():
		_fail("Run this test with -- --mobile-controls.")
		return
	var game_scene: PackedScene = load("res://main.tscn")
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
	var controls: CanvasLayer = scene.get_node("HotBar/MobileControls") as CanvasLayer
	for frame_index: int in range(40):
		await physics_frame
	if not player.is_on_floor() or scene.get_node("DebugPanel").visible:
		_fail("Mobile gameplay should load with a grounded Player and hidden debug UI.")
		return
	await _capture_screenshot("gameplay")
	var viewport_rect: Rect2 = root.get_visible_rect()
	for button: TouchScreenButton in controls._buttons:
		if not viewport_rect.encloses(Rect2(button.position, Vector2(80.0, 80.0))):
			_fail("Every touch button should fit inside the logical viewport.")
			return
		if not is_equal_approx(button.modulate.a, 0.25):
			_fail("Gameplay buttons should use 25% opacity.")
			return
	var move_stick: Control = controls.get_node("MoveStick") as Control
	if not viewport_rect.encloses(move_stick.get_global_rect()) or not is_equal_approx(move_stick.modulate.a, 0.25):
		_fail("The analog movement stick should fit onscreen at 25% opacity.")
		return
	for test_size: Vector2 in [Vector2(640.0, 360.0), Vector2(960.0, 540.0), Vector2(1280.0, 720.0)]:
		controls.call("_layout_buttons", test_size)
		var stick_rect: Rect2 = Rect2(controls._joystick.position, controls._joystick.size)
		if not Rect2(Vector2.ZERO, test_size).encloses(stick_rect):
			_fail("The analog stick should remain inside viewport %s." % test_size)
			return
		var control_rects: Array[Rect2] = [stick_rect]
		for button: TouchScreenButton in controls._buttons:
			var button_rect: Rect2 = Rect2(button.position, Vector2(80.0, 80.0))
			if not Rect2(Vector2.ZERO, test_size).encloses(button_rect):
				_fail("Gameplay controls should remain onscreen at viewport %s." % test_size)
				return
			for existing_rect: Rect2 in control_rects:
				if button_rect.intersects(existing_rect):
					_fail("Gameplay controls should not overlap at viewport %s." % test_size)
					return
			control_rects.append(button_rect)
	controls.call("_layout_buttons", viewport_rect.size)
	var stick_center: Vector2 = move_stick.get_global_rect().get_center()
	var right_position: Vector2 = stick_center + Vector2(56.0, 0.0)
	var jump_position: Vector2 = controls.get_node("Jump").position + Vector2(40.0, 40.0)
	_touch(0, stick_center, true)
	_drag(0, stick_center, right_position)
	var analog_strength: float = Input.get_action_strength("move_right")
	if analog_strength <= 0.0 or analog_strength >= 1.0:
		_fail("Dragging the movement stick partway should produce analog action strength.")
		return
	await physics_frame
	await physics_frame
	_touch(1, jump_position, true)
	await physics_frame
	await physics_frame
	if player.velocity.x <= 0.0 or player.velocity.y >= 0.0 or not Input.is_action_pressed("move_right"):
		_fail("Two fingers should allow running and jumping simultaneously: velocity=%s, right=%s, jump=%s, screen_transform=%s." % [player.velocity, Input.is_action_pressed("move_right"), Input.is_action_pressed("jump"), root.get_screen_transform()])
		return
	_touch(1, jump_position, false)
	if Input.is_action_pressed("jump") or not Input.is_action_pressed("move_right"):
		_fail("Releasing jump should not release the movement finger.")
		return
	_touch(0, right_position, false)
	if Input.is_action_pressed("move_right"):
		_fail("Releasing movement should stop its action.")
		return
	player.sprite.flip_h = true
	if player._get_aim_direction(player.global_position) != Vector2.LEFT:
		_fail("Touch attacks should aim in the facing direction.")
		return
	player.sprite.flip_h = false
	if player._get_aim_direction(player.global_position) != Vector2.RIGHT:
		_fail("Touch aim should update when the Player turns.")
		return
	Input.action_press("melee_attack")
	await physics_frame
	await physics_frame
	Input.action_release("melee_attack")
	if player._is_attacking:
		_fail("Emulated mouse clicks on mobile UI must not trigger melee attacks.")
		return
	var world_position: Vector2 = viewport_rect.size * 0.5
	_mouse_click(world_position, InputEvent.DEVICE_ID_EMULATION)
	await physics_frame
	await physics_frame
	if player._is_attacking:
		_fail("Mouse events emulated from touch must not trigger melee attacks.")
		return
	_mouse_click(stick_center)
	await physics_frame
	await physics_frame
	if player._is_attacking:
		_fail("Clicking the movement stick must not trigger melee attacks.")
		return
	_mouse_click(jump_position)
	await physics_frame
	await physics_frame
	if player._is_attacking:
		_fail("Clicking Jump must not trigger melee attacks.")
		return
	_mouse_click(world_position)
	await physics_frame
	await physics_frame
	if not player._is_attacking:
		_fail("A physical left click in the world should attack with mobile controls enabled.")
		return
	await create_timer(player.melee_attack_duration + 0.1).timeout
	player._touch_enabled = false
	_mouse_click(world_position)
	await physics_frame
	await physics_frame
	if not player._is_attacking:
		_fail("Physical left clicks should still trigger desktop melee attacks.")
		return
	player._touch_enabled = true
	await create_timer(player.melee_attack_duration + 0.1).timeout
	var attack_position: Vector2 = controls.get_node("Attack").position + Vector2(40.0, 40.0)
	_touch(2, attack_position, true)
	await physics_frame
	await physics_frame
	_touch(2, attack_position, false)
	if not player._is_attacking:
		_fail("The touch attack button should trigger a sword swing.")
		return
	_touch(0, stick_center, true)
	_drag(0, stick_center, right_position)
	controls.open_pause()
	if not paused or Input.is_action_pressed("move_right"):
		_fail("Pausing must stop gameplay and release held touch actions.")
		return
	_touch(0, right_position, false)
	controls.close_pause()
	if paused:
		_fail("Resume should unpause gameplay.")
		return
	controls.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if not paused:
		_fail("Switching away from the app should pause gameplay.")
		return
	controls.close_pause()
	var monster_scene: PackedScene = load("res://scenes/monsters/forest_slime.tscn")
	var sample_monster: Monster = monster_scene.instantiate() as Monster
	root.add_child(sample_monster)
	sample_monster.set_physics_process(false)
	player.captured_pets.clear()
	player.captured_pets.append(sample_monster.get_pet_data())
	sample_monster.queue_free()
	var hotbar: CanvasLayer = scene.get_node("HotBar") as CanvasLayer
	var slot_panel: Control = hotbar._slots[0]["panel"] as Control
	var slot_position: Vector2 = slot_panel.get_global_rect().get_center()
	_touch(4, slot_position, true)
	_touch(4, slot_position, false)
	await process_frame
	if not is_instance_valid(player.active_pet):
		_fail("Tapping a pet slot should summon that pet.")
		return
	_touch(4, slot_position, true)
	_touch(4, slot_position, false)
	await process_frame
	if is_instance_valid(player.active_pet):
		_fail("Tapping the active pet slot again should recall it exactly once.")
		return
	terrain._add_platform(12, terrain.floor_row - 2, 3, 0)
	player.position = Vector2(13.5 * terrain.TILE_SIZE.x, (terrain.floor_row - 2) * terrain.TILE_SIZE.y - 22.0)
	player.velocity = Vector2.ZERO
	for frame_index: int in range(20):
		await physics_frame
	if not player.is_on_floor():
		_fail("Player should stand on the touch drop-through test platform.")
		return
	var down_position: Vector2 = stick_center + Vector2(0.0, 56.0)
	_touch(5, stick_center, true)
	_drag(5, stick_center, down_position)
	await physics_frame
	await physics_frame
	_touch(5, down_position, false)
	for frame_index: int in range(40):
		await physics_frame
	if not player.is_on_floor() or player.position.y <= (terrain.floor_row - 1) * terrain.TILE_SIZE.y or (player.collision_mask & ProceduralTerrain.PLATFORM_COLLISION_MASK) == 0:
		_fail("The mobile Down button should drop through platforms and still land on solid ground.")
		return
	scene.queue_free()
	await process_frame
	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	if not menu.debug_button.visible or menu.quit_button.visible or menu.play_button.size.y < 64.0 or menu.debug_button.size.y < 64.0:
		_fail("Mobile menu should show a touch-sized Debug button and hide Quit.")
		return
	for button: Button in [menu.play_button, menu.arena_button, menu.debug_button, menu.inventory_button]:
		if not viewport_rect.encloses(button.get_global_rect()):
			_fail("All mobile menu buttons, including Debug, should fit the screen.")
			return
	menu.call("_layout_responsive_ui", Vector2(640.0, 360.0))
	if menu.play_button.custom_minimum_size.y > 48.0 or menu.inventory_panel.offset_left > 16.0 or menu.inventory_panel.offset_top > 12.0:
		_fail("The menu should reduce control height and margins on short landscape viewports.")
		return
	menu.call("_layout_responsive_ui", viewport_rect.size)
	menu._open_inventory()
	await menu.inventory_panel.ui_opened
	await process_frame
	await process_frame
	if not viewport_rect.encloses(menu.inventory_panel.get_global_rect()) or menu.close_button.size.y < 48.0:
		_fail("Mobile inventory should fit the screen and have a large close target.")
		return
	if menu.collection_grid.columns < 4 or quit_on_go_back or not auto_accept_quit:
		_fail("Inventory should use the screen width, Android Back should be handled, and window close should still work.")
		return
	await _capture_screenshot("inventory")
	menu.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await menu.inventory_panel.ui_closed
	if menu.inventory_panel.visible:
		_fail("Android Back should close the inventory.")
		return
	menu.call("_on_play_pressed")
	await menu.inventory_panel.ui_opened
	await process_frame
	await process_frame
	await process_frame
	var fighter_row: Control = menu.get_node("%TeamRow") as Control
	var mount_row: Control = menu.get_node("%MountRow") as Control
	if absf(fighter_row.global_position.y - mount_row.global_position.y) > 1.0 or fighter_row.get_global_rect().intersects(mount_row.get_global_rect()):
		_fail("Mobile Play fighter and mount selections should sit side by side.")
		return
	if menu.collection_grid.get_parent().size.y < 48.0:
		_fail("Play selection should leave visible space for the scrollable collection.")
		return
	await _capture_screenshot("play-loadout")
	menu.call("_close_inventory")
	await menu.inventory_panel.ui_closed
	menu.debug_button.pressed.emit()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://scenes/DebugBattle.tscn":
		_fail("The mobile menu Debug button should open DebugBattle.")
		return
	print("Mobile controls and menu smoke test passed.")
	quit(0)


func _capture_screenshot(screen_name: String) -> void:
	if not "--capture-screenshots" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = OS.get_cache_dir().path_join("peast-mobile-%s.png" % screen_name)
	image.save_png(path)
	print("Screenshot: ", path)


func _touch(finger: int, position: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = finger
	event.position = root.get_screen_transform() * position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse_click(position: Vector2, device: int = 0) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.device = device
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = root.get_screen_transform() * position
		event.global_position = event.position
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _drag(finger: int, start_position: Vector2, end_position: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = finger
	event.position = root.get_screen_transform() * end_position
	event.relative = root.get_screen_transform() * (end_position - start_position)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _fail(message: String) -> void:
	paused = false
	push_error(message)
	quit(1)