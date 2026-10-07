# Đăng ký kiểu Monster để CaptureBall có thể nhận diện quái khi va chạm.
class_name Monster
# CharacterBody2D cho phép Monster có collider tương tác với vật thể vật lý.
extends CharacterBody2D

# Máu tối đa của Monster; có thể chỉnh giá trị này trong Inspector.
@export var max_hp: int = 100
# Máu hiện tại; luôn đầy máu khi Monster được spawn.
var current_hp: int = 0
# Kiểu tấn công được kế thừa khi Monster được bắt thành Pet.
@export_enum("Melee", "Ranged") var attack_style: String = "Melee"
# Tên hiển thị của loại Monster này khi trở thành Pet.
@export var monster_name: String = "Monster"
# Lực đẩy Monster theo phương ngang khi trúng đòn.
@export var knockback_strength: float = 180.0
# Lực hất nhẹ lên trên khi trúng đòn.
@export var knockback_lift: float = 60.0
# Tốc độ đi tuần khi chưa phát hiện Player.
@export var patrol_speed: float = 40.0
# Tốc độ Monster chạy về phía mục tiêu.
@export var movement_speed: float = 90.0
# Khoảng cách Monster có thể đứng yên và ra đòn.
@export var attack_range: float = 38.0
# Sát thương Monster gây ra cho Player hoặc Pet.
@export var attack_damage: int = 8
# Thời gian giữa hai đòn đánh liên tiếp.
@export var attack_interval: float = 1.2
# Khoảng cách Monster kiểu Ranged đứng lại và bắn đạn.
@export var ranged_attack_range: float = 200.0
# Melee đánh trúng khi khoảng hở giữa thân Monster và thân mục tiêu không quá giá trị này.
@export var melee_contact_reach: float = 10.0
# Ground: đi bộ có trọng lực; Swim: tự do trong nước; Fly: bay tự do. Tile vẫn chặn mọi kiểu.
@export_enum("Ground", "Swim", "Fly") var movement_mode: String = "Ground"
# Swim/Fly tuần tra qua lại trong khoảng này quanh điểm xuất phát.
@export var free_patrol_range: float = 120.0

const FIREBALL_SCENE: PackedScene = preload("res://scenes/fireball.tscn")

enum State { PATROL, CHASE }

# Lấy trọng lực mặc định để Monster rơi và đứng trên sàn vật lý.
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
# Trạng thái AI hiện tại; đã phát hiện Player thì không quay lại tuần tra trừ khi hết mục tiêu.
var state: State = State.PATROL
# Hướng đi tuần: -1 trái, 1 phải.
var _patrol_direction: float = 1.0
# Bộ đếm thời gian chờ giữa các đòn đánh.
var _attack_cooldown_remaining: float = 0.0
# Giữ lực đẩy của đòn đánh trúng trước đó trong một khoảng ngắn.
var _knockback_time_remaining: float = 0.0
var _home_x: float = NAN
# Tham chiếu tới thanh máu hiển thị bên dưới Monster.
@onready var health_bar: ProgressBar = $HealthBar
# Vùng tròn phát hiện Player.
@onready var detection_zone: Area2D = $DetectionZone
# Raycast ngang dò tường phía trước.
@onready var wall_check: RayCast2D = $WallCheck
# Raycast chếch xuống dò rìa vực phía trước.
@onready var ledge_check: RayCast2D = $LedgeCheck


# Đưa mọi Monster vào cùng một nhóm để panel debug có thể reset chúng.
func _ready() -> void:
	add_to_group("monsters")
	current_hp = max_hp
	wall_check.add_exception(self)
	ledge_check.add_exception(self)
	_update_health_bar()


# Duy trì vật lý, đuổi theo mục tiêu gần nhất và tấn công trong tầm.
func _physics_process(delta: float) -> void:
	if is_nan(_home_x):
		_home_x = global_position.x
	var free_movement: bool = _uses_free_movement()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING if free_movement else CharacterBody2D.MOTION_MODE_GROUNDED
	# Áp dụng trọng lực khi Monster đang ở trên không (trừ khi đang bay/bơi).
	if free_movement:
		pass
	elif not is_on_floor():
		velocity.y += gravity * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0

	# Giảm cooldown đòn đánh theo thời gian vật lý.
	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
	if _knockback_time_remaining > 0.0:
		# Tạm hoãn di chuyển AI để lực knockback vẫn nhìn thấy được.
		_knockback_time_remaining = maxf(_knockback_time_remaining - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		if free_movement:
			velocity.y = move_toward(velocity.y, 0.0, 300.0 * delta)
	elif free_movement:
		if state == State.PATROL:
			_process_free_patrol()
		else:
			_process_free_chase(delta)
	else:
		if state == State.PATROL:
			_process_patrol()
		else:
			_process_chase(delta)

	move_and_slide()


func _uses_free_movement() -> bool:
	if movement_mode == "Fly":
		return true
	if movement_mode == "Swim":
		var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
		return terrain != null and terrain.is_underwater(global_position)
	return false


# Bay/bơi qua lại quanh điểm xuất phát, đảo chiều khi gặp tile.
func _process_free_patrol() -> void:
	if _player_in_detection_zone():
		state = State.CHASE
		return

	_update_rays(_patrol_direction)
	var too_far: bool = (global_position.x - _home_x) * _patrol_direction > free_patrol_range
	if wall_check.is_colliding() or is_on_wall() or too_far:
		_patrol_direction = -_patrol_direction
	velocity.x = _patrol_direction * patrol_speed
	velocity.y = sin(Time.get_ticks_msec() / 400.0) * 18.0


# Lao thẳng tới mục tiêu theo cả hai trục; move_and_slide để tile chặn đường.
func _process_free_chase(delta: float) -> void:
	var target: Node2D = _find_closest_target()
	if target == null:
		state = State.PATROL
		return

	var target_offset: Vector2 = target.global_position - global_position
	if _in_attack_reach(target):
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		if _attack_cooldown_remaining <= 0.0:
			_attack_target(target)
	else:
		velocity = target_offset.normalized() * movement_speed


# Đi qua lại, đảo chiều khi gặp tường hoặc rìa vực; chuyển sang đuổi khi Player vào vùng.
func _process_patrol() -> void:
	if _player_in_detection_zone():
		state = State.CHASE
		return

	_update_rays(_patrol_direction)
	if is_on_floor() and (wall_check.is_colliding() or not ledge_check.is_colliding()):
		_patrol_direction = -_patrol_direction
		_update_rays(_patrol_direction)
	velocity.x = _patrol_direction * patrol_speed


# Đuổi mục tiêu gần nhất và đánh khi vào tầm; hết mục tiêu thì quay lại tuần tra.
func _process_chase(delta: float) -> void:
	var target: Node2D = _find_closest_target()
	if target == null:
		state = State.PATROL
		return

	var target_offset: Vector2 = target.global_position - global_position
	var direction: float = signf(target_offset.x)
	_update_rays(direction)
	if _in_attack_reach(target):
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if _attack_cooldown_remaining <= 0.0:
			_attack_target(target)
	elif is_on_floor() and (wall_check.is_colliding() or not ledge_check.is_colliding()):
		# Không tự lao xuống vực hay đâm tường khi đuổi.
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	else:
		velocity.x = direction * movement_speed


# Ranged: tính từ tâm. Melee: tính từ mép thân Monster tới mép thân mục tiêu, nên đứng trên đầu cũng bị đánh.
func _in_attack_reach(target: Node2D) -> bool:
	if attack_style == "Ranged":
		return global_position.distance_squared_to(target.global_position) <= ranged_attack_range * ranged_attack_range
	return Monster.distance_to_body_surface(target, global_position) - body_radius() <= melee_contact_reach


func body_radius() -> float:
	var circle: CircleShape2D = ($CollisionShape2D as CollisionShape2D).shape as CircleShape2D
	return circle.radius if circle != null else 0.0


# Khoảng cách từ một điểm tới bề mặt CollisionShape2D của body (bỏ qua xoay); Pet cũng dùng.
static func distance_to_body_surface(body: Node2D, point: Vector2) -> float:
	var shape_node: CollisionShape2D = body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return point.distance_to(body.global_position)
	var center: Vector2 = shape_node.global_position
	var shape: Shape2D = shape_node.shape
	if shape is CircleShape2D:
		return point.distance_to(center) - (shape as CircleShape2D).radius
	if shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = shape
		var half_segment: float = maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var closest: Vector2 = Vector2(center.x, clampf(point.y, center.y - half_segment, center.y + half_segment))
		return point.distance_to(closest) - capsule.radius
	if shape is RectangleShape2D:
		var outside: Vector2 = (point - center).abs() - (shape as RectangleShape2D).size * 0.5
		return Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length() + minf(maxf(outside.x, outside.y), 0.0)
	return point.distance_to(center)


# Đặt hướng cho hai raycast theo hướng đi.
func _update_rays(direction: float) -> void:
	if is_zero_approx(direction):
		return
	wall_check.target_position.x = absf(wall_check.target_position.x) * direction
	ledge_check.position.x = absf(ledge_check.position.x) * direction
	wall_check.force_raycast_update()
	ledge_check.force_raycast_update()


# Player nằm trong DetectionZone (Pet không có body vật lý nên không được dò ở đây).
func _player_in_detection_zone() -> bool:
	for body: Node2D in detection_zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


# Chọn mục tiêu sống gần nhất trong group Player và Pet, không giới hạn tầm khi đang đuổi.
func _find_closest_target() -> Node2D:
	var closest_target: Node2D
	var closest_distance_squared: float = INF

	for group_name: String in ["player", "pets"]:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
				continue
			if not candidate.has_method("take_damage"):
				continue
			if candidate.has_method("is_alive") and not candidate.call("is_alive"):
				continue

			var target: Node2D = candidate as Node2D
			if target == null:
				continue

			var distance_squared: float = global_position.distance_squared_to(target.global_position)
			if distance_squared <= closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_target = target

	return closest_target


# Dữ liệu để biến chính Monster này thành Pet: hình ảnh, kiểu đánh và chỉ số.
func get_pet_data() -> Dictionary:
	var monster_sprite: Sprite2D = $Sprite2D
	return {
		"name": monster_name,
		"attack_style": attack_style,
		"texture": monster_sprite.texture,
		"sprite_scale": monster_sprite.scale,
		"max_hp": max_hp,
		"attack_damage": attack_damage,
		"attack_interval": attack_interval,
		"attack_range": attack_range,
		"movement_mode": movement_mode,
		"melee_contact_reach": melee_contact_reach,
	}


# Gây sát thương và khởi động cooldown sau mỗi đòn trúng mục tiêu.
func _attack_target(target: Node2D) -> void:
	if attack_style == "Ranged":
		_shoot_at(target)
	else:
		target.call("take_damage", attack_damage, global_position)
	_attack_cooldown_remaining = attack_interval


# Cùng loại đạn với Pet Ranged, nhưng nhắm Player/Pet và nhuộm màu khác.
func _shoot_at(target: Node2D) -> void:
	var fireball: FireballProjectile = FIREBALL_SCENE.instantiate()
	fireball.hostile = true
	fireball.damage = attack_damage
	fireball.modulate = Color(1.0, 0.55, 0.9)
	get_parent().add_child(fireball)
	fireball.global_position = global_position
	fireball.launch_to(target.global_position)


# Bị đẩy ra khỏi nguồn sát thương và tạm dừng hành vi đuổi bắt.
func _apply_knockback(attack_origin: Vector2) -> void:
	var knockback_direction: float = signf(global_position.x - attack_origin.x)
	if is_zero_approx(knockback_direction):
		knockback_direction = 1.0
	velocity.x = knockback_direction * knockback_strength
	velocity.y = -knockback_lift
	_knockback_time_remaining = 0.2


# Trừ HP, đẩy Monster ra xa hướng tấn công và xóa nó khi HP hết.
func take_damage(amount: int, attack_origin: Vector2) -> void:
	# Không tiếp tục xử lý nếu Monster đã hết HP.
	if current_hp <= 0:
		return

	# Giới hạn HP nhỏ nhất bằng 0 và in trạng thái mới ra Output.
	current_hp = maxi(current_hp - amount, 0)
	_update_health_bar()
	print("Monster nhận ", amount, " sát thương. HP còn: ", current_hp, "/", max_hp)

	# Đẩy Monster tránh xa vị trí bắt đầu đòn đánh.
	_apply_knockback(attack_origin)
	# Bị đánh thì lập tức đuổi theo.
	state = State.CHASE

	# Xóa Monster khỏi scene khi HP đã về 0.
	if current_hp == 0:
		queue_free()


# Đồng bộ ProgressBar với HP hiện tại, kể cả khi max_hp được chỉnh trong Inspector.
func _update_health_bar() -> void:
	health_bar.max_value = maxi(max_hp, 1)
	health_bar.value = clampi(current_hp, 0, maxi(max_hp, 1))
