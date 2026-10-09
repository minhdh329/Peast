class_name StatusEffectComponent
extends Node

const POISON: String = "Poison"
const BURN: String = "Burn"
const STUN: String = "Stun"
const BLINK_FREQUENCY: float = 4.0
const STATUS_STARS_NAME: String = "StatusStars"

@export_range(0, 100, 1) var burn_damage_per_second: int = 4

var _affected_actor: Node
var _remaining_duration: Dictionary = {}
var _burn_tick_remaining: float = 1.0
var _burn_source: Vector2 = Vector2.ZERO
var _visual_time: float = 0.0
var _actor_sprite: Sprite2D
var _original_sprite_modulate: Color = Color.WHITE
var _stars_root: Node2D
var _stars: Array[Polygon2D] = []


func _ready() -> void:
	_affected_actor = get_parent()
	_actor_sprite = _affected_actor.get_node_or_null("Sprite2D") as Sprite2D
	if _actor_sprite != null:
		_original_sprite_modulate = _actor_sprite.modulate


func apply_effect(effect_type: String, source: Vector2, chance: float = 1.0) -> bool:
	if not is_instance_valid(_affected_actor) or not _affected_actor.is_inside_tree():
		return false
	if _affected_actor.has_method("is_alive") and not _affected_actor.call("is_alive"):
		return false
	if randf() >= clampf(chance, 0.0, 1.0):
		return false

	var duration: float
	match effect_type:
		POISON:
			duration = 3.0
			if _is_resistant_crab():
				duration *= 0.5
			_remaining_duration[POISON] = maxf(float(_remaining_duration.get(POISON, 0.0)), duration)
		BURN:
			duration = 5.0
			if _is_resistant_crab():
				duration *= 0.5
			if not _remaining_duration.has(BURN):
				_burn_tick_remaining = 1.0
			_burn_source = source
			_remaining_duration[BURN] = maxf(float(_remaining_duration.get(BURN, 0.0)), duration)
		STUN:
			duration = 1.0
			if _is_resistant_crab():
				duration *= 0.5
			_remaining_duration[STUN] = maxf(float(_remaining_duration.get(STUN, 0.0)), duration)
			_ensure_stun_stars()
		_:
			return false
	return true


func is_stunned() -> bool:
	return float(_remaining_duration.get(STUN, 0.0)) > 0.0


func has_effect(effect_type: String) -> bool:
	return float(_remaining_duration.get(effect_type, 0.0)) > 0.0


func modify_incoming_damage(amount: int, effect_type: String, is_over_time: bool = false) -> int:
	var adjusted_damage: int = maxi(amount, 0)
	if has_effect(POISON) and not is_over_time:
		adjusted_damage = roundi(adjusted_damage * 1.1)
	if _is_resistant_crab() and effect_type in [BURN, POISON]:
		adjusted_damage = roundi(adjusted_damage * 0.5)
	return adjusted_damage


func _process(delta: float) -> void:
	if not is_instance_valid(_affected_actor):
		return
	_visual_time += delta
	for effect_type: String in _remaining_duration.keys():
		var remaining: float = float(_remaining_duration[effect_type])
		if effect_type == BURN:
			_burn_tick_remaining -= delta
			while _burn_tick_remaining <= 0.0 and remaining > 0.0:
				_deal_burn_tick()
				_burn_tick_remaining += 1.0
		remaining = maxf(remaining - delta, 0.0)
		if remaining <= 0.0:
			_remaining_duration.erase(effect_type)
		else:
			_remaining_duration[effect_type] = remaining
	_update_flash_visuals()
	_update_stun_stars()


func _deal_burn_tick() -> void:
	if burn_damage_per_second <= 0 or not is_instance_valid(_affected_actor):
		return
	if _affected_actor.has_method("take_damage"):
		_affected_actor.call("take_damage", burn_damage_per_second, _burn_source, BURN, 0.0, true)


func _is_resistant_crab() -> bool:
	return is_instance_valid(_affected_actor) and bool(_affected_actor.get("is_resistant_crab"))


func _update_flash_visuals() -> void:
	if _actor_sprite == null:
		return
	var burn_active: bool = has_effect(BURN)
	var poison_active: bool = has_effect(POISON)
	if not burn_active and not poison_active:
		_actor_sprite.modulate = _original_sprite_modulate
		return
	var flash_on: bool = sin(_visual_time * TAU * BLINK_FREQUENCY) > 0.0
	if not flash_on:
		_actor_sprite.modulate = _original_sprite_modulate
	elif burn_active and poison_active:
		_actor_sprite.modulate = Color("#ff3d32") if sin(_visual_time * TAU * 0.5) >= 0.0 else Color("#bd50ed")
	elif burn_active:
		_actor_sprite.modulate = Color("#ff3d32")
	else:
		_actor_sprite.modulate = Color("#bd50ed")


func _ensure_stun_stars() -> void:
	if _stars_root != null and is_instance_valid(_stars_root):
		_stars_root.visible = true
		return
	_stars_root = Node2D.new()
	_stars_root.name = STATUS_STARS_NAME
	_stars_root.z_index = 5
	_affected_actor.add_child(_stars_root)
	for star_index: int in range(3):
		var star: Polygon2D = Polygon2D.new()
		star.color = Color("#fff16a")
		star.polygon = _create_star_points(7.0, 3.2)
		_stars_root.add_child(star)
		_stars.append(star)


func _create_star_points(outer_radius: float, inner_radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(10):
		var angle: float = -PI * 0.5 + TAU * float(point_index) / 10.0
		var radius: float = outer_radius if point_index % 2 == 0 else inner_radius
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _update_stun_stars() -> void:
	if _stars_root == null or not is_instance_valid(_stars_root):
		return
	var stunned: bool = is_stunned()
	_stars_root.visible = stunned
	if not stunned:
		return
	for star_index: int in range(_stars.size()):
		var star: Polygon2D = _stars[star_index]
		var phase: float = _visual_time * 3.0 + float(star_index) * TAU / 3.0
		star.position = Vector2(cos(phase) * 18.0, -38.0 + sin(phase) * 4.0)
		star.rotation = phase * 0.4