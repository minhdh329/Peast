extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host: Control = Control.new()
	root.add_child(host)
	current_scene = host
	var panel: PanelContainer = preload("res://scripts/ui_manager.gd").new() as PanelContainer
	panel.hide()
	panel.position = Vector2(100.0, 80.0)
	panel.size = Vector2(600.0, 350.0)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	var close: Button = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(120.0, 48.0)
	column.add_child(close)
	host.add_child(panel)
	await process_frame
	await process_frame
	if not panel.pivot_offset.is_equal_approx(panel.size * 0.5) or not close.pivot_offset.is_equal_approx(close.size * 0.5):
		_fail("Panel and button pivots should automatically track their centers.")
		return
	panel.call("OpenUI")
	if not panel.visible or panel.scale.length() > 0.001 or not is_zero_approx(panel.modulate.a):
		_fail("OpenUI should start a hidden panel at zero scale and alpha: scale=%s alpha=%s visible=%s." % [panel.scale, panel.modulate.a, panel.visible])
		return
	var largest_scale: float = 0.0
	while (panel.get("_panel_tween") as Tween).is_running():
		await process_frame
		largest_scale = maxf(largest_scale, panel.scale.x)
	if largest_scale <= 1.02 or not panel.scale.is_equal_approx(Vector2.ONE) or not is_equal_approx(panel.modulate.a, 1.0):
		_fail("Opening should overshoot then settle at full scale and opacity.")
		return
	close.mouse_entered.emit()
	await create_timer(0.16).timeout
	if not close.scale.is_equal_approx(Vector2.ONE * 1.1):
		_fail("Hover should scale buttons to 1.1.")
		return
	close.mouse_exited.emit()
	await create_timer(0.16).timeout
	if not close.scale.is_equal_approx(Vector2.ONE):
		_fail("Mouse exit should restore scale 1.0.")
		return
	close.pressed.emit()
	var minimum_scale: float = 1.0
	var maximum_scale: float = 0.0
	var button_tweens: Dictionary = panel.get("_button_tweens")
	while (button_tweens[close.get_instance_id()] as Tween).is_running():
		await process_frame
		minimum_scale = minf(minimum_scale, close.scale.x)
		maximum_scale = maxf(maximum_scale, close.scale.x)
	if minimum_scale >= 0.98 or maximum_scale <= 1.02:
		_fail("Press should shrink the button before bouncing back.")
		return
	var dynamic_button: Button = Button.new()
	dynamic_button.text = "Pet"
	column.add_child(dynamic_button)
	await process_frame
	await process_frame
	if not dynamic_button.has_meta("ui_tween_registered") or not dynamic_button.pivot_offset.is_equal_approx(dynamic_button.size * 0.5):
		_fail("New Pet buttons should receive animations and centered pivots automatically.")
		return
	panel.size = Vector2(640.0, 360.0)
	await process_frame
	if not panel.pivot_offset.is_equal_approx(panel.size * 0.5):
		_fail("Panel pivot should stay centered after resizing.")
		return
	panel.call("CloseUI")
	if not panel.visible:
		_fail("CloseUI must not hide the panel before its animation finishes.")
		return
	await create_timer(0.05).timeout
	panel.call("OpenUI")
	await create_timer(0.4).timeout
	if not panel.visible or not panel.scale.is_equal_approx(Vector2.ONE):
		_fail("Reopening during close should cancel the old completion without hiding the new panel.")
		return
	panel.call("CloseUI")
	await panel.ui_closed
	if panel.visible or panel.scale.length() > 0.001 or not is_zero_approx(panel.modulate.a):
		_fail("CloseUI should finish hidden at zero scale and alpha.")
		return
	panel.call("OpenUI")
	panel.call("HideImmediately")
	await create_timer(0.4).timeout
	if panel.visible or not panel.scale.is_equal_approx(Vector2.ONE):
		_fail("Immediate scene handoffs should kill any unfinished popup Tween.")
		return
	host.queue_free()
	await process_frame
	print("UI Tween smoke test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)