# CanvasLayer giữ bảng debug cố định trên màn hình khi thế giới game di chuyển.
extends CanvasLayer

# Scene Monster được gán trong Inspector của debug_panel.tscn.
@export var monster_scene: PackedScene
# Vị trí thế giới nơi Monster mới sẽ xuất hiện.
@export var monster_spawn_position: Vector2 = Vector2(580.0, 462.0)

# Lấy các control để nối nút và cập nhật trạng thái.
@onready var respawn_button: Button = $Panel/Margin/VBox/RespawnButton
@onready var respawn_player_button: Button = $Panel/Margin/VBox/RespawnPlayerButton
@onready var status_label: Label = $Panel/Margin/VBox/Status
@onready var toggle_button: Button = $ToggleButton
@onready var panel: PanelContainer = $Panel
@onready var reset_progress_button: Button = $Panel/Margin/VBox/ResetProgressButton
@onready var reset_confirm: ConfirmationDialog = $ResetConfirm


# Nối sự kiện nút sau khi các node con đã sẵn sàng.
func _ready() -> void:
	respawn_button.pressed.connect(_on_respawn_pressed)
	respawn_player_button.pressed.connect(_on_respawn_player_pressed)
	toggle_button.toggled.connect(func(shown: bool) -> void: panel.visible = shown)
	reset_progress_button.pressed.connect(reset_confirm.popup_centered)
	reset_confirm.confirmed.connect(_on_reset_progress_confirmed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		toggle_button.button_pressed = not toggle_button.button_pressed


# Xóa file save rồi tải lại màn chơi để mọi thứ về trạng thái ban đầu.
func _on_reset_progress_confirmed() -> void:
	PetStorage.reset_progress()
	get_tree().reload_current_scene()


# Đưa Player về điểm spawn của biome với đầy máu.
func _on_respawn_player_pressed() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		status_label.text = "No player in scene"
		return

	var terrain: ProceduralTerrain = get_tree().get_first_node_in_group("procedural_terrain") as ProceduralTerrain
	var spawn_position: Vector2 = terrain.get_player_spawn_position() if terrain != null else Vector2(180.0, 350.0)
	player.call("respawn", spawn_position)
	status_label.text = "Player: respawned"


# Xóa các Monster hiện có và tạo lại đúng một Monster mới tại vị trí spawn.
func _on_respawn_pressed() -> void:
	# Không tiếp tục nếu PackedScene chưa được gán trong Inspector.
	if monster_scene == null:
		status_label.text = "Monster scene is not assigned"
		push_warning("Hãy gán scenes/monster.tscn vào Monster Scene trong Inspector.")
		return

	# Lấy scene gốc đang chạy để Monster mới được thêm vào thế giới game.
	var game_root: Node = get_tree().current_scene
	if game_root == null:
		status_label.text = "No active game scene"
		return

	# Đánh dấu các Monster cũ để giải phóng, tránh tạo nhiều bản sao khi bấm reset.
	for existing_monster: Node in get_tree().get_nodes_in_group("monsters"):
		existing_monster.queue_free()

	# Spawn một Monster thuộc đúng biome hiện tại tại điểm an toàn.
	var terrain: ProceduralTerrain = game_root.get_node_or_null("Terrain") as ProceduralTerrain
	if terrain != null:
		terrain.spawn_random_monster(terrain.get_debug_monster_spawn_position())
		status_label.text = "Monster: respawned"
		return

	var monster: Monster = monster_scene.instantiate()
	game_root.add_child(monster)
	monster.global_position = monster_spawn_position
	status_label.text = "Monster: respawned"
