# TileMapLayer creates a collision TileSet and generates the selected biome.
class_name ProceduralTerrain
extends TileMapLayer

enum Biome { FOREST, VOLCANO, OCEAN, SKY_ISLANDS, CITY }
const RANDOM_BIOMES: Array[int] = [Biome.FOREST, Biome.VOLCANO, Biome.OCEAN, Biome.SKY_ISLANDS, Biome.CITY]

const TILE_SIZE: Vector2i = Vector2i(32, 32)
const GRASS_TEXTURE: Texture2D = preload("res://assets/terrain_tile.svg")
const OCEAN_TEXTURE: Texture2D = preload("res://assets/terrain_ocean.svg")
const VOLCANO_TEXTURE: Texture2D = preload("res://assets/terrain_volcano.svg")
const SKY_TEXTURE: Texture2D = preload("res://assets/terrain_sky.svg")
const CITY_TEXTURE: Texture2D = preload("res://assets/terrain_city.svg")
const CITY_SKYLINE: Texture2D = preload("res://assets/city_skyline.svg")
const EXIT_PORTAL_SCRIPT: GDScript = preload("res://scripts/exit_portal.gd")

# Mỗi biome chỉ spawn đúng nhóm Monster của nó.
const MONSTER_SCENES: Dictionary = {
	Biome.FOREST: [preload("res://scenes/monsters/forest_slime.tscn"), preload("res://scenes/monsters/forest_mushroom.tscn")],
	Biome.VOLCANO: [preload("res://scenes/monsters/volcano_imp.tscn"), preload("res://scenes/monsters/volcano_golem.tscn")],
	Biome.OCEAN: [preload("res://scenes/monsters/ocean_crab.tscn"), preload("res://scenes/monsters/ocean_jelly.tscn")],
	Biome.SKY_ISLANDS: [preload("res://scenes/monsters/sky_bird.tscn"), preload("res://scenes/monsters/sky_cloud.tscn")],
	Biome.CITY: [preload("res://scenes/monsters/city_cat.tscn"), preload("res://scenes/monsters/city_car.tscn")],
}

@export var biome: Biome = Biome.FOREST
# Randomly choose a biome for each newly spawned game scene.
@export var randomize_biome_on_spawn: bool = true
@export var spawn_monsters_on_ready: bool = true
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
		biome = RANDOM_BIOMES[biome_rng.randi_range(0, RANDOM_BIOMES.size() - 1)] as Biome
		print("Spawned biome: ", Biome.keys()[biome])
	tile_set = _create_terrain_tile_set()
	_generate_layout()
	_place_demo_characters()
	if spawn_monsters_on_ready:
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
		Biome.CITY:
			return CITY_TEXTURE
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
		Biome.CITY:
			_generate_city()
		_:
			_generate_forest(random_generator)


func _generate_forest(random_generator: RandomNumberGenerator) -> void:
	_add_background(Color("#18282d"))
	_add_forest_scenery(random_generator)
	_generate_floor_and_walls(0)
	for start_x: int in [3, map_width_cells - 8]:
		var platform_length: int = random_generator.randi_range(3, 5)
		var platform_row: int = random_generator.randi_range(floor_row - 3, floor_row - 2)
		_add_platform(start_x, platform_row, platform_length, 0)
	_monster_spawns = [_ground_spawn(14.5, floor_row), _ground_spawn(21.5, floor_row), _ground_spawn(26.5, floor_row)]


func _generate_ocean(random_generator: RandomNumberGenerator) -> void:
	_add_background(Color("#167d9b"), water_surface_y)
	_add_ocean_scenery(random_generator)
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
	_add_volcano_scenery(random_generator)
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
	_add_sky_scenery()
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


func _generate_city() -> void:
	_add_background(Color("#b1dedb"))
	var skyline: Sprite2D = Sprite2D.new()
	skyline.name = "CitySkyline"
	skyline.texture = CITY_SKYLINE
	skyline.centered = false
	skyline.z_index = -9
	skyline.scale = Vector2(float(map_width_cells * TILE_SIZE.x) / 960.0, float(floor_row * TILE_SIZE.y) / 480.0)
	add_child(skyline)
	_add_city_scenery()
	_generate_floor_and_walls(0)
	var building_columns: Array[int] = [int(map_width_cells * 0.32), int(map_width_cells * 0.65)]
	for building_index: int in range(building_columns.size()):
		var start_x: int = building_columns[building_index]
		var roof_row: int = floor_row - 3 - building_index
		_add_platform(start_x - 2, floor_row - 2, 2, 0)
		for row: int in range(roof_row, floor_row):
			_add_platform(start_x, row, 4, 0)
	_debug_player_spawn = Vector2(3.5 * TILE_SIZE.x, floor_row * TILE_SIZE.y - 22.0)
	_monster_spawns = [
		_ground_spawn(building_columns[0] + 1.5, floor_row - 3),
		_ground_spawn(building_columns[1] + 1.5, floor_row - 4),
		_ground_spawn(map_width_cells - 3.5, floor_row),
	]
	_debug_monster_spawn = _monster_spawns[0]


func _add_forest_scenery(random_generator: RandomNumberGenerator) -> void:
	var world_width: float = float(map_width_cells * TILE_SIZE.x)
	_add_mountain_range("DistantMountains", random_generator, 365.0, 145.0, 265.0, Color("#879cad"), -9)
	_add_mountain_range("ForestRidges", random_generator, 410.0, 245.0, 335.0, Color("#527b70"), -8)
	for tree_index: int in range(36):
		var x: float = random_generator.randf_range(0.0, world_width)
		var height: float = random_generator.randf_range(48.0, 112.0)
		var base_y: float = random_generator.randf_range(350.0, float(floor_row * TILE_SIZE.y - 18))
		_add_pine_tree(x, base_y, height, Color("#315b52") if tree_index % 2 == 0 else Color("#3d6a57"), -6)
	for x: float in [48.0, 128.0, 410.0, 530.0, 710.0, 900.0]:
		_add_deciduous_tree(x, float(floor_row * TILE_SIZE.y - 10), random_generator.randf_range(108.0, 188.0), random_generator, -3)
	for bush_x: float in [34.0, 222.0, 372.0, 642.0, 840.0, 946.0]:
		_add_bush(bush_x, float(floor_row * TILE_SIZE.y - 13), random_generator, -2)


func _add_ocean_scenery(random_generator: RandomNumberGenerator) -> void:
	var sky: Polygon2D = Polygon2D.new()
	sky.name = "OceanSky"
	sky.z_index = -12
	sky.polygon = PackedVector2Array([Vector2.ZERO, Vector2(map_width_cells * TILE_SIZE.x, 0), Vector2(map_width_cells * TILE_SIZE.x, water_surface_y), Vector2(0, water_surface_y)])
	sky.color = Color("#82c9d8")
	add_child(sky)
	_add_mountain_range("OceanIslandsFar", random_generator, water_surface_y + 36.0, 48.0, 118.0, Color("#83aa9c"), -9)
	for coral_index: int in range(15):
		var coral_x: float = random_generator.randf_range(0.0, float(map_width_cells * TILE_SIZE.x))
		var coral_y: float = random_generator.randf_range(water_surface_y + 42.0, float(floor_row * TILE_SIZE.y - 18))
		_add_coral(coral_x, coral_y, random_generator, -3)


func _add_volcano_scenery(random_generator: RandomNumberGenerator) -> void:
	_add_mountain_range("VolcanoAshMountains", random_generator, 390.0, 160.0, 280.0, Color("#625765"), -9)
	_add_mountain_range("VolcanoRidges", random_generator, 430.0, 280.0, 355.0, Color("#493e4b"), -8)
	var world_width: float = float(map_width_cells * TILE_SIZE.x)
	for plume_index: int in range(8):
		var plume_x: float = random_generator.randf_range(0.0, world_width)
		var plume_y: float = random_generator.randf_range(100.0, 270.0)
		_add_cloud_puff(plume_x, plume_y, random_generator.randf_range(24.0, 52.0), Color(0.88, 0.72, 0.63, 0.28), -7)
	for ember_index: int in range(28):
		var ember: Polygon2D = Polygon2D.new()
		ember.name = "DistantEmber"
		ember.z_index = -2
		var ember_x: float = random_generator.randf_range(0.0, world_width)
		var ember_y: float = random_generator.randf_range(265.0, float(floor_row * TILE_SIZE.y - 28))
		ember.polygon = _ellipse_points(ember_x, ember_y, random_generator.randf_range(1.0, 2.5), random_generator.randf_range(1.0, 3.0), 8)
		ember.color = Color("#ef9860")
		add_child(ember)


func _add_sky_scenery() -> void:
	var random_generator: RandomNumberGenerator = RandomNumberGenerator.new()
	random_generator.seed = generation_seed + 73
	for cloud_index: int in range(13):
		var cloud_x: float = random_generator.randf_range(-30.0, float(map_width_cells * TILE_SIZE.x))
		var cloud_y: float = random_generator.randf_range(48.0, 345.0)
		_add_cloud_puff(cloud_x, cloud_y, random_generator.randf_range(26.0, 68.0), Color(0.92, 0.98, 0.98, 0.48), -9)
	_add_mountain_range("SkyIslandsFar", random_generator, 430.0, 245.0, 365.0, Color("#74b8ba"), -8)


func _add_city_scenery() -> void:
	var world_width: float = float(map_width_cells * TILE_SIZE.x)
	for lamp_x: float in [92.0, 462.0, 860.0]:
		var lamp: Polygon2D = Polygon2D.new()
		lamp.name = "StreetLamp"
		lamp.z_index = -2
		lamp.polygon = PackedVector2Array([
			Vector2(lamp_x - 2.0, 305.0), Vector2(lamp_x + 2.0, 305.0),
			Vector2(lamp_x + 2.0, float(floor_row * TILE_SIZE.y)), Vector2(lamp_x - 2.0, float(floor_row * TILE_SIZE.y)),
		])
		lamp.color = Color("#485761")
		add_child(lamp)
		_add_glow(lamp_x, 306.0, Color("#ffdf8b", 0.7), -1)
	var wire: Line2D = Line2D.new()
	wire.name = "OverheadWire"
	wire.z_index = -2
	wire.width = 2.0
	wire.default_color = Color("#52616c")
	wire.points = PackedVector2Array([Vector2(0.0, 292.0), Vector2(world_width * 0.25, 307.0), Vector2(world_width * 0.5, 294.0), Vector2(world_width * 0.75, 309.0), Vector2(world_width, 296.0)])
	add_child(wire)


func _add_mountain_range(layer_name: String, random_generator: RandomNumberGenerator, base_y: float, min_peak_y: float, max_peak_y: float, color: Color, draw_order: int) -> void:
	var world_width: float = float(map_width_cells * TILE_SIZE.x)
	var step: float = 112.0
	var points: PackedVector2Array = PackedVector2Array([Vector2(0.0, base_y)])
	var segment_count: int = ceili(world_width / step)
	for segment_index: int in range(segment_count):
		var start_x: float = float(segment_index) * step
		var end_x: float = minf(start_x + step, world_width)
		var peak_x: float = start_x + (end_x - start_x) * random_generator.randf_range(0.38, 0.62)
		points.append(Vector2(peak_x, random_generator.randf_range(min_peak_y, max_peak_y)))
		points.append(Vector2(end_x, base_y))
	points.append(Vector2(world_width, float(ProjectSettings.get_setting("display/window/size/viewport_height"))))
	points.append(Vector2(0.0, float(ProjectSettings.get_setting("display/window/size/viewport_height"))))
	_add_polygon(layer_name, points, color, draw_order)


func _add_pine_tree(x: float, base_y: float, height: float, color: Color, draw_order: int) -> void:
	var trunk: Polygon2D = Polygon2D.new()
	trunk.name = "DistantPineTrunk"
	trunk.z_index = draw_order
	trunk.polygon = PackedVector2Array([Vector2(x - 2.0, base_y - height * 0.3), Vector2(x + 2.0, base_y - height * 0.3), Vector2(x + 2.5, base_y), Vector2(x - 2.5, base_y)])
	trunk.color = Color("#574d43")
	add_child(trunk)
	for tier: int in range(3):
		var top_y: float = base_y - height + float(tier) * height * 0.24
		var tier_width: float = height * (0.23 + float(tier) * 0.1)
		_add_polygon("DistantPine", PackedVector2Array([Vector2(x, top_y), Vector2(x - tier_width, top_y + height * 0.42), Vector2(x + tier_width, top_y + height * 0.42)]), color.darkened(float(tier) * 0.08), draw_order)


func _add_deciduous_tree(x: float, base_y: float, height: float, random_generator: RandomNumberGenerator, draw_order: int) -> void:
	var trunk_width: float = random_generator.randf_range(7.0, 12.0)
	_add_polygon("ForestTreeTrunk", PackedVector2Array([Vector2(x - trunk_width * 0.5, base_y), Vector2(x + trunk_width * 0.5, base_y), Vector2(x + 2.5, base_y - height), Vector2(x - 2.5, base_y - height)]), Color("#70533e"), draw_order)
	for branch_index: int in range(3):
		var branch_y: float = base_y - height * (0.3 + float(branch_index) * 0.2)
		var side: float = -1.0 if branch_index % 2 == 0 else 1.0
		_add_polygon("ForestTreeBranch", PackedVector2Array([Vector2(x, branch_y + 10.0), Vector2(x + side * 44.0, branch_y - 18.0), Vector2(x + side * 50.0, branch_y - 13.0), Vector2(x + 2.0, branch_y + 14.0)]), Color("#70533e"), draw_order)
	var foliage_colors: Array[Color] = [Color("#356f52"), Color("#47865a"), Color("#65945c"), Color("#8e9c5c"), Color("#c9799b")]
	var foliage_color: Color = foliage_colors[random_generator.randi_range(0, foliage_colors.size() - 1)]
	for cluster: int in range(8):
		var angle: float = TAU * float(cluster) / 8.0
		var center: Vector2 = Vector2(x + cos(angle) * 30.0, base_y - height - 8.0 + sin(angle) * 20.0)
		var foliage: Polygon2D = Polygon2D.new()
		foliage.name = "ForestCanopy"
		foliage.z_index = draw_order
		foliage.polygon = _ellipse_points(center.x, center.y, 26.0, 22.0, 12)
		foliage.color = foliage_color.darkened(random_generator.randf_range(0.0, 0.16))
		add_child(foliage)


func _add_bush(x: float, y: float, random_generator: RandomNumberGenerator, draw_order: int) -> void:
	var color: Color = Color("#4d8a58")
	for cluster: int in range(4):
		var center_x: float = x + float(cluster - 1) * 9.0
		_add_polygon("ForestBush", _ellipse_points(center_x, y - random_generator.randf_range(4.0, 10.0), 12.0, 9.0, 10), color.lightened(random_generator.randf_range(0.0, 0.15)), draw_order)


func _add_coral(x: float, y: float, random_generator: RandomNumberGenerator, draw_order: int) -> void:
	var coral_color: Color = Color("#ef987d") if random_generator.randf() > 0.5 else Color("#e6c66e")
	var width: float = random_generator.randf_range(8.0, 15.0)
	_add_polygon("DistantCoral", PackedVector2Array([Vector2(x - 2.0, y + 20.0), Vector2(x + 2.0, y + 20.0), Vector2(x + 1.0, y - 8.0), Vector2(x + width, y - 22.0), Vector2(x + width - 2.0, y - 25.0), Vector2(x - 1.0, y - 14.0), Vector2(x - width, y - 29.0), Vector2(x - width - 2.0, y - 25.0), Vector2(x - 2.0, y - 12.0)]), coral_color, draw_order)


func _add_cloud_puff(x: float, y: float, radius: float, color: Color, draw_order: int) -> void:
	for puff_index: int in range(4):
		var center_x: float = x + (float(puff_index) - 1.5) * radius * 0.42
		var center_y: float = y + absf(float(puff_index) - 1.5) * radius * 0.08
		_add_polygon("SceneryCloud", _ellipse_points(center_x, center_y, radius * 0.48, radius * 0.26, 14), color, draw_order)


func _add_glow(x: float, y: float, color: Color, draw_order: int) -> void:
	_add_polygon("StreetLampGlow", _ellipse_points(x, y, 15.0, 15.0, 16), color, draw_order)


func _ellipse_points(x: float, y: float, radius_x: float, radius_y: float, point_count: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(point_count):
		var angle: float = TAU * float(point_index) / float(point_count)
		points.append(Vector2(x + cos(angle) * radius_x, y + sin(angle) * radius_y))
	return points


func _add_polygon(node_name: String, points: PackedVector2Array, color: Color, draw_order: int) -> Polygon2D:
	var polygon: Polygon2D = Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.z_index = draw_order
	add_child(polygon)
	return polygon


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


func wrap_horizontal(body: Node2D) -> void:
	if biome != Biome.SKY_ISLANDS:
		return
	var world_width: float = float(map_width_cells * TILE_SIZE.x)
	var local_position: Vector2 = to_local(body.global_position)
	if local_position.x >= 0.0 and local_position.x < world_width:
		return
	local_position.x = fposmod(local_position.x, world_width)
	body.global_position = to_global(local_position)


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
	var city_spawn_count: int = 0
	for spawn_position: Vector2 in _monster_spawns:
		if player != null and spawn_position.distance_to(player.global_position) < safe_radius:
			continue
		var forced_scene: PackedScene = null
		if biome == Biome.CITY and city_spawn_count < 2:
			forced_scene = MONSTER_SCENES[Biome.CITY][city_spawn_count]
		spawn_random_monster(spawn_position, forced_scene)
		city_spawn_count += 1
	_monsters_spawned = true


# Tạo một Monster ngẫu nhiên thuộc đúng biome hiện tại.
func spawn_random_monster(world_position: Vector2, forced_scene: PackedScene = null) -> Node2D:
	var pool: Array = MONSTER_SCENES.get(biome, [])
	if pool.is_empty():
		return null
	var monster_scene: PackedScene = forced_scene if forced_scene != null else pool[randi() % pool.size()]
	var monster: Node2D = monster_scene.instantiate()
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
