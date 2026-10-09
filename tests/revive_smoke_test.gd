extends SceneTree


class DummyTarget extends Node2D:
	var hp: int = 100

	func take_damage(amount: int, source: Vector2, effect_type: String = "", effect_chance: float = 1.0, is_over_time: bool = false) -> void:
		hp -= amount

	func is_alive() -> bool:
		return hp > 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var target: DummyTarget = DummyTarget.new()
	target.add_to_group("player")
	target.add_to_group("TeamPlayer")
	root.add_child(target)

	var monster_scene: PackedScene = load("res://scenes/monster.tscn")
	var monster: Monster = monster_scene.instantiate() as Monster
	root.add_child(monster)
	monster.set_arena_team("TeamEnemy")
	monster.current_traits = [Monster.TRAIT_REVIVE, Monster.TRAIT_EXPLODE_ON_DEATH]
	monster.max_hp = 100
	monster.current_hp = 10
	monster.take_damage(10, target.global_position)
	if not monster._is_reviving or monster.current_hp != 0 or monster.is_alive() or target.hp != 20:
		_fail("Monster should remain dead/unavailable while Revive is charging.")
		return
	var hunter: Monster = monster_scene.instantiate() as Monster
	root.add_child(hunter)
	hunter.set_arena_team("TeamPlayer")
	hunter.set_physics_process(false)
	if hunter._find_closest_target() != null or not _revive_visual_visible(monster):
		_fail("An enemy should not target a reviving Monster, which should show the revive animation.")
		return
	monster._attack_target(target)
	monster.take_damage(50, target.global_position)
	if target.hp != 20 or monster.current_hp != 0:
		_fail("Monster should neither attack nor receive damage while reviving.")
		return
	await create_timer(0.8).timeout
	if not monster._is_reviving or monster.current_hp != 0:
		_fail("Monster should not revive before 1.5 seconds.")
		return
	await create_timer(0.8).timeout
	if monster._is_reviving or monster.current_hp != 30 or not monster.is_alive() or _revive_visual_visible(monster):
		_fail("Monster should revive at 30% HP and hide its animation after 1.5 seconds.")
		return
	if hunter._find_closest_target() != monster:
		_fail("A revived Monster should be targetable again.")
		return
	monster.take_damage(30, target.global_position)
	await process_frame
	if is_instance_valid(monster) and not monster.is_queued_for_deletion():
		_fail("Revive should only activate once.")
		return
	hunter.queue_free()

	var pet_scene: PackedScene = load("res://scenes/pet.tscn")
	var pet: Pet = pet_scene.instantiate() as Pet
	root.add_child(pet)
	pet.set_arena_team("TeamPlayer")
	pet.set_physics_process(false)
	var enemy: Monster = monster_scene.instantiate() as Monster
	root.add_child(enemy)
	enemy.set_arena_team("TeamEnemy")
	enemy.set_physics_process(false)
	enemy.max_hp = 1000
	enemy.current_hp = 1000
	enemy.global_position = Vector2(20.0, 0.0)
	pet.current_traits = [Monster.TRAIT_REVIVE, Monster.TRAIT_EXPLODE_ON_DEATH]
	pet.max_hp = 100
	pet.current_hp = 10
	pet.take_damage(10, target.global_position)
	if not pet._is_reviving or pet.current_hp != 0 or pet.is_alive() or not _revive_visual_visible(pet):
		_fail("Pet should enter its animated revive state at 0 HP.")
		return
	if enemy.current_hp != 920:
		_fail("Pet ExplodeOnDeath should trigger when Revive begins.")
		return
	pet._refresh_nearest_target()
	var enemy_hp_before: int = enemy.current_hp
	pet._on_attack_timer_timeout()
	if enemy.current_hp != enemy_hp_before:
		_fail("Pet should not attack while reviving.")
		return
	pet.take_damage(50, target.global_position)
	if pet.current_hp != 0:
		_fail("Pet should be invulnerable while reviving.")
		return
	await create_timer(1.6).timeout
	if pet._is_reviving or pet.current_hp != 30 or not pet.is_alive() or _revive_visual_visible(pet):
		_fail("Pet should revive at 30% HP after 1.5 seconds.")
		return

	pet.queue_free()
	enemy.queue_free()
	target.queue_free()
	print("Revive smoke test passed.")
	quit(0)


func _revive_visual_visible(actor: Node) -> bool:
	var revive_effect: Node2D = actor.get_node_or_null("ReviveEffect") as Node2D
	return revive_effect != null and revive_effect.visible


func _fail(message: String) -> void:
	push_error(message)
	quit(1)