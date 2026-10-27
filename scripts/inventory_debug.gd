extends ColorRect

signal closed
signal monster_added(pet_data: Dictionary)

var _species: OptionButton
var _scenes: Array[PackedScene] = []
var _trait_checks: Array[CheckBox] = []
var _status: Label
var _panel: PanelContainer


func _ready() -> void:
	name = "InventoryDebug"
	color = Color(0.0, 0.0, 0.0, 0.85)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().quit_on_go_back = false
	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 16.0
	_panel.offset_right = -16.0
	_panel.offset_top = 12.0
	_panel.offset_bottom = -12.0
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	var title: Label = Label.new()
	title.text = "Debug: thêm Monster"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	_species = OptionButton.new()
	_species.custom_minimum_size.y = 48.0
	column.add_child(_species)
	for pool: Array in ProceduralTerrain.MONSTER_SCENES.values():
		for scene: PackedScene in pool:
			if _scenes.has(scene):
				continue
			var monster: Monster = scene.instantiate() as Monster
			_species.add_item(monster.monster_name)
			_scenes.append(scene)
			monster.free()
	var hint: Label = Label.new()
	hint.text = "Chọn thuộc tính tùy ý (có thể không chọn hoặc chọn nhiều hơn 4)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var traits: VBoxContainer = VBoxContainer.new()
	traits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(traits)
	var badges: Dictionary = preload("res://scripts/passive_vfx.gd").BADGES
	for trait_name: String in Monster.AVAILABLE_TRAITS:
		var check: CheckBox = CheckBox.new()
		check.text = "%s (%s)" % [badges[trait_name][2], trait_name]
		check.tooltip_text = preload("res://scripts/pet_details.gd").get_trait_description(trait_name, {})
		check.custom_minimum_size.y = 48.0
		traits.add_child(check)
		_trait_checks.append(check)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	var add: Button = Button.new()
	add.text = "Thêm vào Inventory"
	add.custom_minimum_size.y = 48.0
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(_add_monster)
	actions.add_child(add)
	var back: Button = Button.new()
	back.text = "Đóng"
	back.custom_minimum_size = Vector2(100.0, 48.0)
	back.pressed.connect(func() -> void: closed.emit())
	actions.add_child(back)
	_species.grab_focus()


func _add_monster() -> void:
	if _species.selected < 0 or _species.selected >= _scenes.size():
		_status.text = "Hãy chọn loài Monster."
		return
	var monster: Monster = _scenes[_species.selected].instantiate() as Monster
	monster.randomize_traits_on_spawn = false
	for index: int in range(_trait_checks.size()):
		if _trait_checks[index].button_pressed:
			monster.current_traits.append(Monster.AVAILABLE_TRAITS[index])
	monster.set_physics_process(false)
	monster.hide()
	add_child(monster)
	var data: Dictionary = monster.get_pet_data()
	monster.free()
	PetStorage.add_captured_pet(data)
	_status.text = "Đã thêm %s với %d thuộc tính." % [data["name"], data["current_traits"].size()]
	monster_added.emit(data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
