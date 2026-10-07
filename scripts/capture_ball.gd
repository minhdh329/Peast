# Đăng ký kiểu CaptureBall để Player có thể tạo bóng với kiểu dữ liệu rõ ràng.
class_name CaptureBall
# RigidBody2D tự chịu trọng lực và va chạm của physics engine.
extends RigidBody2D

# Lực ném; chỉnh giá trị này trong Inspector của node CaptureBall trong scene.
@export var throw_force: float = 450.0
# Thời gian bóng nằm yên trên sàn trước khi bắt đầu mờ đi.
@export var despawn_delay: float = 1.5
# Thời gian tween làm alpha của hình ảnh giảm về 0.
@export var fade_duration: float = 0.5

# Lấy Sprite2D để chỉ làm mờ hình ảnh, không làm mờ node vật lý.
@onready var sprite: Sprite2D = $Sprite2D
# Cờ này ngăn nhiều va chạm mặt đất khởi chạy nhiều bộ đếm cùng lúc.
var _is_despawning: bool = false


# Kết nối tín hiệu va chạm để nhận biết lúc bóng chạm sàn.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Bóng rơi xuống nước hoặc ra ngoài map sẽ không chạm sàn nên cần giới hạn thời gian sống.
	get_tree().create_timer(8.0).timeout.connect(queue_free)


# Player gọi hàm này với hướng ngắm (đã chuẩn hóa); trọng lực vẫn làm quỹ đạo cong xuống.
func launch(aim_direction: Vector2) -> void:
	linear_velocity = aim_direction * throw_force


# Chỉ bắt đầu vòng đời biến mất khi bóng chạm một StaticBody2D như sàn thử nghiệm.
func _on_body_entered(body: Node) -> void:
	# Bỏ qua các va chạm phát sinh thêm khi bóng đã bắt đầu biến mất.
	if _is_despawning:
		return

	# Nếu va chạm với Monster thì tính kết quả bắt thú và xóa bóng ngay.
	if body is Monster:
		_is_despawning = true
		_try_capture(body)
		queue_free()
		return

	# Vật thể không phải Monster hay sàn không làm bóng bắt đầu biến mất.
	# TileMapLayer báo va chạm bằng chính node TileMapLayer, không phải StaticBody2D.
	if not (body is StaticBody2D or body is TileMapLayer):
		return

	# Đánh dấu ngay để va chạm lặp không tạo thêm timer hoặc tween.
	_is_despawning = true
	# Bóng vẫn mô phỏng vật lý bình thường (trọng lực, nảy, lăn); chỉ bắt đầu đếm ngược để biến mất.
	_despawn_after_delay()


# Tính tỷ lệ bắt, in kết quả ngẫu nhiên và chỉ xóa Monster khi bắt thành công.
func _try_capture(monster: Monster) -> void:
	# Tránh phép chia cho 0 nếu max_hp bị đặt sai trong Inspector.
	if monster.max_hp <= 0:
		print("Bắt thất bại: max_hp của Monster phải lớn hơn 0.")
		return

	# Tính xác suất đúng theo công thức yêu cầu và giới hạn trong khoảng 0 đến 100%.
	var catch_chance: float = clampf(100.0 - (float(monster.current_hp) / float(monster.max_hp) * 100.0), 0.0, 100.0)
	# Sinh số ngẫu nhiên trong khoảng 0-100 để quyết định thành công hay thất bại.
	var roll: float = randf_range(0.0, 100.0)

	# Nếu kết quả ngẫu nhiên thấp hơn tỷ lệ bắt thì bắt thành công.
	if roll < catch_chance:
		print("Bắt thú thành công! Tỷ lệ: ", catch_chance, "% (roll: ", roll, ")")
		# Tìm Player đang chơi và cập nhật trạng thái có Pet.
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and player.has_method("on_pet_captured"):
			player.call("on_pet_captured", monster.get_pet_data())
		# Xóa Monster khỏi scene khi bắt thành công.
		monster.queue_free()
	else:
		# Khi thất bại chỉ in kết quả; Monster vẫn còn trong scene.
		print("Bắt thú thất bại. Tỷ lệ: ", catch_chance, "% (roll: ", roll, ")")


# Đợi đủ thời gian trên sàn, làm mờ Sprite2D rồi giải phóng node bóng.
func _despawn_after_delay() -> void:
	# Bóng còn nguyên độ sáng trong khoảng thời gian được cấu hình.
	await get_tree().create_timer(despawn_delay).timeout
	# Nếu scene đã xóa bóng trong lúc chờ thì không tiếp tục thao tác lên node đó.
	if not is_inside_tree():
		return

	# Tạo tween chỉ trên alpha của Sprite2D để collider không bị làm mờ theo.
	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(sprite, "modulate:a", 0.0, fade_duration)
	# Đợi tween hoàn tất để hình ảnh biến mất hẳn trước khi xóa node.
	await fade_tween.finished
	queue_free()
