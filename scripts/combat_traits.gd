extends RefCounted


static func damage(base_damage: float, maximum_hp: int, traits: Array[String]) -> int:
	var value: float = base_damage
	if traits.has("StoneBody"):
		value += maximum_hp * 0.1
	if traits.has("DoubleDamage"):
		value *= 2.0
	if traits.has("Berserk"):
		value *= 2.5
	return roundi(value)


static func movement_multiplier(traits: Array[String]) -> float:
	var multiplier: float = 1.5 if traits.has("FastMovement") else 1.0
	if traits.has("SlowMovement"):
		multiplier *= 0.5
	return multiplier


static func attack_speed_multiplier(traits: Array[String]) -> float:
	var multiplier: float = 0.75 if traits.has("Lazy") else 1.0
	if traits.has("StoneBody"):
		multiplier *= 0.5
	return multiplier


static func starting_hp(maximum_hp: int, traits: Array[String]) -> int:
	return maxi(ceili(maximum_hp * 0.5), 1) if traits.has("HalfHealth") else maximum_hp


static func is_berserk(actor: Node) -> bool:
	return (actor.get("current_traits") as Array).has("Berserk") and int(actor.get("current_hp")) * 4 < int(actor.get("max_hp"))


static func can_target(actor: Node, target: Node) -> bool:
	if not is_instance_valid(target) or target == actor or target.is_queued_for_deletion() or not target.has_method("take_damage"):
		return false
	if target.has_method("is_alive") and not target.call("is_alive"):
		return false
	if is_berserk(actor):
		return target.is_in_group("player") or target.is_in_group("pets") or target.is_in_group("monsters") or target.is_in_group("TeamPlayer") or target.is_in_group("TeamEnemy")
	var team: String = str(actor.get("arena_team"))
	if not team.is_empty():
		return target.is_in_group("TeamEnemy" if team == "TeamPlayer" else "TeamPlayer")
	return target.is_in_group("monsters") if actor.is_in_group("pets") else target.is_in_group("player") or target.is_in_group("pets")


static func targets(actor: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for group_name: String in ["player", "pets", "monsters", "TeamPlayer", "TeamEnemy"]:
		for node: Node in actor.get_tree().get_nodes_in_group(group_name):
			var target: Node2D = node as Node2D
			if target != null and can_target(actor, target) and not result.has(target):
				result.append(target)
	return result


static func farthest_target(actor: Node2D) -> Node2D:
	var farthest: Node2D
	var greatest_distance_squared: float = -1.0
	for target: Node2D in targets(actor):
		var distance_squared: float = actor.global_position.distance_squared_to(target.global_position)
		if distance_squared > greatest_distance_squared:
			greatest_distance_squared = distance_squared
			farthest = target
	return farthest
