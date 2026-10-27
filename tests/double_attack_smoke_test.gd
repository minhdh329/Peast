extends SceneTree


class Target extends Node2D:
	var hp: int = 1000
	var hits: Array[int] = []
	var hit_times: Array[int] = []
	var effects: Array[String] = []

	func take_damage(amount: int, source: Vector2, effect: String = "None", chance: float = 1.0, over_time: bool = false) -> void:
		hp -= amount
		hits.append(amount)
		hit_times.append(Engine.get_physics_frames())
		effects.append(effect)

	func is_alive() -> bool:
		return hp > 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for as_pet: bool in [false, true]:
		if not await _test_melee(as_pet):
			return
		if not await _test_ranged(as_pet):
			return
		for style: String in ["Cat", "Car"]:
			if not await _test_charge(as_pet, style):
				return
		for reason: String in ["dead", "freed", "reviving", "stunned", "target_dead", "target_freed", "inactive"]:
			if not await _test_cancellation(as_pet, reason):
				return
		if not await _test_pause(as_pet):
			return
		if not await _test_bird(as_pet):
			return
		for in_arena: bool in [false, true]:
			if not await _test_farthest_dash(as_pet, in_arena):
				return
	print("DoubleAttack smoke test passed.")
	quit(0)


func _world() -> Node2D:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	return world


func _target(world: Node2D, position: Vector2 = Vector2.ZERO) -> Target:
	var target: Target = Target.new()
	target.add_to_group("TeamEnemy")
	world.add_child(target)
	target.position = position
	return target


func _actor(world: Node2D, as_pet: bool, ranged: bool = false) -> Node2D:
	var actor: Node2D
	if as_pet:
		var pet: Pet = (load("res://scenes/pet.tscn") as PackedScene).instantiate() as Pet
		world.add_child(pet)
		pet.attack_timer.stop()
		pet.set_attack_style("Ranged" if ranged else "Melee")
		pet.fireball_scene = load("res://scenes/fireball.tscn")
		actor = pet
	else:
		var monster: Monster = (load("res://scenes/monster.tscn") as PackedScene).instantiate() as Monster
		world.add_child(monster)
		monster.attack_style = "Ranged" if ranged else "Melee"
		actor = monster
	actor.set_physics_process(false)
	actor.call("set_arena_team", "TeamPlayer")
	actor.set("current_traits", [Monster.TRAIT_DOUBLE_ATTACK, Monster.TRAIT_LIFESTEAL] as Array[String])
	actor.set("max_hp", 100)
	actor.set("current_hp", 50)
	actor.set("attack_damage", 10)
	actor.set("attack_effect", "Poison")
	return actor


func _attack(actor: Node2D, target: Target) -> void:
	if actor is Pet:
		actor.call("_on_attack_timer_timeout")
	else:
		actor.call("_attack_target", target)


func _test_melee(as_pet: bool) -> bool:
	var world: Node2D = _world()
	var target: Target = _target(world)
	var secondary: Target = _target(world, Vector2(30.0, 0.0))
	var actor: Node2D = _actor(world, as_pet)
	actor.set("chain_lightning", true)
	actor.set("chain_lightning_damage_fraction", 0.3)
	actor.set("charge_style", "Car")
	var charge: Node = actor.get("city_charge") as Node
	_attack(actor, target)
	_attack(actor, target)
	if target.hits != [10] or secondary.hits != [3] or int(charge.get("trigger_count")) != 1 or int(actor.get("current_hp")) != 52:
		return _fail("The first hit must deal base damage and trigger lightning, lifesteal and charge once; overlapping cycles must be blocked.")
	await create_timer(0.05, false, true).timeout
	if target.hits.size() != 1:
		return _fail("The second hit must not occur immediately.")
	await create_timer(0.2, false, true).timeout
	if target.hits != [10, 10] or target.effects != ["Poison", "Poison"] or secondary.hits != [3, 3]:
		return _fail("Both melee hits must independently apply base damage, attack effects and chain lightning.")
	if target.hit_times[1] - target.hit_times[0] < ceili(0.15 * Engine.physics_ticks_per_second):
		return _fail("DoubleAttack hits must be at least 0.15 seconds apart.")
	if int(charge.get("trigger_count")) != 2 or int(actor.get("current_hp")) != 54:
		return _fail("Each hit must independently count for charge and heal through lifesteal.")
	actor.set("current_traits", [] as Array[String])
	_attack(actor, target)
	await create_timer(0.25, false, true).timeout
	if target.hits.size() != 3:
		return _fail("Actors without DoubleAttack must still attack exactly once.")
	actor.set("charge_style", "None")
	actor.set("attack_damage", 20)
	actor.set("current_traits", [Monster.TRAIT_DOUBLE_DAMAGE] as Array[String])
	_attack(actor, target)
	await create_timer(0.25, false, true).timeout
	if target.hits != [10, 10, 10, 20]:
		return _fail("DoubleDamage must remain a single hit with increased base damage.")
	actor.set("current_traits", [Monster.TRAIT_DOUBLE_DAMAGE, Monster.TRAIT_DOUBLE_ATTACK] as Array[String])
	_attack(actor, target)
	await create_timer(0.25, false, true).timeout
	if target.hits != [10, 10, 10, 20, 20, 20]:
		return _fail("DoubleAttack and DoubleDamage must combine as two increased-damage hits.")
	world.queue_free()
	await process_frame
	return true


func _projectiles(world: Node2D) -> Array[FireballProjectile]:
	var shots: Array[FireballProjectile] = []
	for child: Node in world.get_children():
		if child is FireballProjectile and not child.is_queued_for_deletion():
			child.set_physics_process(false)
			shots.append(child as FireballProjectile)
	return shots


func _test_ranged(as_pet: bool) -> bool:
	var world: Node2D = _world()
	var target: Target = _target(world, Vector2(100.0, 0.0))
	var actor: Node2D = _actor(world, as_pet, true)
	actor.set("charge_style", "Car")
	_attack(actor, target)
	if _projectiles(world).size() != 1:
		return _fail("Ranged DoubleAttack must initially fire only one projectile.")
	await create_timer(0.05, false, true).timeout
	if _projectiles(world).size() != 1:
		return _fail("The second projectile must not fire before the delay.")
	await create_timer(0.12, false, true).timeout
	var shots: Array[FireballProjectile] = _projectiles(world)
	if shots.size() != 2:
		return _fail("Ranged DoubleAttack must fire a second independent projectile.")
	for shot: FireballProjectile in shots:
		if shot.damage != 10 or shot.effect_type != "Poison":
			return _fail("Each projectile must retain base damage and its own attack effect.")
		shot.global_position = target.global_position
		shot._check_hostile_hit()
	if target.hits != [10, 10] or target.effects != ["Poison", "Poison"] or int(actor.get("current_hp")) != 54:
		return _fail("Both projectiles must hit and apply lifesteal independently.")
	if int((actor.get("city_charge") as Node).get("trigger_count")) != 2:
		return _fail("Each ranged shot must count separately for charge.")
	world.queue_free()
	await process_frame
	return true


func _test_cancellation(as_pet: bool, reason: String) -> bool:
	var world: Node2D = _world()
	var target: Target = _target(world)
	var actor: Node2D = _actor(world, as_pet)
	_attack(actor, target)
	match reason:
		"dead":
			actor.set("current_hp", 0)
		"freed":
			actor.queue_free()
		"reviving":
			actor.set("_is_reviving", true)
		"stunned":
			actor.get_node("StatusEffects").call("apply_effect", "Stun", Vector2.ZERO)
		"target_dead":
			target.hp = 0
		"target_freed":
			target.queue_free()
		"inactive":
			actor.call("set_arena_active", false)
	await create_timer(0.25, false, true).timeout
	if is_instance_valid(actor) and bool(actor.get("_attack_sequence_active")):
		return _fail("Cancelled sequences must release the attack lock: %s." % reason)
	if is_instance_valid(target) and target.hits.size() != 1:
		return _fail("The follow-up must be cancelled when %s." % reason)
	world.queue_free()
	await process_frame
	return true


func _test_charge(as_pet: bool, style: String) -> bool:
	var world: Node2D = _world()
	var target: Target = _target(world, Vector2(20.0, 0.0))
	var actor: Node2D = _actor(world, as_pet)
	actor.set("charge_style", style)
	var charge: Node = actor.get("city_charge") as Node
	var threshold: int = 7 if style == "Cat" else 5
	charge.set("trigger_count", threshold - 2)
	_attack(actor, target)
	if bool(charge.get("active")) or int(charge.get("trigger_count")) != threshold - 1:
		return _fail("The first DoubleAttack hit must advance the %s counter once." % style)
	await create_timer(0.25, false, true).timeout
	if not bool(charge.get("active")) or target.hits != [10, 10]:
		return _fail("The second DoubleAttack hit must trigger %s charge at its threshold." % style)
	world.queue_free()
	await process_frame
	return true


func _test_pause(as_pet: bool) -> bool:
	var world: Node2D = _world()
	var target: Target = _target(world)
	var actor: Node2D = _actor(world, as_pet)
	_attack(actor, target)
	paused = true
	await create_timer(0.25).timeout
	if target.hits != [10]:
		paused = false
		return _fail("The follow-up must not execute while gameplay is paused.")
	paused = false
	await create_timer(0.25, false, true).timeout
	if target.hits != [10, 10]:
		return _fail("The follow-up should resume after gameplay is unpaused.")
	world.queue_free()
	await process_frame
	return true


func _test_bird(as_pet: bool) -> bool:
	var world: Node2D = _world()
	var target: Target = _target(world, Vector2(100.0, 0.0))
	var actor: Node2D = _actor(world, as_pet, true)
	actor.set("wind_dash_enabled", true)
	_attack(actor, target)
	_projectiles(world)
	if int(actor.get("attack_count")) != 1:
		return _fail("A wind bird must count only the first shot before the delay.")
	await create_timer(0.17, false, true).timeout
	_projectiles(world)
	if int(actor.get("attack_count")) != 2 or bool(actor.get("is_dashing")):
		return _fail("DoubleAttack must count as two separate shots toward the wind dash.")
	_attack(actor, target)
	if not bool(actor.get("is_dashing")):
		return _fail("The next bird attack must become a wind dash.")
	actor.call("_apply_wind_dash_hit", target)
	if target.hits != [20] or int(actor.get("attack_count")) != 0:
		return _fail("Wind dash must keep its own double-damage mechanic and reset its counter.")
	await create_timer(0.2, false, true).timeout
	if _projectiles(world).size() != 2:
		return _fail("Starting a dash must not leave an extra DoubleAttack shot pending.")
	world.queue_free()
	await process_frame
	return true


func _test_farthest_dash(as_pet: bool, in_arena: bool) -> bool:
	var world: Node2D = _world()
	var near: Target = _target(world, Vector2(80.0, 0.0))
	var far: Target = _target(world, Vector2(-600.0, 200.0))
	var dead: Target = _target(world, Vector2(1000.0, 0.0))
	dead.hp = 0
	var removed: Target = _target(world, Vector2(1200.0, 0.0))
	removed.queue_free()
	var ally: Target = _target(world, Vector2(1500.0, 0.0))
	ally.remove_from_group("TeamEnemy")
	ally.add_to_group("TeamPlayer")
	var actor: Node2D = _actor(world, as_pet, true)
	actor.set("current_traits", [] as Array[String])
	actor.set("wind_dash_enabled", true)
	if not in_arena:
		actor.call("set_arena_team", "")
		for target: Target in [near, far, dead, removed]:
			target.remove_from_group("TeamEnemy")
			target.add_to_group("monsters" if as_pet else "player")
		ally.remove_from_group("TeamPlayer")
		ally.add_to_group("pets" if as_pet else "monsters")
	_attack(actor, near)
	_projectiles(world)
	_attack(actor, near)
	_projectiles(world)
	if int(actor.get("attack_count")) != 2 or bool(actor.get("is_dashing")):
		return _fail("Farthest targeting must preserve the two-shot dash trigger.")
	far.position = Vector2(-700.0, 300.0)
	_attack(actor, near)
	var expected_direction: Vector2 = actor.global_position.direction_to(far.global_position)
	if not bool(actor.get("is_dashing")) or not (actor.get("_dash_direction") as Vector2).is_equal_approx(expected_direction):
		return _fail("Wind dash must select the farthest living enemy at activation, beyond shooting range, ignoring allies and removed/dead targets.")
	actor.call("_finish_wind_dash")
	far.hp = 0
	actor.call("_start_wind_dash")
	if not (actor.get("_dash_direction") as Vector2).is_equal_approx(actor.global_position.direction_to(near.global_position)):
		return _fail("A dead farthest enemy must be replaced by the next living target.")
	actor.call("_finish_wind_dash")
	actor.set("current_traits", [Monster.TRAIT_BERSERK] as Array[String])
	actor.set("current_hp", 24)
	actor.call("_start_wind_dash")
	if not (actor.get("_dash_direction") as Vector2).is_equal_approx(actor.global_position.direction_to(ally.global_position)):
		return _fail("Berserk wind dash must preserve friendly-fire targeting and select the farthest eligible target.")
	actor.call("_finish_wind_dash")
	actor.set("current_traits", [] as Array[String])
	near.hp = 0
	actor.call("_start_wind_dash")
	if bool(actor.get("is_dashing")):
		return _fail("Wind dash must not start when no living enemy remains.")
	world.queue_free()
	await process_frame
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
