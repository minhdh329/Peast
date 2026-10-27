extends RefCounted


static func build_tooltip(pet: Dictionary) -> String:
	var details: PackedStringArray = [
		str(pet.get("name", "Pet")),
		"Kiểu tấn công: %s" % pet.get("attack_style", "Melee"),
		"HP tối đa: %d" % int(pet.get("max_hp", 0)),
		"Sát thương: %d" % int(pet.get("attack_damage", 0)),
		"Số lần dung hợp: %d" % int(pet.get("fusion_count", 0)),
		"Giới hạn dung hợp: %d lần" % PetStorage.MAX_FUSION_COUNT,
		"Thưởng dung hợp: +%d%% HP và sát thương cơ bản của loài" % int(pet.get("fusion_count", 0)),
		"Thời gian giữa đòn: %.2f giây" % float(pet.get("attack_interval", 0.0)),
		"Tầm đánh: %.0f px" % float(pet.get("attack_range", 0.0)),
		"Chế độ di chuyển: %s" % pet.get("movement_mode", "Ground"),
		"Tầm cận chiến: %.0f px" % float(pet.get("melee_contact_reach", 0.0)),
		"Đặc tính:",
	]
	if bool(pet.get("wind_dash_enabled", false)):
		details.insert(details.size() - 1, "Lướt gió: sau 2 phát bắn, lao về mục tiêu còn sống xa nhất; gây sát thương x2 khi va chạm.")
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
			return "Mỗi lượt tấn công 2 lần cách nhau %.2f giây; mỗi đòn tính nội tại riêng. Đòn sau bị hủy nếu người đánh chết, bị choáng hoặc mục tiêu chết." % Monster.DOUBLE_ATTACK_DELAY
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
		"HalfHealth":
			return "Nửa máu: vào trận với 50% HP, vẫn có thể hồi tới HP tối đa."
		"SlowMovement":
			return "Chậm chạp: tốc độ di chuyển còn 50%."
		"Lazy":
			return "Lười: tốc độ đánh còn 75% (thời gian giữa đòn chia cho 0,75)."
		"Berserk":
			return "Điên loạn: sát thương x2,5. Dưới 25% HP, đánh mục tiêu gần nhất kể cả đồng minh và người chơi, trừ chính mình."
		"StoneBody":
			return "Cứng như đá: cộng sát thương bằng 10% HP tối đa trước các hệ số sát thương; tốc độ đánh còn 50%."
		_:
			return ""