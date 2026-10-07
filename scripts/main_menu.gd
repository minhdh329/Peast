extends Control

const GAME_SCENE := "res://main.tscn"
const CARD_SIZE := Vector2(130, 120)

@onready var menu_center: CenterContainer = %MenuCenter
@onready var play_button: Button = %PlayButton
@onready var inventory_button: Button = %InventoryButton
@onready var quit_button: Button = %QuitButton
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var close_button: Button = %CloseButton
@onready var team_row: HBoxContainer = %TeamRow
@onready var collection_grid: GridContainer = %CollectionGrid
@onready var info_label: Label = %InfoLabel
@onready var release_confirm: ConfirmationDialog = %ReleaseConfirm

var _pending_release_index: int = -1


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	inventory_button.pressed.connect(_open_inventory)
	quit_button.pressed.connect(_on_quit_pressed)
	close_button.pressed.connect(_close_inventory)
	release_confirm.confirmed.connect(_on_release_confirmed)
	play_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if inventory_panel.visible and event.is_action_pressed("ui_cancel"):
		_close_inventory()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _open_inventory() -> void:
	menu_center.visible = false
	inventory_panel.visible = true
	info_label.text = ""
	_refresh_inventory()
	close_button.grab_focus()


func _close_inventory() -> void:
	inventory_panel.visible = false
	menu_center.visible = true
	inventory_button.grab_focus()


func _refresh_inventory() -> void:
	for child: Node in team_row.get_children():
		child.queue_free()
	for child: Node in collection_grid.get_children():
		child.queue_free()

	for team_slot: int in range(PetStorage.TEAM_SIZE):
		team_row.add_child(_create_team_slot(team_slot))

	if PetStorage.collection.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "Chưa bắt được Pet nào. Hãy vào game và ném bóng (chuột phải) vào Monster!"
		collection_grid.add_child(empty_label)
		return
	for collection_index: int in range(PetStorage.collection.size()):
		collection_grid.add_child(_create_collection_card(collection_index))


func _create_team_slot(team_slot: int) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var has_pet: bool = team_slot < PetStorage.team.size()
	var card: Button = Button.new()
	card.custom_minimum_size = CARD_SIZE
	if has_pet:
		var collection_index: int = PetStorage.team[team_slot]
		_fill_card(card, collection_index, "%d. " % (team_slot + 1))
		card.tooltip_text = "Bấm để bỏ khỏi đội"
		card.pressed.connect(func() -> void:
			PetStorage.remove_from_team(collection_index)
			_refresh_inventory.call_deferred())
	else:
		card.text = "%d.\n(trống)" % (team_slot + 1)
		card.disabled = true
	box.add_child(card)

	var arrows: HBoxContainer = HBoxContainer.new()
	arrows.alignment = BoxContainer.ALIGNMENT_CENTER
	for offset: int in [-1, 1]:
		var arrow: Button = Button.new()
		arrow.text = "<" if offset < 0 else ">"
		arrow.custom_minimum_size = Vector2(40, 26)
		arrow.disabled = not has_pet or team_slot + offset < 0 or team_slot + offset >= PetStorage.team.size()
		arrow.pressed.connect(func() -> void:
			PetStorage.move_in_team(team_slot, offset)
			_refresh_inventory.call_deferred())
		arrows.add_child(arrow)
	box.add_child(arrows)
	return box


func _create_collection_card(collection_index: int) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var card: Button = Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.toggle_mode = true
	card.button_pressed = PetStorage.is_in_team(collection_index)
	_fill_card(card, collection_index, "[x] " if card.button_pressed else "")
	card.pressed.connect(_on_collection_card_pressed.bind(collection_index))
	box.add_child(card)

	var release_button: Button = Button.new()
	release_button.text = "Thả"
	release_button.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	release_button.pressed.connect(_ask_release.bind(collection_index))
	box.add_child(release_button)
	return box


func _ask_release(collection_index: int) -> void:
	_pending_release_index = collection_index
	release_confirm.dialog_text = "Thả %s? Pet này sẽ bị xóa vĩnh viễn." % PetStorage.collection[collection_index]["name"]
	release_confirm.popup_centered()


func _on_release_confirmed() -> void:
	if _pending_release_index < 0:
		return
	var pet_name: String = PetStorage.collection[_pending_release_index]["name"]
	PetStorage.release_pet(_pending_release_index)
	_pending_release_index = -1
	info_label.text = "Đã thả %s." % pet_name
	_refresh_inventory.call_deferred()


func _fill_card(card: Button, collection_index: int, prefix: String) -> void:
	var pet: Dictionary = PetStorage.get_runtime_pet(collection_index)
	card.icon = pet["texture"]
	card.expand_icon = true
	card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	card.add_theme_font_size_override("font_size", 11)
	card.text = "%s%s\n%s  HP %d  ATK %d" % [prefix, pet["name"], pet["attack_style"], pet["max_hp"], pet["attack_damage"]]


func _on_collection_card_pressed(collection_index: int) -> void:
	if PetStorage.is_in_team(collection_index):
		PetStorage.remove_from_team(collection_index)
		info_label.text = ""
	elif PetStorage.add_to_team(collection_index):
		info_label.text = ""
	else:
		info_label.text = "Đội đã đủ %d Pet. Bỏ bớt một Pet trước khi thêm." % PetStorage.TEAM_SIZE
	_refresh_inventory.call_deferred()
