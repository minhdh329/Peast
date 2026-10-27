extends Control

signal closed

var _selected_indices: Array[int] = []
var _pet_buttons: Array[Button] = []
var _details_labels: Array[Label] = []
var _slot_buttons: Array[Button] = []
var _roster: VBoxContainer
var _status: Label
var _combine_button: Button
var _confirm: ConfirmationDialog
var _confirming: bool = false
var _closing: bool = false
var _content: MarginContainer
var _result_screen: ColorRect
var _result_image: TextureRect
var _result_details: RichTextLabel
var _result_continue: Button
var _back_button: Button


func _ready() -> void:
	get_tree().quit_on_go_back = false
	_build_ui()
	_build_result_screen()
	_refresh_roster()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("#192627")
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin: MarginContainer = MarginContainer.new()
	_content = margin
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Label.new()
	title.text = "Dung Hợp"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back: Button = Button.new()
	_back_button = back
	back.name = "BackButton"
	back.text = "Quay lại"
	back.custom_minimum_size = Vector2(120.0, 48.0)
	back.pressed.connect(_back)
	header.add_child(back)
	var slots: HBoxContainer = HBoxContainer.new()
	slots.add_theme_constant_override("separation", 12)
	column.add_child(slots)
	for slot_index: int in range(2):
		var slot: Button = Button.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size.y = 80.0
		slot.expand_icon = true
		slot.add_theme_constant_override("icon_max_width", 40)
		slot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slot.pressed.connect(_remove_selection.bind(slot_index))
		slots.add_child(slot)
		_slot_buttons.append(slot)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "CollectionScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_roster = VBoxContainer.new()
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster.add_theme_constant_override("separation", 8)
	scroll.add_child(_roster)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_combine_button = Button.new()
	_combine_button.name = "CombineButton"
	_combine_button.text = "Dung Hợp"
	_combine_button.custom_minimum_size.y = 52.0
	_combine_button.pressed.connect(_request_combine)
	column.add_child(_combine_button)
	_confirm = ConfirmationDialog.new()
	_confirm.name = "FusionConfirm"
	_confirm.title = "Xác nhận dung hợp"
	_confirm.dialog_autowrap = true
	_confirm.ok_button_text = "Dung Hợp"
	_confirm.cancel_button_text = "Hủy"
	_confirm.get_ok_button().custom_minimum_size.y = 48.0
	_confirm.get_cancel_button().custom_minimum_size.y = 48.0
	_confirm.confirmed.connect(_confirm_combine)
	_confirm.canceled.connect(func() -> void: _confirming = false)
	add_child(_confirm)
	back.grab_focus()


func _build_result_screen() -> void:
	_result_screen = ColorRect.new()
	_result_screen.name = "FusionSuccess"
	_result_screen.color = Color("#192627")
	add_child(_result_screen)
	_result_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_screen.hide()
	var margin: MarginContainer = MarginContainer.new()
	_result_screen.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var heading: Label = Label.new()
	heading.text = "Dung hợp thành công!"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("#8fea91"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)
	_result_image = TextureRect.new()
	_result_image.custom_minimum_size = Vector2(144.0, 144.0)
	_result_image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_result_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_result_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(_result_image)
	_result_details = RichTextLabel.new()
	_result_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_details.add_theme_font_size_override("normal_font_size", 18)
	body.add_child(_result_details)
	_result_continue = Button.new()
	_result_continue.name = "ContinueButton"
	_result_continue.text = "Tiếp tục"
	_result_continue.custom_minimum_size.y = 52.0
	_result_continue.pressed.connect(_dismiss_result)
	column.add_child(_result_continue)


func _show_result(pet: Dictionary) -> void:
	_result_image.texture = pet.get("texture") as Texture2D
	_result_details.text = preload("res://scripts/pet_details.gd").build_tooltip(pet)
	_result_details.scroll_to_line(0)
	_content.hide()
	_result_screen.show()
	_result_continue.grab_focus()


func _dismiss_result() -> void:
	_result_screen.hide()
	_content.show()
	_back_button.grab_focus()


func _refresh_roster() -> void:
	for child: Node in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	_pet_buttons.clear()
	_details_labels.clear()
	for collection_index: int in range(PetStorage.collection.size()):
		var pet: Dictionary = PetStorage.get_runtime_pet(collection_index)
		var item: VBoxContainer = VBoxContainer.new()
		_roster.add_child(item)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		item.add_child(row)
		var card: Button = Button.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 64.0
		card.icon = pet.get("texture") as Texture2D
		card.expand_icon = true
		card.add_theme_constant_override("icon_max_width", 40)
		card.text = "%s | HP %d | ATK %d" % [pet.get("name", "Pet"), pet.get("max_hp", 0), pet.get("attack_damage", 0)]
		card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.toggle_mode = true
		card.pressed.connect(_select_pet.bind(collection_index))
		row.add_child(card)
		_pet_buttons.append(card)
		var info: Button = Button.new()
		info.text = "i"
		info.tooltip_text = "Xem thông tin thú"
		info.custom_minimum_size = Vector2(48.0, 48.0)
		info.pressed.connect(_toggle_details.bind(collection_index))
		row.add_child(info)
		var details: Label = Label.new()
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.text = preload("res://scripts/pet_details.gd").build_tooltip(pet)
		details.hide()
		item.add_child(details)
		_details_labels.append(details)
	if PetStorage.collection.is_empty():
		var empty: Label = Label.new()
		empty.text = "Chưa có thú trong bộ sưu tập."
		_roster.add_child(empty)
	_refresh_selection()


func _select_pet(collection_index: int) -> void:
	if _confirming or _closing or _result_screen.visible:
		return
	if int(PetStorage.collection[collection_index].get("fusion_count", 0)) >= PetStorage.MAX_FUSION_COUNT:
		_status.text = "Thú đã đạt giới hạn %d lần dung hợp." % PetStorage.MAX_FUSION_COUNT
		return
	if _selected_indices.has(collection_index):
		_selected_indices.erase(collection_index)
	elif _selected_indices.size() >= 2:
		_refresh_selection()
		_status.text = "Đã chọn đủ 2 thú."
		return
	elif not _selected_indices.is_empty() and _species(collection_index) != _species(_selected_indices[0]):
		_refresh_selection()
		_status.text = "Chỉ được ghép thú cùng loài!"
		return
	else:
		_selected_indices.append(collection_index)
	_refresh_selection()


func _species(collection_index: int) -> String:
	var pet: Dictionary = PetStorage.collection[collection_index]
	return str(pet.get("type", pet.get("name", "")))


func _remove_selection(slot_index: int) -> void:
	if not _confirming and slot_index < _selected_indices.size():
		_selected_indices.remove_at(slot_index)
		_refresh_selection()


func _toggle_details(collection_index: int) -> void:
	_details_labels[collection_index].visible = not _details_labels[collection_index].visible


func _refresh_selection() -> void:
	for collection_index: int in range(_pet_buttons.size()):
		_pet_buttons[collection_index].set_pressed_no_signal(_selected_indices.has(collection_index))
		var at_limit: bool = int(PetStorage.collection[collection_index].get("fusion_count", 0)) >= PetStorage.MAX_FUSION_COUNT
		_pet_buttons[collection_index].disabled = at_limit
		_pet_buttons[collection_index].tooltip_text = "Đã đạt giới hạn %d lần dung hợp." % PetStorage.MAX_FUSION_COUNT if at_limit else ""
		var item: Control = _details_labels[collection_index].get_parent() as Control
		item.visible = _selected_indices.is_empty() or _species(collection_index) == _species(_selected_indices[0])
	for slot_index: int in range(2):
		var slot: Button = _slot_buttons[slot_index]
		var has_pet: bool = slot_index < _selected_indices.size()
		slot.disabled = not has_pet
		slot.icon = null
		slot.tooltip_text = ""
		slot.text = "Thú A" if slot_index == 0 else "Thú B"
		if has_pet:
			var pet: Dictionary = PetStorage.get_runtime_pet(_selected_indices[slot_index])
			slot.icon = pet.get("texture") as Texture2D
			slot.text = "%s\nHP %d | ATK %d" % [pet.get("name", "Pet"), pet.get("max_hp", 0), pet.get("attack_damage", 0)]
			slot.tooltip_text = preload("res://scripts/pet_details.gd").build_tooltip(pet)
	_combine_button.disabled = not _can_combine_selection()
	_status.text = "%d / 2 thú cùng loài | Miễn phí\nMỗi lần: +1%% HP và sát thương cơ bản của loài, tối đa %d lần.\nSố lần mới = số lần cao hơn của hai thú + 1. Thú đạt giới hạn không thể dùng làm nguyên liệu." % [_selected_indices.size(), PetStorage.MAX_FUSION_COUNT]


func _can_combine_selection() -> bool:
	if _selected_indices.size() != 2:
		return false
	for index: int in _selected_indices:
		if index < 0 or index >= PetStorage.collection.size() or int(PetStorage.collection[index].get("fusion_count", 0)) >= PetStorage.MAX_FUSION_COUNT:
			return false
	return true


func _request_combine() -> void:
	if not _can_combine_selection() or _confirming or _closing or _result_screen.visible:
		return
	var first: Dictionary = PetStorage.collection[_selected_indices[0]]
	var second: Dictionary = PetStorage.collection[_selected_indices[1]]
	var fusion_count: int = maxi(int(first.get("fusion_count", 0)), int(second.get("fusion_count", 0))) + 1
	_confirm.dialog_text = "Dung hợp %s và %s?\nHai thú nguyên liệu sẽ bị xóa và thay bằng một thú mới.\nSố lần dung hợp: %d (+%d%% HP và sát thương cơ bản của loài).\nĐặc tính được chọn ngẫu nhiên." % [first.get("name", "Pet"), second.get("name", "Pet"), fusion_count, fusion_count]
	_confirming = true
	_confirm.popup_centered_clamped(Vector2i(560, 220), 0.9)


func _confirm_combine() -> void:
	if not _confirming:
		return
	_confirming = false
	if not _can_combine_selection():
		_refresh_selection()
		_status.text = "Không thể dung hợp: thú đã đạt giới hạn hoặc lựa chọn không còn hợp lệ."
		return
	var result: Dictionary = PetStorage.CombinePets(_selected_indices[0], _selected_indices[1])
	_selected_indices.clear()
	_refresh_roster()
	if result.is_empty():
		_status.text = "Không thể dung hợp hai thú đã chọn."
	else:
		var traits: PackedStringArray = PackedStringArray(result.get("current_traits", []))
		_status.text = "Dung hợp thành công: %s | HP %d | ATK %d\nĐặc tính: %s" % [result.get("name", "Pet"), result.get("max_hp", 0), result.get("attack_damage", 0), ", ".join(traits)]
		_show_result(result)


func _back() -> void:
	if _result_screen.visible:
		_dismiss_result()
		return
	if _confirm.visible:
		_confirm.hide()
		_confirming = false
		return
	if not _closing:
		_closing = true
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		_back()