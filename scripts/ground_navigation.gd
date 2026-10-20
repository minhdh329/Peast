extends RefCounted

const PLATFORM_MASK: int = 4
const PLATFORM_ALTERNATIVE: int = 1

var _graph: AStar2D = AStar2D.new()
var _cells: Dictionary = {}
var _edges: Dictionary = {}
var _flight_times: Dictionary = {}
var _terrain: TileMapLayer
var _map_hash: int = 0
var _speed: float = 0.0
var _jump_velocity: float = 0.0
var _half_size: Vector2 = Vector2(18.0, 18.0)
var _recheck_time: float = 0.0
var _air_target: Vector2 = Vector2.INF
var _air_time: float = 0.0
var _air_velocity: float = 0.0
var _drop_y: float = INF


static func feet_for(body: Node2D) -> Vector2:
	var shape_node: CollisionShape2D = body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return body.global_position
	return shape_node.global_position + Vector2(0.0, shape_node.shape.get_rect().size.y * absf(shape_node.global_scale.y) * 0.5)


func update(actor: CharacterBody2D) -> void:
	if _drop_y != INF and (actor.global_position.y - _half_size.y > _drop_y + 9.0 or (actor.is_on_floor() and feet_for(actor).y > _drop_y + 10.0)):
		actor.collision_mask |= PLATFORM_MASK
		_drop_y = INF


func reset(actor: CharacterBody2D) -> void:
	actor.collision_mask |= PLATFORM_MASK
	_drop_y = INF
	_air_target = Vector2.INF
	_air_time = 0.0


func is_dropping() -> bool:
	return _drop_y != INF


func steer(actor: CharacterBody2D, destination: Vector2, speed: float, jump_velocity: float, delta: float) -> bool:
	update(actor)
	var terrain: TileMapLayer = actor.get_tree().get_first_node_in_group("procedural_terrain") as TileMapLayer
	if terrain == null or terrain.tile_set == null:
		return false
	if _air_target != Vector2.INF:
		_air_time += delta
		if (actor.is_on_floor() and _air_time > 0.08) or _air_time > 2.5:
			_air_target = Vector2.INF
		else:
			actor.velocity.x = clampf((_air_target.x - actor.global_position.x) / maxf(delta, 0.001), -absf(_air_velocity), absf(_air_velocity))
			return true
	if not actor.is_on_floor():
		return false
	_recheck_time -= delta
	if terrain != _terrain or not is_equal_approx(speed, _speed) or not is_equal_approx(jump_velocity, _jump_velocity) or _recheck_time <= 0.0:
		var used_cells: Array[Vector2i] = terrain.get_used_cells()
		var map_hash: int = hash(used_cells)
		if terrain != _terrain or map_hash != _map_hash or not is_equal_approx(speed, _speed) or not is_equal_approx(jump_velocity, _jump_velocity):
			_terrain = terrain
			_map_hash = map_hash
			_speed = maxf(speed, 1.0)
			_jump_velocity = jump_velocity
			var shape_node: CollisionShape2D = actor.get_node("CollisionShape2D") as CollisionShape2D
			_half_size = shape_node.shape.get_rect().size * shape_node.global_scale.abs() * 0.5
			_build_graph(used_cells, float(ProjectSettings.get_setting("physics/2d/default_gravity")))
		_recheck_time = 0.4
	if _graph.get_point_count() == 0:
		return false
	var start_id: int = _graph.get_closest_point(feet_for(actor))
	var end_id: int = _graph.get_closest_point(destination)
	var path: PackedInt64Array = _graph.get_id_path(start_id, end_id, true)
	if path.size() < 2:
		var surface_x: float = _graph.get_point_position(start_id).x
		var goal_x: float = clampf(destination.x, surface_x - 12.0, surface_x + 12.0) if start_id == end_id else surface_x
		actor.velocity.x = clampf((goal_x - actor.global_position.x) / maxf(delta, 0.001), -speed, speed)
		return true
	var from_position: Vector2 = _graph.get_point_position(path[0])
	var next_position: Vector2 = _graph.get_point_position(path[1])
	var mode: String = _edges[Vector2i(path[0], path[1])]
	if mode == "walk":
		actor.velocity.x = signf(next_position.x - actor.global_position.x) * speed
		return true
	if absf(actor.global_position.x - from_position.x) > 4.0:
		actor.velocity.x = clampf((from_position.x - actor.global_position.x) / maxf(delta, 0.001), -speed, speed)
		return true
	_air_target = next_position
	_air_time = 0.0
	_air_velocity = (next_position.x - actor.global_position.x) / float(_flight_times[Vector2i(path[0], path[1])])
	actor.velocity.x = _air_velocity
	if mode == "drop":
		_drop_y = from_position.y
		actor.collision_mask &= ~PLATFORM_MASK
		actor.velocity.y = 100.0
	else:
		actor.velocity.y = jump_velocity
	return true


func _is_solid(cell: Vector2i) -> bool:
	return _terrain.get_cell_source_id(cell) != -1 and _terrain.get_cell_alternative_tile(cell) != PLATFORM_ALTERNATIVE


func _build_graph(used_cells: Array[Vector2i], gravity: float) -> void:
	_graph.clear()
	_cells.clear()
	_edges.clear()
	_flight_times.clear()
	var tile_size: Vector2i = _terrain.tile_set.tile_size
	for cell: Vector2i in used_cells:
		if _is_solid(cell + Vector2i.UP):
			continue
		var surface: Vector2 = _terrain.to_global(_terrain.map_to_local(cell) - Vector2(0.0, tile_size.y * 0.5))
		var needs_edge_points: bool = not _body_clear(surface)
		for direction: int in [-1, 1]:
			if _is_solid(cell + Vector2i(direction, -1)) or _is_solid(cell + Vector2i(direction * 2, -1)):
				needs_edge_points = true
			if _is_solid(cell) and _terrain.get_cell_source_id(cell + Vector2i(direction, 0)) == -1:
				needs_edge_points = true
		var candidates: Array[Vector2] = [surface]
		if needs_edge_points:
			candidates.append(surface - Vector2(tile_size.x * 0.25, 0.0))
			candidates.append(surface + Vector2(tile_size.x * 0.25, 0.0))
		for candidate: Vector2 in candidates:
			if not _body_clear(candidate):
				continue
			var point_id: int = _graph.get_point_count()
			_graph.add_point(point_id, candidate)
			_cells[point_id] = cell
	var max_rise: float = _jump_velocity * _jump_velocity / (2.0 * gravity)
	for from_id: int in _graph.get_point_ids():
		var start: Vector2 = _graph.get_point_position(from_id)
		for to_id: int in _graph.get_point_ids():
			if from_id == to_id:
				continue
			var finish: Vector2 = _graph.get_point_position(to_id)
			var offset: Vector2 = finish - start
			if offset.y < -max_rise + 2.0 or offset.y > tile_size.y * 6.0 or absf(offset.x) > _speed * 1.3:
				continue
			var mode: String = "jump"
			var launch_velocity: float = _jump_velocity
			if absf(offset.y) < 1.0 and absf(offset.x) <= tile_size.x + 1.0:
				mode = "walk"
			elif offset.y >= maxf(tile_size.y * 2.0, _half_size.y * 2.0 + 12.0) and _terrain.get_cell_alternative_tile(_cells[from_id]) == PLATFORM_ALTERNATIVE:
				mode = "drop"
				launch_velocity = 100.0
			var flight_time: float = (-launch_velocity + sqrt(launch_velocity * launch_velocity + 2.0 * gravity * offset.y)) / gravity
			if mode == "walk":
				flight_time = absf(offset.x) / _speed
			elif absf(offset.x) > _speed * flight_time - 2.0:
				continue
			if not _arc_clear(start, finish, flight_time, launch_velocity, gravity, mode):
				continue
			_graph.connect_points(from_id, to_id, false)
			_edges[Vector2i(from_id, to_id)] = mode
			_flight_times[Vector2i(from_id, to_id)] = flight_time


func _body_clear(feet: Vector2) -> bool:
	var top_left: Vector2i = _terrain.local_to_map(_terrain.to_local(feet + Vector2(-_half_size.x + 1.0, -_half_size.y * 2.0 + 1.0)))
	var bottom_right: Vector2i = _terrain.local_to_map(_terrain.to_local(feet + Vector2(_half_size.x - 1.0, -1.0)))
	for column: int in range(top_left.x, bottom_right.x + 1):
		for row: int in range(top_left.y, bottom_right.y + 1):
			if _is_solid(Vector2i(column, row)):
				return false
	return true


func _arc_clear(start: Vector2, finish: Vector2, duration: float, launch_velocity: float, gravity: float, mode: String) -> bool:
	var sample_count: int = maxi(12, ceili(duration * 60.0))
	var previous: Vector2 = start
	for sample_index: int in range(1, sample_count + 1):
		var fraction: float = float(sample_index) / sample_count
		var elapsed: float = duration * fraction
		var feet: Vector2 = Vector2(lerpf(start.x, finish.x, fraction), start.y)
		if mode != "walk":
			feet.y += launch_velocity * elapsed + gravity * elapsed * elapsed * 0.5
		if not _body_clear(feet):
			return false
		if mode == "jump" and feet.y > previous.y:
			var cell: Vector2i = _terrain.local_to_map(_terrain.to_local(feet))
			for row: int in range(_terrain.local_to_map(_terrain.to_local(previous)).y, cell.y + 1):
				var crossed_cell: Vector2i = Vector2i(cell.x, row)
				var top_y: float = _terrain.to_global(_terrain.map_to_local(crossed_cell)).y - _terrain.tile_set.tile_size.y * 0.5
				if top_y < finish.y - 1.0 and previous.y <= top_y and feet.y >= top_y and _terrain.get_cell_alternative_tile(crossed_cell) == PLATFORM_ALTERNATIVE:
					return false
		previous = feet
	return true