extends SceneTree

const TEST_SAVE_PATH := "user://economy_smoke_test.json"
var _storage: Node
var _original_save_path: String


class Combatant extends Node2D:
	var alive: bool = true

	func is_alive() -> bool:
		return alive


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_storage = root.get_node("PetStorage")
	_original_save_path = str(_storage.get("save_path"))
	_storage.set("save_path", TEST_SAVE_PATH)
	_storage.call("reset_progress")
	if int(_storage.get("gold")) != 3:
		_fail("New players should receive three gold for their first capture run.")
		return
	var legacy_file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"collection": [], "team": []}))
	legacy_file.close()
	_storage.call("load_data")
	if int(_storage.get("gold")) != 3:
		_fail("Legacy saves without a wallet should receive the starting balance.")
		return
	_storage.call("add_gold", 7)
	_storage.call("load_data")
	if int(_storage.get("gold")) != 10 or _storage.call("spend_gold", 11):
		_fail("Gold should survive reload and reject unaffordable spending.")
		return
	if _storage.call("spend_gold", -3) or int(_storage.get("gold")) != 10:
		_fail("Invalid spending must not increase or decrease gold.")
		return

	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	menu.call("_on_play_pressed")
	menu.call("_close_inventory")
	if int(_storage.get("gold")) != 10:
		_fail("Opening and cancelling Play must not charge an entry fee.")
		return
	_storage.set("gold", 2)
	menu.call("_on_play_pressed")
	menu.call("_start_game")
	var entry_button: Button = menu.get_node("%PlayStartButton") as Button
	var balance_label: Label = menu.get_node("%PanelGoldBalance") as Label
	if not entry_button.disabled or int(_storage.get("gold")) != 2 or not balance_label.text.contains("Thiếu 1") or current_scene != menu:
		_fail("Insufficient gold should disable entry, display the shortfall, and preserve the balance.")
		return
	_storage.call("add_gold", 8)
	if entry_button.disabled or not entry_button.text.contains("3"):
		_fail("Entry should show its cost and become available when the balance is sufficient.")
		return
	menu.call("_start_game")
	menu.call("_start_game")
	await process_frame
	await process_frame
	if current_scene == null or current_scene.scene_file_path != "res://main.tscn" or int(_storage.get("gold")) != 7:
		_fail("Confirmed capture entry should charge exactly three gold once, even with repeated presses.")
		return
	var hud: Node = current_scene.get_node("HotBar")
	var hud_label: Label = hud.get("_gold_label") as Label
	if not hud_label.text.contains("7"):
		_fail("Gameplay HUD should display the remaining gold.")
		return
	current_scene.queue_free()
	await process_frame
	_storage.call("load_data")
	if int(_storage.get("gold")) != 7:
		_fail("The capture entry deduction should persist to disk.")
		return

	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	var manager_script: Script = load("res://scripts/arena_manager.gd")
	var manager: Node2D = manager_script.new() as Node2D
	world.add_child(manager)
	manager.set_process(false)
	var player: Combatant = Combatant.new()
	player.add_to_group("TeamPlayer")
	world.add_child(player)
	var enemy: Combatant = Combatant.new()
	enemy.add_to_group("TeamEnemy")
	world.add_child(enemy)
	manager.set("_battle_started", true)
	manager.call("_process", 0.0)
	if int(_storage.get("gold")) != 7:
		_fail("An unfinished Arena should not grant gold.")
		return
	for outcome: String in ["win", "loss", "draw"]:
		player.alive = outcome == "win"
		enemy.alive = outcome == "loss"
		manager.set("_battle_started", true)
		manager.set("_battle_finished", false)
		var before: int = int(_storage.get("gold"))
		var reward: int = 5 if outcome == "win" else 2 if outcome == "loss" else 0
		manager.call("_process", 0.0)
		manager.call("_process", 0.0)
		if int(_storage.get("gold")) != before + reward:
			_fail("Arena %s should pay %d gold exactly once." % [outcome, reward])
			return
		var reward_label: Label = manager.get("_reward_label") as Label
		if not reward_label.text.contains("+%d" % reward):
			_fail("Arena results should show the gold payout.")
			return
	_storage.call("load_data")
	if int(_storage.get("gold")) != 14:
		_fail("Arena payouts should persist after reloading the save.")
		return
	_finish(0)


func _fail(message: String) -> void:
	push_error(message)
	_finish(1)


func _finish(exit_code: int) -> void:
	if current_scene != null:
		current_scene.queue_free()
	if _storage != null:
		_storage.set("save_path", _original_save_path)
		_storage.call("load_data")
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	if exit_code == 0:
		print("Economy smoke test passed.")
	quit(exit_code)