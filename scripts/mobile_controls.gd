extends CanvasLayer

const BUTTON_SIZE: float = 80.0
const JOYSTICK_SIZE: float = 160.0
const TOUCH_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"jump",
	&"mobile_melee_attack",
]
const BUTTON_CENTERS: Dictionary = {
	"Jump": Vector2(-80.0, -80.0),
	"Attack": Vector2(-164.0, -164.0),
	"Pause": Vector2(-56.0, 56.0),
}

class MobileAnalogStick extends Control:
	signal direction_changed(direction: Vector2)

	const RADIUS: float = 64.0
	const DEADZONE: float = 0.16
	var _finger_index: int = -1
	var _knob_offset: Vector2 = Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		modulate = Color(1.0, 1.0, 1.0, 0.25)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch: InputEventScreenTouch = event as InputEventScreenTouch
			if touch.pressed and _finger_index == -1:
				_finger_index = touch.index
				_update_direction(touch.position)
				accept_event()
			elif not touch.pressed and touch.index == _finger_index:
				reset()
				accept_event()
		elif event is InputEventScreenDrag:
			var drag: InputEventScreenDrag = event as InputEventScreenDrag
			if drag.index == _finger_index:
				_update_direction(drag.position)
				accept_event()

	func reset() -> void:
		_finger_index = -1
		_knob_offset = Vector2.ZERO
		direction_changed.emit(Vector2.ZERO)
		queue_redraw()

	func _update_direction(touch_position: Vector2) -> void:
		var center: Vector2 = size * 0.5
		var offset: Vector2 = touch_position - center
		_knob_offset = offset.limit_length(RADIUS)
		var magnitude: float = minf(offset.length() / RADIUS, 1.0)
		var direction: Vector2 = Vector2.ZERO
		if magnitude > DEADZONE:
			direction = offset.normalized() * ((magnitude - DEADZONE) / (1.0 - DEADZONE))
		direction_changed.emit(direction)
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		draw_circle(center, RADIUS, Color("#25383b"))
		draw_arc(center, RADIUS, 0.0, TAU, 48, Color("#d4e4d8"), 2.0, true)
		draw_circle(center + _knob_offset, 22.0, Color("#f1d58a"))


var _buttons: Array[TouchScreenButton] = []
var _joystick: MobileAnalogStick
var _pause_overlay: ColorRect


static func is_enabled() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or "--mobile-controls" in OS.get_cmdline_user_args()


func _ready() -> void:
	add_to_group("mobile_controls")
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().quit_on_go_back = false
	if "--mobile-controls" in OS.get_cmdline_user_args():
		Input.emulate_touch_from_mouse = true
	_create_joystick()
	_add_button("Jump", &"jump", "^", null, Color("#38885b"))
	_add_button("Attack", &"mobile_melee_attack", "", preload("res://assets/sword.svg"), Color("#b34b4b"))
	var pause_button: TouchScreenButton = _add_button("Pause", &"", "II")
	pause_button.pressed.connect(open_pause)
	_create_pause_overlay()
	get_viewport().size_changed.connect(_layout_buttons)
	_layout_buttons()


func is_pointer_over_button(viewport_position: Vector2) -> bool:
	# TouchScreenButton does not consume the original mouse event.
	for button: TouchScreenButton in _buttons:
		if button.is_visible_in_tree():
			var local_position: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * viewport_position
			if Rect2(Vector2.ZERO, Vector2.ONE * BUTTON_SIZE).has_point(local_position):
				return true
	return false


func _create_joystick() -> void:
	_joystick = MobileAnalogStick.new()
	_joystick.name = "MoveStick"
	_joystick.size = Vector2.ONE * JOYSTICK_SIZE
	_joystick.direction_changed.connect(_on_joystick_direction_changed)
	add_child(_joystick)


func _on_joystick_direction_changed(direction: Vector2) -> void:
	_set_action_strength(&"move_left", maxf(-direction.x, 0.0))
	_set_action_strength(&"move_right", maxf(direction.x, 0.0))
	_set_action_strength(&"move_up", maxf(-direction.y, 0.0))
	_set_action_strength(&"move_down", maxf(direction.y, 0.0))


func _set_action_strength(action_name: StringName, strength: float) -> void:
	if strength <= 0.01:
		Input.action_release(action_name)
	else:
		Input.action_press(action_name, strength)


func _add_button(button_name: String, action_name: StringName, symbol: String, icon: Texture2D = null, color: Color = Color(0.16, 0.22, 0.24, 1.0)) -> TouchScreenButton:
	var button: TouchScreenButton = TouchScreenButton.new()
	button.name = button_name
	button.action = action_name
	button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	button.modulate = Color(1.0, 1.0, 1.0, 0.25)
	button.texture_normal = _button_texture(color)
	button.texture_pressed = _button_texture(color.lightened(0.35))
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = BUTTON_SIZE * 0.5
	button.shape = circle
	add_child(button)
	_buttons.append(button)
	if icon != null:
		var image: TextureRect = TextureRect.new()
		image.texture = icon
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.position = Vector2(20.0, 20.0)
		image.size = Vector2(40.0, 40.0)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(image)
	else:
		var label: Label = Label.new()
		label.text = symbol
		label.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 32)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
	return button


func _button_texture(color: Color) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.92, 1.0])
	gradient.colors = PackedColorArray([color, color, Color(color.r, color.g, color.b, 0.0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = int(BUTTON_SIZE)
	texture.height = int(BUTTON_SIZE)
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _layout_buttons(viewport_size: Vector2 = Vector2.ZERO) -> void:
	if viewport_size == Vector2.ZERO:
		viewport_size = get_viewport().get_visible_rect().size
	var compact_layout: bool = viewport_size.y < 420.0
	var joystick_center_x: float = minf(148.0, viewport_size.x * 0.25)
	var joystick_bottom_margin: float = minf(148.0, viewport_size.y * 0.32)
	_joystick.position = Vector2(joystick_center_x, viewport_size.y - joystick_bottom_margin) - Vector2.ONE * JOYSTICK_SIZE * 0.5
	for button: TouchScreenButton in _buttons:
		var center: Vector2
		if compact_layout:
			match button.name:
				"Jump":
					center = Vector2(viewport_size.x - 72.0, viewport_size.y - 72.0)
				"Attack":
					center = Vector2(viewport_size.x - 168.0, viewport_size.y - 72.0)
				_:
					center = Vector2(viewport_size.x - 56.0, 56.0)
		else:
			center = BUTTON_CENTERS[button.name]
			if center.x < 0.0:
				center.x += viewport_size.x
			if center.y < 0.0:
				center.y += viewport_size.y
		button.position = center - Vector2.ONE * BUTTON_SIZE * 0.5


func _create_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	add_child(_pause_overlay)
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	_pause_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	for entry: Array in [["Resume", "Tiep tuc", close_pause], ["MainMenu", "Menu", _return_to_menu]]:
		var button: Button = Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.custom_minimum_size = Vector2(240.0, 64.0)
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(entry[2])
		column.add_child(button)
	_pause_overlay.hide()


func open_pause() -> void:
	for button: TouchScreenButton in _buttons:
		button.hide()
	_joystick.reset()
	_joystick.hide()
	_release_actions()
	_pause_overlay.show()
	get_tree().paused = true


func close_pause() -> void:
	get_tree().paused = false
	_pause_overlay.hide()
	for button: TouchScreenButton in _buttons:
		button.show()
	_joystick.show()


func _return_to_menu() -> void:
	close_pause()
	_release_actions()
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")


func _release_actions() -> void:
	for action_name: StringName in TOUCH_ACTIONS:
		Input.action_release(action_name)


func _notification(what: int) -> void:
	if not is_instance_valid(_pause_overlay):
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		open_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _pause_overlay.visible:
			close_pause()
		else:
			open_pause()


func _exit_tree() -> void:
	_release_actions()
	if is_instance_valid(_pause_overlay) and _pause_overlay.visible:
		get_tree().paused = false