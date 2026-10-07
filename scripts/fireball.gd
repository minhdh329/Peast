# Projectile Area2D dùng để bay thẳng và phát hiện va chạm với Monster.
class_name FireballProjectile
extends Area2D

# Tốc độ bay của viên đạn tính bằng pixel mỗi giây.
@export var speed: float = 360.0
# Sát thương được Pet ghi đè trước khi phóng.
@export var damage: int = 10
# Thời gian tối đa Fireball tồn tại nếu không trúng vật thể nào.
@export var lifetime: float = 3.0

# Hướng bay được khóa khi Pet phóng đạn.
var _direction: Vector2 = Vector2.RIGHT
# Player sở hữu Pet; Fireball sẽ bỏ qua va chạm với nhân vật này.
var source_player: CharacterBody2D
# Bộ đếm vòng đời để xóa đạn bay hụt khỏi scene.
var _time_remaining: float = 0.0
# Đạn do Monster bắn: trúng Player/Pet thay vì Monster.
var hostile: bool = false
const HOSTILE_HIT_RADIUS: float = 18.0


# Kết nối sự kiện va chạm và khởi động bộ đếm vòng đời.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_time_remaining = lifetime


# Tính hướng từ Fireball tới vị trí mục tiêu tại thời điểm bắn.
func launch_to(target_position: Vector2) -> void:
	var target_direction: Vector2 = target_position - global_position
	if target_direction.length_squared() > 0.001:
		_direction = target_direction.normalized()
	rotation = _direction.angle()


# Pet gán chủ sở hữu để viên đạn có thể đi xuyên qua đúng Player đó.
func set_source_player(player: CharacterBody2D) -> void:
	source_player = player


# Di chuyển viên đạn theo hướng đã khóa và tự xóa khi hết thời gian.
func _physics_process(delta: float) -> void:
	_time_remaining -= delta
	if _time_remaining <= 0.0:
		queue_free()
		return

	global_position += _direction * speed * delta
	if hostile:
		_check_hostile_hit()


# Pet không có body vật lý nên đạn của Monster dò mục tiêu theo khoảng cách.
func _check_hostile_hit() -> void:
	for group_name: String in ["player", "pets"]:
		for target: Node in get_tree().get_nodes_in_group(group_name):
			var target_2d: Node2D = target as Node2D
			if target_2d == null or target_2d.is_queued_for_deletion() or not target_2d.has_method("take_damage"):
				continue
			if target_2d.has_method("is_alive") and not target_2d.call("is_alive"):
				continue
			if global_position.distance_to(target_2d.global_position) <= HOSTILE_HIT_RADIUS:
				target_2d.call("take_damage", damage, global_position)
				queue_free()
				return


# Chỉ Monster mới chặn đạn; đạn bay xuyên địa hình và chủ nhân, không bị tile giữa Pet và mục tiêu xoá mất.
func _on_body_entered(body: Node2D) -> void:
	if hostile:
		return
	if body.is_in_group("monsters") and body.has_method("take_damage"):
		body.call("take_damage", damage, global_position)
		queue_free()
