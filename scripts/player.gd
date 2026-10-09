# Script gắn vào node gốc là CharacterBody2D của nhân vật chính.
extends CharacterBody2D

# @export hiển thị biến trong Inspector để chỉnh mà không cần sửa code.
# Tốc độ di chuyển ngang (pixel/giây).
@export var SPEED: float = 200.0
# Vận tốc nhảy; âm vì trục Y của Godot hướng xuống dưới (nhảy lên = Y giảm).
@export var JUMP_VELOCITY: float = -400.0
# Scene của quả bóng; kéo capture_ball.tscn vào ô này trong Inspector.
@export var capture_ball_scene: PackedScene
# Scene Pet được tạo khi người chơi triệu hồi.
@export var pet_scene: PackedScene
# Điểm ném tính từ tâm Player; độ lệch ngang đổi dấu theo hướng nhân vật quay mặt.
@export var throw_offset: Vector2 = Vector2(24.0, -8.0)
# Lượng HP Monster mất khi bị chém trúng.
@export var melee_damage: int = 10
# Thời gian Hitbox hoạt động cho mỗi nhát chém.
@export var melee_attack_duration: float = 0.2
# Góc cung quét của kiếm tính bằng radian.
@export var sword_swing_arc: float = 0.9
# Máu tối đa của Player để Monster có thể gây sát thương.
@export var max_hp: int = 100
# Máu hiện tại của Player.
@export var current_hp: int = 100
var is_resistant_crab: bool = false

# Mỗi phần tử là một thú đã bắt: {"name": String, "attack_style": String}.
var captured_pets: Array[Dictionary] = []
# Vị trí trong captured_pets của thú đang được triệu hồi hoặc được chọn gần nhất.
var selected_pet_index: int = 0
# Tham chiếu tới Pet đang được triệu hồi để có thể thu hồi bằng cùng phím.
var active_pet: Pet
# Các action phím 1, 2, 3 tương ứng với vị trí 0, 1, 2 trong danh sách.
const PET_SLOT_ACTIONS: Array[String] = ["summon_pet_1", "summon_pet_2", "summon_pet_3"]
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
var _is_dead: bool = false
# Đếm số lần Player đã nhảy kể từ lần chạm đất gần nhất.
var jump_count: int = 0
# Trạng thái được bật khi Player đang ở dưới mặt nước của biome Ocean.
var is_swimming: bool = false
# Vận tốc knockback tạm thời từ các đòn đánh của Monster.
var _knockback_velocity: Vector2 = Vector2.ZERO
# Thời gian còn lại mà knockback được ưu tiên hơn điều khiển ngang.
var _knockback_time_remaining: float = 0.0

# Lấy giá trị trọng lực mặc định từ Project Settings > Physics > 2D > Default Gravity.
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# Tham chiếu tới node hình ảnh con tên "Sprite2D" (AnimatedSprite2D cũng có flip_h,
# nếu dùng loại đó hãy đổi tên/đường dẫn cho khớp scene của bạn).
@onready var sprite: Sprite2D = $Sprite2D
# AnimationPlayer chứa bốn animation idle/run/jump/swim.
@onready var anim_player: AnimationPlayer = $AnimationPlayer
# Area2D làm Hitbox cận chiến; CollisionShape2D bên trong được bật/tắt khi tấn công.
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var melee_hitbox_shape: CollisionShape2D = $MeleeHitbox/CollisionShape2D
# Pivot chứa sprite kiếm và được xoay theo hướng con trỏ khi tấn công.
@onready var sword_pivot: Node2D = $SwordPivot
# Thanh máu cố định tương đối với Player.
@onready var health_bar: ProgressBar = $HealthBar
@onready var status_effects: Node = $StatusEffects

# Cờ ngăn bắt đầu một nhát chém khác khi Hitbox hiện đang hoạt động.
var _is_attacking: bool = false
# Lưu instance ID để mỗi Monster chỉ nhận sát thương một lần trong một nhát chém.
var _hit_monster_ids: Dictionary = {}


# Đăng ký Player để CaptureBall tìm và thông báo khi bắt thành công.
func _ready() -> void:
	add_to_group("player")
	captured_pets = PetStorage.get_team_runtime()
	current_hp = max_hp
	melee_hitbox.body_entered.connect(_on_melee_hitbox_body_entered)
	_update_health_bar()


# _physics_process chạy mỗi khung vật lý cố định; delta là thời gian giữa 2 khung (giây).
func _physics_process(delta: float) -> void:
	# Kiểm tra biome hiện tại để chọn vật lý bơi hoặc vật lý đi bộ.
	var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
	if terrain != null and global_position.y > terrain.fall_death_y:
		print("Player đã rơi khỏi map.")
		_die()
		return
	is_swimming = terrain != null and terrain.is_underwater(global_position)
	if status_effects.call("is_stunned"):
		velocity.x = 0.0
		if is_swimming:
			velocity.y = 0.0
		elif not is_on_floor():
			velocity.y += gravity * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		if terrain != null:
			terrain.wrap_horizontal(self)
		_update_animation()
		return
	if is_swimming:
		# Trong nước, W/S hoặc Space điều khiển hướng bơi theo chiều dọc.
		jump_count = 0
		var swim_direction: float = Input.get_axis("move_up", "move_down")
		if Input.is_action_pressed("jump"):
			swim_direction = -1.0
		velocity.y = move_toward(velocity.y, swim_direction * terrain.swim_speed, terrain.water_drag * delta)
	else:
		# Trên đất liền, áp dụng trọng lực và quy tắc nhảy hiện có.
		if not is_on_floor():
			velocity.y += gravity * delta
		if is_on_floor():
			jump_count = 0

		var max_jumps: int = 2 if is_instance_valid(active_pet) else 1
		if Input.is_action_just_pressed("jump") and jump_count < max_jumps:
			velocity.y = JUMP_VELOCITY
			jump_count += 1

	# Trả về -1 (nhấn A), 1 (nhấn D) hoặc 0 (không nhấn / nhấn cả hai).
	var direction: float = Input.get_axis("move_left", "move_right")

	# Nếu có nhập hướng thì di chuyển.
	if direction != 0.0:
		# Nước làm giảm tốc độ ngang và tăng quán tính bơi.
		if is_swimming and terrain != null:
			velocity.x = move_toward(velocity.x, direction * SPEED * terrain.water_speed_factor, terrain.water_drag * delta)
		else:
			velocity.x = direction * SPEED
		# Lật hình khi đi sang trái (direction < 0), giữ nguyên khi đi sang phải.
		sprite.flip_h = direction < 0.0
	else:
		# Lực cản nước giảm dần vận tốc ngang; trên đất liền dùng cách dừng cũ.
		var stopping_force: float = terrain.water_drag * delta if is_swimming and terrain != null else SPEED
		velocity.x = move_toward(velocity.x, 0.0, stopping_force)

	# Khi vừa bấm action ném, tạo một CaptureBall theo hướng Sprite2D đang quay.
	if Input.is_action_just_pressed("throw_capture_ball"):
		_throw_capture_ball()

	# Chuột trái bắt đầu một nhát chém cận chiến.
	if Input.is_action_just_pressed("melee_attack"):
		_start_melee_attack()

	# Nhấn E để bật/tắt thú đang chọn.
	if Input.is_action_just_pressed("summon_pet"):
		_toggle_pet()

	# Phím 1/2/3 thu hồi thú hiện tại rồi triệu hồi thú ở vị trí tương ứng.
	for slot_index: int in range(PET_SLOT_ACTIONS.size()):
		if Input.is_action_just_pressed(PET_SLOT_ACTIONS[slot_index]):
			_switch_to_pet(slot_index)

	# Ưu tiên lực knockback trong thời gian ngắn để không bị input ngang ghi đè.
	if _knockback_time_remaining > 0.0:
		_knockback_time_remaining = maxf(_knockback_time_remaining - delta, 0.0)
		velocity.x = _knockback_velocity.x
		_knockback_velocity.x = move_toward(_knockback_velocity.x, 0.0, 1000.0 * delta)

	# Di chuyển nhân vật theo velocity và tự xử lý va chạm (trượt theo sàn/tường).
	move_and_slide()
	if terrain != null:
		terrain.wrap_horizontal(self)
	_update_animation()


# Chọn animation theo trạng thái: bơi > trên không > chạy > đứng yên.
func _update_animation() -> void:
	var next_animation: StringName = &"idle"
	if is_swimming:
		next_animation = &"swim"
	elif not is_on_floor():
		next_animation = &"jump"
	elif absf(velocity.x) > 10.0:
		next_animation = &"run"
	if anim_player.current_animation != next_animation:
		anim_player.play(next_animation)


# Tạo bóng ở gần Player rồi đặt vận tốc ban đầu để trọng lực làm cong quỹ đạo.
func _throw_capture_ball() -> void:
	# Báo rõ trong Output nếu scene chưa được gán trong Inspector.
	if capture_ball_scene == null:
		push_warning("Hãy gán res://scenes/capture_ball.tscn vào Capture Ball Scene trong Inspector.")
		return

	# Ném theo hướng con trỏ chuột, tính từ điểm ném (hơi cao hơn tâm Player).
	var throw_origin: Vector2 = global_position + Vector2(0.0, throw_offset.y)
	var aim_direction: Vector2 = throw_origin.direction_to(get_global_mouse_position())
	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2(-1.0 if sprite.flip_h else 1.0, 0.0)
	if not is_zero_approx(aim_direction.x):
		sprite.flip_h = aim_direction.x < 0.0
	var spawn_position: Vector2 = throw_origin + aim_direction * throw_offset.x
	# Tạo một instance mới từ PackedScene và thêm vào scene hiện tại để nó mô phỏng độc lập.
	var capture_ball: CaptureBall = capture_ball_scene.instantiate()
	get_tree().current_scene.add_child(capture_ball)
	# Bóng vẫn va chạm với thế giới nhưng không đẩy hoặc chặn chính người ném.
	capture_ball.add_collision_exception_with(self)
	# Đặt vị trí sau khi thêm vào scene để global_position dùng đúng transform thế giới.
	capture_ball.global_position = spawn_position
	capture_ball.launch(aim_direction)


# Bật Hitbox ở phía trước Player trong khoảng thời gian ngắn rồi tắt nó.
func _start_melee_attack() -> void:
	# Bỏ qua lệnh chém mới nếu nhát chém hiện tại chưa kết thúc.
	if _is_attacking:
		return

	_is_attacking = true
	_hit_monster_ids.clear()
	# Lấy hướng từ Player tới con trỏ trong hệ tọa độ cục bộ của Player.
	var aim_direction: Vector2 = to_local(get_global_mouse_position())
	if aim_direction.length_squared() < 0.001:
		aim_direction = Vector2(-1.0 if sprite.flip_h else 1.0, 0.0)
	else:
		aim_direction = aim_direction.normalized()
	var aim_angle: float = aim_direction.angle()
	# Đặt Hitbox phía trước và xoay nó để hướng về phía con trỏ.
	melee_hitbox.position = aim_direction * 28.0
	melee_hitbox.rotation = aim_angle
	# Làm hiện kiếm tại đầu cung quét rồi cho nó vung qua hướng ngắm.
	sword_pivot.rotation = aim_angle - sword_swing_arc
	sword_pivot.visible = true
	# Bật theo chế độ deferred để thay đổi collision ngoài lúc xử lý physics query.
	melee_hitbox.set_deferred("monitoring", true)
	melee_hitbox_shape.set_deferred("disabled", false)
	# Tạo chuyển động quét kiếm trong cùng khoảng thời gian Hitbox hoạt động.
	var swing_tween: Tween = create_tween()
	swing_tween.tween_property(sword_pivot, "rotation", aim_angle + sword_swing_arc * 0.15, melee_attack_duration)
	swing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await swing_tween.finished
	# Tắt vùng va chạm sau khi nhát chém kết thúc.
	melee_hitbox.set_deferred("monitoring", false)
	melee_hitbox_shape.set_deferred("disabled", true)
	# Ẩn kiếm giữa các nhát chém.
	sword_pivot.visible = false
	_is_attacking = false


# Area2D gọi hàm này khi Hitbox đi vào một PhysicsBody2D.
func _on_melee_hitbox_body_entered(body: Node2D) -> void:
	# Chỉ xử lý đối tượng thuộc group monsters có hàm nhận sát thương.
	if not body.is_in_group("monsters") or not body.has_method("take_damage"):
		return

	# Bỏ qua Monster đã bị đánh trong nhát chém hiện tại.
	var monster_id: int = body.get_instance_id()
	if _hit_monster_ids.has(monster_id):
		return

	_hit_monster_ids[monster_id] = true
	# Gửi sát thương cùng vị trí Player để Monster xác định hướng knockback.
	body.call("take_damage", melee_damage, global_position)


# CaptureBall truyền dữ liệu của chính Monster vừa bắt vào danh sách thú.
func on_pet_captured(pet_data: Dictionary) -> void:
	if PetStorage.add_captured_pet(pet_data):
		captured_pets.append(pet_data)
		print("Đã lưu ", pet_data["name"], " (", pet_data["attack_style"], ") vào ô ", captured_pets.size(), ". Nhấn phím số tương ứng để triệu hồi.")
	else:
		print("Đội đã đủ ", PetStorage.TEAM_SIZE, " Pet. ", pet_data["name"], " được gửi vào Inventory.")


# Monster/debug panel gọi hàm này để hồi sinh Player tại vị trí cho trước với đầy máu.
func respawn(spawn_position: Vector2) -> void:
	_recall_pet()
	current_hp = max_hp
	_update_health_bar()
	global_position = spawn_position
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	_knockback_time_remaining = 0.0


# Monster gọi hàm này khi tấn công Player, truyền vị trí để xác định hướng bị đẩy.
func take_damage(amount: int, attack_origin: Vector2, effect_type: String = "", effect_chance: float = 1.0, is_over_time: bool = false) -> void:
	if current_hp <= 0:
		return

	var damage_taken: int = int(status_effects.call("modify_incoming_damage", amount, effect_type, is_over_time))
	current_hp = maxi(current_hp - damage_taken, 0)
	_update_health_bar()
	print("Player nhận ", damage_taken, " sát thương. HP còn: ", current_hp, "/", max_hp)
	var knockback_direction: float = signf(global_position.x - attack_origin.x)
	if is_zero_approx(knockback_direction):
		knockback_direction = 1.0
	_knockback_velocity = Vector2(knockback_direction * 220.0, 0.0)
	velocity.y = -90.0
	_knockback_time_remaining = 0.18
	if current_hp == 0:
		print("Player đã hết HP.")
		_die()
	elif not effect_type.is_empty() and effect_type != "None":
		status_effects.call("apply_effect", effect_type, attack_origin, effect_chance)


# Player chết thì quay về Main Menu; Pet đã bắt vẫn được lưu.
func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	current_hp = 0
	set_physics_process(false)
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU_SCENE)


# Báo Monster ngừng chọn Player làm mục tiêu khi HP đã hết.
func is_alive() -> bool:
	return current_hp > 0


# Cập nhật thanh máu theo HP hiện tại.
func _update_health_bar() -> void:
	health_bar.max_value = maxi(max_hp, 1)
	health_bar.value = clampi(current_hp, 0, maxi(max_hp, 1))


# Phím E: thu hồi thú đang ra, hoặc triệu hồi thú đang chọn.
func _toggle_pet() -> void:
	if is_instance_valid(active_pet):
		_recall_pet()
	else:
		_summon_pet(selected_pet_index)


func is_pet_fainted(index: int) -> bool:
	return index >= 0 and index < captured_pets.size() and captured_pets[index].get("fainted", false)


func _on_active_pet_fainted() -> void:
	captured_pets[selected_pet_index]["fainted"] = true
	active_pet = null


# Phím số: thu hồi thú hiện tại rồi triệu hồi thú ở ô được chọn; bấm lại đúng ô đang ra thì chỉ thu hồi.
func _switch_to_pet(index: int) -> void:
	if index >= captured_pets.size():
		print("Ô ", index + 1, " chưa có thú.")
		return
	if is_pet_fainted(index):
		print(captured_pets[index]["name"], " đã bị hạ gục, không thể gọi lại trong trận này.")
		return

	var same_pet_active: bool = is_instance_valid(active_pet) and selected_pet_index == index
	_recall_pet()
	if not same_pet_active:
		_summon_pet(index)


func _recall_pet() -> void:
	if is_instance_valid(active_pet):
		active_pet.queue_free()
	active_pet = null


# Tạo Pet từ dữ liệu trong captured_pets và gắn nó theo Player.
func _summon_pet(index: int) -> void:
	if captured_pets.is_empty():
		print("Bạn chưa có Pet để triệu hồi.")
		return
	if pet_scene == null:
		push_warning("Hãy gán res://scenes/pet.tscn vào Pet Scene trong Inspector.")
		return

	selected_pet_index = clampi(index, 0, captured_pets.size() - 1)
	if is_pet_fainted(selected_pet_index):
		print(captured_pets[selected_pet_index]["name"], " đã bị hạ gục, không thể gọi lại trong trận này.")
		return
	var pet_data: Dictionary = captured_pets[selected_pet_index]
	active_pet = pet_scene.instantiate()
	active_pet.fainted.connect(_on_active_pet_fainted)
	get_tree().current_scene.add_child(active_pet)
	active_pet.global_position = global_position
	active_pet.set_follow_target(self)
	active_pet.apply_pet_data(pet_data)
	print("Triệu hồi ", pet_data["name"])
