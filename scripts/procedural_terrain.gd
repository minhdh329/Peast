# TileMapLayer creates a collision TileSet and generates the selected biome.
class_name ProceduralTerrain
extends TileMapLayer

enum Biome { FOREST, VOLCANO, OCEAN, SKY_ISLANDS }

const TILE_SIZE: Vector2i = Vector2i(32, 32)
const GRASS_TEXTURE: Texture2D = preload("res://assets/terrain_tile.svg")
const OCEAN_TEXTURE: Texture2D = preload("res://assets/terrain_ocean.svg")
const VOLCANO_TEXTURE: Texture2D = preload("res://assets/terrain_volcano.svg")
const SKY_TEXTURE: Texture2D = preload("res://assets/terrain_sky.svg")
const EXIT_PORTAL_SCRIPT: GDScript = preload("res://scripts/exit_portal.gd")

# Mỗi biome chỉ spawn đúng nhóm Monster của nó.
const MONSTER_SCENES: Dictionary = {
	Biome.FOREST: [preload("res://scenes/monsters/forest_slime.tscn"), preload("res://scenes/monsters/forest_mushroom.tscn")],
	Biome.VOLCANO: [preload("res://scenes/monsters/volcano_imp.tscn"), preload("res://scenes/monsters/volcano_golem.tscn")],
	Biome.OCEAN: [preload("res://scenes/monsters/ocean_crab.tscn"), preload("res://scenes/monsters/ocean_jelly.tscn")],
	Biome.SKY_ISLANDS: [preload("res://scenes/monsters/sky_bird.tscn"), preload("res://scenes/monsters/sky_cloud.tscn")],
}

@export var biome: Biome = Biome.FOREST
# Randomly choose a biome for each newly spawned game scene.
@export var randomize_biome_on_spawn: bool = true
@export var generation_seed: int = 20261002
@export_range(16, 60, 1) var map_width_cells: int = 30
@export_range(8, 24, 1) var floor_row: int = 15
@export var water_surface_y: float = 160.0
@export var swim_speed: float = 145.0
@export var water_drag: float = 520.0
@export_range(0.1, 1.0, 0.05) var water_speed_factor: float = 0.55
@export var lava_damage: int = 10
@export var lava_damage_interval: float = 0.8
@export var player_safe_radius_tiles: float = 5.0
# Rơi xuống dưới độ cao này thì coi như đã rơi khỏi map.
@export var fall_death_y: float = 700.0

var _lava_areas: Array[Rect2] = []
var _hazard_cooldowns: Dictionary = {}
var _debug_player_spawn: Vector2 = Vector2(180.0, 350.0)
var _debug_monster_spawn: Vector2 = Vector2(580.0, 462.0)
var _monster_spawns: Array[Vector2] = []
var _monsters_spawned: bool = false
var _exit_portal: Area2D


func _ready() -> void:
	add_to_group("procedural_terrain")
	if randomize_biome_on_spawn:
		var biome_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		biome_rng.randomize()
		biome = biome_rng.randi_range(Biome.FOREST, Biome.SKY_ISLANDS) as Biome
		print("Spawned biome: ", Biome.keys()[biome])
	tile_set = _create_terrain_tile_set()
	_generate_layout()
	_place_demo_characters()
	_spawn_biome_monsters.call_deferred()


func _process(delta: float) -> void:
	if biome == Biome.VOLCANO:
		_apply_lava_damage(delta)
	_respawn_fallen_monsters()
	if _monsters_spawned and _exit_portal == null and _is_map_cleared():
		_open_exit_portal()


# Monster rơi khỏi map được thả lại từ trên trời xuống một điểm spawn ngẫu nhiên.
func _respawn_fallen_monsters() -> void:
	if _monster_spawns.is_empty():
		return
	for monster: Node in get_tree().get_nodes_in_group("monsters"):
		var body: CharacterBody2D = monster as CharacterBody2D
		if body == null or body.global_position.y <= fall_death_y:
			continue
		var spawn_position: Vector2 = _monster_spawns.pick_random()
		body.global_position = Vector2(spawn_position.x, -40.0)
		body.velocity = Vector2.ZERO


func _is_map_cleared() -> bool:
	for monster: Node in get_tree().get_nodes_in_group("monsters"):
		if not monster.is_queued_for_deletion():
			return false
	return true


# Cổng đặt tại điểm spawn Monster xa nhất (cuối map), đáy cổng chạm mặt đất.
func _open_exit_portal() -> void:
	_exit_portal = EXIT_PORTAL_SCRIPT.new()
	get_parent().add_child(_exit_portal)
	_exit_portal.global_position = _monster_spawns.back() + Vector2(0.0, 18.0 - EXIT_PORTAL_SCRIPT.RADIUS.y - 2.0)
	print("Đã dọn sạch Monster! Cổng thoát đã mở.")


func _create_terrain_tile_set() -> TileSet:
	var terrain_tile_set: TileSet = TileSet.new()
	terrain_tile_set.tile_size = TILE_SIZE

	var atlas_source: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas_source.texture = _get_biome_texture()
	atlas_source.texture_region_size = TILE_SIZE
	var atlas_tile_count: int = 2 if biome == Biome.VOLCANO else 1
	for atlas_x: int in range(atlas_tile_count):
		atlas_source.create_tile(Vector2i(atlas_x, 0))
	terrain_tile_set.add_source(atlas_source, 0)
	terrain_tile_set.add_physics_layer()
	terrain_tile_set.set_physics_layer_collision_layer(0, 1)
	terrain_tile_set.set_physics_layer_collision_mask(0, 1)

	for atlas_x: int in range(atlas_tile_count):
		var tile_data: TileData = atlas_source.get_tile_data(Vector2i(atlas_x, 0), 0)
		tile_data.set_collision_polygons_count(0, 1)
		tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2(-16, -16),
			Vector2(16, -16),
			Vector2(16, 16),
			Vector2(-16, 16)
		]))
	return terrain_tile_set


func _get_biome_texture() -> Texture2D:
	match biome:
		Biome.OCEAN:
			return OCEAN_TEXTURE
		Biome.VOLCANO:
			return VOLCANO_TEXTURE
		Biome.SKY_ISLANDS:
			return SKY_TEXTURE
		_:
			return GRASS_TEXTURE


func _generate_layout() -> void:
	clear()
	_lava_areas.clear()
	_hazard_cooldowns.clear()
	var random_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	random_generator.seed = generation_seed

	match biome:
		Biome.OCEAN:
			_generate_ocean(random_generator)
		Biome.VOLCANO:
			_generate_volcano(random_generator)
		Biome.SKY_ISLANDS:
			_generate_sky_islands()
		_:
			_generate_forest(random_generator)


func _generate_forest(random_generator: RandomNumberGenerator) -> void:
	_add_background(Color("#18282d"))
	_generate_floor_and_walls(0)
	for start_x: int in [3, map_width_cells - 8]:
		var platform_length: int = random_generator.randi_range(3, 5)
		var platform_row: int = random_generator.randi_range(floor_row - 3, floor_row - 2)
		_add_platform(start_x, platform_row, platform_length, 0)
	_monster_spawns = [_ground_spawn(14.5, floor_row), _ground_spawn(21.5, floor_row), _ground_spawn(26.5, floor_row)]


func _generate_ocean(random_generator: RandomNumberGenerator) -> void:
	_add_background(Color("#167d9b"), water_surface_y)
	_add_water_surface_line()
	_generate_floor_and_walls(0)
	_add_platform(2, 6, random_generator.randi_range(4, 5), 0)
	_add_platform(10, 9, random_generator.randi_range(4, 5), 0)
	_add_platform(18, 7, random_generator.randi_range(5, 6), 0)
	_add_platform(26, 10, 3, 0)
	_debug_player_spawn = Vector2(3.5 * TILE_SIZE.x, water_surface_y + 10.0)
	_debug_monster_spawn = Vector2(21.5 * TILE_SIZE.x, 7 * TILE_SIZE.y - 18.0)
	_monster_spawns = [_ground_spawn(11.5, 9), _ground_spawn(19.5, 7), _ground_spawn(27.5, 10)]


func _generate_volcano(random_generator: RandomNumberGenerator) -> void:
	_add_background(Color("#302a32"))
	_generate_side_walls(0)
	var lava_segments: Array[Vector2i] = [Vector2i(7, 10), Vector2i(15, 18), Vector2i(24, 26)]
	for x: int in range(map_width_cells):
		var lava_tile: bool = _is_lava_column(x, lava_segments)
		var atlas_x: int = 1 if lava_tile else 0
		for y: int in range(floor_row, floor_row + 4):
			set_cell(Vector2i(x, y), 0, Vector2i(atlas_x if y == floor_row else 0, 0))
		if lava_tile:
			_lava_areas.append(Rect2(Vector2(x * TILE_SIZE.x, floor_row * TILE_SIZE.y - 26), Vector2(TILE_SIZE.x, TILE_SIZE.y + 24)))

	_add_platform(3, floor_row - 3, random_generator.randi_range(3, 5), 0)
	_add_platform(11, floor_row - 4, random_generator.randi_range(3, 5), 0)
	_debug_player_spawn = Vector2(3.5 * TILE_SIZE.x, floor_row * TILE_SIZE.y - 22.0)
	_debug_monster_spawn = Vector2(21.5 * TILE_SIZE.x, floor_row * TILE_SIZE.y - 18.0)
	_monster_spawns = [_ground_spawn(13.5, floor_row), _ground_spawn(20.5, floor_row), _ground_spawn(28.5, floor_row)]


func _generate_sky_islands() -> void:
	_add_background(Color("#83c9d2"))
	_add_platform(2, 13, 5, 0)
	_add_platform(12, 10, 5, 0)
	_add_platform(22, 7, 5, 0)
	_debug_player_spawn = Vector2(3.5 * TILE_SIZE.x, 13 * TILE_SIZE.y - 22.0)
	_debug_monster_spawn = Vector2(14.5 * TILE_SIZE.x, 10 * TILE_SIZE.y - 18.0)
	_monster_spawns = [_ground_spawn(13.5, 10), _ground_spawn(15.5, 10), _ground_spawn(24.5, 7)]


func _generate_floor_and_walls(atlas_x: int) -> void:
	for x: int in range(map_width_cells):
		for y: int in range(floor_row, floor_row + 4):
			set_cell(Vector2i(x, y), 0, Vector2i(atlas_x if y == floor_row else 0, 0))
	_generate_side_walls(0)


func _generate_side_walls(atlas_x: int) -> void:
	for y: int in range(floor_row):
		set_cell(Vector2i(0, y), 0, Vector2i(atlas_x, 0))
		set_cell(Vector2i(map_width_cells - 1, y), 0, Vector2i(atlas_x, 0))


func _add_platform(start_x: int, row: int, length: int, atlas_x: int) -> void:
	for x: int in range(start_x, mini(start_x + length, map_width_cells - 1)):
		set_cell(Vector2i(x, row), 0, Vector2i(atlas_x, 0))


func _is_lava_column(column: int, segments: Array[Vector2i]) -> bool:
	for segment: Vector2i in segments:
		if column >= segment.x and column < segment.y:
			return true
	return false


func _add_background(color: Color, top_y: float = 0.0) -> void:
	var background: Polygon2D = Polygon2D.new()
	background.name = "BiomeBackground"
	background.z_index = -10
	var screen_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var world_width: float = map_width_cells * TILE_SIZE.x
	background.polygon = PackedVector2Array([
		Vector2(0.0, top_y), Vector2(world_width, top_y),
		Vector2(world_width, screen_height), Vector2(0.0, screen_height)
	])
	background.color = color
	add_child(background)


func _add_water_surface_line() -> void:
	var surface: Polygon2D = Polygon2D.new()
	surface.name = "WaterSurface"
	surface.z_index = -9
	var world_width: float = map_width_cells * TILE_SIZE.x
	surface.polygon = PackedVector2Array([
		Vector2(0.0, water_surface_y - 2.0), Vector2(world_width, water_surface_y - 2.0),
		Vector2(world_width, water_surface_y + 2.0), Vector2(0.0, water_surface_y + 2.0)
	])
	surface.color = Color("#75d7d0")
	add_child(surface)


func is_underwater(world_position: Vector2) -> bool:
	return biome == Biome.OCEAN and world_position.x >= 0.0 and world_position.x < map_width_cells * TILE_SIZE.x and world_position.y >= water_surface_y


func is_lava_at(world_position: Vector2) -> bool:
	for lava_area: Rect2 in _lava_areas:
		if lava_area.has_point(world_position):
			return true
	return false


func get_debug_monster_spawn_position() -> Vector2:
	return _debug_monster_spawn


func get_player_spawn_position() -> Vector2:
	return _debug_player_spawn


func _place_demo_characters() -> void:
	if biome == Biome.FOREST:
		return
	var scene_root: Node = get_parent()
	var player: CharacterBody2D = scene_root.get_node_or_null("Player") as CharacterBody2D
	if player != null:
		player.global_position = _debug_player_spawn
		player.velocity = Vector2.ZERO


# Vị trí tâm Monster đứng trên mặt tile ở hàng `row`; x tính theo ô lưới.
func _ground_spawn(cell_x: float, row: int) -> Vector2:
	return Vector2(cell_x * TILE_SIZE.x, row * TILE_SIZE.y - 18.0)


func _spawn_biome_monsters() -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var safe_radius: float = player_safe_radius_tiles * TILE_SIZE.x
	for spawn_position: Vector2 in _monster_spawns:
		if player != null and spawn_position.distance_to(player.global_position) < safe_radius:
			continue
		spawn_random_monster(spawn_position)
	_monsters_spawned = true


# Tạo một Monster ngẫu nhiên thuộc đúng biome hiện tại.
func spawn_random_monster(world_position: Vector2) -> Node2D:
	var pool: Array = MONSTER_SCENES.get(biome, [])
	if pool.is_empty():
		return null
	var monster: Node2D = (pool[randi() % pool.size()] as PackedScene).instantiate()
	get_parent().add_child(monster)
	monster.global_position = world_position
	return monster


func _apply_lava_damage(delta: float) -> void:
	for group_name: String in ["player", "pets"]:
		for target: Node2D in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(target) or target.is_queued_for_deletion():
				continue
			if not target.has_method("take_damage") or (target.has_method("is_alive") and not target.call("is_alive")):
				continue

			var instance_id: int = target.get_instance_id()
			if not is_lava_at(target.global_position):
				_hazard_cooldowns.erase(instance_id)
				continue

			var cooldown: float = float(_hazard_cooldowns.get(instance_id, 0.0)) - delta
			if cooldown <= 0.0:
				target.call("take_damage", lava_damage, target.global_position - Vector2(16.0, 0.0))
				cooldown = lava_damage_interval
			_hazard_cooldowns[instance_id] = cooldown
