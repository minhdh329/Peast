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
@export var jump_velocity: float = -400.0
# Khoảng cách Monster có thể đứng yên và ra đòn.
@export var attack_range: float = 38.0
# Sát thương Monster gây ra cho Player hoặc Pet.
@export var attack_damage: int = 8
@export_enum("None", "Poison", "Burn", "Stun") var attack_effect: String = "None"
@export_range(0.0, 1.0, 0.05) var attack_effect_chance: float = 1.0
@export var is_resistant_crab: bool = false
@export var immune_to_knockback: bool = false
@export var split_on_death: bool = false
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
@export var scale_size: Vector2 = Vector2(2.0, 2.0)
var split_count: int = 0
var attack_count: int = 0
var is_dashing: bool = false
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
const GROUND_NAVIGATION: GDScript = preload("res://scripts/ground_navigation.gd")
var _ground_navigation = GROUND_NAVIGATION.new()
const TRAIT_DOUBLE_ATTACK: String = "DoubleAttack"
const TRAIT_FAST_MOVEMENT: String = "FastMovement"
const TRAIT_EXPLODE_ON_DEATH: String = "ExplodeOnDeath"
const TRAIT_REVIVE: String = "Revive"
const TRAIT_LIFESTEAL: String = "Lifesteal"
const TRAIT_DOUBLE_HP: String = "DoubleHP"
const TRAIT_DOUBLE_DAMAGE: String = "DoubleDamage"
const AVAILABLE_TRAITS: Array[String] = [
	TRAIT_DOUBLE_ATTACK,
	TRAIT_FAST_MOVEMENT,
	TRAIT_EXPLODE_ON_DEATH,
	TRAIT_REVIVE,
	TRAIT_LIFESTEAL,
	TRAIT_DOUBLE_HP,
	TRAIT_DOUBLE_DAMAGE,
]
const DEFAULT_LIFESTEAL_CHANCE: float = 1.0
const DEFAULT_LIFESTEAL_HEAL_FRACTION: float = 0.15
const DEFAULT_DEATH_EXPLOSION_DAMAGE: int = 50

enum State { PATROL, CHASE }
enum MountType { GROUND, FLY, SWIM }

@export_range(0.0, 1.0, 0.05) var lifesteal_chance: float = DEFAULT_LIFESTEAL_CHANCE
@export_range(0.0, 1.0, 0.05) var lifesteal_heal_fraction: float = DEFAULT_LIFESTEAL_HEAL_FRACTION
@export_range(0.0, 512.0, 1.0) var death_explosion_radius: float = 128.0
@export var death_explosion_damage: int = DEFAULT_DEATH_EXPLOSION_DAMAGE
var current_traits: Array[String] = []
var _revive_available: bool = true
var _is_reviving: bool = false
var _inherit_split_traits: bool = false
var arena_team: String = ""
var _arena_active: bool = true
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_time_remaining: float = 0.0

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
@onready var status_effects: Node = $StatusEffects
@onready var dash_hitbox: Area2D = $DashHitbox
@onready var passive_vfx: Node2D = $PassiveVFX


# Đưa mọi Monster vào cùng một nhóm để panel debug có thể reset chúng.
func _ready() -> void:
	collision_mask |= ProceduralTerrain.PLATFORM_COLLISION_MASK
	add_to_group("monsters")
	city_charge = preload("res://scripts/city_charge.gd").new()
	add_child(city_charge)
	if not arena_team.is_empty():
		add_to_group(arena_team)
		_ignore_same_team_collisions()
	if not _inherit_split_traits:
		_randomize_traits()
		_apply_passive_traits()
	else:
		_apply_movement_trait()
	($Sprite2D as Sprite2D).scale = scale_size
	current_hp = max_hp
	wall_check.add_exception(self)
	ledge_check.add_exception(self)
	wall_check.collision_mask = 1
	ledge_check.collision_mask = 1 | ProceduralTerrain.PLATFORM_COLLISION_MASK
	_update_health_bar()
	passive_vfx.call("refresh")
	var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
	if terrain != null:
		terrain.register_capture_candidate(self)


func set_arena_team(team_tag: String) -> void:
	if not arena_team.is_empty() and is_in_group(arena_team):
		remove_from_group(arena_team)
	arena_team = team_tag
	if not arena_team.is_empty():
		add_to_group(arena_team)
		if is_inside_tree():
			_ignore_same_team_collisions()


func _ignore_same_team_collisions() -> void:
	if arena_team.is_empty():
		return
	for teammate: Node in get_tree().get_nodes_in_group(arena_team):
		var teammate_body: PhysicsBody2D = teammate as PhysicsBody2D
		if teammate_body == null or teammate_body == self or teammate_body.is_queued_for_deletion():
			continue
		add_collision_exception_with(teammate_body)
		teammate_body.add_collision_exception_with(self)


func set_arena_active(active: bool) -> void:
	_arena_active = active
	if not active and city_charge != null:
		city_charge.call("finish")
	if active:
		state = State.CHASE
		_attack_cooldown_remaining = 0.0
	else:
		velocity = Vector2.ZERO


func _randomize_traits() -> void:
	var shuffled_traits: Array[String] = AVAILABLE_TRAITS.duplicate()
	shuffled_traits.shuffle()
	var trait_count: int = randi_range(1, mini(4, shuffled_traits.size()))
	current_traits.clear()
	for trait_index: int in range(trait_count):
		current_traits.append(shuffled_traits[trait_index])


func _apply_passive_traits() -> void:
	if current_traits.has(TRAIT_DOUBLE_HP):
		max_hp *= 2
	if current_traits.has(TRAIT_DOUBLE_DAMAGE):
		attack_damage *= 2
	_apply_movement_trait()


func _apply_movement_trait() -> void:
	if current_traits.has(TRAIT_FAST_MOVEMENT):
		patrol_speed *= 1.5
		movement_speed *= 1.5


func prepare_split_offspring(parent_monster: Monster) -> void:
	arena_team = parent_monster.arena_team
	_arena_active = parent_monster._arena_active
	current_traits = parent_monster.current_traits.duplicate()
	max_hp = maxi(roundi(parent_monster.max_hp * 0.5), 1)
	attack_damage = maxi(roundi(parent_monster.attack_damage * 0.5), 1)
	scale_size = parent_monster.scale_size * 0.5
	split_count = parent_monster.split_count
	_inherit_split_traits = true


# Duy trì vật lý, đuổi theo mục tiêu gần nhất và tấn công trong tầm.
func _physics_process(delta: float) -> void:
	_ground_navigation.update(self)
	if _is_reviving:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not _arena_active:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if is_nan(_home_x):
		_home_x = global_position.x
	var free_movement: bool = _uses_free_movement()
	if free_movement:
		_ground_navigation.reset(self)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING if free_movement else CharacterBody2D.MOTION_MODE_GROUNDED
	# Áp dụng trọng lực khi Monster đang ở trên không (trừ khi đang bay/bơi).
	if free_movement:
		pass
	elif not is_on_floor():
		velocity.y += gravity * delta
	elif velocity.y > 0.0:
		velocity.y = 0.0
	if status_effects.call("is_stunned"):
		city_charge.call("finish")
		if is_dashing:
			_finish_wind_dash()
		velocity.x = 0.0
		if free_movement:
			velocity.y = 0.0
		move_and_slide()
		return
	if city_charge.call("step", delta, false):
		return
	if is_dashing:
		_process_wind_dash(delta)
		return

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
	var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
	if terrain != null:
		terrain.wrap_horizontal(self)


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
	if not is_on_floor():
		return
	if _player_in_detection_zone():
		state = State.CHASE
		return

	_update_rays(_patrol_direction)
	if wall_check.is_colliding():
		velocity.y = jump_velocity
	elif not ledge_check.is_colliding():
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
	else:
		if _ground_navigation.steer(self, GROUND_NAVIGATION.feet_for(target), movement_speed, jump_velocity, delta):
			return
		velocity.x = direction * movement_speed
		if is_on_floor() and ((target_offset.y < -32.0 and absf(target_offset.x) < 96.0) or wall_check.is_colliding() or not ledge_check.is_colliding()):
			velocity.y = jump_velocity


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
	if not arena_team.is_empty():
		return _find_closest_target() != null
	var target: Node2D = _find_closest_target()
	var detection_shape: CollisionShape2D = detection_zone.get_node("CollisionShape2D") as CollisionShape2D
	var radius: float = detection_shape.shape.get_rect().size.x * 0.5
	return target != null and global_position.distance_squared_to(target.global_position) <= radius * radius


# Chọn mục tiêu sống gần nhất trong group Player và Pet, không giới hạn tầm khi đang đuổi.
func _find_closest_target() -> Node2D:
	var closest_target: Node2D
	var closest_distance_squared: float = INF
	var target_groups: Array[String] = ["player", "pets"]
	if not arena_team.is_empty():
		target_groups = [_opposing_team_tag()]

	for group_name: String in target_groups:
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


func _opposing_team_tag() -> String:
	return "TeamEnemy" if arena_team == "TeamPlayer" else "TeamPlayer"


# Dữ liệu để biến chính Monster này thành Pet: hình ảnh, kiểu đánh và chỉ số.
func get_pet_data() -> Dictionary:
	var monster_sprite: Sprite2D = $Sprite2D
	return {
		"name": monster_name,
		"type": monster_name,
		"attack_style": attack_style,
		"texture": monster_sprite.texture,
		"sprite_scale": monster_sprite.scale,
		"max_hp": max_hp,
		"attack_damage": attack_damage,
		"attack_interval": attack_interval,
		"attack_range": attack_range,
		"movement_mode": movement_mode,
		"mount_type": _get_mount_type(),
		"split_on_death": split_on_death,
		"split_count": split_count,
		"melee_contact_reach": melee_contact_reach,
		"attack_effect": attack_effect,
		"attack_effect_chance": attack_effect_chance,
		"is_resistant_crab": is_resistant_crab,
		"immune_to_knockback": immune_to_knockback,
		"chain_lightning": chain_lightning,
		"chain_lightning_radius": chain_lightning_radius,
		"chain_lightning_damage_fraction": chain_lightning_damage_fraction,
		"wind_dash_enabled": wind_dash_enabled,
		"charge_style": charge_style,
		"charge_trigger_range": charge_trigger_range,
		"charge_speed": charge_speed,
		"city_charge_count": city_charge.get("trigger_count"),
		"city_charge_ready": city_charge.get("charge_ready"),
		"dash_speed": dash_speed,
		"dash_duration": dash_duration,
		"current_traits": current_traits.duplicate(),
		"revive_available": _revive_available,
		"lifesteal_chance": lifesteal_chance,
		"lifesteal_heal_fraction": lifesteal_heal_fraction,
		"death_explosion_radius": death_explosion_radius,
		"death_explosion_damage": death_explosion_damage,
	}


func _get_mount_type() -> int:
	match movement_mode:
		"Fly":
			return MountType.FLY
		"Swim":
			return MountType.SWIM
		_:
			return MountType.GROUND


# Gây sát thương và khởi động cooldown sau mỗi đòn trúng mục tiêu.
func _attack_target(target: Node2D) -> void:
	if _is_reviving or current_hp <= 0:
		return
	if wind_dash_enabled:
		var shots_this_attack: int = 2 if current_traits.has(TRAIT_DOUBLE_ATTACK) else 1
		for shot_index: int in range(shots_this_attack):
			if attack_count == 2:
				_start_wind_dash(target)
				break
			_shoot_at(target)
			attack_count += 1
		_attack_cooldown_remaining = attack_interval
		return
	var hit_count: int = 2 if current_traits.has(TRAIT_DOUBLE_ATTACK) else 1
	for attack_index: int in range(hit_count):
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			break
		if target.has_method("is_alive") and not target.call("is_alive"):
			break
		if attack_style == "Ranged":
			_shoot_at(target)
		else:
			target.call("take_damage", attack_damage, global_position, attack_effect, attack_effect_chance)
			_try_lifesteal(attack_damage)
			if chain_lightning:
				_chain_lightning(target)
		if charge_style != "None":
			city_charge.call("record_attack", target)
			if city_charge.get("active"):
				break
	_attack_cooldown_remaining = attack_interval


func _start_wind_dash(target: Node2D) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return
	_dash_direction = (target.global_position - global_position).normalized()
	if _dash_direction.is_zero_approx():
		_dash_direction = Vector2(-1.0 if ($Sprite2D as Sprite2D).flip_h else 1.0, 0.0)
	_dash_time_remaining = dash_duration
	is_dashing = true
	dash_hitbox.set_deferred("monitoring", true)
	($DashHitbox/CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)


func _process_wind_dash(delta: float) -> void:
	_dash_time_remaining -= delta
	velocity = _dash_direction * dash_speed
	move_and_slide()
	_process_dash_collisions()
	var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
	if terrain != null:
		terrain.wrap_horizontal(self)
	if is_dashing and _dash_time_remaining <= 0.0:
		_finish_wind_dash()


func _process_dash_collisions() -> void:
	for body: Node2D in dash_hitbox.get_overlapping_bodies():
		if _is_enemy_target(body):
			_apply_wind_dash_hit(body)
			if not is_dashing:
				return
	# Pet bodies use collision_layer 0, so include grouped targets with a radius check.
	for pet_node: Node in get_tree().get_nodes_in_group("pets"):
		var pet: Node2D = pet_node as Node2D
		if pet != null and global_position.distance_to(pet.global_position) <= 38.0:
			_apply_wind_dash_hit(pet)
			if not is_dashing:
				return


func _apply_wind_dash_hit(target: Node2D) -> void:
	if not is_dashing or not _is_enemy_target(target) or target.is_queued_for_deletion() or not target.has_method("take_damage"):
		return
	if target.has_method("is_alive") and not target.call("is_alive"):
		return
	target.call("take_damage", attack_damage * 2, global_position, attack_effect, attack_effect_chance)
	_finish_wind_dash()


func _finish_wind_dash() -> void:
	is_dashing = false
	attack_count = 0
	_dash_time_remaining = 0.0
	velocity = Vector2.ZERO
	_knockback_time_remaining = 0.0
	dash_hitbox.set_deferred("monitoring", false)
	($DashHitbox/CollisionShape2D as CollisionShape2D).set_deferred("disabled", true)


func _chain_lightning(primary_target: Node2D) -> void:
	var chain_damage: int = maxi(roundi(attack_damage * chain_lightning_damage_fraction), 1)
	var groups: Array[String] = ["player", "pets"]
	if not arena_team.is_empty():
		groups = [_opposing_team_tag()]
	for group_name: String in groups:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			var target: Node2D = candidate as Node2D
			if target == null or target == primary_target or target.is_queued_for_deletion():
				continue
			if target.has_method("is_alive") and not target.call("is_alive"):
				continue
			if primary_target.global_position.distance_squared_to(target.global_position) > chain_lightning_radius * chain_lightning_radius:
				continue
			if target.has_method("take_damage"):
				passive_vfx.call("play_chain_lightning", primary_target.global_position, target.global_position)
				target.call("take_damage", chain_damage, global_position)


# Cùng loại đạn với Pet Ranged, nhưng nhắm Player/Pet và nhuộm màu khác.
func _shoot_at(target: Node2D) -> void:
	var fireball: FireballProjectile = FIREBALL_SCENE.instantiate()
	fireball.hostile = true
	fireball.arena_team = arena_team
	fireball.damage = attack_damage
	fireball.effect_type = attack_effect
	fireball.effect_chance = attack_effect_chance
	fireball.modulate = Color(1.0, 0.55, 0.9)
	if current_traits.has(TRAIT_LIFESTEAL):
		fireball.set_lifesteal_source(self, lifesteal_chance, lifesteal_heal_fraction)
	get_parent().add_child(fireball)
	fireball.global_position = global_position
	fireball.launch_to(target.global_position)


# Bị đẩy ra khỏi nguồn sát thương và tạm dừng hành vi đuổi bắt.
func _apply_knockback(attack_origin: Vector2) -> void:
	if immune_to_knockback:
		return
	var knockback_direction: float = signf(global_position.x - attack_origin.x)
	if is_zero_approx(knockback_direction):
		knockback_direction = 1.0
	velocity.x = knockback_direction * knockback_strength
	velocity.y = -knockback_lift
	_knockback_time_remaining = 0.2


# Trừ HP, đẩy Monster ra xa hướng tấn công và xóa nó khi HP hết.
func take_damage(amount: int, attack_origin: Vector2, effect_type: String = "", effect_chance: float = 1.0, is_over_time: bool = false) -> void:
	# Không tiếp tục xử lý nếu Monster đã hết HP.
	if current_hp <= 0 or _is_reviving:
		return

	# Giới hạn HP nhỏ nhất bằng 0 và in trạng thái mới ra Output.
	var damage_taken: int = int(status_effects.call("modify_incoming_damage", amount, effect_type, is_over_time))
	current_hp = maxi(current_hp - damage_taken, 0)
	_update_health_bar()
	print("Monster nhận ", damage_taken, " sát thương. HP còn: ", current_hp, "/", max_hp)

	# Đẩy Monster tránh xa vị trí bắt đầu đòn đánh.
	_apply_knockback(attack_origin)
	# Bị đánh thì lập tức đuổi theo.
	state = State.CHASE

	# Xử lý hồi sinh hoặc hiệu ứng chết trước khi xóa Monster.
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
	if current_traits.has(TRAIT_REVIVE) and _revive_available:
		_revive_available = false
		_is_reviving = true
		current_hp = 0
		velocity = Vector2.ZERO
		passive_vfx.call("set_reviving", true)
		_complete_revival.call_deferred()
		return
	queue_free()


func _trigger_death_passives() -> void:
	if current_traits.has(TRAIT_EXPLODE_ON_DEATH):
		_explode_on_death()
	if split_on_death and split_count == 0:
		_split_into_slimes()


func _complete_revival() -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	current_hp = maxi(ceili(max_hp * 0.3), 1)
	_is_reviving = false
	_update_health_bar()
	passive_vfx.call("set_reviving", false)


func _split_into_slimes() -> void:
	split_count = 1
	var slime_scene: PackedScene = load("res://scenes/monsters/forest_slime.tscn") as PackedScene
	if slime_scene == null:
		push_warning("Không thể tải scene Slime rừng để tách đôi.")
		return
	var scene_root: Node = get_parent()
	var offspring_group: Array[Monster] = []
	for offset: float in [-12.0, 12.0]:
		var offspring: Monster = slime_scene.instantiate() as Monster
		offspring.prepare_split_offspring(self)
		scene_root.add_child(offspring)
		for sibling: Monster in offspring_group:
			offspring.add_collision_exception_with(sibling)
			sibling.add_collision_exception_with(offspring)
		offspring_group.append(offspring)
		offspring.global_position = global_position + Vector2(offset, 0.0)


func restore_lifesteal(damage: int, heal_fraction: float) -> void:
	current_hp = mini(current_hp + maxi(roundi(damage * heal_fraction), 1), max_hp)
	_update_health_bar()


func _try_lifesteal(damage: int) -> void:
	if current_traits.has(TRAIT_LIFESTEAL) and randf() < lifesteal_chance:
		restore_lifesteal(damage, lifesteal_heal_fraction)


func _explode_on_death() -> void:
	passive_vfx.call("play_explosion", death_explosion_radius)
	var groups: Array[String] = ["player", "pets"]
	if not arena_team.is_empty():
		groups = [_opposing_team_tag()]
	for group_name: String in groups:
		for target: Node in get_tree().get_nodes_in_group(group_name):
			var target_2d: Node2D = target as Node2D
			if target_2d == null or target_2d.is_queued_for_deletion():
				continue
			if global_position.distance_to(target_2d.global_position) > death_explosion_radius:
				continue
			if target_2d.has_method("take_damage"):
				target_2d.call("take_damage", death_explosion_damage, global_position)


func is_alive() -> bool:
	return current_hp > 0 and not _is_reviving


func is_reviving() -> bool:
	return _is_reviving


func _is_enemy_target(target: Node) -> bool:
	if not arena_team.is_empty():
		return target.is_in_group(_opposing_team_tag())
	return target.is_in_group("player") or target.is_in_group("pets")


# Đồng bộ ProgressBar với HP hiện tại, kể cả khi max_hp được chỉnh trong Inspector.
func _update_health_bar() -> void:
	health_bar.max_value = maxi(max_hp, 1)
	health_bar.value = clampi(current_hp, 0, maxi(max_hp, 1))
