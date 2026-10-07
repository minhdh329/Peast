# Cổng thoát xuất hiện khi map đã sạch Monster; Player bước vào để về Main Menu.
extends Area2D

const MENU_SCENE := "res://scenes/main_menu.tscn"
const RADIUS := Vector2(20.0, 30.0)

var _time: float = 0.0
var _used: bool = false


func _ready() -> void:
	var shape: CollisionShape2D = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = RADIUS.x
	capsule.height = RADIUS.y * 2.0
	shape.shape = capsule
	add_child(shape)

	var label: Label = Label.new()
	label.text = "EXIT"
	label.position = Vector2(-18.0, -RADIUS.y - 24.0)
	label.add_theme_color_override("font_color", Color("#c9a6ff"))
	add_child(label)

	body_entered.connect(_on_body_entered)
	scale = Vector2.ZERO
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
	_draw_ellipse(RADIUS + Vector2(4.0, 4.0), Color(0.55, 0.3, 1.0, 0.35 + 0.25 * pulse))
	_draw_ellipse(RADIUS, Color("#6a3fd6"))
	_draw_ellipse(RADIUS * (0.65 + 0.1 * pulse), Color("#a77bff"))
	_draw_ellipse(RADIUS * 0.35, Color("#efe6ff"))


func _draw_ellipse(radius: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(32):
		var angle: float = TAU * i / 32.0
		points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _on_body_entered(body: Node2D) -> void:
	if _used or not body.is_in_group("player"):
		return
	_used = true
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
