extends Control

const GAME_SCENE := "res://main.tscn"
const ARENA_SCENE := "res://scenes/ArenaTest.tscn"
const ARENA_TEAM_SIZE := 5
const CARD_SIZE := Vector2(130, 120)
const MOBILE_CONTROLS: GDScript = preload("res://scripts/mobile_controls.gd")

@onready var menu_center: CenterContainer = %MenuCenter
@onready var play_button: Button = %PlayButton
@onready var arena_button: Button = %ArenaButton
@onready var debug_button: Button = %DebugButton
@onready var inventory_button: Button = %InventoryButton
@onready var quit_button: Button = %QuitButton
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var close_button: Button = %CloseButton
@onready var arena_start_button: Button = %ArenaStartButton
@onready var play_start_button: Button = %PlayStartButton
@onready var team_row: HBoxContainer = %TeamRow
@onready var mount_row: HBoxContainer = %MountRow
@onready var loadout_row: HBoxContainer = %LoadoutRow
@onready var team_label: Label = %TeamLabel
@onready var mount_label: Label = %MountLabel
@onready var collection_grid: GridContainer = %CollectionGrid
@onready var info_label: Label = %InfoLabel
@onready var release_confirm: ConfirmationDialog = %ReleaseConfirm
@onready var gold_label: Label = %GoldBalance
@onready var panel_gold_label: Label = %PanelGoldBalance
@onready var fusion_button: Button = %FusionButton

var _pending_release_index: int = -1
var _touch_enabled: bool = MOBILE_CONTROLS.is_enabled()
var _arena_selection_active: bool = false
var _arena_team_indices: Array[int] = []
var _play_selection_active: bool = false
var _play_team_indices: Array[int] = []
var _play_mount_index: int = -1
var _fusion_screen: Control


func _ready() -> void:
	PetStorage.gold_changed.connect(_update_gold_display)
	_update_gold_display(PetStorage.gold)
	if _touch_enabled:
		_configure_touch_layout()
		get_viewport().size_changed.connect(_layout_responsive_ui)
		_layout_responsive_ui()
	play_button.pressed.connect(_on_play_pressed)
	arena_button.pressed.connect(_on_arena_pressed)
	debug_button.pressed.connect(_on_debug_pressed)
	inventory_button.pressed.connect(_open_inventory)
	fusion_button.pressed.connect(_open_fusion)
	quit_button.pressed.connect(_on_quit_pressed)
	close_button.pressed.connect(_close_inventory)
	arena_start_button.pressed.connect(_start_arena)
	play_start_button.pressed.connect(_start_game)
	release_confirm.confirmed.connect(_on_release_confirmed)
	play_button.grab_focus()


func _update_gold_display(balance: int) -> void:
	gold_label.text = "Vàng: %d" % balance
	panel_gold_label.text = "Vàng: %d" % balance
	play_button.text = "Bắt thú · %d vàng" % PetStorage.CAPTURE_ENTRY_COST
	play_start_button.text = "Vào game · %d vàng" % PetStorage.CAPTURE_ENTRY_COST
	arena_button.text = "Arena 5v5 · Miễn phí"
	arena_button.tooltip_text = "Miễn phí | Thắng +5 vàng | Thua +2 vàng"
	if _play_selection_active:
		_update_play_entry_state()


func _update_play_entry_state() -> void:
	var missing_gold: int = maxi(0, PetStorage.CAPTURE_ENTRY_COST - PetStorage.gold)
	panel_gold_label.text = "Vàng: %d | Phí: %d vàng" % [PetStorage.gold, PetStorage.CAPTURE_ENTRY_COST]
	if missing_gold > 0:
		panel_gold_label.text += " | Thiếu %d vàng" % missing_gold
	var valid_team: bool = _play_team_indices.size() == PetStorage.TEAM_SIZE or PetStorage.collection.is_empty()
	play_start_button.disabled = missing_gold > 0 or not valid_team


func _configure_touch_layout() -> void:
	get_tree().quit_on_go_back = false
	quit_button.hide()
	menu_center.get_node("VBoxContainer/Spacer").hide()
	menu_center.get_node("VBoxContainer").add_theme_constant_override("separation", 12)
	menu_center.get_node("VBoxContainer/Title").add_theme_font_size_override("font_size", 48)
	for button: Button in [play_button, arena_button, debug_button, inventory_button]:
		button.custom_minimum_size = Vector2(280.0, 64.0)
	close_button.custom_minimum_size = Vector2(100.0, 48.0)
	arena_start_button.custom_minimum_size = Vector2(140.0, 48.0)
	play_start_button.custom_minimum_size = Vector2(140.0, 48.0)
	inventory_panel.offset_left = 16.0
	inventory_panel.offset_right = -16.0
	inventory_panel.offset_top = 12.0
	inventory_panel.offset_bottom = -12.0
	team_label.text = "Đội hình"
	inventory_panel.get_node("Margin/VBox/CollectionLabel").text = "Bộ sưu tập"
	release_confirm.get_ok_button().custom_minimum_size.y = 48.0
	release_confirm.get_cancel_button().custom_minimum_size.y = 48.0
	collection_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_grid.get_parent().resized.connect(_resize_collection_grid)
	_resize_collection_grid()


func _resize_collection_grid() -> void:
	var scroll: ScrollContainer = collection_grid.get_parent() as ScrollContainer
	var cell_width: float = 124.0 if _is_compact_touch_layout() else 164.0
	collection_grid.columns = maxi(1, int((scroll.size.x - 16.0) / cell_width))


func _is_compact_touch_layout() -> bool:
	return _touch_enabled and get_viewport().get_visible_rect().size.y < 420.0


func _layout_responsive_ui(viewport_size: Vector2 = Vector2.ZERO) -> void:
	if not _touch_enabled:
		return
	if viewport_size == Vector2.ZERO:
		viewport_size = get_viewport().get_visible_rect().size
	var compact_layout: bool = viewport_size.y < 420.0
	var button_height: float = 48.0 if compact_layout else 64.0
	var title_size: int = 36 if compact_layout else 48
	var menu_column: VBoxContainer = menu_center.get_node("VBoxContainer") as VBoxContainer
	menu_column.add_theme_constant_override("separation", 8 if compact_layout else 12)
	menu_center.get_node("VBoxContainer/Title").add_theme_font_size_override("font_size", title_size)
	for button: Button in [play_button, arena_button, debug_button, inventory_button]:
		button.custom_minimum_size = Vector2(280.0, button_height)
	close_button.custom_minimum_size = Vector2(100.0, 48.0 if compact_layout else 48.0)
	arena_start_button.custom_minimum_size = Vector2(140.0, 48.0)
	play_start_button.custom_minimum_size = Vector2(140.0, 48.0)
	var horizontal_margin: float = clampf(viewport_size.x * 0.025, 8.0, 16.0)
	var vertical_margin: float = clampf(viewport_size.y * 0.025, 8.0, 12.0)
	inventory_panel.offset_left = horizontal_margin
	inventory_panel.offset_right = -horizontal_margin
	inventory_panel.offset_top = vertical_margin
	inventory_panel.offset_bottom = -vertical_margin
	collection_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resize_collection_grid()
	if inventory_panel.visible:
		_refresh_inventory.call_deferred()


func _notification(what: int) -> void:
	if is_instance_valid(_fusion_screen):
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(inventory_panel):
		if inventory_panel.visible:
			_close_inventory()
		elif _touch_enabled:
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if inventory_panel.visible and event.is_action_pressed("ui_cancel"):
		_close_inventory()


func _on_play_pressed() -> void:
	_play_selection_active = true
	_arena_selection_active = false
	_play_team_indices.clear()
	for collection_index: int in PetStorage.team:
		if collection_index >= 0 and collection_index < PetStorage.collection.size():
			_play_team_indices.append(collection_index)
			break
	_play_mount_index = PetStorage.mount_pet_index
	if _play_mount_index < 0 or _play_mount_index >= PetStorage.collection.size() or _play_team_indices.has(_play_mount_index):
		_play_mount_index = -1
	_show_team_selection(false)


func _on_arena_pressed() -> void:
	_arena_selection_active = true
	_play_selection_active = false
	_play_mount_index = -1
	_arena_team_indices.clear()
	var preferred_team: Array[int] = PetStorage.arena_team_indices if not PetStorage.arena_team_indices.is_empty() else PetStorage.team
	for collection_index: int in preferred_team:
		if collection_index >= 0 and collection_index < PetStorage.collection.size() and not _arena_team_indices.has(collection_index):
			_arena_team_indices.append(collection_index)
			if _arena_team_indices.size() == ARENA_TEAM_SIZE:
				break
	for collection_index: int in range(PetStorage.collection.size()):
		if _arena_team_indices.size() >= ARENA_TEAM_SIZE:
			break
		if not _arena_team_indices.has(collection_index):
			_arena_team_indices.append(collection_index)
	_show_team_selection(true)


func _show_team_selection(is_arena: bool) -> void:
	fusion_button.hide()
	menu_center.visible = false
	gold_label.visible = false
	inventory_panel.visible = true
	team_row.visible = true
	loadout_row.visible = true
	team_label.visible = true
	mount_row.visible = not is_arena
	mount_row.get_parent().visible = not is_arena
	mount_label.visible = not is_arena
	arena_start_button.visible = is_arena
	play_start_button.visible = not is_arena
	panel_gold_label.text = "Vàng: %d | Arena miễn phí | Thắng +5 / Thua +2 vàng" % PetStorage.gold
	close_button.text = "Quay lại"
	inventory_panel.get_node("Margin/VBox/Header/Title").text = "Xếp đội Arena 5v5" if is_arena else "Xếp đội trước khi chơi"
	team_label.text = "Đội Arena (dùng mũi tên để đổi thứ tự)" if is_arena else "Pet chiến đấu (chọn 1)"
	mount_label.text = "Thú cưỡi (không chiến đấu)"
	inventory_panel.get_node("Margin/VBox/CollectionLabel").text = "Chọn tối đa 5 Pet từ bộ sưu tập" if is_arena else "Chọn Pet chiến đấu hoặc bấm Chọn cưỡi"
	_inventory_selection_changed()


func _on_debug_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/DebugBattle.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _open_inventory() -> void:
	fusion_button.show()
	_arena_selection_active = false
	_play_selection_active = false
	panel_gold_label.text = "Vàng: %d" % PetStorage.gold
	menu_center.visible = false
	gold_label.visible = false
	inventory_panel.visible = true
	team_row.visible = false
	mount_row.visible = false
	loadout_row.visible = false
	team_label.visible = false
	mount_label.visible = false
	arena_start_button.visible = false
	play_start_button.visible = false
	close_button.text = "Đóng"
	inventory_panel.get_node("Margin/VBox/Header/Title").text = "Inventory Pet"
	inventory_panel.get_node("Margin/VBox/CollectionLabel").text = "Bộ sưu tập" if _touch_enabled else "Thú đã bắt"
	info_label.text = ""
	_refresh_inventory()
	close_button.grab_focus()


func _open_fusion() -> void:
	if not inventory_panel.visible or _play_selection_active or _arena_selection_active or is_instance_valid(_fusion_screen):
		return
	_fusion_screen = (load("res://scenes/pet_fusion.tscn") as PackedScene).instantiate() as Control
	_fusion_screen.connect("closed", _on_fusion_closed)
	inventory_panel.hide()
	add_child(_fusion_screen)


func _on_fusion_closed() -> void:
	_fusion_screen.queue_free()
	_fusion_screen = null
	_open_inventory()
	fusion_button.grab_focus()


func _close_inventory() -> void:
	fusion_button.hide()
	var was_arena_selection: bool = _arena_selection_active
	var was_play_selection: bool = _play_selection_active
	inventory_panel.visible = false
	team_row.visible = false
	mount_row.visible = false
	loadout_row.visible = false
	team_label.visible = false
	mount_label.visible = false
	arena_start_button.visible = false
	play_start_button.visible = false
	close_button.text = "Đóng"
	_arena_selection_active = false
	_play_selection_active = false
	inventory_panel.get_node("Margin/VBox/Header/Title").text = "Inventory Pet"
	team_label.text = "Pet chiến đấu (chọn 1)"
	mount_label.text = "Thú cưỡi (không chiến đấu)"
	inventory_panel.get_node("Margin/VBox/CollectionLabel").text = "Bộ sưu tập" if _touch_enabled else "Thú đã bắt"
	menu_center.visible = true
	gold_label.visible = true
	if was_arena_selection:
		arena_button.grab_focus()
	elif was_play_selection:
		play_button.grab_focus()
	else:
		inventory_button.grab_focus()


func _refresh_inventory() -> void:
	for child: Node in team_row.get_children():
		child.queue_free()
	for child: Node in mount_row.get_children():
		child.queue_free()
	for child: Node in collection_grid.get_children():
		child.queue_free()

	var selection_active: bool = _arena_selection_active or _play_selection_active
	team_row.visible = selection_active
	loadout_row.visible = selection_active
	team_label.visible = selection_active
	mount_row.visible = _play_selection_active
	mount_row.get_parent().visible = _play_selection_active
	mount_label.visible = _play_selection_active
	var team_size: int = ARENA_TEAM_SIZE if _arena_selection_active else PetStorage.TEAM_SIZE
	if selection_active:
		for team_slot: int in range(team_size):
			team_row.add_child(_create_team_slot(team_slot))
	if _play_selection_active:
		mount_row.add_child(_create_mount_slot())

	if PetStorage.collection.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "Chưa có thú."
		collection_grid.add_child(empty_label)
		return
	for collection_index: int in range(PetStorage.collection.size()):
		collection_grid.add_child(_create_collection_card(collection_index))


func _create_team_slot(team_slot: int) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var selected_team: Array[int] = _arena_team_indices if _arena_selection_active else _play_team_indices
	var has_pet: bool = team_slot < selected_team.size()
	var card: Button = Button.new()
	card.custom_minimum_size = Vector2(112.0, 56.0) if _is_compact_touch_layout() else Vector2(156.0, 96.0) if _touch_enabled else CARD_SIZE
	if has_pet:
		var collection_index: int = selected_team[team_slot]
		_fill_card(card, collection_index, "")
		card.tooltip_text += "\nBấm để bỏ khỏi đội"
		card.pressed.connect(func() -> void:
			if _arena_selection_active:
				_arena_team_indices.remove_at(team_slot)
			else:
				_play_team_indices.remove_at(team_slot)
			_inventory_selection_changed())
	else:
		card.text = "(trống)"
		card.disabled = true
	box.add_child(card)

	if not _arena_selection_active:
		return box

	var arrows: HBoxContainer = HBoxContainer.new()
	arrows.alignment = BoxContainer.ALIGNMENT_CENTER
	for offset: int in [-1, 1]:
		var arrow: Button = Button.new()
		arrow.text = "<" if offset < 0 else ">"
		arrow.custom_minimum_size = Vector2(44.0, 32.0) if _is_compact_touch_layout() else Vector2(64, 48) if _touch_enabled else Vector2(40, 26)
		arrow.disabled = not has_pet or team_slot + offset < 0 or team_slot + offset >= selected_team.size()
		arrow.pressed.connect(func() -> void:
			if _arena_selection_active:
				var moved_index: int = _arena_team_indices[team_slot]
				_arena_team_indices[team_slot] = _arena_team_indices[team_slot + offset]
				_arena_team_indices[team_slot + offset] = moved_index
			else:
				var moved_index: int = _play_team_indices[team_slot]
				_play_team_indices[team_slot] = _play_team_indices[team_slot + offset]
				_play_team_indices[team_slot + offset] = moved_index
			_inventory_selection_changed())
		arrows.add_child(arrow)
	box.add_child(arrows)
	return box


func _create_mount_slot() -> Control:
	var card: Button = Button.new()
	card.custom_minimum_size = Vector2(112.0, 56.0) if _is_compact_touch_layout() else Vector2(156.0, 96.0) if _touch_enabled else CARD_SIZE
	if _play_mount_index >= 0 and _play_mount_index < PetStorage.collection.size():
		_fill_card(card, _play_mount_index, "Cưỡi: ")
		card.tooltip_text += "\nBấm để bỏ chọn thú cưỡi"
		card.pressed.connect(func() -> void:
			_play_mount_index = -1
			_inventory_selection_changed())
	else:
		card.text = "Chưa chọn\nthú cưỡi"
		card.disabled = true
	return card


func _create_collection_card(collection_index: int) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var card: Button = Button.new()
	card.custom_minimum_size = Vector2(112.0, 64.0) if _is_compact_touch_layout() else Vector2(156.0, 96.0) if _touch_enabled else CARD_SIZE
	var selection_active: bool = _arena_selection_active or _play_selection_active
	card.toggle_mode = selection_active
	card.button_pressed = _arena_team_indices.has(collection_index) if _arena_selection_active else _play_team_indices.has(collection_index) if _play_selection_active else false
	_fill_card(card, collection_index, "[x] " if card.button_pressed else "")
	card.pressed.connect(_on_collection_card_pressed.bind(collection_index))
	box.add_child(card)

	if _play_selection_active:
		var mount_button: Button = Button.new()
		mount_button.text = "Đang chọn cưỡi" if _play_mount_index == collection_index else "Chọn cưỡi"
		mount_button.custom_minimum_size.y = 48.0 if _touch_enabled else 32.0
		mount_button.toggle_mode = true
		mount_button.button_pressed = _play_mount_index == collection_index
		mount_button.pressed.connect(_on_mount_card_pressed.bind(collection_index))
		box.add_child(mount_button)
		return box

	if selection_active:
		return box

	var release_button: Button = Button.new()
	release_button.text = "Thả"
	if _touch_enabled:
		release_button.custom_minimum_size.y = 36.0 if _is_compact_touch_layout() else 48.0
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
	card.add_theme_font_size_override("font_size", 14 if _touch_enabled else 11)
	if _touch_enabled:
		card.add_theme_constant_override("icon_max_width", 32)
		card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.text = "%s%s\n%s\nHP %d  ATK %d" % [prefix, pet["name"], pet["attack_style"], pet["max_hp"], pet["attack_damage"]]
	else:
		card.text = "%s%s\n%s  HP %d  ATK %d" % [prefix, pet["name"], pet["attack_style"], pet["max_hp"], pet["attack_damage"]]
	card.tooltip_text = _build_pet_tooltip(pet)


func _build_pet_tooltip(pet: Dictionary) -> String:
	return preload("res://scripts/pet_details.gd").build_tooltip(pet)


func _get_trait_description(trait_name: String, pet: Dictionary) -> String:
	return preload("res://scripts/pet_details.gd").get_trait_description(trait_name, pet)


func _on_collection_card_pressed(collection_index: int) -> void:
	if _arena_selection_active:
		var selected_team: Array[int] = _arena_team_indices
		if selected_team.has(collection_index):
			selected_team.erase(collection_index)
		elif selected_team.size() < ARENA_TEAM_SIZE:
			selected_team.append(collection_index)
		else:
			info_label.text = "Đội đã đủ %d Pet. Bỏ bớt một Pet trước khi thêm." % ARENA_TEAM_SIZE
		_inventory_selection_changed()
		return
	if _play_selection_active:
		if _play_team_indices.has(collection_index):
			_play_team_indices.clear()
		else:
			_play_team_indices.assign([collection_index])
			if _play_mount_index == collection_index:
				_play_mount_index = -1
		_inventory_selection_changed()
		return
	info_label.text = _build_pet_tooltip(PetStorage.get_runtime_pet(collection_index))


func _on_mount_card_pressed(collection_index: int) -> void:
	if _play_mount_index == collection_index:
		_play_mount_index = -1
	else:
		_play_mount_index = collection_index
		_play_team_indices.erase(collection_index)
	_inventory_selection_changed()


func _inventory_selection_changed() -> void:
	if _arena_selection_active:
		info_label.text = "%d / %d Pet được chọn cho Arena 5v5." % [_arena_team_indices.size(), ARENA_TEAM_SIZE]
		arena_start_button.disabled = _arena_team_indices.size() != ARENA_TEAM_SIZE
	else:
		var mount_name: String = "chưa chọn"
		if _play_mount_index >= 0 and _play_mount_index < PetStorage.collection.size():
			mount_name = str(PetStorage.collection[_play_mount_index].get("name", "Pet"))
		info_label.text = "%d / 1 Pet chiến đấu | Thú cưỡi: %s" % [_play_team_indices.size(), mount_name]
		_update_play_entry_state()
	_refresh_inventory.call_deferred()


func _start_game() -> void:
	if not _play_selection_active or (_play_team_indices.size() != PetStorage.TEAM_SIZE and not PetStorage.collection.is_empty()):
		return
	if not PetStorage.spend_gold(PetStorage.CAPTURE_ENTRY_COST):
		_update_play_entry_state()
		return
	PetStorage.team.assign(_play_team_indices)
	var mount_index: int = _play_mount_index if _play_mount_index >= 0 and _play_mount_index < PetStorage.collection.size() and not PetStorage.team.has(_play_mount_index) else -1
	if not PetStorage.set_mount_pet(mount_index):
		PetStorage.set_mount_pet(-1)
	_play_selection_active = false
	var scene_error: Error = get_tree().change_scene_to_file(GAME_SCENE)
	if scene_error != OK:
		_play_selection_active = true
		PetStorage.add_gold(PetStorage.CAPTURE_ENTRY_COST)
		info_label.text = "Không thể mở màn chơi. Đã hoàn lại phí vào chơi."


func _start_arena() -> void:
	if _arena_team_indices.size() != ARENA_TEAM_SIZE:
		return
	if not PetStorage.set_arena_team(_arena_team_indices):
		return
	PetStorage.arena_lineup.clear()
	for collection_index: int in _arena_team_indices:
		PetStorage.arena_lineup.append(PetStorage.get_runtime_pet(collection_index))
	_arena_selection_active = false
	get_tree().change_scene_to_file(ARENA_SCENE)
