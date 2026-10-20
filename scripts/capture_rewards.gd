extends Control

var _candidates: Array[Dictionary] = []
var _attempted: Array[bool] = []
var _capture_buttons: Array[Button] = []
var _result_labels: Array[Label] = []
var _gold_label: Label
var _finish_button: Button
var _finished: bool = false
var _capture_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _info_buttons: Array[Button] = []
var _info_overlay: ColorRect
var _info_text: RichTextLabel
var _info_title: Label
var _info_icon: TextureRect
var _info_close_button: Button
var _info_origin: Button


func _ready() -> void:
	_candidates.assign(PetStorage.pending_capture_candidates.duplicate(true))
	PetStorage.pending_capture_candidates.clear()
	_capture_rng.randomize()
	get_tree().quit_on_go_back = false
	_build_ui()
	_build_info_dialog()
	PetStorage.gold_changed.connect(_refresh_balance)
	_refresh_balance(PetStorage.gold)
	_finish_button.grab_focus()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("#192627")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Label.new()
	title.text = "Chiến thắng!"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold_label = Label.new()
	_gold_label.name = "GoldBalance"
	_gold_label.add_theme_font_size_override("font_size", 22)
	_gold_label.add_theme_color_override("font_color", Color("#ffd15a"))
	header.add_child(_gold_label)
	var terms: Label = Label.new()
	terms.text = "Bắt thú: %d vàng / lần | Thành công 50%% | Mỗi Monster chỉ thử 1 lần" % PetStorage.CAPTURE_ATTEMPT_COST
	terms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(terms)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var roster: VBoxContainer = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 12)
	scroll.add_child(roster)
	for candidate_index: int in range(_candidates.size()):
		_attempted.append(false)
		_add_candidate_row(roster, candidate_index)
	if _candidates.is_empty():
		var empty: Label = Label.new()
		empty.text = "Không có Monster để bắt."
		roster.add_child(empty)
	_finish_button = Button.new()
	_finish_button.name = "FinishButton"
	_finish_button.text = "Hoàn Thành"
	_finish_button.custom_minimum_size.y = 52.0
	_finish_button.pressed.connect(_finish)
	column.add_child(_finish_button)


func _add_candidate_row(roster: VBoxContainer, candidate_index: int) -> void:
	var pet_data: Dictionary = _candidates[candidate_index]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	roster.add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.texture = pet_data.get("texture") as Texture2D
	icon.custom_minimum_size = Vector2(64.0, 64.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var name_label: Label = Label.new()
	name_label.text = "%d. %s" % [candidate_index + 1, pet_data.get("name", "Monster")]
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(name_label)
	var stats: Label = Label.new()
	stats.text = "HP %d | ATK %d | %s" % [pet_data.get("max_hp", 0), pet_data.get("attack_damage", 0), pet_data.get("movement_mode", "Ground")]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(stats)
	var result: Label = Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(result)
	_result_labels.append(result)
	var info: Button = Button.new()
	info.text = "i"
	info.tooltip_text = "Xem thông tin Monster"
	info.custom_minimum_size = Vector2(48.0, 52.0)
	info.pressed.connect(_show_info.bind(candidate_index))
	row.add_child(info)
	_info_buttons.append(info)
	var capture: Button = Button.new()
	capture.custom_minimum_size = Vector2(156.0, 52.0)
	capture.text = "Bắt · %d vàng · 50%%" % PetStorage.CAPTURE_ATTEMPT_COST
	capture.pressed.connect(_try_capture.bind(candidate_index))
	row.add_child(capture)
	_capture_buttons.append(capture)


func _build_info_dialog() -> void:
	_info_overlay = ColorRect.new()
	_info_overlay.name = "MonsterInfo"
	_info_overlay.color = Color(0.0, 0.0, 0.0, 0.8)
	add_child(_info_overlay)
	_info_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info_overlay.hide()
	var panel: PanelContainer = PanelContainer.new()
	_info_overlay.add_child(panel)
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	_info_icon = TextureRect.new()
	_info_icon.custom_minimum_size = Vector2(64.0, 64.0)
	_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_info_icon)
	_info_title = Label.new()
	_info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_title.add_theme_font_size_override("font_size", 24)
	header.add_child(_info_title)
	_info_text = RichTextLabel.new()
	_info_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_text.add_theme_font_size_override("normal_font_size", 18)
	column.add_child(_info_text)
	_info_close_button = Button.new()
	_info_close_button.text = "Đóng"
	_info_close_button.custom_minimum_size.y = 52.0
	_info_close_button.pressed.connect(_close_info)
	column.add_child(_info_close_button)


func _show_info(candidate_index: int) -> void:
	if _finished or candidate_index < 0 or candidate_index >= _candidates.size():
		return
	var pet_data: Dictionary = _candidates[candidate_index]
	_info_origin = _info_buttons[candidate_index]
	_info_title.text = str(pet_data.get("name", "Monster"))
	_info_icon.texture = pet_data.get("texture") as Texture2D
	_info_text.text = preload("res://scripts/pet_details.gd").build_tooltip(pet_data)
	_info_text.scroll_to_line(0)
	_info_overlay.show()
	_info_close_button.grab_focus()


func _close_info() -> void:
	_info_overlay.hide()
	if is_instance_valid(_info_origin):
		_info_origin.grab_focus()


func _try_capture(candidate_index: int) -> void:
	if _finished or _info_overlay.visible or candidate_index < 0 or candidate_index >= _candidates.size() or _attempted[candidate_index]:
		return
	if PetStorage.gold < PetStorage.CAPTURE_ATTEMPT_COST:
		_refresh_balance(PetStorage.gold)
		return
	_attempted[candidate_index] = true
	if not PetStorage.spend_gold(PetStorage.CAPTURE_ATTEMPT_COST):
		_attempted[candidate_index] = false
		_refresh_balance(PetStorage.gold)
		return
	var success: bool = _capture_rng.randf() < PetStorage.CAPTURE_SUCCESS_CHANCE
	if success:
		PetStorage.add_captured_pet(_candidates[candidate_index].duplicate(true))
		_result_labels[candidate_index].text = "Đã bắt thành công và lưu vào bộ sưu tập."
		_capture_buttons[candidate_index].text = "Đã bắt"
	else:
		_result_labels[candidate_index].text = "Bắt thất bại. Không thể thử lại Monster này."
		_capture_buttons[candidate_index].text = "Đã thất bại"
	_capture_buttons[candidate_index].disabled = true


func _refresh_balance(balance: int) -> void:
	_gold_label.text = "Vàng: %d" % balance
	for candidate_index: int in range(_capture_buttons.size()):
		if _attempted[candidate_index]:
			_capture_buttons[candidate_index].disabled = true
		else:
			_capture_buttons[candidate_index].disabled = balance < PetStorage.CAPTURE_ATTEMPT_COST
			_capture_buttons[candidate_index].text = "Bắt · %d vàng · 50%%" % PetStorage.CAPTURE_ATTEMPT_COST if balance >= PetStorage.CAPTURE_ATTEMPT_COST else "Thiếu %d vàng" % (PetStorage.CAPTURE_ATTEMPT_COST - balance)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	PetStorage.pending_capture_candidates.clear()
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _info_overlay.visible:
			_close_info()
		else:
			_finish()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		if _info_overlay.visible:
			_close_info()
		else:
			_finish()