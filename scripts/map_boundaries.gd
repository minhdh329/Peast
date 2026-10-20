extends StaticBody2D

@export var map_width: float = 960.0:
	set(value):
		map_width = value
		if is_instance_valid(_right_wall):
			_right_wall.position.x = map_width

var _right_wall: CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var left_wall: CollisionShape2D = CollisionShape2D.new()
	left_wall.name = "LeftWall"
	var left_shape: WorldBoundaryShape2D = WorldBoundaryShape2D.new()
	left_shape.normal = Vector2.RIGHT
	left_wall.shape = left_shape
	add_child(left_wall)
	_right_wall = CollisionShape2D.new()
	_right_wall.name = "RightWall"
	var right_shape: WorldBoundaryShape2D = WorldBoundaryShape2D.new()
	right_shape.normal = Vector2.LEFT
	_right_wall.shape = right_shape
	_right_wall.position.x = map_width
	add_child(_right_wall)