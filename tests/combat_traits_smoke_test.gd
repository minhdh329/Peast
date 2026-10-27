extends SceneTree

const SAVE_PATH := "user://combat_traits_smoke_test.json"


class FixedMonster extends Monster:
	func _randomize_traits() -> void:
		pass


class Target extends CharacterBody2D:
	var hp: int = 1000

	func take_damage(amount: int, source: Vector2, effect: String = "", chance: float = 1.0, over_time: bool = false) -> void:
		hp -= amount

	func is_alive() -> bool:
		return hp > 0


func _initialize() -> void:
	call_deferred("_run")


func _monster(world: Node2D, traits: Array[String]) -> Monster:
	var monster: Monster = (load("res://scenes/monster.tscn") as PackedScene).instantiate() as Monster
	monster.set_script(FixedMonster)
	monster.current_traits = traits.duplicate()
	monster.max_hp = 100
	monster.attack_damage = 10
	monster.attack_interval = 1.2
	monster.patrol_speed = 40.0
	monster.movement_speed = 90.0
	world.add_child(monster)
	monster.set_physics_process(false)
	return monster


func _pet(world: Node2D, data: Dictionary) -> Pet:
	var pet: Pet = (load("res://scenes/pet.tscn") as PackedScene).instantiate() as Pet
	world.add_child(pet)
	pet.set_physics_process(false)
	pet.apply_pet_data(data)
	pet.attack_timer.stop()
	return pet


func _target(world: Node2D, group: String, position: Vector2) -> Target:
	var target: Target = Target.new()
	world.add_child(target)
	target.add_to_group(group)
	target.position = position
	return target


func _run() -> void:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	seed(20261021)
	var seen_traits: Array[String] = []
	for trial: int in range(128):
		var probe: Monster = (load("res://scenes/monster.tscn") as PackedScene).instantiate() as Monster
		probe._randomize_traits()
		for trait_name: String in probe.current_traits:
			if not seen_traits.has(trait_name):
				seen_traits.append(trait_name)
		probe.free()
	for trait_name: String in Monster.AVAILABLE_TRAITS:
		if not seen_traits.has(trait_name):
			_fail("All traits must be reachable through random generation.")
			return
	var traits: Array[String] = ["HalfHealth", "SlowMovement", "FastMovement", "Lazy", "StoneBody", "DoubleDamage", "DoubleHP", "Berserk"]
	for trait_name: String in traits:
		if not Monster.AVAILABLE_TRAITS.has(trait_name):
			_fail("New traits must be available for random Monster generation.")
			return
	var monster: Monster = _monster(world, traits)
	if monster.max_hp != 200 or monster.current_hp != 100 or monster.attack_damage != 150:
		_fail("HalfHealth must preserve max HP; StoneBody + DoubleDamage + Berserk should yield (10 + 20) * 2 * 2.5 damage.")
		return
	if not is_equal_approx(monster.attack_interval, 3.2) or not is_equal_approx(monster.movement_speed, 67.5) or not is_equal_approx(monster.patrol_speed, 30.0):
		_fail("Lazy/StoneBody attack speed and FastMovement/SlowMovement must combine multiplicatively.")
		return
	monster.restore_lifesteal(1000, 1.0)
	if monster.current_hp != 200:
		_fail("HalfHealth must allow healing all the way to maximum HP.")
		return
	var data: Dictionary = monster.get_pet_data()
	var pet: Pet = _pet(world, data)
	if pet.max_hp != 200 or pet.current_hp != 100 or pet.attack_damage != 150 or not is_equal_approx(pet.attack_timer.wait_time, 3.2):
		_fail("Captured pets must retain adjusted stats without applying damage or attack speed twice.")
		return
	if not is_equal_approx(pet.follow_speed, 180.0) or not is_equal_approx(pet.melee_move_speed, 135.0):
		_fail("Captured pets must combine movement traits.")
		return
	pet.restore_lifesteal(1000, 1.0)
	if pet.current_hp != 200:
		_fail("HalfHealth pets must be able to heal to full.")
		return
	data["current_hp"] = 170
	pet.apply_pet_data(data)
	pet.attack_timer.stop()
	if pet.current_hp != 170 or not is_equal_approx(pet.follow_speed, 180.0):
		_fail("Recalling/resummoning must preserve current HP and never compound movement modifiers.")
		return
	var details: GDScript = preload("res://scripts/pet_details.gd")
	for trait_name: String in ["HalfHealth", "SlowMovement", "Lazy", "StoneBody", "Berserk"]:
		if details.get_trait_description(trait_name, data).is_empty():
			_fail("Every new trait needs a description.")
			return
	world.queue_free()
	await process_frame
	if not _test_storage(data):
		return
	for as_pet: bool in [false, true]:
		if not await _test_movement_and_split(as_pet):
			return
		for in_arena: bool in [false, true]:
			if not await _test_berserk(as_pet, in_arena):
				return
	print("Combat traits smoke test passed.")
	quit(0)


func _test_storage(data: Dictionary) -> bool:
	var storage: Node = (load("res://scripts/pet_storage.gd") as GDScript).new()
	storage.set("save_path", SAVE_PATH)
	storage.call("add_captured_pet", data)
	storage.call("load_data")
	var loaded: Dictionary = storage.call("get_runtime_pet", 0)
	if loaded["current_traits"] != data["current_traits"] or loaded["attack_damage"] != 150 or not is_equal_approx(loaded["attack_interval"], 3.2):
		_fail("New traits and adjusted stats must survive capture/save/reload.")
		storage.free()
		return false
	for trait_name: String in ["HalfHealth", "SlowMovement", "Lazy", "Berserk", "StoneBody"]:
		var parent: Dictionary = data.duplicate(true)
		parent["name"] = "Slime rừng"
		parent["type"] = "Slime rừng"
		parent["current_traits"] = [trait_name]
		parent["attack_interval"] = 99.0
		var saved: Dictionary = storage.call("_to_saved", parent)
		storage.set("collection", [saved.duplicate(true), saved.duplicate(true)] as Array[Dictionary])
		var fused: Dictionary = storage.call("CombinePets", 0, 1)
		var hp: int = roundi(60 * 1.01)
		var expected_damage: int = roundi((5 * 1.01 + (hp * 0.1 if trait_name == "StoneBody" else 0.0)) * (2.5 if trait_name == "Berserk" else 1.0))
		var base: Dictionary = storage.call("_get_species_base_stats", "Slime rừng")
		var expected_interval: float = float(base["attack_interval"]) / (0.75 if trait_name == "Lazy" else 0.5 if trait_name == "StoneBody" else 1.0)
		if fused["current_traits"] != [trait_name] or fused["attack_damage"] != expected_damage or not is_equal_approx(fused["attack_interval"], expected_interval):
			_fail("Fusion must inherit %s and recalculate damage/interval from the species, not the parent." % trait_name)
			storage.free()
			return false
	storage.free()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	return true


func _test_movement_and_split(as_pet: bool) -> bool:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	var monster: Monster = _monster(world, ["SlowMovement", "HalfHealth", "Lazy", "StoneBody", "Berserk"])
	var actor: Node2D = monster
	if as_pet:
		actor = _pet(world, monster.get_pet_data())
		monster.free()
	actor.call("set_arena_team", "TeamPlayer")
	var target: Target = _target(world, "TeamEnemy", Vector2(1000.0, 0.0))
	actor.set("charge_style", "Car")
	var charge: Node = actor.get("city_charge")
	charge.call("start", target)
	charge.call("step", 1.0 / 60.0, false)
	if not is_equal_approx(absf((actor as CharacterBody2D).velocity.x), 400.0):
		return _fail("SlowMovement must halve city charge speed.")
	charge.call("finish")
	actor.call("_start_wind_dash")
	await process_frame
	actor.call("_process_wind_dash", 1.0 / 60.0)
	if not is_equal_approx(absf((actor as CharacterBody2D).velocity.x), 450.0):
		return _fail("SlowMovement must halve wind dash speed.")
	actor.call("_finish_wind_dash")
	actor.call("_split_into_slimes")
	var count: int = 0
	for child: Node in world.get_children():
		if child == actor or not (child is Pet or child is Monster):
			continue
		child.set_physics_process(false)
		if child is Pet:
			child.attack_timer.stop()
		var interval: float = (child as Pet).attack_timer.wait_time if child is Pet else float(child.get("attack_interval"))
		if int(child.get("max_hp")) != 50 or int(child.get("current_hp")) != 25 or int(child.get("attack_damage")) != 25 or not is_equal_approx(interval, 3.2):
			return _fail("Split offspring must inherit adjusted damage/attack interval once, and start at half HP.")
		count += 1
	if count != 2:
		return _fail("Trait-bearing slimes must still create two offspring.")
	world.queue_free()
	await process_frame
	return true


func _test_berserk(as_pet: bool, in_arena: bool) -> bool:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	var monster: Monster = _monster(world, ["Berserk"])
	var actor: Node2D = monster
	if as_pet:
		actor = _pet(world, monster.get_pet_data())
		monster.free()
	var ally: Target = _target(world, "TeamPlayer" if in_arena else "player" if as_pet else "monsters", Vector2(20.0, 0.0))
	var enemy: Target = _target(world, "TeamEnemy" if in_arena else "monsters" if as_pet else "player", Vector2(100.0, 0.0))
	if as_pet and not in_arena:
		(actor as Pet).set_follow_target(ally)
	if in_arena:
		actor.call("set_arena_team", "TeamPlayer")
	actor.set("current_hp", 25)
	if (actor.call("get_combat_targets") as Array).has(ally):
		return _fail("At exactly 25% HP, Berserk must not attack allies.")
	actor.set("current_hp", 24)
	var targets: Array = actor.call("get_combat_targets")
	if not targets.has(ally) or not targets.has(enemy) or targets.has(actor):
		return _fail("Below 25% HP, Berserk must target both teams but never itself.")
	if as_pet:
		actor.call("_refresh_nearest_target")
		if actor.get("_target_monster") != ally:
			return _fail("Berserk pets must choose the nearest target, including their player.")
		actor.call("_on_attack_timer_timeout")
	else:
		if actor.call("_find_closest_target") != ally:
			return _fail("Berserk Monsters must choose their nearest ally over a distant opponent.")
		actor.call("_attack_target", ally)
	if ally.hp != 975 or enemy.hp != 1000:
		return _fail("Berserk melee must deal x2.5 damage to the nearest ally.")
	actor.set("attack_style" if not as_pet else "_attack_style", "Ranged")
	if as_pet:
		actor.set("fireball_scene", load("res://scenes/fireball.tscn"))
		actor.call("_on_attack_timer_timeout")
	else:
		actor.call("_attack_target", ally)
	var shot: FireballProjectile
	for child: Node in world.get_children():
		if child is FireballProjectile:
			shot = child as FireballProjectile
	if shot == null or shot._can_hit(actor) or not shot._can_hit(ally) or not shot._can_hit(enemy):
		return _fail("Berserk projectiles must hit either team, never their shooter.")
	shot.global_position = ally.global_position
	shot._physics_process(0.0)
	if ally.hp != 950:
		return _fail("Berserk projectiles must actually damage allies.")
	actor.set("chain_lightning_radius", 200.0)
	actor.call("_chain_lightning", enemy)
	if ally.hp != 944 or int(actor.get("current_hp")) != 24:
		return _fail("Berserk chain lightning must hit allies without hitting the caster.")
	actor.set("charge_style", "Car")
	var charge: Node = actor.get("city_charge")
	charge.call("start", enemy)
	charge.call("_check_hits", Vector2.ZERO, enemy.position)
	charge.call("finish")
	if ally.hp != 919:
		return _fail("Berserk city charges must hit allies.")
	actor.call("_start_wind_dash")
	actor.call("_apply_wind_dash_hit", ally)
	if ally.hp != 869:
		return _fail("Berserk wind dash must hit allies with its own dash damage.")
	actor.set("current_hp", 26)
	if (actor.call("get_combat_targets") as Array).has(ally):
		return _fail("Healing above the threshold must restore normal team targeting.")
	var safe_shot: FireballProjectile = (load("res://scenes/fireball.tscn") as PackedScene).instantiate()
	world.add_child(safe_shot)
	safe_shot.arena_team = "TeamPlayer" if in_arena else ""
	safe_shot.hostile = not as_pet
	if safe_shot._can_hit(ally) or not safe_shot._can_hit(enemy):
		return _fail("Normal projectiles must retain team protection.")
	world.queue_free()
	await process_frame
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
