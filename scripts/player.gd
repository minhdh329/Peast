# Script gắn vào node gốc là CharacterBody2D của nhân vật chính.
extends CharacterBody2D

# @export hiển thị biến trong Inspector để chỉnh mà không cần sửa code.
# Tốc độ di chuyển ngang (pixel/giây).
@export var SPEED: float = 200.0
# Vận tốc nhảy; âm vì trục Y của Godot hướng xuống dưới (nhảy lên = Y giảm).
@export var JUMP_VELOCITY: float = -400.0
# Scene Pet được tạo khi người chơi triệu hồi.
@export var pet_scene: PackedScene
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
# Thú cưỡi được chọn riêng và không nằm trong danh sách Pet chiến đấu.
var mount_pet_data: Dictionary = {}
# Vị trí trong captured_pets của thú đang được triệu hồi hoặc được chọn gần nhất.
var selected_pet_index: int = 0
# Tham chiếu tới Pet đang được triệu hồi để có thể thu hồi bằng cùng phím.
var active_pet: Pet
# Pet chiến đấu duy nhất dùng phím 1.
const PET_SLOT_ACTIONS: Array[String] = ["summon_pet_1"]
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const MOBILE_CONTROLS: GDScript = preload("res://scripts/mobile_controls.gd")
const GROUND_MOUNT_SPEED_MULTIPLIER: float = 1.5
const SWIM_MOUNT_SPEED_MULTIPLIER: float = 1.5
const SWIM_MOUNT_LAND_SPEED_MULTIPLIER: float = 0.25
var _touch_enabled: bool = MOBILE_CONTROLS.is_enabled()
var _is_dead: bool = false
var is_mounted: bool = false
var _mounted_type: int = Monster.MountType.GROUND
var _mount_sprite: Sprite2D
var _default_sprite_position: Vector2
# Đếm số lần Player đã nhảy kể từ lần chạm đất gần nhất.
var jump_count: int = 0
# Trạng thái được bật khi Player đang ở dưới mặt nước của biome Ocean.
var is_swimming: bool = false
# Vận tốc knockback tạm thời từ các đòn đánh của Monster.
var _knockback_velocity: Vector2 = Vector2.ZERO
# Thời gian còn lại mà knockback được ưu tiên hơn điều khiển ngang.
var _knockback_time_remaining: float = 0.0
var _drop_through_floor_y: float = NAN

# Lấy giá trị trọng lực mặc định từ Project Settings > Physics > 2D > Default Gravity.
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# Tham chiếu tới node hình ảnh con tên "Sprite2D" (AnimatedSprite2D cũng có flip_h,
# nếu dùng loại đó hãy đổi tên/đường dẫn cho khớp scene của bạn).
@onready var sprite: Sprite2D = $Sprite2D
@onready var water_detector: Area2D = $WaterDetector
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


func _ready() -> void:
	collision_mask |= ProceduralTerrain.PLATFORM_COLLISION_MASK
	add_to_group("player")
	_default_sprite_position = sprite.position
	captured_pets = PetStorage.get_team_runtime()
	mount_pet_data = PetStorage.get_mount_runtime_pet()
	mount_pet_data = PetStorage.get_mount_runtime_pet()
	current_hp = max_hp
	melee_hitbox.body_entered.connect(_on_melee_hitbox_body_entered)
	_update_health_bar()


func _unhandled_input(event: InputEvent) -> void:
	if not _touch_enabled or _is_dead or status_effects.call("is_stunned"):
		return
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.is_action_pressed("melee_attack"):
		var mobile_controls: MOBILE_CONTROLS = get_tree().get_first_node_in_group("mobile_controls") as MOBILE_CONTROLS
		if mobile_controls != null and mobile_controls.is_pointer_over_button(event.position):
			return
		_start_melee_attack()
		get_viewport().set_input_as_handled()


# _physics_process chạy mỗi khung vật lý cố định; delta là thời gian giữa 2 khung (giây).
func _physics_process(delta: float) -> void:
	# Kiểm tra biome hiện tại để chọn vật lý bơi hoặc vật lý đi bộ.
	var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
	if terrain != null and global_position.y > terrain.fall_death_y:
		if terrain.wrap_sky_fall(self):
			collision_mask |= ProceduralTerrain.PLATFORM_COLLISION_MASK
			_drop_through_floor_y = NAN
			jump_count = 1
		else:
			print("Player đã rơi khỏi map.")
			_die()
			return
	is_swimming = _is_in_water(terrain)
	if Input.is_action_just_pressed("interact") and not status_effects.call("is_stunned"):
		_toggle_mount()
	if not is_nan(_drop_through_floor_y) and global_position.y > _drop_through_floor_y + ProceduralTerrain.TILE_SIZE.y:
		collision_mask |= ProceduralTerrain.PLATFORM_COLLISION_MASK
		_drop_through_floor_y = NAN
	if status_effects.call("is_stunned"):
		velocity.x = 0.0
		if is_mounted and _mounted_uses_free_movement():
			velocity.y = 0.0
		elif is_swimming:
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
	var dropping: bool = false
	if not _mounted_uses_free_movement() and terrain != null and is_on_floor() and Input.is_action_just_pressed("move_down"):
		dropping = _try_drop_through_platform(terrain)
	if is_mounted:
		_process_mounted_movement(delta, dropping)
	else:
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

			if Input.is_action_just_pressed("jump") and is_on_floor() and not dropping:
				velocity.y = JUMP_VELOCITY
				jump_count += 1

		# Trả về -1 (nhấn A), 1 (nhấn D) hoặc 0 (không nhấn / nhấn cả hai).
		var direction: float = Input.get_axis("move_left", "move_right")
		if direction != 0.0:
			if is_swimming and terrain != null:
				velocity.x = move_toward(velocity.x, direction * SPEED * terrain.water_speed_factor, terrain.water_drag * delta)
			else:
				velocity.x = direction * SPEED
			sprite.flip_h = direction < 0.0
		else:
			var stopping_force: float = terrain.water_drag * delta if is_swimming and terrain != null else SPEED
			velocity.x = move_toward(velocity.x, 0.0, stopping_force)

	# Chuột trái bắt đầu một nhát chém cận chiến.
	if Input.is_action_just_pressed("mobile_melee_attack") or (not _touch_enabled and Input.is_action_just_pressed("melee_attack")):
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
	if is_instance_valid(_mount_sprite):
		_mount_sprite.flip_h = sprite.flip_h
	_update_animation()


func _is_in_water(terrain: ProceduralTerrain) -> bool:
	if terrain != null and terrain.is_underwater(global_position):
		return true
	for area: Area2D in water_detector.get_overlapping_areas():
		if area.is_in_group("water"):
			return true
	return false


func _mounted_uses_free_movement() -> bool:
	return is_mounted and (_mounted_type == Monster.MountType.FLY or (_mounted_type == Monster.MountType.SWIM and is_swimming))


func _process_mounted_movement(delta: float, dropping: bool) -> void:
	if _mounted_uses_free_movement():
		var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down").limit_length(1.0)
		var speed_multiplier: float = SWIM_MOUNT_SPEED_MULTIPLIER if _mounted_type == Monster.MountType.SWIM else GROUND_MOUNT_SPEED_MULTIPLIER
		velocity = direction * SPEED * speed_multiplier
		jump_count = 0
	else:
		if not is_on_floor():
			velocity.y += gravity * delta
		else:
			jump_count = 0
		if Input.is_action_just_pressed("jump") and is_on_floor() and not dropping:
			velocity.y = JUMP_VELOCITY
			jump_count += 1
		var horizontal_direction: float = Input.get_axis("move_left", "move_right")
		var speed_multiplier: float = GROUND_MOUNT_SPEED_MULTIPLIER
		if _mounted_type == Monster.MountType.SWIM:
			speed_multiplier = SWIM_MOUNT_LAND_SPEED_MULTIPLIER
		if horizontal_direction != 0.0:
			velocity.x = horizontal_direction * SPEED * speed_multiplier
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
	if not is_zero_approx(velocity.x):
		sprite.flip_h = velocity.x < 0.0


func _toggle_mount() -> void:
	if is_mounted:
		_dismount_mount()
		return
	if mount_pet_data.is_empty():
		return
	var mount_texture: Texture2D = mount_pet_data.get("texture") as Texture2D
	if mount_texture == null:
		return

	_mounted_type = int(mount_pet_data.get("mount_type", Monster.MountType.GROUND))
	is_mounted = true
	_mount_sprite = Sprite2D.new()
	_mount_sprite.texture = mount_texture
	_mount_sprite.scale = mount_pet_data.get("sprite_scale", Vector2.ONE)
	_mount_sprite.flip_h = sprite.flip_h
	_mount_sprite.position = Vector2(0.0, 12.0)
	add_child(_mount_sprite)
	move_child(_mount_sprite, sprite.get_index())
	sprite.position = _default_sprite_position + Vector2(0.0, -10.0)
	sprite.frame = 0
	anim_player.pause()


func _dismount_mount() -> void:
	_clear_mount_visual()


func _clear_mount_visual() -> void:
	is_mounted = false
	_mounted_type = Monster.MountType.GROUND
	if is_instance_valid(_mount_sprite):
		_mount_sprite.queue_free()
	_mount_sprite = null
	sprite.position = _default_sprite_position
	anim_player.play(&"idle")


func _try_drop_through_platform(terrain: ProceduralTerrain) -> bool:
	for collision_index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(collision_index)
		if collision.get_collider() != terrain or collision.get_normal().dot(Vector2.UP) < 0.7:
			continue
		var cell: Vector2i = terrain.local_to_map(terrain.to_local(collision.get_position() + Vector2.DOWN))
		if terrain.get_cell_alternative_tile(cell) != ProceduralTerrain.PLATFORM_ALTERNATIVE:
			continue
		_drop_through_floor_y = terrain.to_global(terrain.map_to_local(cell)).y - ProceduralTerrain.TILE_SIZE.y * 0.5
		collision_mask &= ~ProceduralTerrain.PLATFORM_COLLISION_MASK
		velocity.y = 100.0
		jump_count = 1
		return true
	return false


# Chọn animation theo trạng thái: bơi > trên không > chạy > đứng yên.
func _update_animation() -> void:
	if is_mounted:
		return
	var next_animation: StringName = &"idle"
	if is_swimming:
		next_animation = &"swim"
	elif not is_on_floor():
		next_animation = &"jump"
	elif absf(velocity.x) > 10.0:
		next_animation = &"run"
	if anim_player.current_animation != next_animation:
		anim_player.play(next_animation)


# Bật Hitbox ở phía trước Player trong khoảng thời gian ngắn rồi tắt nó.
func _start_melee_attack() -> void:
	# Bỏ qua lệnh chém mới nếu nhát chém hiện tại chưa kết thúc.
	if _is_attacking:
		return

	_is_attacking = true
	_hit_monster_ids.clear()
	# Lấy hướng từ Player tới con trỏ trong hệ tọa độ cục bộ của Player.
	var aim_direction: Vector2 = _get_aim_direction(global_position)
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


func _get_aim_direction(origin: Vector2) -> Vector2:
	if _touch_enabled:
		return Vector2(-1.0 if sprite.flip_h else 1.0, 0.0)
	var direction: Vector2 = origin.direction_to(get_global_mouse_position())
	if direction == Vector2.ZERO:
		return Vector2(-1.0 if sprite.flip_h else 1.0, 0.0)
	return direction


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


# Monster/debug panel gọi hàm này để hồi sinh Player tại vị trí cho trước với đầy máu.
func respawn(spawn_position: Vector2) -> void:
	_recall_pet()
	current_hp = max_hp
	_update_health_bar()
	global_position = spawn_position
	velocity = Vector2.ZERO
	collision_mask |= ProceduralTerrain.PLATFORM_COLLISION_MASK
	_drop_through_floor_y = NAN
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
	if selected_pet_index >= 0 and selected_pet_index < captured_pets.size():
		captured_pets[selected_pet_index]["fainted"] = true
		captured_pets[selected_pet_index]["current_hp"] = 0
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
	if not _recall_pet():
		return
	if not same_pet_active:
		_summon_pet(index)


func _recall_pet() -> bool:
	if is_instance_valid(active_pet):
		if not active_pet.can_be_recalled():
			return false
		captured_pets[selected_pet_index]["current_hp"] = active_pet.current_hp
		captured_pets[selected_pet_index]["revive_available"] = active_pet._revive_available
		active_pet.queue_free()
	active_pet = null
	return true


# Tạo Pet từ dữ liệu trong captured_pets và gắn nó theo Player.
func _summon_pet(index: int) -> void:
	if is_instance_valid(active_pet):
		return
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
