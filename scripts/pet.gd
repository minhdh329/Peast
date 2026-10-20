# Pet bay theo Player; Pet Swim/Fly va chạm với tile, Pet Ground đi xuyên như trước.
class_name Pet
extends CharacterBody2D

# Khoảng cách Pet bám phía sau Player, tính bằng pixel.
@export var follow_distance: float = 34.0
# Tốc độ Pet di chuyển tới vị trí bám theo.
@export var follow_speed: float = 240.0
@export var jump_velocity: float = -400.0
const GROUND_NAVIGATION: GDScript = preload("res://scripts/ground_navigation.gd")
var _ground_navigation = GROUND_NAVIGATION.new()
# Scene Fireball được tạo mỗi khi timer tấn công hết thời gian.
@export var fireball_scene: PackedScene
# Sát thương mỗi viên Fireball gây ra cho Monster.
@export var attack_damage: int = 10
@export var attack_effect: String = "None"
@export var attack_effect_chance: float = 1.0
@export var is_resistant_crab: bool = false
@export var immune_to_knockback: bool = false
@export var chain_lightning: bool = false
@export_range(1.0, 512.0, 1.0) var chain_lightning_radius: float = 72.0
@export_range(0.0, 1.0, 0.05) var chain_lightning_damage_fraction: float = 0.25
@export var wind_dash_enabled: bool = false
@export_enum("None", "Cat", "Car") var charge_style: String = "None"
@export var charge_trigger_range: float = 140.0
@export var charge_speed: float = 800.0
var city_charge: Node
@export var dash_speed: float = 900.0
@export var dash_duration: float = 0.25
var attack_count: int = 0
var is_dashing: bool = false
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
@export var split_on_death: bool = false
var split_count: int = 0
var _pet_data: Dictionary = {}

signal fainted

# Tham chiếu tới Player được gán lúc triệu hồi.
var _target_player: CharacterBody2D
# Kiểu tấn công được truyền từ Monster lúc Player bắt thành công.
var _attack_style: String = "Ranged"
var arena_team: String = ""
var _arena_active: bool = true
var _movement_mode: String = "Ground"
var mount_type: int = Monster.MountType.GROUND
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_traits: Array[String] = []
var _revive_available: bool = true
var _is_reviving: bool = false
var _lifesteal_chance: float = Monster.DEFAULT_LIFESTEAL_CHANCE
var _lifesteal_heal_fraction: float = Monster.DEFAULT_LIFESTEAL_HEAL_FRACTION
var _death_explosion_radius: float = 128.0
var _death_explosion_damage: int = Monster.DEFAULT_DEATH_EXPLOSION_DAMAGE
# Monster còn sống gần Pet nhất trên toàn map.
var _target_monster: Node2D
# Vận tốc đẩy lùi tạm thời khi Monster đánh Pet.
var _knockback_velocity: Vector2 = Vector2.ZERO
# Thời gian còn lại của chuyển động knockback.
var _knockback_time_remaining: float = 0.0
# Đi vòng khi Pet Swim/Fly bị tile chặn; quá số lần thử thì dịch chuyển về cạnh Player.
var _detour_time: float = 0.0
var _detour_direction: Vector2 = Vector2.ZERO
var _detour_attempts: int = 0
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_time_remaining: float = 0.0
const DETOUR_TIME: float = 0.5
const MAX_DETOUR_ATTEMPTS: int = 6
# Lấy Sprite2D để đảo chiều hình Pet theo hướng Player.
@onready var sprite: Sprite2D = $Sprite2D
# Thanh máu hiển thị dưới Pet.
@onready var health_bar: ProgressBar = $HealthBar
# Timer lặp dùng để giới hạn tốc độ bắn.
@onready var attack_timer: Timer = $AttackTimer
@onready var ground_check: RayCast2D = $GroundCheck
@onready var status_effects: Node = $StatusEffects
@onready var dash_hitbox: Area2D = $DashHitbox
@onready var passive_vfx: Node2D = $PassiveVFX


# Player truyền chính nó vào hàm này khi Pet được triệu hồi.
func set_follow_target(player: CharacterBody2D) -> void:
	_target_player = player
	add_collision_exception_with(player)


func set_arena_team(team_tag: String) -> void:
	if not arena_team.is_empty() and is_in_group(arena_team):
		remove_from_group(arena_team)
	arena_team = team_tag
	if not arena_team.is_empty():
		add_to_group(arena_team)


func set_arena_active(active: bool) -> void:
	_arena_active = active
	if not active and city_charge != null:
		city_charge.call("finish")
	if not active:
		velocity = Vector2.ZERO


# Biến Pet thành đúng Monster đã bắt: đổi hình ảnh, kiểu đánh, máu và sát thương.
func apply_pet_data(pet_data: Dictionary) -> void:
	_pet_data = pet_data.duplicate(true)
	split_on_death = bool(pet_data.get("split_on_death", false))
	split_count = int(pet_data.get("split_count", 0))
	_attack_style = pet_data["attack_style"]
	sprite.texture = pet_data["texture"]
	sprite.scale = pet_data["sprite_scale"]
	max_hp = pet_data["max_hp"]
	current_hp = clampi(int(pet_data.get("current_hp", max_hp)), 0, max_hp)
	attack_damage = pet_data["attack_damage"]
	attack_effect = str(pet_data.get("attack_effect", "None"))
	attack_effect_chance = float(pet_data.get("attack_effect_chance", 1.0))
	is_resistant_crab = bool(pet_data.get("is_resistant_crab", false))
	immune_to_knockback = bool(pet_data.get("immune_to_knockback", false))
	chain_lightning = bool(pet_data.get("chain_lightning", false))
	chain_lightning_radius = float(pet_data.get("chain_lightning_radius", chain_lightning_radius))
	chain_lightning_damage_fraction = float(pet_data.get("chain_lightning_damage_fraction", chain_lightning_damage_fraction))
	wind_dash_enabled = bool(pet_data.get("wind_dash_enabled", false))
	charge_style = str(pet_data.get("charge_style", "None"))
	charge_trigger_range = float(pet_data.get("charge_trigger_range", 140.0))
	charge_speed = float(pet_data.get("charge_speed", 800.0))
	city_charge.set("trigger_count", int(pet_data.get("city_charge_count", 0)))
	city_charge.set("charge_ready", bool(pet_data.get("city_charge_ready", false)))
	dash_speed = float(pet_data.get("dash_speed", dash_speed))
	dash_duration = float(pet_data.get("dash_duration", dash_duration))
	current_traits.clear()
	for trait_value: Variant in pet_data.get("current_traits", []):
		if trait_value is String and not current_traits.has(trait_value):
			current_traits.append(trait_value)
	_revive_available = bool(pet_data.get("revive_available", true))
	_lifesteal_chance = float(pet_data.get("lifesteal_chance", _lifesteal_chance))
	_lifesteal_heal_fraction = float(pet_data.get("lifesteal_heal_fraction", _lifesteal_heal_fraction))
	_death_explosion_radius = float(pet_data.get("death_explosion_radius", _death_explosion_radius))
	_death_explosion_damage = int(pet_data.get("death_explosion_damage", _death_explosion_damage))
	if current_traits.has(Monster.TRAIT_FAST_MOVEMENT):
		follow_speed *= 1.5
		melee_move_speed *= 1.5
	melee_contact_reach = pet_data.get("melee_contact_reach", melee_contact_reach)
	attack_timer.wait_time = pet_data.get("attack_interval", attack_timer.wait_time)
	attack_timer.start()
	_movement_mode = str(pet_data.get("movement_mode", "Ground"))
	mount_type = int(pet_data.get("mount_type", _get_mount_type_for_movement_mode(_movement_mode)))
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING if _uses_free_movement() else CharacterBody2D.MOTION_MODE_GROUNDED
	collision_mask = 1 | ProceduralTerrain.PLATFORM_COLLISION_MASK
	_update_health_bar()
	passive_vfx.call("refresh")


func _get_mount_type_for_movement_mode(mode: String) -> int:
	match mode:
		"Fly":
			return Monster.MountType.FLY
		"Swim":
			return Monster.MountType.SWIM
		_:
			return Monster.MountType.GROUND


# Player truyền kiểu chiến đấu đã lưu từ Monster vào Pet khi triệu hồi.
func set_attack_style(attack_style: String) -> void:
	_attack_style = attack_style


# Kết nối vùng dò và bắt đầu chu kỳ tự động tấn công.
func _ready() -> void:
	collision_mask |= ProceduralTerrain.PLATFORM_COLLISION_MASK
	add_to_group("pets")
	city_charge = preload("res://scripts/city_charge.gd").new()
	add_child(city_charge)
	ground_check.add_exception(self)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	attack_timer.start()
	_update_health_bar()


# Cập nhật vị trí Pet mỗi frame để nó bám theo phía sau Player.
func _physics_process(delta: float) -> void:
	_ground_navigation.update(self)
	# Tự xóa Pet nếu Player không còn tồn tại trong scene.
	if not is_instance_valid(_target_player) and arena_team.is_empty():
		queue_free()
		return
	if _is_reviving:
		velocity = Vector2.ZERO
		move_and_slide()
		_wrap_horizontal_on_sky_islands()
		return
	var free_movement: bool = _uses_free_movement()
	if free_movement:
		_ground_navigation.reset(self)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING if free_movement else CharacterBody2D.MOTION_MODE_GROUNDED
	if not _arena_active:
		velocity = Vector2.ZERO
		move_and_slide()
		_wrap_horizontal_on_sky_islands()
		return
	if status_effects.call("is_stunned"):
		city_charge.call("finish")
		if is_dashing:
			_finish_wind_dash()
		if not free_movement:
			_move_on_ground(Vector2.ZERO, delta)
		else:
			velocity = Vector2.ZERO
			move_and_slide()
		_wrap_horizontal_on_sky_islands()
		return
	if city_charge.call("step", delta):
		_wrap_horizontal_on_sky_islands()
		return
	if is_dashing:
		_process_wind_dash(delta)
		return
	if _knockback_time_remaining > 0.0:
		# Cho Pet lùi khỏi Monster trước khi tiếp tục bám theo Player.
		_knockback_time_remaining = maxf(_knockback_time_remaining - delta, 0.0)
		_move(_knockback_velocity * delta, delta, false)
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 1000.0 * delta)
		return

	# Mặc định Player quay phải; kiểm tra Sprite2D để tìm hướng đang nhìn.
	var facing_direction: float = 1.0
	if is_instance_valid(_target_player):
		var player_sprite: Sprite2D = _target_player.get_node_or_null("Sprite2D") as Sprite2D
		if player_sprite != null and player_sprite.flip_h:
			facing_direction = -1.0

	# Đặt mục tiêu ở phía sau Player và hơi cao hơn tâm nhân vật.
	var follow_position: Vector2 = global_position
	if arena_team.is_empty() and is_instance_valid(_target_player):
		follow_position = _target_player.global_position + Vector2(-follow_distance * facing_direction, -4.0)
	var movement_speed: float = follow_speed
	sprite.flip_h = facing_direction < 0.0

	# Còn Monster trên map thì tự đi tới tấn công; hết Monster thì quay về cạnh Player.
	_refresh_nearest_target()
	if is_instance_valid(_target_monster):
		var pet_to_monster: Vector2 = _target_monster.global_position - global_position
		var stop_distance: float = ranged_attack_range * 0.8
		if _attack_style == "Melee":
			stop_distance = float(_target_monster.call("body_radius")) + _body_radius() + melee_contact_reach * 0.5
		follow_position = global_position
		if pet_to_monster.length() > stop_distance:
			follow_position = _target_monster.global_position - pet_to_monster.normalized() * stop_distance
		movement_speed = melee_move_speed
		sprite.flip_h = pet_to_monster.x < 0.0
	if not free_movement:
		var goal: Vector2 = follow_position + Vector2(0.0, _body_radius())
		if is_instance_valid(_target_monster):
			goal = GROUND_NAVIGATION.feet_for(_target_monster)
		elif is_instance_valid(_target_player):
			goal = GROUND_NAVIGATION.feet_for(_target_player) + Vector2(-follow_distance * facing_direction, 0.0)
		if _ground_navigation.steer(self, goal, movement_speed, jump_velocity, delta):
			if is_instance_valid(_target_monster) and Monster.distance_to_body_surface(_target_monster, global_position) - _body_radius() <= stop_distance_for_ground_target():
				velocity.x = 0.0
			_move_on_ground(Vector2(velocity.x * delta, 0.0), delta, false)
			_wrap_horizontal_on_sky_islands()
			return

	# Di chuyển mượt với tốc độ độc lập theo thời gian frame.
	var target_position: Vector2 = global_position.move_toward(follow_position, movement_speed * delta)
	_move(target_position - global_position, delta, true)


# Pet Ground đi trên tile bằng gravity; Swim/Fly trượt theo tile và được cứu nếu kẹt quá lâu.
func _move(motion: Vector2, delta: float, check_stuck: bool) -> void:
	if not _uses_free_movement():
		_move_on_ground(motion, delta)
		_wrap_horizontal_on_sky_islands()
		return
	if check_stuck and _detour_time > 0.0:
		_detour_time -= delta
		velocity = _detour_direction * melee_move_speed
		move_and_slide()
		_wrap_horizontal_on_sky_islands()
		return
	var start_position: Vector2 = global_position
	velocity = motion / delta
	move_and_slide()
	_wrap_horizontal_on_sky_islands()
	if not check_stuck:
		return
	if motion.length() > 0.5 and start_position.distance_to(global_position) < motion.length() * 0.2:
		# Bị tile chặn: đi vòng sang ngang (đổi bên mỗi lần), thử quá nhiều thì dịch chuyển về Player.
		_detour_attempts += 1
		if _detour_attempts > MAX_DETOUR_ATTEMPTS:
			global_position = _target_player.global_position + Vector2(0.0, -4.0)
			_detour_attempts = 0
			_wrap_horizontal_on_sky_islands()
			return
		var side: float = 1.0 if _detour_attempts % 2 == 1 else -1.0
		_detour_direction = motion.normalized().orthogonal() * side
		_detour_time = DETOUR_TIME * ceili(_detour_attempts / 2.0)
	else:
		_detour_attempts = 0


func _uses_free_movement() -> bool:
	if _movement_mode == "Fly":
		return true
	if _movement_mode == "Swim":
		var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
		return terrain != null and terrain.is_underwater(global_position)
	return false


func stop_distance_for_ground_target() -> float:
	return melee_contact_reach * 0.5 if _attack_style == "Melee" else ranged_attack_range * 0.8


func _move_on_ground(motion: Vector2, delta: float, check_ledge: bool = true) -> void:
	if is_on_floor():
		if velocity.y > 0.0 and not _ground_navigation.is_dropping():
			velocity.y = 0.0
	else:
		velocity.y += _gravity * delta

	velocity.x = motion.x / maxf(delta, 0.001)
	if check_ledge and is_on_floor() and not is_zero_approx(velocity.x):
		ground_check.position.x = signf(velocity.x) * 12.0
		ground_check.target_position = Vector2(0.0, 26.0)
		ground_check.force_raycast_update()
		if not ground_check.is_colliding():
			velocity.x = 0.0
	move_and_slide()
	_detour_time = 0.0
	_detour_attempts = 0


func _wrap_horizontal_on_sky_islands() -> void:
	var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
	if terrain != null:
		terrain.wrap_horizontal(self)


# Monster gọi hàm này khi tấn công Pet và truyền vị trí để tính hướng knockback.
func take_damage(amount: int, attack_origin: Vector2, effect_type: String = "", effect_chance: float = 1.0, is_over_time: bool = false) -> void:
	if current_hp <= 0 or _is_reviving:
		return

	var damage_taken: int = int(status_effects.call("modify_incoming_damage", amount, effect_type, is_over_time))
	current_hp = maxi(current_hp - damage_taken, 0)
	_update_health_bar()
	print("Pet nhận ", damage_taken, " sát thương. HP còn: ", current_hp, "/", max_hp)
	if not immune_to_knockback:
		var knockback_direction: float = signf(global_position.x - attack_origin.x)
		if is_zero_approx(knockback_direction):
			knockback_direction = 1.0
		_knockback_velocity = Vector2(knockback_direction * 180.0, -35.0)
		_knockback_time_remaining = 0.18
	if current_hp == 0:
		die()
	if current_hp > 0 and not effect_type.is_empty() and effect_type != "None":
		status_effects.call("apply_effect", effect_type, attack_origin, effect_chance)
	if current_hp > 0 and amount > 0 and not is_over_time and charge_style == "Cat":
		city_charge.call("record_hit")


func die() -> void:
	if _is_reviving or is_queued_for_deletion():
		return
	_trigger_death_passives()
	if current_traits.has(Monster.TRAIT_REVIVE) and _revive_available:
		_revive_available = false
		_is_reviving = true
		current_hp = 0
		velocity = Vector2.ZERO
		passive_vfx.call("set_reviving", true)
		_complete_revival.call_deferred()
		return
	print("Pet đã bị hạ gục và không thể gọi lại trong trận này.")
	fainted.emit()
	queue_free()


func _trigger_death_passives() -> void:
	if current_traits.has(Monster.TRAIT_EXPLODE_ON_DEATH):
		_explode_on_death()
	if split_on_death and split_count == 0:
		_split_into_slimes()


func _split_into_slimes() -> void:
	split_count = 1
	var pet_scene: PackedScene = load("res://scenes/pet.tscn")
	var offspring_group: Array[Pet] = []
	for offset: float in [-12.0, 12.0]:
		var offspring: Pet = pet_scene.instantiate() as Pet
		offspring.set_arena_team(arena_team)
		offspring.set_arena_active(_arena_active)
		get_parent().add_child(offspring)
		var offspring_data: Dictionary = _pet_data.duplicate(true)
		offspring_data["max_hp"] = maxi(roundi(max_hp * 0.5), 1)
		offspring_data["current_hp"] = offspring_data["max_hp"]
		offspring_data["attack_damage"] = maxi(roundi(attack_damage * 0.5), 1)
		offspring_data["sprite_scale"] = sprite.scale * 0.5
		offspring_data["current_traits"] = current_traits.duplicate()
		offspring_data["revive_available"] = _revive_available
		offspring_data["split_on_death"] = true
		offspring_data["split_count"] = split_count
		offspring.apply_pet_data(offspring_data)
		if is_instance_valid(_target_player):
			offspring.set_follow_target(_target_player)
		for sibling: Pet in offspring_group:
			offspring.add_collision_exception_with(sibling)
			sibling.add_collision_exception_with(offspring)
		offspring.add_collision_exception_with(self)
		add_collision_exception_with(offspring)
		offspring_group.append(offspring)
		offspring.global_position = global_position + Vector2(offset, 0.0)


func _complete_revival() -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	current_hp = maxi(ceili(max_hp * 0.3), 1)
	_is_reviving = false
	_update_health_bar()
	passive_vfx.call("set_reviving", false)


func restore_lifesteal(damage: int, heal_fraction: float) -> void:
	current_hp = mini(current_hp + maxi(roundi(damage * heal_fraction), 1), max_hp)
	_update_health_bar()


func _try_lifesteal(damage: int) -> void:
	if current_traits.has(Monster.TRAIT_LIFESTEAL) and randf() < _lifesteal_chance:
		restore_lifesteal(damage, _lifesteal_heal_fraction)


func _explode_on_death() -> void:
	passive_vfx.call("play_explosion", _death_explosion_radius)
	var target_group: String = "monsters" if arena_team.is_empty() else _opposing_team_tag()
	for node: Node in get_tree().get_nodes_in_group(target_group):
		var target: Node2D = node as Node2D
		if target == null or target.is_queued_for_deletion() or not target.has_method("take_damage"):
			continue
		if target.has_method("is_alive") and not target.call("is_alive"):
			continue
		if global_position.distance_to(target.global_position) <= _death_explosion_radius:
			target.call("take_damage", _death_explosion_damage, global_position)


# Báo Monster không chọn Pet đã hết HP làm mục tiêu.
func is_alive() -> bool:
	return current_hp > 0 and not _is_reviving


func is_reviving() -> bool:
	return _is_reviving


func can_be_recalled() -> bool:
	return is_alive() and split_count == 0 and not (current_traits.has(Monster.TRAIT_REVIVE) and not _revive_available)


# Cập nhật thanh máu theo HP hiện tại.
func _update_health_bar() -> void:
	health_bar.max_value = maxi(max_hp, 1)
	health_bar.value = clampi(current_hp, 0, maxi(max_hp, 1))


# Chọn Monster còn sống gần Pet nhất trên toàn map.
func _refresh_nearest_target() -> void:
	var nearest_monster: Node2D
	var nearest_distance_squared: float = INF

	var target_group: String = "monsters" if arena_team.is_empty() else _opposing_team_tag()
	for node: Node in get_tree().get_nodes_in_group(target_group):
		var candidate: Node2D = node as Node2D
		if candidate == null or candidate.is_queued_for_deletion() or not candidate.has_method("take_damage"):
			continue
		if candidate.has_method("is_alive") and not candidate.call("is_alive"):
			continue
		if not arena_team.is_empty() and not candidate.is_in_group(_opposing_team_tag()):
			continue
		var distance_squared: float = global_position.distance_squared_to(candidate.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_monster = candidate

	_target_monster = nearest_monster


func _opposing_team_tag() -> String:
	return "TeamEnemy" if arena_team == "TeamPlayer" else "TeamPlayer"


func _body_radius() -> float:
	var circle: CircleShape2D = ($CollisionShape2D as CollisionShape2D).shape as CircleShape2D
	return circle.radius if circle != null else 0.0


func body_radius() -> float:
	return _body_radius()


# Timer gọi hàm này theo attack_interval; chỉ đánh khi mục tiêu đã vào tầm.
func _on_attack_timer_timeout() -> void:
	if not _arena_active or _is_reviving or is_dashing or (city_charge != null and bool(city_charge.get("active"))):
		return
	_refresh_nearest_target()
	if not is_instance_valid(_target_monster):
		return
	if status_effects.call("is_stunned"):
		return

	var distance_squared: float = global_position.distance_squared_to(_target_monster.global_position)
	if _attack_style == "Melee":
		# Tính từ mép thân tới mép thân nên chạm bất kỳ điểm nào trên Monster cũng đánh được.
		if Monster.distance_to_body_surface(_target_monster, global_position) - _body_radius() <= melee_contact_reach:
			var attack_count: int = 2 if current_traits.has(Monster.TRAIT_DOUBLE_ATTACK) else 1
			for attack_index: int in range(attack_count):
				if not is_instance_valid(_target_monster) or _target_monster.is_queued_for_deletion() or not _target_monster.call("is_alive"):
					break
				_target_monster.call("take_damage", attack_damage, global_position, attack_effect, attack_effect_chance)
				_try_lifesteal(attack_damage)
				if charge_style != "None":
					city_charge.call("record_attack", _target_monster)
				if chain_lightning:
					_chain_lightning(_target_monster)
				if city_charge.get("active"):
					break
		return

	if distance_squared > ranged_attack_range * ranged_attack_range:
		return
	if wind_dash_enabled and attack_count == 2:
		_start_wind_dash(_target_monster)
		return
	if fireball_scene == null:
		push_warning("Hãy gán res://scenes/fireball.tscn vào Fireball Scene trong Inspector của Pet.")
		return

	var game_scene: Node = get_tree().current_scene
	if game_scene == null:
		return
	var shots_per_cycle: int = 2 if current_traits.has(Monster.TRAIT_DOUBLE_ATTACK) else 1
	for shot_index: int in range(shots_per_cycle):
		if wind_dash_enabled and attack_count == 2:
			_start_wind_dash(_target_monster)
			break
		var fireball: FireballProjectile = fireball_scene.instantiate()
		game_scene.add_child(fireball)
		fireball.global_position = global_position
		fireball.damage = attack_damage
		fireball.effect_type = attack_effect
		fireball.effect_chance = attack_effect_chance
		fireball.arena_team = arena_team
		fireball.set_source_player(_target_player)
		if current_traits.has(Monster.TRAIT_LIFESTEAL):
			fireball.set_lifesteal_source(self, _lifesteal_chance, _lifesteal_heal_fraction)
		fireball.launch_to(_target_monster.global_position)
		if charge_style != "None":
			city_charge.call("record_attack", _target_monster)
		if wind_dash_enabled:
			attack_count += 1


func _start_wind_dash(target: Node2D) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return
	_dash_direction = (target.global_position - global_position).normalized()
	if _dash_direction.is_zero_approx():
		_dash_direction = Vector2.RIGHT
	_dash_time_remaining = dash_duration
	is_dashing = true
	dash_hitbox.set_deferred("monitoring", true)
	($DashHitbox/CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)


func _process_wind_dash(delta: float) -> void:
	_dash_time_remaining -= delta
	velocity = _dash_direction * dash_speed
	var start_position: Vector2 = global_position
	move_and_slide()
	for body: Node2D in dash_hitbox.get_overlapping_bodies():
		if _is_enemy_target(body):
			_apply_wind_dash_hit(body)
			if not is_dashing:
				break
	if is_dashing and not arena_team.is_empty():
		for node: Node in get_tree().get_nodes_in_group(_opposing_team_tag()):
			var target: Node2D = node as Node2D
			if target == null:
				continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, start_position, global_position)
			if closest.distance_to(target.global_position) <= 38.0:
				_apply_wind_dash_hit(target)
				if not is_dashing:
					break
	_wrap_horizontal_on_sky_islands()
	if is_dashing and _dash_time_remaining <= 0.0:
		_finish_wind_dash()


func _apply_wind_dash_hit(target: Node2D) -> void:
	if not is_dashing or not _is_enemy_target(target) or target.is_queued_for_deletion() or not target.has_method("take_damage"):
		return
	if target.has_method("is_alive") and not target.call("is_alive"):
		return
	target.call("take_damage", attack_damage * 2, global_position, attack_effect, attack_effect_chance)
	if chain_lightning:
		_chain_lightning(target)
	_finish_wind_dash()


func _finish_wind_dash() -> void:
	is_dashing = false
	attack_count = 0
	_dash_time_remaining = 0.0
	velocity = Vector2.ZERO
	_knockback_time_remaining = 0.0
	dash_hitbox.set_deferred("monitoring", false)
	($DashHitbox/CollisionShape2D as CollisionShape2D).set_deferred("disabled", true)


func _is_enemy_target(target: Node) -> bool:
	return target.is_in_group("monsters") if arena_team.is_empty() else target.is_in_group(_opposing_team_tag())


func _chain_lightning(primary_target: Node2D) -> void:
	var chain_damage: int = maxi(roundi(attack_damage * chain_lightning_damage_fraction), 1)
	var target_group: String = "monsters" if arena_team.is_empty() else _opposing_team_tag()
	for node: Node in get_tree().get_nodes_in_group(target_group):
		var target: Node2D = node as Node2D
		if target == null or target == primary_target or target.is_queued_for_deletion() or not target.has_method("take_damage"):
			continue
		if target.has_method("is_alive") and not target.call("is_alive"):
			continue
		if primary_target.global_position.distance_squared_to(target.global_position) > chain_lightning_radius * chain_lightning_radius:
			continue
		passive_vfx.call("play_chain_lightning", primary_target.global_position, target.global_position)
		target.call("take_damage", chain_damage, global_position)
