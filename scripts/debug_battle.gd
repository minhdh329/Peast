extends Node2D

const SPECIES: Array[PackedScene] = [
	preload("res://scenes/monsters/forest_slime.tscn"),
	preload("res://scenes/monsters/forest_mushroom.tscn"),
	preload("res://scenes/monsters/volcano_imp.tscn"),
	preload("res://scenes/monsters/volcano_golem.tscn"),
	preload("res://scenes/monsters/ocean_crab.tscn"),
	preload("res://scenes/monsters/ocean_jelly.tscn"),
	preload("res://scenes/monsters/sky_bird.tscn"),
	preload("res://scenes/monsters/sky_cloud.tscn"),
	preload("res://scenes/monsters/city_cat.tscn"),
	preload("res://scenes/monsters/city_car.tscn"),
]
const PET_SCENE: PackedScene = preload("res://scenes/pet.tscn")

var world: Node2D
var terrain: ProceduralTerrain
var battle_running: bool = false
var _elapsed: float = 0.0
var _map_choice: OptionButton
var _species_choice: OptionButton
var _team_choice: OptionButton
var _random_traits: CheckBox
var _quantity: SpinBox
var _spawn_x: SpinBox
var _spawn_y: SpinBox
var _pause_button: Button
var _summary: Label
var _result: String = "Chưa bắt đầu"


func _ready() -> void:
	_build_controls()
	_load_map(0)


func _build_controls() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 30
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)
	var band: ColorRect = ColorRect.new()
	band.color = Color("#18232b")
	canvas.add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 106.0
	var margin: MarginContainer = MarginContainer.new()
	canvas.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)
	var options: HBoxContainer = HBoxContainer.new()
	column.add_child(options)
	_map_choice = _add_choice(options, "Map", ["Rừng", "Núi lửa", "Đại dương", "Đảo trên trời", "Thành phố"])
	_map_choice.item_selected.connect(_load_map)
	_species_choice = _add_choice(options, "Monster", ["Slime rừng", "Nấm độc", "Quỷ lửa", "Golem dung nham", "Cua biển", "Sứa biển", "Chim gió", "Mây dông", "Mèo trắng", "Ô tô"])
	_team_choice = _add_choice(options, "Phe", ["TeamPlayer", "TeamEnemy"])
	_team_choice.item_selected.connect(func(_index: int) -> void: _reset_spawn_position())
	_random_traits = CheckBox.new()
	_random_traits.text = "Traits ngẫu nhiên"
	options.add_child(_random_traits)
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	_quantity = _add_number(actions, "Số lượng", 1.0, 6.0, 1.0)
	_spawn_x = _add_number(actions, "X", 32.0, 928.0, 120.0)
	_spawn_y = _add_number(actions, "Y", 110.0, 650.0, 350.0)
	_spawn_x.tooltip_text = "Nhấp vào map để chọn vị trí spawn"
	_spawn_y.tooltip_text = _spawn_x.tooltip_text
	_add_button(actions, "Spawn", _on_spawn_pressed)
	_add_button(actions, "Bắt đầu", start_battle)
	_pause_button = _add_button(actions, "Tạm dừng", _toggle_pause)
	_pause_button.disabled = true
	_add_button(actions, "Xóa trận", clear_battle)
	_add_button(actions, "Menu chính", _return_to_menu)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	column.add_child(_summary)


func _add_choice(row: HBoxContainer, title: String, choices: Array[String]) -> OptionButton:
	var label: Label = Label.new()
	label.text = title
	row.add_child(label)
	var choice: OptionButton = OptionButton.new()
	for entry: String in choices:
		choice.add_item(entry)
	row.add_child(choice)
	return choice


func _add_number(row: HBoxContainer, title: String, minimum: float, maximum: float, initial: float) -> SpinBox:
	var label: Label = Label.new()
	label.text = title
	row.add_child(label)
	var number: SpinBox = SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.value = initial
	number.custom_minimum_size.x = 76.0
	row.add_child(number)
	return number


func _add_button(row: HBoxContainer, title: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.pressed.connect(action)
	row.add_child(button)
	return button


func _load_map(index: int) -> void:
	get_tree().paused = false
	battle_running = false
	_pause_button.disabled = true
	_pause_button.text = "Tạm dừng"
	_elapsed = 0.0
	_result = "Chưa bắt đầu"
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = Node2D.new()
	world.name = "DebugWorld"
	add_child(world)
	terrain = preload("res://scripts/procedural_terrain.gd").new() as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	terrain.biome = index as ProceduralTerrain.Biome
	world.add_child(terrain)
	_reset_spawn_position()
	_update_summary()


func _reset_spawn_position() -> void:
	if not is_instance_valid(terrain):
		return
	var point: Vector2 = terrain.get_player_spawn_position()
	if _team_choice.selected == 1:
		point = terrain._monster_spawns.back()
	_spawn_x.value = point.x
	_spawn_y.value = point.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point: Vector2 = get_global_mouse_position()
		if point.y > 106.0:
			_spawn_x.value = point.x
			_spawn_y.value = point.y


func _on_spawn_pressed() -> void:
	var team_index: int = _team_choice.selected
	var as_pet: bool = team_index == 0
	for unit_index: int in range(int(_quantity.value)):
		var point: Vector2 = Vector2(_spawn_x.value + unit_index * 24.0, _spawn_y.value)
		point.x = clampf(point.x, 32.0, 928.0)
		spawn_unit(_species_choice.selected, as_pet, team_index, point, _random_traits.button_pressed)
	_update_summary()


func spawn_unit(species_index: int, as_pet: bool, team_index: int, point: Vector2, random_traits: bool = false) -> CharacterBody2D:
	var team_tag: String = "TeamPlayer" if team_index == 0 else "TeamEnemy"
	var template: Monster = SPECIES[species_index].instantiate() as Monster
	template._inherit_split_traits = not random_traits
	template.set_arena_team(team_tag)
	template.set_arena_active(false)
	world.add_child(template)
	template.global_position = point
	var actor: CharacterBody2D = template
	if as_pet:
		var data: Dictionary = template.get_pet_data()
		world.remove_child(template)
		template.free()
		var pet: Pet = PET_SCENE.instantiate() as Pet
		pet.set_arena_team(team_tag)
		pet.set_arena_active(false)
		world.add_child(pet)
		pet.global_position = point
		pet.apply_pet_data(data)
		actor = pet
	actor.call("set_arena_active", battle_running)
	(actor.get_node("Sprite2D") as Sprite2D).flip_h = team_index == 1
	return actor


func start_battle() -> void:
	if _living_count("TeamPlayer") == 0 or _living_count("TeamEnemy") == 0:
		_result = "Cần nhân vật ở cả hai phe"
		_update_summary()
		return
	get_tree().paused = false
	battle_running = true
	_result = "Đang đấu"
	_pause_button.disabled = false
	_pause_button.text = "Tạm dừng"
	for actor: Node in _actors():
		actor.call("set_arena_active", true)


func _toggle_pause() -> void:
	if not battle_running:
		return
	get_tree().paused = not get_tree().paused
	_pause_button.text = "Tiếp tục" if get_tree().paused else "Tạm dừng"
	_result = "Tạm dừng" if get_tree().paused else "Đang đấu"
	_update_summary()


func clear_battle() -> void:
	_load_map(_map_choice.selected)


func _actors() -> Array[Node]:
	var actors: Array[Node] = []
	for tag: String in ["TeamPlayer", "TeamEnemy"]:
		for actor: Node in get_tree().get_nodes_in_group(tag):
			if world.is_ancestor_of(actor) and not actor.is_queued_for_deletion():
				actors.append(actor)
	return actors


func _living_count(tag: String) -> int:
	var count: int = 0
	for actor: Node in _actors():
		if actor.is_in_group(tag) and (actor.call("is_alive") or actor.call("is_reviving")):
			count += 1
	return count


func _process(delta: float) -> void:
	if battle_running:
		_elapsed += delta
		var left: int = _living_count("TeamPlayer")
		var right: int = _living_count("TeamEnemy")
		if left == 0 or right == 0:
			battle_running = false
			_result = "Hòa" if left == 0 and right == 0 else ("TeamPlayer thắng" if left > 0 else "TeamEnemy thắng")
			_pause_button.disabled = true
			for actor: Node in _actors():
				actor.call("set_arena_active", false)
	_update_summary()


func _update_summary() -> void:
	var left_hp: int = 0
	var right_hp: int = 0
	for actor: Node in _actors():
		if actor.is_in_group("TeamPlayer"):
			left_hp += int(actor.get("current_hp"))
		else:
			right_hp += int(actor.get("current_hp"))
	_summary.text = "TeamPlayer: %d sống / %d HP   |   TeamEnemy: %d sống / %d HP   |   %.1f giây   |   %s" % [_living_count("TeamPlayer"), left_hp, _living_count("TeamEnemy"), right_hp, _elapsed, _result]


func _return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")