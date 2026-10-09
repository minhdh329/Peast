extends Node2D

const TEAM_PLAYER: String = "TeamPlayer"
const TEAM_ENEMY: String = "TeamEnemy"
const BATTLE_START_DELAY: float = 2.0
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const PLAYER_SPAWNS: Array[Vector2] = [
	Vector2(150.0, 420.0),
	Vector2(210.0, 350.0),
	Vector2(150.0, 280.0),
]
const ENEMY_SPAWNS: Array[Vector2] = [
	Vector2(810.0, 420.0),
	Vector2(750.0, 350.0),
	Vector2(810.0, 280.0),
]
@export var enemy_monster_scenes: Array[PackedScene] = [
	preload("res://scenes/monsters/forest_slime.tscn"),
	preload("res://scenes/monsters/forest_mushroom.tscn"),
	preload("res://scenes/monsters/volcano_imp.tscn"),
	preload("res://scenes/monsters/volcano_golem.tscn"),
	preload("res://scenes/monsters/ocean_crab.tscn"),
	preload("res://scenes/monsters/ocean_jelly.tscn"),
	preload("res://scenes/monsters/sky_bird.tscn"),
	preload("res://scenes/monsters/sky_cloud.tscn"),
]

@export var arena_team: Array[Dictionary] = []
@export var pet_scene: PackedScene = preload("res://scenes/pet.tscn")

var _combatants: Array[Node] = []
var _battle_started: bool = false
var battle_has_started: bool = false
var activated_combatant_count: int = 0
var _battle_finished: bool = false
var _result_overlay: Control
var _result_label: Label
var _return_button: Button


func _ready() -> void:
	_create_result_ui()
	randomize()
	arena_team = _resolve_arena_team()
	if arena_team.size() != 3:
		push_error("ArenaTest cần đúng 3 Pet đã bắt được. Hãy chọn đủ 3 Pet hoặc gán arena_team trong Inspector.")
		return
	_spawn_player_team()
	_spawn_enemy_team()
	_start_battle_after_delay()


func _resolve_arena_team() -> Array[Dictionary]:
	var resolved_team: Array[Dictionary] = arena_team.duplicate(true)
	if resolved_team.size() >= 3:
		resolved_team.resize(3)
		return resolved_team

	var collection_indices: Array[int] = []
	for index: int in PetStorage.team:
		collection_indices.append(index)
	for index: int in range(PetStorage.collection.size()):
		if collection_indices.size() >= 3:
			break
		if not collection_indices.has(index):
			collection_indices.append(index)

	for index: int in collection_indices:
		if resolved_team.size() >= 3:
			break
		resolved_team.append(PetStorage.get_runtime_pet(index))
	return resolved_team


func _spawn_player_team() -> void:
	for team_index: int in range(3):
		var pet: Pet = pet_scene.instantiate() as Pet
		pet.set_arena_team(TEAM_PLAYER)
		pet.set_arena_active(false)
		add_child(pet)
		pet.global_position = PLAYER_SPAWNS[team_index]
		pet.apply_pet_data(arena_team[team_index])
		pet.get_node("Sprite2D").flip_h = false
		_combatants.append(pet)


func _spawn_enemy_team() -> void:
	if enemy_monster_scenes.is_empty():
		push_error("ArenaManager cần ít nhất một PackedScene trong enemy_monster_scenes.")
		return
	for team_index: int in range(3):
		var monster_scene: PackedScene = enemy_monster_scenes.pick_random()
		var monster: Monster = monster_scene.instantiate() as Monster
		monster.set_arena_team(TEAM_ENEMY)
		monster.set_arena_active(false)
		add_child(monster)
		monster.global_position = ENEMY_SPAWNS[team_index]
		monster.get_node("Sprite2D").flip_h = true
		_combatants.append(monster)


func _start_battle_after_delay() -> void:
	await get_tree().create_timer(BATTLE_START_DELAY).timeout
	if not is_inside_tree() or _battle_finished:
		return
	_battle_started = true
	battle_has_started = true
	print("BẮT ĐẦU CHIẾN ĐẤU!")
	for combatant: Node in _combatants:
		if is_instance_valid(combatant) and not combatant.is_queued_for_deletion():
			combatant.call("set_arena_active", true)
			activated_combatant_count += 1


func _process(_delta: float) -> void:
	if not _battle_started or _battle_finished:
		return
	var players_alive: bool = _has_living_team(TEAM_PLAYER)
	var enemies_alive: bool = _has_living_team(TEAM_ENEMY)
	if players_alive and enemies_alive:
		return
	_battle_finished = true
	_battle_started = false
	if players_alive:
		print("PHE PLAYER CHIẾN THẮNG!")
		_result_label.text = "CHIẾN THẮNG!"
		_result_label.add_theme_color_override("font_color", Color("#8fea91"))
	elif enemies_alive:
		print("PHE ENEMY CHIẾN THẮNG!")
		_result_label.text = "THUA"
		_result_label.add_theme_color_override("font_color", Color("#ff8667"))
	else:
		print("TRẬN ĐẤU HÒA!")
		_result_label.text = "HÒA"
		_result_label.add_theme_color_override("font_color", Color("#ffca58"))
	for combatant: Node in _combatants:
		if is_instance_valid(combatant) and not combatant.is_queued_for_deletion():
			combatant.call("set_arena_active", false)
	_result_overlay.show()
	_return_button.grab_focus()


func _create_result_ui() -> void:
	var result_layer: CanvasLayer = CanvasLayer.new()
	result_layer.layer = 20
	add_child(result_layer)
	_result_overlay = Control.new()
	result_layer.add_child(_result_overlay)
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.hide()

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.7)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_overlay.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var result_center: CenterContainer = CenterContainer.new()
	_result_overlay.add_child(result_center)
	result_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var result_column: VBoxContainer = VBoxContainer.new()
	result_column.add_theme_constant_override("separation", 24)
	result_center.add_child(result_column)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 40)
	result_column.add_child(_result_label)
	_return_button = Button.new()
	_return_button.text = "Về màn hình chính"
	_return_button.custom_minimum_size = Vector2(280.0, 48.0)
	_return_button.add_theme_font_size_override("font_size", 20)
	_return_button.pressed.connect(_return_to_main_menu)
	result_column.add_child(_return_button)


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU_SCENE)


func _has_living_team(team_tag: String) -> bool:
	for combatant: Node in get_tree().get_nodes_in_group(team_tag):
		if combatant.is_queued_for_deletion():
			continue
		if combatant.has_method("is_alive") and combatant.call("is_alive"):
			return true
		if combatant.has_method("is_reviving") and combatant.call("is_reviving"):
			return true
	return false