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
	if not monster._is_reviving or monster.current_hp != 0 or monster.is_alive() or target.hp != 50:
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
	if target.hp != 50 or monster.current_hp != 0:
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
	if enemy.current_hp != 950:
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
	await process_frame
	if not await _test_summon_state():
		return
	if not await _test_death_passives_with_revive():
		return
	print("Revive smoke test passed.")
	quit(0)


func _test_summon_state() -> bool:
	var game_scene: PackedScene = load("res://main.tscn")
	var scene: Node2D = game_scene.instantiate() as Node2D
	var terrain: ProceduralTerrain = scene.get_node("Terrain") as ProceduralTerrain
	terrain.randomize_biome_on_spawn = false
	terrain.spawn_monsters_on_ready = false
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
	player.set_physics_process(false)
	var slime_scene: PackedScene = load("res://scenes/monsters/forest_slime.tscn")
	var sample: Monster = slime_scene.instantiate() as Monster
	root.add_child(sample)
	sample.set_physics_process(false)
	sample.current_traits.clear()
	var slime_data: Dictionary = sample.get_pet_data()
	sample.queue_free()
	var revive_data: Dictionary = slime_data.duplicate(true)
	revive_data["name"] = "Reviving pet"
	revive_data["current_traits"] = [Monster.TRAIT_REVIVE]
	revive_data["revive_available"] = true
	player.captured_pets.clear()
	player.captured_pets.append(slime_data.duplicate(true))
	player.captured_pets.append(revive_data)
	player.captured_pets.append(slime_data.duplicate(true))
	player._summon_pet(0)
	var summoned: Pet = player.active_pet
	summoned.set_physics_process(false)
	summoned.attack_timer.stop()
	summoned.take_damage(17, player.global_position)
	var remaining_hp: int = summoned.current_hp
	player._toggle_pet()
	if is_instance_valid(player.active_pet) or player.captured_pets[0].get("current_hp") != remaining_hp:
		_fail("Recalling should save the pet's remaining HP for this scene.")
		return false
	await process_frame
	player._toggle_pet()
	summoned = player.active_pet
	summoned.set_physics_process(false)
	summoned.attack_timer.stop()
	if summoned.current_hp != remaining_hp or int(summoned.health_bar.value) != remaining_hp:
		_fail("Resummoning should restore remaining HP and its health bar, not heal the pet.")
		return false
	player._switch_to_pet(1)
	await process_frame
	player.active_pet.set_physics_process(false)
	player.active_pet.attack_timer.stop()
	player._switch_to_pet(0)
	await process_frame
	summoned = player.active_pet
	summoned.set_physics_process(false)
	summoned.attack_timer.stop()
	if summoned.current_hp != remaining_hp:
		_fail("Switching between slots should preserve each pet's HP.")
		return false
	summoned.take_damage(remaining_hp, player.global_position)
	await process_frame
	player._summon_pet(0)
	if is_instance_valid(player.active_pet) or not player.is_pet_fainted(0):
		_fail("A dead slime must remain fainted and cannot be resummoned in this scene.")
		return false
	player._summon_pet(1)
	summoned = player.active_pet
	summoned.set_physics_process(false)
	summoned.attack_timer.stop()
	if not summoned.can_be_recalled():
		_fail("A pet with unused Revive should still be recallable.")
		return false
	summoned.take_damage(summoned.max_hp, player.global_position)
	player._toggle_pet()
	player._switch_to_pet(1)
	player._switch_to_pet(2)
	player._summon_pet(2)
	if player.active_pet != summoned or player.selected_pet_index != 1 or summoned.is_queued_for_deletion() or not summoned.is_reviving() or player._recall_pet():
		_fail("Once Revive triggers, recalling or switching must not cancel revival or replace the pet.")
		return false
	await create_timer(1.6).timeout
	player._toggle_pet()
	player._switch_to_pet(2)
	if player.active_pet != summoned or summoned.is_queued_for_deletion() or summoned.can_be_recalled() or summoned.current_hp != ceili(summoned.max_hp * 0.3):
		_fail("The revived pet should keep 30% HP and remain locked against recall.")
		return false
	summoned.take_damage(summoned.current_hp, player.global_position)
	await process_frame
	player._summon_pet(1)
	if is_instance_valid(player.active_pet) or not player.is_pet_fainted(1):
		_fail("A revived pet's second death should leave its slot fainted.")
		return false
	var storage: Node = root.get_node("PetStorage")
	var saved: Dictionary = storage.call("_to_saved", player.captured_pets[0])
	if saved.has("current_hp") or saved.has("fainted") or slime_data.has("current_hp"):
		_fail("Scene HP and fainted state must not leak into collection data.")
		return false
	scene.queue_free()
	await process_frame
	var fresh_scene: Node2D = game_scene.instantiate() as Node2D
	var fresh_terrain: ProceduralTerrain = fresh_scene.get_node("Terrain") as ProceduralTerrain
	fresh_terrain.randomize_biome_on_spawn = false
	fresh_terrain.spawn_monsters_on_ready = false
	root.add_child(fresh_scene)
	current_scene = fresh_scene
	var fresh_player: CharacterBody2D = fresh_scene.get_node("Player") as CharacterBody2D
	fresh_player.set_physics_process(false)
	fresh_player.captured_pets.clear()
	fresh_player.captured_pets.append(slime_data.duplicate(true))
	fresh_player._summon_pet(0)
	if fresh_player.active_pet.current_hp != fresh_player.active_pet.max_hp or fresh_player.is_pet_fainted(0):
		_fail("A new scene should start with full HP and no previous scene's fainted state.")
		return false
	fresh_scene.queue_free()
	await process_frame
	return true


func _test_death_passives_with_revive() -> bool:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	var slime_scene: PackedScene = load("res://scenes/monsters/forest_slime.tscn")
	var wild_slime: Monster = slime_scene.instantiate() as Monster
	world.add_child(wild_slime)
	wild_slime.set_arena_team("TeamEnemy")
	wild_slime.set_physics_process(false)
	wild_slime.current_traits = [Monster.TRAIT_REVIVE, Monster.TRAIT_EXPLODE_ON_DEATH]
	wild_slime.max_hp = 100
	wild_slime.attack_damage = 20
	wild_slime.current_hp = 1
	wild_slime.global_position = Vector2(1000.0, 1000.0)
	var pet_data: Dictionary = wild_slime.get_pet_data()
	var target: DummyTarget = DummyTarget.new()
	target.add_to_group("TeamPlayer")
	world.add_child(target)
	target.global_position = wild_slime.global_position
	wild_slime.take_damage(1, Vector2.ZERO)
	if not wild_slime.is_reviving() or get_nodes_in_group("TeamEnemy").size() != 3 or target.hp != 50:
		_fail("A wild Slime's Split and Explosion should both trigger before Revive.")
		return false
	world.queue_free()
	await process_frame
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var storage_script: Script = load("res://scripts/pet_storage.gd")
	var storage: Node = storage_script.new()
	var saved: Dictionary = storage.call("_to_saved", pet_data)
	storage.collection.append(saved)
	var runtime: Dictionary = storage.call("get_runtime_pet", 0)
	if not runtime.get("split_on_death", false) or runtime.get("split_count", -1) != 0:
		_fail("Capture and save/load should preserve the Slime's splitting passive.")
		return false
	storage.collection[0].erase("split_on_death")
	storage.collection[0].erase("split_count")
	var legacy_runtime: Dictionary = storage.call("get_runtime_pet", 0)
	if not legacy_runtime.get("split_on_death", false):
		_fail("Previously saved forest Slimes should regain their missing splitting passive.")
		return false
	storage.free()
	var pet_scene: PackedScene = load("res://scenes/pet.tscn")
	var parent_pet: Pet = pet_scene.instantiate() as Pet
	parent_pet.set_arena_team("TeamPlayer")
	world.add_child(parent_pet)
	parent_pet.apply_pet_data(runtime)
	parent_pet.set_physics_process(false)
	parent_pet.attack_timer.stop()
	var monster_scene: PackedScene = load("res://scenes/monster.tscn")
	var enemy: Monster = monster_scene.instantiate() as Monster
	world.add_child(enemy)
	enemy.set_arena_team("TeamEnemy")
	enemy.set_physics_process(false)
	enemy.current_traits.clear()
	enemy.max_hp = 1000
	enemy.current_hp = 1000
	enemy.global_position = Vector2(20.0, 0.0)
	parent_pet.take_damage(parent_pet.max_hp, enemy.global_position)
	var children: Array[Pet] = []
	for member: Node in get_nodes_in_group("pets"):
		var child: Pet = member as Pet
		if child == parent_pet:
			continue
		child.set_physics_process(false)
		child.attack_timer.stop()
		children.append(child)
	if not parent_pet.is_reviving() or children.size() != 2 or enemy.current_hp != 950 or parent_pet.can_be_recalled():
		_fail("A captured Slime should explode, spawn two allied children and lock recall before Revive.")
		return false
	for child: Pet in children:
		if child.max_hp != 50 or child.current_hp != 50 or child.attack_damage != 10 or child.sprite.scale != parent_pet.sprite.scale * 0.5:
			_fail("Slime Pet children should have half-sized stats and visuals.")
			return false
		if child.arena_team != parent_pet.arena_team or child.current_traits != parent_pet.current_traits or child.split_count != 1:
			_fail("Slime Pet children should inherit their parent's team, traits and split guard.")
			return false
		for sibling: Pet in children:
			if sibling != child and not child.get_collision_exceptions().has(sibling):
				_fail("Slime Pet children should not collide with siblings.")
				return false
	parent_pet.die()
	if enemy.current_hp != 950 or get_nodes_in_group("pets").size() != 3:
		_fail("Repeated death calls during Revive should not repeat death passives.")
		return false
	children[0].take_damage(children[0].max_hp, enemy.global_position)
	if not children[0].is_reviving() or enemy.current_hp != 900 or get_nodes_in_group("pets").size() != 3:
		_fail("A child should explode and revive, but must not spawn further Slimes.")
		return false
	await create_timer(1.6).timeout
	if parent_pet.current_hp != 30 or children[0].current_hp != 15 or parent_pet.can_be_recalled():
		_fail("Split Slimes should complete Revive without unlocking recall.")
		return false
	parent_pet.take_damage(parent_pet.current_hp, enemy.global_position)
	await process_frame
	if enemy.current_hp != 850 or get_nodes_in_group("pets").size() != 2:
		_fail("Final death should explode again without spawning duplicate children.")
		return false
	world.queue_free()
	await process_frame
	return true


func _revive_visual_visible(actor: Node) -> bool:
	var revive_effect: Node2D = actor.get_node_or_null("ReviveEffect") as Node2D
	return revive_effect != null and revive_effect.visible


func _fail(message: String) -> void:
	push_error(message)
	quit(1)