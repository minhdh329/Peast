extends RefCounted


static func build_tooltip(pet: Dictionary) -> String:
	var details: PackedStringArray = [
		str(pet.get("name", "Pet")),
		"Kiểu tấn công: %s" % pet.get("attack_style", "Melee"),
		"HP tối đa: %d" % int(pet.get("max_hp", 0)),
		"Sát thương: %d" % int(pet.get("attack_damage", 0)),
		"Thời gian giữa đòn: %.2f giây" % float(pet.get("attack_interval", 0.0)),
		"Tầm đánh: %.0f px" % float(pet.get("attack_range", 0.0)),
		"Chế độ di chuyển: %s" % pet.get("movement_mode", "Ground"),
		"Tầm cận chiến: %.0f px" % float(pet.get("melee_contact_reach", 0.0)),
		"Đặc tính:",
	]
	var traits: Array = pet.get("current_traits", [])
	if traits.is_empty():
		details.append("- Không có")
	else:
		for trait_value: Variant in traits:
			var trait_name: String = str(trait_value)
			details.append("- %s: %s" % [trait_name, get_trait_description(trait_name, pet)])
	return "\n".join(details)


static func get_trait_description(trait_name: String, pet: Dictionary) -> String:
	match trait_name:
		"DoubleAttack":
			return "Mỗi lượt đánh gây 2 đòn."
		"FastMovement":
			return "Tốc độ di chuyển tăng 50%."
		"ExplodeOnDeath":
			return "Khi gục, nổ gây %d sát thương trong bán kính %.0f px." % [int(pet.get("death_explosion_damage", Monster.DEFAULT_DEATH_EXPLOSION_DAMAGE)), float(pet.get("death_explosion_radius", 128.0))]
		"Revive":
			return "Hồi sinh 1 lần với 30%% HP (%s)." % ("còn sẵn" if bool(pet.get("revive_available", true)) else "đã dùng")
		"Lifesteal":
			return "%.0f%% cơ hội hồi %.0f%% sát thương gây ra." % [float(pet.get("lifesteal_chance", 1.0)) * 100.0, float(pet.get("lifesteal_heal_fraction", 0.15)) * 100.0]
		"DoubleHP":
			return "Máu tối đa được nhân đôi."
		"DoubleDamage":
			return "Sát thương được nhân đôi."
		_:
			return ""