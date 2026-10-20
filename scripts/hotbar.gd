# Hot bar hiển thị Pet chiến đấu duy nhất đang được chọn hoặc triệu hồi.
extends CanvasLayer

const SLOT_COUNT: int = 1
const SLOT_SIZE: Vector2 = Vector2(26.0, 30.0)
const MOBILE_CONTROLS: GDScript = preload("res://scripts/mobile_controls.gd")

var _player: Node
var _slots: Array[Dictionary] = []
var _touch_enabled: bool = MOBILE_CONTROLS.is_enabled()
var _gold_label: Label


func _ready() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	row.position = Vector2(24.0, 24.0) if _touch_enabled else Vector2(16.0, 16.0)
	add_child(row)

	for slot_index: int in range(SLOT_COUNT):
		row.add_child(_create_slot(slot_index))
	_gold_label = Label.new()
	_gold_label.name = "GoldBalance"
	_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_label.add_theme_color_override("font_color", Color("#ffd15a"))
	_gold_label.add_theme_font_size_override("font_size", 20)
	row.add_child(_gold_label)
	PetStorage.gold_changed.connect(_update_gold_display)
	_update_gold_display(PetStorage.gold)
	if _touch_enabled:
		var mobile_controls: CanvasLayer = MOBILE_CONTROLS.new()
		mobile_controls.name = "MobileControls"
		add_child(mobile_controls)


func _update_gold_display(balance: int) -> void:
	_gold_label.text = "  Vàng: %d" % balance


func _create_slot(slot_index: int) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(64.0, 64.0) if _touch_enabled else SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_slot_input.bind(slot_index))

	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var number_label: Label = Label.new()
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number_label.text = str(slot_index + 1)
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.add_theme_font_size_override("font_size", 14 if _touch_enabled else 8)
	column.add_child(number_label)

	var icon: TextureRect = TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(48.0, 40.0) if _touch_enabled else Vector2(20.0, 14.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(icon)

	_slots.append({"panel": panel, "icon": icon, "state": null})
	return panel


func _on_slot_input(event: InputEvent, slot_index: int) -> void:
	var tapped: bool = event is InputEventScreenTouch and event.pressed
	var clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION and not Input.emulate_touch_from_mouse
	if tapped or clicked:
		if not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player")
		if is_instance_valid(_player):
			_player.call("_switch_to_pet", slot_index)
		(_slots[slot_index]["panel"] as Control).accept_event()


# Đọc danh sách thú của Player mỗi frame để cũng bắt được trường hợp Pet tự chết.
func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return

	var pets: Array = _player.captured_pets
	var active_index: int = _player.selected_pet_index if is_instance_valid(_player.active_pet) else -1

	for slot_index: int in range(SLOT_COUNT):
		var slot: Dictionary = _slots[slot_index]
		var pet_data: Dictionary = pets[slot_index] if slot_index < pets.size() else {}
		var fainted: bool = pet_data.get("fainted", false)
		var state: Array = [pet_data.get("name", ""), slot_index == active_index, fainted]
		if slot["state"] == state:
			continue

		slot["state"] = state
		(slot["icon"] as TextureRect).texture = pet_data.get("texture")
		(slot["icon"] as TextureRect).modulate = Color(0.3, 0.3, 0.3, 0.6) if fainted else Color.WHITE
		(slot["panel"] as PanelContainer).add_theme_stylebox_override("panel", _make_style(slot_index == active_index, not pet_data.is_empty()))


func _make_style(active: bool, filled: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.2, 0.22, 0.9) if filled else Color(0.1, 0.12, 0.14, 0.7)
	style.border_color = Color("#f4d06f") if active else Color(0.35, 0.4, 0.42, 1.0)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(2.0)
	return style
