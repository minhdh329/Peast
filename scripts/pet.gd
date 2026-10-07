# Pet bay theo Player; Pet Swim/Fly va chạm với tile, Pet Ground đi xuyên như trước.
class_name Pet
extends CharacterBody2D

# Khoảng cách Pet bám phía sau Player, tính bằng pixel.
@export var follow_distance: float = 34.0
# Tốc độ Pet di chuyển tới vị trí bám theo.
@export var follow_speed: float = 240.0
# Scene Fireball được tạo mỗi khi timer tấn công hết thời gian.
@export var fireball_scene: PackedScene
# Sát thương mỗi viên Fireball gây ra cho Monster.
@export var attack_damage: int = 10
# Khoảng cách Pet đứng để đánh trực tiếp khi thuộc hệ Melee.
# Melee đánh trúng khi khoảng hở giữa thân Pet và thân Monster không quá giá trị này (giống Monster).
@export var melee_contact_reach: float = 10.0
# Tốc độ Pet áp sát Monster cận chiến.
@export var melee_move_speed: float = 180.0
# Pet Ranged dừng lại và bắn khi cách Monster trong khoảng này (giống Monster Ranged).
@export var ranged_attack_range: float = 200.0
# Máu tối đa của Pet; Monster có thể hạ gục Pet bằng các đòn tấn công.
@export var max_hp: int = 40
# Máu hiện tại của Pet.
@export var current_hp: int = 40

signal fainted

# Tham chiếu tới Player được gán lúc triệu hồi.
var _target_player: CharacterBody2D
# Kiểu tấn công được truyền từ Monster lúc Player bắt thành công.
var _attack_style: String = "Ranged"
# Monster còn sống gần Pet nhất trên toàn map.
var _target_monster: Monster
# Vận tốc đẩy lùi tạm thời khi Monster đánh Pet.
var _knockback_velocity: Vector2 = Vector2.ZERO
# Thời gian còn lại của chuyển động knockback.
var _knockback_time_remaining: float = 0.0
# Đi vòng khi Pet Swim/Fly bị tile chặn; quá số lần thử thì dịch chuyển về cạnh Player.
var _detour_time: float = 0.0
var _detour_direction: Vector2 = Vector2.ZERO
var _detour_attempts: int = 0
const DETOUR_TIME: float = 0.5
const MAX_DETOUR_ATTEMPTS: int = 6
# Lấy Sprite2D để đảo chiều hình Pet theo hướng Player.
@onready var sprite: Sprite2D = $Sprite2D
# Thanh máu hiển thị dưới Pet.
@onready var health_bar: ProgressBar = $HealthBar
# Timer lặp dùng để giới hạn tốc độ bắn.
@onready var attack_timer: Timer = $AttackTimer


# Player truyền chính nó vào hàm này khi Pet được triệu hồi.
func set_follow_target(player: CharacterBody2D) -> void:
	_target_player = player
	add_collision_exception_with(player)


# Biến Pet thành đúng Monster đã bắt: đổi hình ảnh, kiểu đánh, máu và sát thương.
func apply_pet_data(pet_data: Dictionary) -> void:
	_attack_style = pet_data["attack_style"]
	sprite.texture = pet_data["texture"]
	sprite.scale = pet_data["sprite_scale"]
	max_hp = pet_data["max_hp"]
	current_hp = max_hp
	attack_damage = pet_data["attack_damage"]
	melee_contact_reach = pet_data.get("melee_contact_reach", melee_contact_reach)
	attack_timer.wait_time = pet_data.get("attack_interval", attack_timer.wait_time)
	attack_timer.start()
	var movement_mode: String = pet_data.get("movement_mode", "Ground")
	collision_mask = 1 if movement_mode == "Swim" or movement_mode == "Fly" else 0
	_update_health_bar()


# Player truyền kiểu chiến đấu đã lưu từ Monster vào Pet khi triệu hồi.
func set_attack_style(attack_style: String) -> void:
	_attack_style = attack_style


# Kết nối vùng dò và bắt đầu chu kỳ tự động tấn công.
func _ready() -> void:
	add_to_group("pets")
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	attack_timer.start()
	_update_health_bar()


# Cập nhật vị trí Pet mỗi frame để nó bám theo phía sau Player.
func _physics_process(delta: float) -> void:
	# Tự xóa Pet nếu Player không còn tồn tại trong scene.
	if not is_instance_valid(_target_player):
		queue_free()
		return
	if _knockback_time_remaining > 0.0:
		# Cho Pet lùi khỏi Monster trước khi tiếp tục bám theo Player.
		_knockback_time_remaining = maxf(_knockback_time_remaining - delta, 0.0)
		_move(_knockback_velocity * delta, delta, false)
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 1000.0 * delta)
		return

	# Mặc định Player quay phải; kiểm tra Sprite2D để tìm hướng đang nhìn.
	var facing_direction: float = 1.0
	var player_sprite: Sprite2D = _target_player.get_node_or_null("Sprite2D") as Sprite2D
	if player_sprite != null and player_sprite.flip_h:
		facing_direction = -1.0

	# Đặt mục tiêu ở phía sau Player và hơi cao hơn tâm nhân vật.
	var follow_position: Vector2 = _target_player.global_position + Vector2(-follow_distance * facing_direction, -4.0)
	var movement_speed: float = follow_speed
	sprite.flip_h = facing_direction < 0.0

	# Còn Monster trên map thì tự đi tới tấn công; hết Monster thì quay về cạnh Player.
	_refresh_nearest_target()
	if is_instance_valid(_target_monster):
		var pet_to_monster: Vector2 = _target_monster.global_position - global_position
		var stop_distance: float = ranged_attack_range * 0.8
		if _attack_style == "Melee":
			stop_distance = _target_monster.body_radius() + _body_radius() + melee_contact_reach * 0.5
		follow_position = global_position
		if pet_to_monster.length() > stop_distance:
			follow_position = _target_monster.global_position - pet_to_monster.normalized() * stop_distance
		movement_speed = melee_move_speed
		sprite.flip_h = pet_to_monster.x < 0.0

	# Di chuyển mượt với tốc độ độc lập theo thời gian frame.
	var target_position: Vector2 = global_position.move_toward(follow_position, movement_speed * delta)
	_move(target_position - global_position, delta, true)


# Pet Ground dịch chuyển thẳng; Pet Swim/Fly trượt theo tile và được cứu nếu kẹt quá lâu.
func _move(motion: Vector2, delta: float, check_stuck: bool) -> void:
	if collision_mask == 0:
		global_position += motion
		return
	if check_stuck and _detour_time > 0.0:
		_detour_time -= delta
		velocity = _detour_direction * melee_move_speed
		move_and_slide()
		return
	var start_position: Vector2 = global_position
	velocity = motion / delta
	move_and_slide()
	if not check_stuck:
		return
	if motion.length() > 0.5 and start_position.distance_to(global_position) < motion.length() * 0.2:
		# Bị tile chặn: đi vòng sang ngang (đổi bên mỗi lần), thử quá nhiều thì dịch chuyển về Player.
		_detour_attempts += 1
		if _detour_attempts > MAX_DETOUR_ATTEMPTS:
			global_position = _target_player.global_position + Vector2(0.0, -4.0)
			_detour_attempts = 0
			return
		var side: float = 1.0 if _detour_attempts % 2 == 1 else -1.0
		_detour_direction = motion.normalized().orthogonal() * side
		_detour_time = DETOUR_TIME * ceili(_detour_attempts / 2.0)
	else:
		_detour_attempts = 0


# Monster gọi hàm này khi tấn công Pet và truyền vị trí để tính hướng knockback.
func take_damage(amount: int, attack_origin: Vector2) -> void:
	if current_hp <= 0:
		return

	current_hp = maxi(current_hp - amount, 0)
	_update_health_bar()
	print("Pet nhận ", amount, " sát thương. HP còn: ", current_hp, "/", max_hp)
	var knockback_direction: float = signf(global_position.x - attack_origin.x)
	if is_zero_approx(knockback_direction):
		knockback_direction = 1.0
	_knockback_velocity = Vector2(knockback_direction * 180.0, -35.0)
	_knockback_time_remaining = 0.18
	if current_hp == 0:
		print("Pet đã bị hạ gục và không thể gọi lại trong trận này.")
		fainted.emit()
		queue_free()


# Báo Monster không chọn Pet đã hết HP làm mục tiêu.
func is_alive() -> bool:
	return current_hp > 0


# Cập nhật thanh máu theo HP hiện tại.
func _update_health_bar() -> void:
	health_bar.max_value = maxi(max_hp, 1)
	health_bar.value = clampi(current_hp, 0, maxi(max_hp, 1))


# Chọn Monster còn sống gần Pet nhất trên toàn map.
func _refresh_nearest_target() -> void:
	var nearest_monster: Monster
	var nearest_distance_squared: float = INF

	for node: Node in get_tree().get_nodes_in_group("monsters"):
		var candidate: Monster = node as Monster
		if candidate == null or candidate.is_queued_for_deletion() or candidate.current_hp <= 0:
			continue
		var distance_squared: float = global_position.distance_squared_to(candidate.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_monster = candidate

	_target_monster = nearest_monster


func _body_radius() -> float:
	var circle: CircleShape2D = ($CollisionShape2D as CollisionShape2D).shape as CircleShape2D
	return circle.radius if circle != null else 0.0


# Timer gọi hàm này theo attack_interval; chỉ đánh khi mục tiêu đã vào tầm.
func _on_attack_timer_timeout() -> void:
	_refresh_nearest_target()
	if not is_instance_valid(_target_monster):
		return

	var distance_squared: float = global_position.distance_squared_to(_target_monster.global_position)
	if _attack_style == "Melee":
		# Tính từ mép thân tới mép thân nên chạm bất kỳ điểm nào trên Monster cũng đánh được.
		if Monster.distance_to_body_surface(_target_monster, global_position) - _body_radius() <= melee_contact_reach:
			_target_monster.take_damage(attack_damage, global_position)
		return

	if distance_squared > ranged_attack_range * ranged_attack_range:
		return
	if fireball_scene == null:
		push_warning("Hãy gán res://scenes/fireball.tscn vào Fireball Scene trong Inspector của Pet.")
		return

	# Tạo viên đạn trong scene game và khởi hành từ vị trí hiện tại của Pet.
	var fireball: FireballProjectile = fireball_scene.instantiate()
	var game_scene: Node = get_tree().current_scene
	if game_scene == null:
		fireball.free()
		return

	game_scene.add_child(fireball)
	fireball.global_position = global_position
	fireball.damage = attack_damage
	fireball.set_source_player(_target_player)
	# Khóa hướng bay theo vị trí Monster tại thời điểm bắn.
	fireball.launch_to(_target_monster.global_position)
