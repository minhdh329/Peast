extends SceneTree

const SAVE_PATH := "user://inventory_debug_smoke_test.json"
var _storage: Node
var _original_path: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_storage = root.get_node("PetStorage")
	_original_path = str(_storage.get("save_path"))
	_storage.set("save_path", SAVE_PATH)
	_storage.call("reset_progress")
	var menu: Control = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	menu.call("_open_inventory")
	await menu.inventory_panel.ui_opened
	var debug_button: Button = menu.get("_inventory_debug_button")
	if not debug_button.is_visible_in_tree():
		_fail("Inventory must expose the debug add button.")
		return
	debug_button.pressed.emit()
	await process_frame
	var debug: Control = menu.get("_inventory_debug")
	if not is_instance_valid(debug) or menu.inventory_panel.visible:
		_fail("Debug must open as a separate modal without the inventory behind it.")
		return
	if debug._scenes.size() != 10 or debug._trait_checks.size() != Monster.AVAILABLE_TRAITS.size():
		_fail("Debug must list every Monster species and every trait.")
		return
	for size: Vector2i in [Vector2i(640, 360), Vector2i(960, 540)]:
		root.size = size
		root.content_scale_size = size
		await process_frame
		await process_frame
		if not root.get_visible_rect().encloses(debug._panel.get_global_rect()):
			_fail("Debug must remain onscreen at mobile/desktop viewport sizes.")
			return
	for index: int in range(debug._scenes.size()):
		var choice: OptionButton = debug._species
		choice.select(index)
		for check: CheckBox in debug._trait_checks:
			check.button_pressed = false
		var selected_traits: Array[String] = ["HalfHealth", "StoneBody", "Lazy", "Berserk", "DoubleDamage"]
		for trait_name: String in selected_traits:
			(debug._trait_checks[Monster.AVAILABLE_TRAITS.find(trait_name)] as CheckBox).button_pressed = true
		debug.call("_add_monster")
		var data: Dictionary = _storage.call("get_runtime_pet", index)
		var base: Monster = (debug._scenes[index] as PackedScene).instantiate() as Monster
		var expected_damage: int = roundi((base.attack_damage + base.max_hp * 0.1) * 2.0 * 2.5)
		if data["name"] != base.monster_name or data["attack_damage"] != expected_damage or not is_equal_approx(data["attack_interval"], base.attack_interval / 0.375):
			base.free()
			_fail("Debug Monsters must have species base stats modified exactly once by selected traits.")
			return
		base.free()
		if data["current_traits"].size() != 5:
			_fail("Debug must allow more than four traits, without adding random traits.")
			return
		for field: String in ["split_on_death", "chain_lightning", "wind_dash_enabled", "charge_style"]:
			var species: Monster = (debug._scenes[index] as PackedScene).instantiate() as Monster
			var expected: Variant = species.get(field)
			species.free()
			if data[field] != expected:
				_fail("Debug additions must retain species passive %s." % field)
				return
		for trait_name: String in selected_traits:
			if not data["current_traits"].has(trait_name):
				_fail("Debug must preserve every selected trait.")
				return
	for check: CheckBox in debug._trait_checks:
		check.button_pressed = false
	debug.call("_add_monster")
	var plain: Dictionary = _storage.call("get_runtime_pet", 10)
	if not plain["current_traits"].is_empty() or int(_storage.get("gold")) != 3:
		_fail("Debug must support no traits and must not charge gold.")
		return
	_storage.call("load_data")
	if (_storage.get("collection") as Array).size() != 11:
		_fail("Debug additions must persist to the save.")
		return
	debug.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await menu.inventory_panel.ui_opened
	await process_frame
	if is_instance_valid(menu.get("_inventory_debug")) or not menu.inventory_panel.visible or menu.collection_grid.get_child_count() != 11:
		_fail("Back must return to refreshed inventory.")
		return
	debug_button.pressed.emit()
	await process_frame
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	Input.flush_buffered_events()
	await menu.inventory_panel.ui_opened
	if not menu.inventory_panel.visible or is_instance_valid(menu.get("_inventory_debug")):
		_fail("Escape must close only the debug screen and restore Inventory.")
		return
	menu.call("_close_inventory")
	await menu.inventory_panel.ui_closed
	menu.call("_on_play_pressed")
	await menu.inventory_panel.ui_opened
	if debug_button.visible:
		_fail("Debug add button must not appear in battle team selection.")
		return
	menu.call("_open_inventory_debug")
	if is_instance_valid(menu.get("_inventory_debug")):
		_fail("Team selection must not allow opening inventory debug.")
		return
	print("Inventory debug smoke test passed.")
	_finish(0)


func _fail(message: String) -> void:
	push_error(message)
	_finish(1)


func _finish(code: int) -> void:
	if current_scene != null:
		current_scene.queue_free()
	if _storage != null:
		_storage.set("save_path", _original_path)
		_storage.call("load_data")
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(code)
