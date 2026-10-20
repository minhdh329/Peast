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
	var slime_scene: PackedScene = load("res://scenes/monsters/forest_slime.tscn")
	var slime: Monster = slime_scene.instantiate() as Monster
	root.add_child(slime)
	slime.current_traits = [Monster.TRAIT_DOUBLE_HP, Monster.TRAIT_DOUBLE_DAMAGE, Monster.TRAIT_FAST_MOVEMENT]
	var parent_traits: Array[String] = slime.current_traits.duplicate()
	slime.max_hp = 80
	slime.attack_damage = 10
	slime.scale_size = Vector2(2.0, 2.0)
	slime.die()
	await process_frame

	var split_children: Array[Node] = get_nodes_in_group("monsters")
	if split_children.size() != 2:
		_fail("Forest slime should split into exactly two children.")
		return
	for child_node: Node in split_children:
		var child: Monster = child_node as Monster
		if child.max_hp != 40 or child.attack_damage != 5 or child.scale_size != Vector2.ONE:
			_fail("Split child stats or scale were not halved.")
			return
		if child.current_traits != parent_traits or child.split_count != 1:
			_fail("Split child did not inherit traits or split guard.")
			return
		for other_child_node: Node in split_children:
			if other_child_node == child:
				continue
			var other_child: Monster = other_child_node as Monster
			if not child.get_collision_exceptions().has(other_child):
				_fail("Split slimes should ignore collision with siblings.")
				return
		child.die()
	await process_frame
	if not get_nodes_in_group("monsters").is_empty():
		_fail("Split children should not split again.")
		return

	var reviving_slime: Monster = slime_scene.instantiate() as Monster
	root.add_child(reviving_slime)
	reviving_slime.split_on_death = true
	reviving_slime.current_traits = [Monster.TRAIT_REVIVE]
	reviving_slime.current_hp = 1
	reviving_slime.take_damage(1, Vector2.ZERO)
	await process_frame
	var revive_split_group: Array[Node] = get_nodes_in_group("monsters")
	if not reviving_slime.is_reviving() or revive_split_group.size() != 3:
		_fail("Revive and Split should both trigger on the Slime's lethal hit.")
		return
	var revive_offspring_count: int = 0
	for member: Node in revive_split_group:
		if member != reviving_slime:
			var offspring: Monster = member as Monster
			if offspring.current_traits != reviving_slime.current_traits or offspring.split_count != 1:
				_fail("Slimes spawned during Revive should inherit traits and split guard.")
				return
			revive_offspring_count += 1
	if revive_offspring_count != 2:
		_fail("A reviving Slime should spawn exactly two offspring.")
		return
	for member: Node in revive_split_group:
		member.queue_free()
	await process_frame

	var golem_scene: PackedScene = load("res://scenes/monsters/volcano_golem.tscn")
	var golem: Monster = golem_scene.instantiate() as Monster
	root.add_child(golem)
	golem.current_hp = golem.max_hp
	golem.take_damage(1, Vector2.LEFT * 100.0)
	if not golem.immune_to_knockback or golem.velocity != Vector2.ZERO:
		_fail("Lava golem should ignore knockback.")
		return
	golem.queue_free()

	var cloud_scene: PackedScene = load("res://scenes/monsters/sky_cloud.tscn")
	var cloud: Monster = cloud_scene.instantiate() as Monster
	root.add_child(cloud)
	if not _has_badge(cloud, "ARC"):
		_fail("Cloud monster is missing its animated chain-lightning badge.")
		return
	cloud.current_traits.clear()
	cloud.attack_damage = 12
	cloud.chain_lightning_radius = 64.0
	var primary: DummyTarget = DummyTarget.new()
	primary.add_to_group("player")
	primary.global_position = Vector2(100.0, 100.0)
	root.add_child(primary)
	var secondary: DummyTarget = DummyTarget.new()
	secondary.add_to_group("pets")
	secondary.global_position = Vector2(130.0, 100.0)
	root.add_child(secondary)
	var distant: DummyTarget = DummyTarget.new()
	distant.add_to_group("pets")
	distant.global_position = Vector2(300.0, 100.0)
	root.add_child(distant)
	cloud._attack_target(primary)
	if primary.hp != 88 or secondary.hp != 97 or distant.hp != 100:
		_fail("Cloud chain lightning damaged the wrong targets or wrong amount.")
		return
	var chain_visual: Node2D = root.get_node_or_null("ChainLightningFX") as Node2D
	if chain_visual == null or chain_visual.get_child_count() != 2:
		_fail("Cloud chain lightning should draw a glowing bolt to the secondary target.")
		return

	var bird_scene: PackedScene = load("res://scenes/monsters/sky_bird.tscn")
	var bird: Monster = bird_scene.instantiate() as Monster
	root.add_child(bird)
	bird.current_traits.clear()
	bird.global_position = Vector2(100.0, 240.0)
	bird._attack_target(primary)
	bird._attack_target(primary)
	if bird.attack_count != 2 or bird.is_dashing:
		_fail("Wind bird should fire two shots before dashing.")
		return
	bird._attack_target(primary)
	if not bird.is_dashing or bird.attack_count != 2:
		_fail("Wind bird should dash instead of firing a third projectile.")
		return
	var primary_hp_before_dash: int = primary.hp
	var bird_dash_damage: int = bird.attack_damage * 2
	bird._apply_wind_dash_hit(primary)
	if primary.hp != primary_hp_before_dash - bird_dash_damage or bird.is_dashing or bird.attack_count != 0:
		_fail("Wind bird dash should deal double damage and reset its state on hit.")
		return
	var captured_bird_data: Dictionary = bird.get_pet_data()
	bird.queue_free()
	await process_frame

	var pet_test_scene: Node2D = Node2D.new()
	root.add_child(pet_test_scene)
	current_scene = pet_test_scene
	var pet_scene: PackedScene = load("res://scenes/pet.tscn")
	var bird_pet: Pet = pet_scene.instantiate() as Pet
	root.add_child(bird_pet)
	bird_pet.apply_pet_data(captured_bird_data)
	if not _has_badge(bird_pet, "DASH"):
		_fail("Captured wind bird is missing its animated dash badge.")
		return
	bird_pet.global_position = Vector2(100.0, 240.0)
	cloud.global_position = Vector2(150.0, 240.0)
	for attack_index: int in range(2):
		bird_pet._on_attack_timer_timeout()
	if bird_pet.attack_count != 2 or bird_pet.is_dashing:
		_fail("Captured wind bird should fire two shots before dashing.")
		return
	bird_pet._on_attack_timer_timeout()
	if not bird_pet.is_dashing or bird_pet.attack_count != 2:
		_fail("Captured wind bird should dash instead of firing a third projectile.")
		return
	var cloud_hp_before_dash: int = cloud.current_hp
	var pet_dash_damage: int = bird_pet.attack_damage * 2
	bird_pet._apply_wind_dash_hit(cloud)
	if cloud.current_hp != cloud_hp_before_dash - pet_dash_damage or bird_pet.is_dashing or bird_pet.attack_count != 0:
		_fail("Captured wind bird dash should deal double damage and reset on hit.")
		return
	var land_swimmer: Pet = pet_scene.instantiate() as Pet
	root.add_child(land_swimmer)
	var swimmer_data: Dictionary = captured_bird_data.duplicate()
	swimmer_data["movement_mode"] = "Swim"
	land_swimmer.apply_pet_data(swimmer_data)
	if land_swimmer._uses_free_movement() or land_swimmer.motion_mode != CharacterBody2D.MOTION_MODE_GROUNDED:
		_fail("A swimming Pet outside water should use grounded movement.")
		return
	var jelly_scene: PackedScene = load("res://scenes/monsters/ocean_jelly.tscn")
	var land_jelly: Monster = jelly_scene.instantiate() as Monster
	root.add_child(land_jelly)
	land_jelly._physics_process(1.0 / 60.0)
	if land_jelly._uses_free_movement() or land_jelly.motion_mode != CharacterBody2D.MOTION_MODE_GROUNDED:
		_fail("A swimming Monster outside water should use grounded movement.")
		return

	var visual_actor: Monster = cloud_scene.instantiate() as Monster
	root.add_child(visual_actor)
	visual_actor.current_traits.clear()
	visual_actor.take_damage(0, Vector2.ZERO, "Burn")
	var visual_effects: Node = visual_actor.get_node("StatusEffects")
	visual_effects.set("_visual_time", 0.1)
	visual_effects.call("_update_flash_visuals")
	if not visual_actor.get_node("Sprite2D").modulate.is_equal_approx(Color("#ff3d32")):
		_fail("Burn should flash the actor red.")
		return
	visual_actor.take_damage(0, Vector2.ZERO, "Stun")
	var status_stars: Node2D = visual_actor.get_node("StatusStars") as Node2D
	if status_stars == null or not status_stars.visible or status_stars.get_child_count() != 3:
		_fail("Stun should show three animated stars above the actor.")
		return

	var poison_actor: Monster = cloud_scene.instantiate() as Monster
	root.add_child(poison_actor)
	poison_actor.take_damage(0, Vector2.ZERO, "Poison")
	var poison_effects: Node = poison_actor.get_node("StatusEffects")
	poison_effects.set("_visual_time", 0.1)
	poison_effects.call("_update_flash_visuals")
	if not poison_actor.get_node("Sprite2D").modulate.is_equal_approx(Color("#bd50ed")):
		_fail("Poison should flash the actor purple.")
		return

	var pet_storage_script: Script = load("res://scripts/pet_storage.gd") as Script
	var legacy_storage: Node = pet_storage_script.new() as Node
	var legacy_mushroom: Dictionary = legacy_storage.call("_get_legacy_special_defaults", "Nấm độc")
	var migrated_lifesteal: Dictionary = legacy_storage.call("_migrate_lifesteal_values", {
		"lifesteal_chance": 0.25,
		"lifesteal_heal_fraction": 0.25,
	})
	legacy_storage.free()
	if legacy_mushroom.get("attack_effect") != "Poison":
		_fail("Legacy mushroom pets should regain their poison attack.")
		return
	if migrated_lifesteal["chance"] != 1.0 or not is_equal_approx(migrated_lifesteal["heal_fraction"], 0.15):
		_fail("Legacy Lifesteal values should migrate to 100% chance and 15% healing.")
		return
	var mushroom_pet: Pet = pet_scene.instantiate() as Pet
	root.add_child(mushroom_pet)
	mushroom_pet.apply_pet_data({
		"name": "Nấm độc",
		"attack_style": "Ranged",
		"texture": load("res://assets/monsters/mushroom.png"),
		"sprite_scale": Vector2.ONE,
		"max_hp": 80,
		"attack_damage": 8,
		"attack_effect": legacy_mushroom["attack_effect"],
	})
	var poison_fireball: FireballProjectile = load("res://scenes/fireball.tscn").instantiate() as FireballProjectile
	root.add_child(poison_fireball)
	poison_fireball.effect_type = mushroom_pet.attack_effect
	poison_fireball.effect_chance = mushroom_pet.attack_effect_chance
	poison_fireball._on_body_entered(visual_actor)
	if mushroom_pet.attack_effect != "Poison" or not visual_effects.call("has_effect", "Poison"):
		_fail("A captured mushroom pet's fireball should poison Monsters.")
		return

	var explosive: Monster = cloud_scene.instantiate() as Monster
	root.add_child(explosive)
	explosive.current_traits = [Monster.TRAIT_EXPLODE_ON_DEATH]
	explosive.death_explosion_damage = 50
	explosive.death_explosion_radius = 128.0
	explosive.global_position = Vector2(0.0, 100.0)
	primary.hp = 200
	secondary.hp = 200
	secondary.global_position = Vector2(100.0, 100.0)
	distant.hp = 200
	for pet_target: Node in get_nodes_in_group("pets"):
		if pet_target != secondary:
			pet_target.remove_from_group("pets")
	explosive.die()
	if primary.hp != 150 or secondary.hp != 150 or distant.hp != 200:
		_fail("Death explosion should deal 50 damage only inside its radius.")
		return
	await process_frame
	if pet_test_scene.get_node_or_null("DeathExplosionFX") == null:
		_fail("Death explosion animation should persist after the Monster is freed.")
		return
	var lifesteal_monster: Monster = cloud_scene.instantiate() as Monster
	root.add_child(lifesteal_monster)
	lifesteal_monster.current_traits = [Monster.TRAIT_LIFESTEAL]
	lifesteal_monster.current_hp = lifesteal_monster.max_hp - 10
	var monster_hp_before: int = lifesteal_monster.current_hp
	lifesteal_monster._try_lifesteal(20)
	if lifesteal_monster.current_hp != monster_hp_before + 3:
		_fail("Monster Lifesteal should always heal 15% of damage dealt.")
		return
	var lifesteal_pet: Pet = pet_scene.instantiate() as Pet
	root.add_child(lifesteal_pet)
	lifesteal_pet.current_traits = [Monster.TRAIT_LIFESTEAL]
	lifesteal_pet.current_hp = lifesteal_pet.max_hp - 10
	var pet_hp_before: int = lifesteal_pet.current_hp
	lifesteal_pet._try_lifesteal(20)
	if lifesteal_pet.current_hp != pet_hp_before + 3:
		_fail("Pet Lifesteal should always heal 15% of damage dealt.")
		return

	print("Monster passive smoke test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _has_badge(actor: Node, badge_text: String) -> bool:
	var passive_vfx: Node = actor.get_node("PassiveVFX")
	for badge: Node in passive_vfx.get_children():
		var label: Label = badge.get_child(0) as Label
		if label != null and label.text == badge_text:
			return true
	return false