# Autoload: lưu toàn bộ Pet đã bắt và đội hình mang vào trận ra file local.
extends Node

const SAVE_PATH := "user://pet_save.json"
const TEAM_SIZE := 1
const ARENA_TEAM_SIZE: int = 5
const STARTING_GOLD: int = 3
const CAPTURE_ENTRY_COST: int = 3
const CAPTURE_ATTEMPT_COST: int = 3
const CAPTURE_SUCCESS_CHANCE: float = 0.5
const ARENA_WIN_GOLD: int = 5
const ARENA_LOSS_GOLD: int = 2
signal gold_changed(balance: int)

var gold: int = STARTING_GOLD
var save_path: String = SAVE_PATH
# Save cũ chưa có movement_mode: suy ra từ hình của loài.
const LEGACY_MOVEMENT_MODES: Dictionary = {
	"crab.png": "Swim", "jelly.png": "Swim", "bird.png": "Fly", "cloud_slime.png": "Fly",
}
const LEGACY_SPECIALS_BY_NAME: Dictionary = {
	"Slime rừng": {"split_on_death": true},
	"Nấm độc": {"attack_effect": "Poison"},
	"Quỷ lửa": {"attack_effect": "Burn"},
	"Sứa biển": {"attack_effect": "Stun", "attack_effect_chance": 0.25},
	"Cua biển": {"is_resistant_crab": true},
	"Golem dung nham": {"immune_to_knockback": true},
	"Mây dông": {"chain_lightning": true, "chain_lightning_radius": 64.0},
	"Chim gió": {"wind_dash_enabled": true},
}

# Mỗi phần tử là dữ liệu Pet dạng JSON được (texture lưu bằng đường dẫn).
var collection: Array[Dictionary] = []
# Chỉ số Pet chiến đấu duy nhất trong collection.
var team: Array[int] = []
# Chỉ số thú cưỡi, tách biệt với đội chiến đấu.
var mount_pet_index: int = -1
# Đội hình dùng một lần khi mở Arena; không được ghi vào save.
var arena_lineup: Array[Dictionary] = []
var arena_team_indices: Array[int] = []
var pending_capture_candidates: Array[Dictionary] = []


func _ready() -> void:
	load_data()


func load_data() -> void:
	collection.clear()
	team.clear()
	arena_team_indices.clear()
	mount_pet_index = -1
	gold = STARTING_GOLD
	if not FileAccess.file_exists(save_path):
		return
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("File lưu Pet bị hỏng, bỏ qua.")
		return
	gold = maxi(0, int(parsed.get("gold", STARTING_GOLD)))
	for entry: Variant in parsed.get("collection", []):
		if entry is Dictionary and _is_valid_entry(entry):
			collection.append(entry)
	for index: Variant in parsed.get("team", []):
		var team_index: int = int(index)
		if team_index >= 0 and team_index < collection.size() and not team.has(team_index) and team.size() < TEAM_SIZE:
			team.append(team_index)
	var saved_mount_index: int = int(parsed.get("mount_pet_index", -1))
	if saved_mount_index >= 0 and saved_mount_index < collection.size() and not team.has(saved_mount_index):
		mount_pet_index = saved_mount_index
	for index: Variant in parsed.get("arena_team_indices", []):
		var arena_index: int = int(index)
		if arena_index >= 0 and arena_index < collection.size() and not arena_team_indices.has(arena_index) and arena_team_indices.size() < ARENA_TEAM_SIZE:
			arena_team_indices.append(arena_index)


func save_data() -> void:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Không thể ghi file lưu Pet: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({"collection": collection, "team": team, "mount_pet_index": mount_pet_index, "gold": gold, "arena_team_indices": arena_team_indices}, "\t"))


func set_arena_team(indices: Array[int]) -> bool:
	if indices.size() != ARENA_TEAM_SIZE:
		return false
	var validated: Array[int] = []
	for index: int in indices:
		if index < 0 or index >= collection.size() or validated.has(index):
			return false
		validated.append(index)
	arena_team_indices.assign(validated)
	save_data()
	return true


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	save_data()
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	save_data()
	gold_changed.emit(gold)
	return true


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
	if team.size() >= TEAM_SIZE or team.has(collection_index) or collection_index == mount_pet_index or collection_index < 0 or collection_index >= collection.size():
		return false
	team.append(collection_index)
	save_data()
	return true


func remove_from_team(collection_index: int) -> void:
	team.erase(collection_index)
	save_data()


func set_mount_pet(collection_index: int) -> bool:
	if collection_index == -1:
		mount_pet_index = -1
		save_data()
		return true
	if collection_index < 0 or collection_index >= collection.size() or team.has(collection_index):
		return false
	mount_pet_index = collection_index
	save_data()
	return true


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
	_remove_pet_at(collection_index)
	save_data()


func _remove_pet_at(collection_index: int) -> void:
	collection.remove_at(collection_index)
	var new_team: Array[int] = []
	for index: int in team:
		if index != collection_index:
			new_team.append(index - 1 if index > collection_index else index)
	team = new_team
	var new_arena_team: Array[int] = []
	for index: int in arena_team_indices:
		if index != collection_index:
			new_arena_team.append(index - 1 if index > collection_index else index)
	arena_team_indices.assign(new_arena_team)
	if mount_pet_index == collection_index:
		mount_pet_index = -1
	elif mount_pet_index > collection_index:
		mount_pet_index -= 1


func CombinePets(index_A: int, index_B: int) -> Dictionary:
	if index_A == index_B:
		push_warning("Không thể dung hợp một thú với chính nó!")
		return {}
	if index_A < 0 or index_B < 0 or index_A >= collection.size() or index_B >= collection.size():
		push_warning("Vị trí thú trong túi đồ không hợp lệ!")
		return {}
	var pet_a: Dictionary = collection[index_A]
	var pet_b: Dictionary = collection[index_B]
	var species_a: String = str(pet_a.get("type", pet_a.get("name", "")))
	var species_b: String = str(pet_b.get("type", pet_b.get("name", "")))
	if species_a.is_empty() or species_a != species_b:
		push_warning("Chỉ được ghép thú cùng loài!")
		return {}

	# Gộp traits của hai thú; chỉ thêm tên chưa tồn tại để loại mọi đặc tính trùng.
	var pool_traits: Array[String] = []
	for parent: Dictionary in [pet_a, pet_b]:
		for trait_value: Variant in parent.get("current_traits", []):
			if trait_value is String and not trait_value.is_empty() and not pool_traits.has(trait_value):
				pool_traits.append(trait_value)
	if pool_traits.is_empty():
		push_warning("Không thể dung hợp thú không có đặc tính!")
		return {}
	var trait_count: int = randi_range(1, mini(4, pool_traits.size()))
	# Xáo trộn pool đã loại trùng rồi lấy N phần tử đầu: bốc ngẫu nhiên không hoàn lại.
	pool_traits.shuffle()
	var combined_traits: Array[String] = []
	for trait_index: int in range(trait_count):
		combined_traits.append(pool_traits[trait_index])

	var combined_pet: Dictionary = pet_a.duplicate(true)
	combined_pet["type"] = species_a
	var parent_traits: Array = pet_a.get("current_traits", [])
	var base_hp: int = int(pet_a["max_hp"])
	var base_attack: int = int(pet_a["attack_damage"])
	if parent_traits.has(Monster.TRAIT_DOUBLE_HP):
		base_hp = maxi(roundi(base_hp / 2.0), 1)
	if parent_traits.has(Monster.TRAIT_DOUBLE_DAMAGE):
		base_attack = maxi(roundi(base_attack / 2.0), 1)
	combined_pet["max_hp"] = base_hp * (2 if combined_traits.has(Monster.TRAIT_DOUBLE_HP) else 1)
	combined_pet["attack_damage"] = base_attack * (2 if combined_traits.has(Monster.TRAIT_DOUBLE_DAMAGE) else 1)
	combined_pet["current_traits"] = combined_traits
	combined_pet["revive_available"] = true
	for transient_field: String in ["current_hp", "fainted", "city_charge_count", "city_charge_ready"]:
		combined_pet.erase(transient_field)
	_remove_pet_at(maxi(index_A, index_B))
	_remove_pet_at(mini(index_A, index_B))
	collection.append(combined_pet)
	save_data()
	print("Dung hợp thành công! Chỉ số mới: HP %d, ATK %d, kích thước %s. Đặc tính: %s" % [combined_pet["max_hp"], combined_pet["attack_damage"], combined_pet["sprite_scale"], combined_traits])
	return get_runtime_pet(collection.size() - 1)


func reset_progress() -> void:
	collection.clear()
	team.clear()
	arena_team_indices.clear()
	mount_pet_index = -1
	gold = STARTING_GOLD
	gold_changed.emit(gold)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# Dữ liệu dùng được trong game (texture đã load, scale là Vector2).
func get_runtime_pet(collection_index: int) -> Dictionary:
	var saved: Dictionary = collection[collection_index]
	var runtime: Dictionary = saved.duplicate()
	runtime["type"] = str(saved.get("type", saved.get("name", "Pet")))
	var species_defaults: Dictionary = _get_legacy_special_defaults(str(saved.get("name", "")))
	var explosion_radius: float = float(saved.get("death_explosion_radius", 128.0))
	var explosion_damage: int = int(saved.get("death_explosion_damage", Monster.DEFAULT_DEATH_EXPLOSION_DAMAGE))
	var lifesteal_values: Dictionary = _migrate_lifesteal_values(saved)
	if is_equal_approx(explosion_radius, 72.0):
		explosion_radius = 128.0
	if explosion_damage == 30 or explosion_damage == 80:
		explosion_damage = Monster.DEFAULT_DEATH_EXPLOSION_DAMAGE
	runtime["texture"] = load(saved["texture_path"]) if ResourceLoader.exists(saved["texture_path"]) else null
	runtime["sprite_scale"] = Vector2(float(saved["sprite_scale"][0]), float(saved["sprite_scale"][1]))
	runtime["max_hp"] = int(saved["max_hp"])
	runtime["attack_damage"] = int(saved["attack_damage"])
	runtime["attack_interval"] = float(saved["attack_interval"])
	runtime["attack_range"] = float(saved["attack_range"])
	var movement_mode: String = str(saved.get("movement_mode", LEGACY_MOVEMENT_MODES.get(str(saved["texture_path"]).get_file(), "Ground")))
	runtime["movement_mode"] = movement_mode
	runtime["mount_type"] = int(saved.get("mount_type", _mount_type_from_movement_mode(movement_mode)))
	runtime["split_on_death"] = bool(saved.get("split_on_death", species_defaults.get("split_on_death", false)))
	runtime["split_count"] = int(saved.get("split_count", 0))
	runtime["melee_contact_reach"] = float(saved.get("melee_contact_reach", 10.0))
	runtime["current_traits"] = saved.get("current_traits", [])
	runtime["revive_available"] = bool(saved.get("revive_available", true))
	runtime["lifesteal_chance"] = lifesteal_values["chance"]
	runtime["lifesteal_heal_fraction"] = lifesteal_values["heal_fraction"]
	runtime["death_explosion_radius"] = explosion_radius
	runtime["death_explosion_damage"] = explosion_damage
	runtime["attack_effect"] = str(saved.get("attack_effect", species_defaults.get("attack_effect", "None")))
	runtime["attack_effect_chance"] = float(saved.get("attack_effect_chance", species_defaults.get("attack_effect_chance", 1.0)))
	runtime["is_resistant_crab"] = bool(saved.get("is_resistant_crab", species_defaults.get("is_resistant_crab", false)))
	runtime["immune_to_knockback"] = bool(saved.get("immune_to_knockback", species_defaults.get("immune_to_knockback", false)))
	runtime["chain_lightning"] = bool(saved.get("chain_lightning", species_defaults.get("chain_lightning", false)))
	runtime["chain_lightning_radius"] = float(saved.get("chain_lightning_radius", species_defaults.get("chain_lightning_radius", 72.0)))
	runtime["chain_lightning_damage_fraction"] = float(saved.get("chain_lightning_damage_fraction", species_defaults.get("chain_lightning_damage_fraction", 0.25)))
	runtime["wind_dash_enabled"] = bool(saved.get("wind_dash_enabled", species_defaults.get("wind_dash_enabled", false)))
	runtime["charge_style"] = str(saved.get("charge_style", "None"))
	runtime["charge_trigger_range"] = float(saved.get("charge_trigger_range", 140.0))
	runtime["charge_speed"] = float(saved.get("charge_speed", 800.0))
	runtime["city_charge_count"] = int(saved.get("city_charge_count", 0))
	runtime["city_charge_ready"] = bool(saved.get("city_charge_ready", false))
	runtime["dash_speed"] = float(saved.get("dash_speed", species_defaults.get("dash_speed", 900.0)))
	runtime["dash_duration"] = float(saved.get("dash_duration", species_defaults.get("dash_duration", 0.25)))
	return runtime


func _get_legacy_special_defaults(pet_name: String) -> Dictionary:
	return LEGACY_SPECIALS_BY_NAME.get(pet_name, {})


func _mount_type_from_movement_mode(mode: String) -> int:
	match mode:
		"Fly":
			return Monster.MountType.FLY
		"Swim":
			return Monster.MountType.SWIM
		_:
			return Monster.MountType.GROUND


func _migrate_lifesteal_values(saved: Dictionary) -> Dictionary:
	var chance: float = float(saved.get("lifesteal_chance", Monster.DEFAULT_LIFESTEAL_CHANCE))
	var heal_fraction: float = float(saved.get("lifesteal_heal_fraction", Monster.DEFAULT_LIFESTEAL_HEAL_FRACTION))
	if is_equal_approx(chance, 0.25) and is_equal_approx(heal_fraction, 0.25):
		chance = Monster.DEFAULT_LIFESTEAL_CHANCE
		heal_fraction = Monster.DEFAULT_LIFESTEAL_HEAL_FRACTION
	return {"chance": chance, "heal_fraction": heal_fraction}


func get_team_runtime() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in team:
		result.append(get_runtime_pet(index))
	return result


func get_mount_runtime_pet() -> Dictionary:
	if mount_pet_index < 0 or mount_pet_index >= collection.size():
		return {}
	return get_runtime_pet(mount_pet_index)


func _to_saved(pet_data: Dictionary) -> Dictionary:
	var texture: Texture2D = pet_data.get("texture")
	var sprite_scale: Vector2 = pet_data.get("sprite_scale", Vector2.ONE)
	var current_traits: Array[String] = []
	for trait_value: Variant in pet_data.get("current_traits", []):
		if trait_value is String and not current_traits.has(trait_value):
			current_traits.append(trait_value)
	return {
		"name": str(pet_data.get("name", "Pet")),
		"type": str(pet_data.get("type", pet_data.get("name", "Pet"))),
		"attack_style": str(pet_data.get("attack_style", "Melee")),
		"texture_path": texture.resource_path if texture != null else "",
		"sprite_scale": [sprite_scale.x, sprite_scale.y],
		"max_hp": int(pet_data.get("max_hp", 50)),
		"attack_damage": int(pet_data.get("attack_damage", 5)),
		"attack_interval": float(pet_data.get("attack_interval", 1.2)),
		"attack_range": float(pet_data.get("attack_range", 38.0)),
		"movement_mode": str(pet_data.get("movement_mode", "Ground")),
		"mount_type": int(pet_data.get("mount_type", _mount_type_from_movement_mode(str(pet_data.get("movement_mode", "Ground"))))),
		"split_on_death": bool(pet_data.get("split_on_death", false)),
		"split_count": int(pet_data.get("split_count", 0)),
		"melee_contact_reach": float(pet_data.get("melee_contact_reach", 10.0)),
		"current_traits": current_traits,
		"revive_available": bool(pet_data.get("revive_available", true)),
		"lifesteal_chance": float(pet_data.get("lifesteal_chance", Monster.DEFAULT_LIFESTEAL_CHANCE)),
		"lifesteal_heal_fraction": float(pet_data.get("lifesteal_heal_fraction", Monster.DEFAULT_LIFESTEAL_HEAL_FRACTION)),
		"death_explosion_radius": float(pet_data.get("death_explosion_radius", 128.0)),
		"death_explosion_damage": int(pet_data.get("death_explosion_damage", Monster.DEFAULT_DEATH_EXPLOSION_DAMAGE)),
		"attack_effect": str(pet_data.get("attack_effect", "None")),
		"attack_effect_chance": float(pet_data.get("attack_effect_chance", 1.0)),
		"is_resistant_crab": bool(pet_data.get("is_resistant_crab", false)),
		"immune_to_knockback": bool(pet_data.get("immune_to_knockback", false)),
		"chain_lightning": bool(pet_data.get("chain_lightning", false)),
		"chain_lightning_radius": float(pet_data.get("chain_lightning_radius", 72.0)),
		"chain_lightning_damage_fraction": float(pet_data.get("chain_lightning_damage_fraction", 0.25)),
		"wind_dash_enabled": bool(pet_data.get("wind_dash_enabled", false)),
		"charge_style": str(pet_data.get("charge_style", "None")),
		"charge_trigger_range": float(pet_data.get("charge_trigger_range", 140.0)),
		"charge_speed": float(pet_data.get("charge_speed", 800.0)),
		"city_charge_count": int(pet_data.get("city_charge_count", 0)),
		"city_charge_ready": bool(pet_data.get("city_charge_ready", false)),
		"dash_speed": float(pet_data.get("dash_speed", 900.0)),
		"dash_duration": float(pet_data.get("dash_duration", 0.25)),
	}


func _is_valid_entry(entry: Dictionary) -> bool:
	for key: String in ["name", "attack_style", "texture_path", "sprite_scale", "max_hp", "attack_damage", "attack_interval", "attack_range"]:
		if not entry.has(key):
			return false
	return entry["texture_path"] is String and str(entry["texture_path"]).begins_with("res://") \
		and entry["sprite_scale"] is Array and entry["sprite_scale"].size() == 2
