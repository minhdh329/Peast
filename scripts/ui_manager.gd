extends PanelContainer

signal ui_opened
signal ui_closed

# Tong 0.30 giay: 70% thoi gian phong len 1.1, 30% con lai ve 1.0.
@export_range(0.01, 2.0, 0.01) var open_duration: float = 0.30
# Thoi gian thu nho va mo dan khi dong bang.
@export_range(0.01, 2.0, 0.01) var close_duration: float = 0.18
# Thoi gian chuyen scale khi hover vao/ra.
@export_range(0.01, 1.0, 0.01) var hover_duration: float = 0.12
# Nhan xuong nhanh, sau do nay tro lai cham hon mot chut.
@export_range(0.01, 1.0, 0.01) var press_duration: float = 0.06
@export_range(0.01, 1.0, 0.01) var release_duration: float = 0.10

var _panel_tween: Tween
var _button_tweens: Dictionary = {}
var _target_open: bool = false


func _ready() -> void:
	resized.connect(_center_panel_pivot)
	_center_panel_pivot()
	RegisterButtons(self)
	get_tree().node_added.connect(_on_node_added)
	_target_open = visible


func _center_panel_pivot() -> void:
	pivot_offset = size * 0.5


func OpenUI() -> void:
	if _target_open and visible:
		return
	_stop_panel_tween()
	_center_panel_pivot()
	if not visible:
		scale = Vector2.ZERO
		modulate.a = 0.0
	_target_open = true
	show()
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(self, "scale", Vector2.ONE * 1.1, open_duration * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(self, "modulate:a", 1.0, open_duration * 0.7)
	_panel_tween.chain().tween_property(self, "scale", Vector2.ONE, open_duration * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_panel_tween.chain().tween_callback(func() -> void: ui_opened.emit())


func CloseUI() -> void:
	if not _target_open or not visible:
		return
	_stop_panel_tween()
	_target_open = false
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(self, "scale", Vector2.ZERO, close_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(self, "modulate:a", 0.0, close_duration)
	_panel_tween.chain().tween_callback(_finish_close)


func HideImmediately() -> void:
	_stop_panel_tween()
	_target_open = false
	hide()
	_reset_button_scales()
	scale = Vector2.ONE
	modulate.a = 1.0


func _finish_close() -> void:
	hide()
	_reset_button_scales()
	ui_closed.emit()


func _reset_button_scales() -> void:
	for node: Node in find_children("*", "BaseButton", true, false):
		var button: BaseButton = node as BaseButton
		_stop_button_tween(button.get_instance_id())
		button.scale = Vector2.ONE


func _stop_panel_tween() -> void:
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()


func RegisterButtons(root: Node) -> void:
	if root is BaseButton:
		_register_button(root as BaseButton)
	for child: Node in root.get_children():
		RegisterButtons(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and is_ancestor_of(node):
		_register_button(node as BaseButton)


func _register_button(button: BaseButton) -> void:
	if button.has_meta("ui_tween_registered"):
		return
	button.set_meta("ui_tween_registered", true)
	button.resized.connect(_center_button_pivot.bind(button))
	_center_button_pivot.call_deferred(button)
	button.mouse_entered.connect(_animate_button.bind(button, Vector2.ONE * 1.1))
	button.mouse_exited.connect(_animate_button.bind(button, Vector2.ONE))
	button.pressed.connect(_press_button.bind(button))
	button.tree_exiting.connect(_forget_button.bind(button.get_instance_id()))


func _center_button_pivot(button: BaseButton) -> void:
	if is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


func _animate_button(button: BaseButton, target: Vector2) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return
	_stop_button_tween(button.get_instance_id())
	var tween: Tween = button.create_tween()
	_button_tweens[button.get_instance_id()] = tween
	tween.tween_property(button, "scale", target, hover_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _press_button(button: BaseButton) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return
	_stop_button_tween(button.get_instance_id())
	var tween: Tween = button.create_tween()
	_button_tweens[button.get_instance_id()] = tween
	tween.tween_property(button, "scale", Vector2.ONE * 0.9, press_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * 1.1, release_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not button.is_hovered():
		tween.tween_property(button, "scale", Vector2.ONE, hover_duration)


func _stop_button_tween(instance_id: int) -> void:
	var tween: Tween = _button_tweens.get(instance_id) as Tween
	if tween != null and tween.is_valid():
		tween.kill()


func _forget_button(instance_id: int) -> void:
	_stop_button_tween(instance_id)
	_button_tweens.erase(instance_id)