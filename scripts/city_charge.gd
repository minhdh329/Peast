extends Node

const CAT_TRIGGER_COUNT: int = 7
const CAR_TRIGGER_COUNT: int = 5

var active: bool = false
var _actor: CharacterBody2D
var _direction: float = 1.0
var _distance_remaining: float = 0.0
var _original_mask: int = 0
var _hit_ids: Dictionary = {}
var _trail_remaining: float = 0.0
var trigger_count: int = 0
var charge_ready: bool = false


func _ready() -> void:
	_actor = get_parent() as CharacterBody2D


func start(target: Node2D) -> void:
	if active or not is_instance_valid(target) or target.is_queued_for_deletion():
		return
	_direction = signf(target.global_position.x - _actor.global_position.x)
	if is_zero_approx(_direction):
		_direction = -1.0 if (_actor.get_node("Sprite2D") as Sprite2D).flip_h else 1.0
	var style: String = str(_actor.get("charge_style"))
	var map_width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 960))
	var terrain: Node = get_tree().get_first_node_in_group("procedural_terrain")
	if terrain != null:
		map_width = float(terrain.get("map_width_cells")) * 32.0
	_distance_remaining = map_width * 0.5 if style == "Car" else float(_actor.get("charge_speed")) * 0.25
	charge_ready = false
	trigger_count = 0
	_hit_ids.clear()
	_original_mask = _actor.collision_mask
	_actor.collision_mask = 1
	active = true
	_trail_remaining = 0.0
	(_actor.get_node("Sprite2D") as Sprite2D).flip_h = _direction < 0.0


func step(delta: float, apply_gravity: bool = true) -> bool:
	if not active and charge_ready:
		_try_start_ready_charge(_find_opponent())
	if not active:
		return false
	var start_position: Vector2 = _actor.global_position
	_actor.velocity.x = _direction * minf(float(_actor.get("charge_speed")), _distance_remaining / maxf(delta, 0.001))
	if not _actor.is_on_floor() and apply_gravity:
		_actor.velocity.y += float(ProjectSettings.get_setting("physics/2d/default_gravity")) * delta
	elif _actor.is_on_floor():
		_actor.velocity.y = 0.0
	_actor.move_and_slide()
	var end_position: Vector2 = _actor.global_position
	_distance_remaining -= absf(end_position.x - start_position.x)
	_trail_remaining -= delta
	if _trail_remaining <= 0.0:
		_spawn_trail()
		_trail_remaining = 0.05
	_check_hits(start_position, end_position)
	if active and (_distance_remaining <= 0.01 or _actor.is_on_wall() or start_position.distance_to(end_position) < 0.01):
		finish()
	return true


func record_attack(target: Node2D) -> void:
	if active:
		return
	var style: String = str(_actor.get("charge_style"))
	if style == "Car":
		trigger_count += 1
		if trigger_count >= CAR_TRIGGER_COUNT:
			trigger_count = 0
			start(target)
	elif style == "Cat":
		trigger_count += 1
		if trigger_count >= CAT_TRIGGER_COUNT:
			trigger_count = 0
			charge_ready = true
			_try_start_ready_charge(target)


func record_hit() -> void:
	if active or str(_actor.get("charge_style")) != "Cat":
		return
	trigger_count += 1
	if trigger_count >= CAT_TRIGGER_COUNT:
		trigger_count = 0
		charge_ready = true
		_try_start_ready_charge(_find_opponent())


func _try_start_ready_charge(target: Node2D) -> void:
	if not charge_ready or not is_instance_valid(target) or target.is_queued_for_deletion():
		return
	var trigger_range: float = float(_actor.get("charge_trigger_range"))
	if _actor.global_position.distance_squared_to(target.global_position) <= trigger_range * trigger_range:
		start(target)


func _find_opponent() -> Node2D:
	var actor_team: String = str(_actor.get("arena_team"))
	var groups: Array[String] = ["player", "pets"]
	if _actor.is_in_group("pets"):
		groups = ["monsters"]
	if not actor_team.is_empty():
		groups = ["TeamEnemy" if actor_team == "TeamPlayer" else "TeamPlayer"]
	var closest_target: Node2D
	var closest_distance_squared: float = INF
	for group_name: String in groups:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			var target: Node2D = candidate as Node2D
			if target == null or target == _actor or target.is_queued_for_deletion() or not target.has_method("take_damage"):
				continue
			if target.has_method("is_alive") and not target.call("is_alive"):
				continue
			var distance_squared: float = _actor.global_position.distance_squared_to(target.global_position)
			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_target = target
	return closest_target


func _check_hits(start_position: Vector2, end_position: Vector2) -> void:
	var team: String = str(_actor.get("arena_team"))
	var groups: Array[String] = ["player", "pets"]
	if _actor.is_in_group("pets"):
		groups = ["monsters"]
	if not team.is_empty():
		groups = ["TeamEnemy" if team == "TeamPlayer" else "TeamPlayer"]
	for group_name: String in groups:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			var target: Node2D = candidate as Node2D
			if target == null or target == _actor or target.is_queued_for_deletion() or not target.has_method("take_damage"):
				continue
			if _hit_ids.has(target.get_instance_id()) or (target.has_method("is_alive") and not target.call("is_alive")):
				continue
			var closest_point: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, start_position, end_position)
			if closest_point.distance_to(target.global_position) > 36.0:
				continue
			_hit_ids[target.get_instance_id()] = true
			var effect: String = "Stun" if str(_actor.get("charge_style")) == "Cat" else "None"
			var damage: int = int(_actor.get("attack_damage"))
			target.call("take_damage", damage, start_position, effect, 1.0)
			_actor.call("_try_lifesteal", damage)
			if effect == "Stun":
				finish()
				return


func finish() -> void:
	if not active:
		return
	active = false
	_actor.collision_mask = _original_mask
	_actor.velocity.x = 0.0


func _spawn_trail() -> void:
	var sprite: Sprite2D = _actor.get_node("Sprite2D") as Sprite2D
	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.flip_h = sprite.flip_h
	ghost.scale = sprite.scale
	ghost.modulate = Color(0.6, 0.95, 1.0, 0.45) if str(_actor.get("charge_style")) == "Cat" else Color(1.0, 0.7, 0.3, 0.45)
	ghost.z_index = -1
	_actor.get_parent().add_child(ghost)
	ghost.global_position = sprite.global_position
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.2)
	tween.tween_callback(ghost.queue_free)