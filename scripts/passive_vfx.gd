extends Node2D

const BADGES: Dictionary = {
	"DoubleAttack": ["2X", Color("#ffca58"), "Đánh hai lần"],
	"FastMovement": ["SPD", Color("#56d8ee"), "Di chuyển nhanh"],
	"ExplodeOnDeath": ["BOOM", Color("#ff704b"), "Nổ khi chết"],
	"Revive": ["REV", Color("#8fea91"), "Hồi sinh"],
	"Lifesteal": ["LIFE", Color("#f2749c"), "Hút máu"],
	"DoubleHP": ["HP2", Color("#67d889"), "Gấp đôi HP"],
	"DoubleDamage": ["DMG2", Color("#ff8667"), "Gấp đôi sát thương"],
	"Split": ["SPLIT", Color("#b3ef62"), "Tách đôi"],
	"KnockbackImmunity": ["IMM", Color("#b5c7d8"), "Miễn đẩy lùi"],
	"ChainLightning": ["ARC", Color("#75c8ff"), "Sét lan"],
	"WindDash": ["DASH", Color("#f4f7ff"), "Lướt gió"],
	"CatCharge": ["POUNCE", Color("#8ce8ef"), "Lao tới và gây choáng"],
	"CarCharge": ["RAM", Color("#ffb866"), "Lao xuyên kẻ địch nửa map"],
	"PoisonAttack": ["POIS", Color("#9ee35f"), "Đòn đánh gây độc"],
	"BurnAttack": ["BURN", Color("#ff8956"), "Đòn đánh gây cháy"],
	"StunAttack": ["STUN", Color("#d4a6ff"), "Đòn đánh gây choáng"],
	"Resistance": ["WARD", Color("#69d7c4"), "Kháng hiệu ứng"],
}

const BADGE_SIZE: Vector2 = Vector2(31.0, 15.0)
const BADGE_GAP: float = 2.0
const BADGES_PER_ROW: int = 4

var _actor: Node
var _badges: Array[PanelContainer] = []
var _elapsed: float = 0.0
var _revive_root: Node2D
var _revive_ring: Line2D
var _revive_label: Label


func _ready() -> void:
	_actor = get_parent()


func _process(delta: float) -> void:
	_elapsed += delta
	for badge_index: int in range(_badges.size()):
		var panel: PanelContainer = _badges[badge_index]
		if not is_instance_valid(panel):
			continue
		var base_y: float = float(panel.get_meta("base_y", panel.position.y))
		var phase: float = _elapsed * 4.0 + float(badge_index) * 0.7
		panel.position.y = base_y + sin(phase) * 2.0
		panel.modulate.a = 0.82 + (sin(phase) + 1.0) * 0.09
	if _revive_root != null and is_instance_valid(_revive_root) and _revive_root.visible:
		var revive_phase: float = _elapsed * 6.0
		_revive_root.rotation = sin(revive_phase) * 0.08
		_revive_ring.scale = Vector2.ONE * (0.9 + 0.12 * sin(revive_phase))
		_revive_ring.modulate.a = 0.72 + 0.28 * (0.5 + 0.5 * sin(revive_phase))
		_revive_label.position.y = -66.0 + sin(revive_phase * 0.7) * 4.0


func refresh() -> void:
	_badges.clear()
	for child: Node in get_children():
		child.queue_free()
	if not is_instance_valid(_actor):
		return

	var active_badges: Array[String] = []
	var traits: Variant = _get_actor_property("current_traits", [])
	if traits is Array:
		for trait_value: Variant in traits:
			var trait_name: String = str(trait_value)
			if BADGES.has(trait_name) and not active_badges.has(trait_name):
				active_badges.append(trait_name)

	if bool(_get_actor_property("split_on_death", false)) and int(_get_actor_property("split_count", 0)) == 0:
		active_badges.append("Split")
	if bool(_get_actor_property("immune_to_knockback", false)):
		active_badges.append("KnockbackImmunity")
	if bool(_get_actor_property("chain_lightning", false)):
		active_badges.append("ChainLightning")
	if bool(_get_actor_property("wind_dash_enabled", false)):
		active_badges.append("WindDash")
	match str(_get_actor_property("charge_style", "None")):
		"Cat":
			active_badges.append("CatCharge")
		"Car":
			active_badges.append("CarCharge")
	if bool(_get_actor_property("is_resistant_crab", false)):
		active_badges.append("Resistance")
	match str(_get_actor_property("attack_effect", "None")):
		"Poison":
			active_badges.append("PoisonAttack")
		"Burn":
			active_badges.append("BurnAttack")
		"Stun":
			active_badges.append("StunAttack")

	var row_count: int = ceili(float(active_badges.size()) / BADGES_PER_ROW)
	for badge_index: int in range(active_badges.size()):
		_add_badge(active_badges[badge_index], badge_index, row_count, active_badges.size())


func play_explosion(radius: float) -> void:
	if not is_instance_valid(_actor) or not _actor is Node2D:
		return
	var explosion: Node2D = Node2D.new()
	explosion.name = "DeathExplosionFX"
	explosion.z_index = 100
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	scene_root.add_child(explosion)
	explosion.global_position = (_actor as Node2D).global_position
	explosion.scale = Vector2.ONE * 0.08

	var outer_burst: Polygon2D = Polygon2D.new()
	outer_burst.polygon = _create_burst_points(radius, radius * 0.62, 16)
	outer_burst.color = Color("#ef4938")
	explosion.add_child(outer_burst)
	var inner_burst: Polygon2D = Polygon2D.new()
	inner_burst.polygon = _create_burst_points(radius * 0.62, radius * 0.4, 16)
	inner_burst.color = Color("#ffd45a")
	explosion.add_child(inner_burst)

	var tween: Tween = explosion.create_tween()
	tween.set_parallel(true)
	tween.tween_property(explosion, "scale", Vector2.ONE * 1.08, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(explosion, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(explosion.queue_free)


func play_chain_lightning(from_position: Vector2, to_position: Vector2) -> Node2D:
	var effect_root: Node2D = Node2D.new()
	effect_root.name = "ChainLightningFX"
	effect_root.z_index = 110
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	scene_root.add_child(effect_root)

	var bolt_points: PackedVector2Array = _create_lightning_points(from_position, to_position, 6, 8.0)
	var glow: Line2D = Line2D.new()
	glow.width = 9.0
	glow.default_color = Color(0.28, 0.82, 1.0, 0.42)
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow.points = bolt_points
	effect_root.add_child(glow)
	var bolt: Line2D = Line2D.new()
	bolt.width = 3.0
	bolt.default_color = Color("#e2fbff")
	bolt.begin_cap_mode = Line2D.LINE_CAP_ROUND
	bolt.end_cap_mode = Line2D.LINE_CAP_ROUND
	bolt.points = bolt_points
	effect_root.add_child(bolt)

	var tween: Tween = effect_root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(glow, "modulate:a", 0.0, 0.2)
	tween.tween_property(bolt, "width", 0.6, 0.2)
	tween.tween_property(bolt, "modulate:a", 0.0, 0.2)
	tween.set_parallel(false)
	tween.tween_callback(effect_root.queue_free)
	return effect_root


func _create_lightning_points(from_position: Vector2, to_position: Vector2, segment_count: int, jitter: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([from_position])
	var perpendicular: Vector2 = (to_position - from_position).normalized().orthogonal()
	for segment_index: int in range(1, segment_count):
		var progress: float = float(segment_index) / float(segment_count)
		points.append(from_position.lerp(to_position, progress) + perpendicular * randf_range(-jitter, jitter))
	points.append(to_position)
	return points


func set_reviving(active: bool) -> void:
	if not is_instance_valid(_actor):
		return
	if _revive_root == null or not is_instance_valid(_revive_root):
		_revive_root = Node2D.new()
		_revive_root.name = "ReviveEffect"
		_revive_root.z_index = 8
		_actor.add_child(_revive_root)
		_revive_ring = Line2D.new()
		_revive_ring.width = 3.0
		_revive_ring.default_color = Color("#75f0e5")
		_revive_ring.closed = true
		_revive_ring.points = _create_circle_points(23.0, 48)
		_revive_root.add_child(_revive_ring)
		var glow: Polygon2D = Polygon2D.new()
		glow.color = Color(0.35, 0.95, 0.85, 0.16)
		glow.polygon = _create_circle_points(20.0, 32)
		_revive_root.add_child(glow)
		_revive_label = Label.new()
		_revive_label.text = "REVIVING"
		_revive_label.position = Vector2(-42.0, -66.0)
		_revive_label.custom_minimum_size = Vector2(84.0, 18.0)
		_revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_revive_label.add_theme_font_size_override("font_size", 10)
		_revive_label.add_theme_color_override("font_color", Color("#d1fff5"))
		_revive_root.add_child(_revive_label)
	_revive_root.visible = active
	if active:
		_elapsed = 0.0


func _create_circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(point_count):
		var angle: float = TAU * float(point_index) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _create_burst_points(outer_radius: float, inner_radius: float, ray_count: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(ray_count * 2):
		var angle: float = -PI * 0.5 + TAU * float(point_index) / float(ray_count * 2)
		var point_radius: float = outer_radius if point_index % 2 == 0 else inner_radius
		points.append(Vector2(cos(angle), sin(angle)) * point_radius)
	return points


func _add_badge(badge_key: String, badge_index: int, row_count: int, total_badges: int) -> void:
	var badge_data: Array = BADGES[badge_key]
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = BADGE_SIZE
	panel.size = BADGE_SIZE
	panel.tooltip_text = str(badge_data[2])
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = (badge_data[1] as Color).darkened(0.72)
	style.border_color = badge_data[1]
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)

	var label: Label = Label.new()
	label.text = str(badge_data[0])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(label)
	add_child(panel)

	var row_index: int = badge_index / BADGES_PER_ROW
	var column_index: int = badge_index % BADGES_PER_ROW
	var badges_in_row: int = mini(total_badges - row_index * BADGES_PER_ROW, BADGES_PER_ROW)
	var row_width: float = float(badges_in_row) * (BADGE_SIZE.x + BADGE_GAP) - BADGE_GAP
	var row_start: float = -row_width * 0.5
	var base_y: float = -48.0 - float(row_count - row_index - 1) * (BADGE_SIZE.y + 2.0)
	panel.position = Vector2(row_start + float(column_index) * (BADGE_SIZE.x + BADGE_GAP), base_y)
	panel.set_meta("base_y", base_y)
	_badges.append(panel)
func _get_actor_property(property_name: String, default_value: Variant) -> Variant:
	if not is_instance_valid(_actor):
		return default_value
	for property_info: Dictionary in _actor.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return _actor.get(property_name)
	return default_value