# Autoload: lưu toàn bộ Pet đã bắt và đội hình mang vào trận ra file local.
extends Node

const SAVE_PATH := "user://pet_save.json"
const TEAM_SIZE := 3
# Save cũ chưa có movement_mode: suy ra từ hình của loài.
const LEGACY_MOVEMENT_MODES: Dictionary = {
	"crab.png": "Swim", "jelly.png": "Swim", "bird.png": "Fly", "cloud_slime.png": "Fly",
}

# Mỗi phần tử là dữ liệu Pet dạng JSON được (texture lưu bằng đường dẫn).
var collection: Array[Dictionary] = []
# Chỉ số trong collection của các Pet mang vào trận, theo thứ tự phím 1/2/3.
var team: Array[int] = []


func _ready() -> void:
	load_data()


func load_data() -> void:
	collection.clear()
	team.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("File lưu Pet bị hỏng, bỏ qua.")
		return
	for entry: Variant in parsed.get("collection", []):
		if entry is Dictionary and _is_valid_entry(entry):
			collection.append(entry)
	for index: Variant in parsed.get("team", []):
		var team_index: int = int(index)
		if team_index >= 0 and team_index < collection.size() and not team.has(team_index) and team.size() < TEAM_SIZE:
			team.append(team_index)


func save_data() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Không thể ghi file lưu Pet: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({"collection": collection, "team": team}, "\t"))


# Thêm Pet mới bắt; tự đưa vào đội nếu còn chỗ. Trả về true nếu Pet vào đội.
func add_captured_pet(pet_data: Dictionary) -> bool:
	collection.append(_to_saved(pet_data))
	var joined_team: bool = team.size() < TEAM_SIZE
	if joined_team:
		team.append(collection.size() - 1)
	save_data()
	return joined_team


func is_in_team(collection_index: int) -> bool:
	return team.has(collection_index)


func add_to_team(collection_index: int) -> bool:
	if team.size() >= TEAM_SIZE or team.has(collection_index) or collection_index < 0 or collection_index >= collection.size():
		return false
	team.append(collection_index)
	save_data()
	return true


func remove_from_team(collection_index: int) -> void:
	team.erase(collection_index)
	save_data()


# Đổi chỗ một Pet trong đội sang trái (-1) hoặc phải (+1).
func move_in_team(team_slot: int, offset: int) -> void:
	var target_slot: int = team_slot + offset
	if team_slot < 0 or team_slot >= team.size() or target_slot < 0 or target_slot >= team.size():
		return
	var moved: int = team[team_slot]
	team[team_slot] = team[target_slot]
	team[target_slot] = moved
	save_data()


func release_pet(collection_index: int) -> void:
	if collection_index < 0 or collection_index >= collection.size():
		return
	collection.remove_at(collection_index)
	var new_team: Array[int] = []
	for index: int in team:
		if index != collection_index:
			new_team.append(index - 1 if index > collection_index else index)
	team = new_team
	save_data()


func reset_progress() -> void:
	collection.clear()
	team.clear()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# Dữ liệu dùng được trong game (texture đã load, scale là Vector2).
func get_runtime_pet(collection_index: int) -> Dictionary:
	var saved: Dictionary = collection[collection_index]
	var runtime: Dictionary = saved.duplicate()
	runtime["texture"] = load(saved["texture_path"]) if ResourceLoader.exists(saved["texture_path"]) else null
	runtime["sprite_scale"] = Vector2(float(saved["sprite_scale"][0]), float(saved["sprite_scale"][1]))
	runtime["max_hp"] = int(saved["max_hp"])
	runtime["attack_damage"] = int(saved["attack_damage"])
	runtime["attack_interval"] = float(saved["attack_interval"])
	runtime["attack_range"] = float(saved["attack_range"])
	runtime["movement_mode"] = saved.get("movement_mode", LEGACY_MOVEMENT_MODES.get(str(saved["texture_path"]).get_file(), "Ground"))
	runtime["melee_contact_reach"] = float(saved.get("melee_contact_reach", 10.0))
	return runtime


func get_team_runtime() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in team:
		result.append(get_runtime_pet(index))
	return result


func _to_saved(pet_data: Dictionary) -> Dictionary:
	var texture: Texture2D = pet_data.get("texture")
	var sprite_scale: Vector2 = pet_data.get("sprite_scale", Vector2.ONE)
	return {
		"name": str(pet_data.get("name", "Pet")),
		"attack_style": str(pet_data.get("attack_style", "Melee")),
		"texture_path": texture.resource_path if texture != null else "",
		"sprite_scale": [sprite_scale.x, sprite_scale.y],
		"max_hp": int(pet_data.get("max_hp", 50)),
		"attack_damage": int(pet_data.get("attack_damage", 5)),
		"attack_interval": float(pet_data.get("attack_interval", 1.2)),
		"attack_range": float(pet_data.get("attack_range", 38.0)),
		"movement_mode": str(pet_data.get("movement_mode", "Ground")),
		"melee_contact_reach": float(pet_data.get("melee_contact_reach", 10.0)),
	}


func _is_valid_entry(entry: Dictionary) -> bool:
	for key: String in ["name", "attack_style", "texture_path", "sprite_scale", "max_hp", "attack_damage", "attack_interval", "attack_range"]:
		if not entry.has(key):
			return false
	return entry["texture_path"] is String and str(entry["texture_path"]).begins_with("res://") \
		and entry["sprite_scale"] is Array and entry["sprite_scale"].size() == 2
