class_name PlayerStatusTests
extends RefCounted

static func fresh_state() -> PlayerState:
	var state := PlayerState.new()
	state.setup_inventory(InventoryGrid.new(false))
	return state

static func run(game: MVPGameRoot, check: Callable) -> void:
	var state := fresh_state()
	check.call(state.survival.hunger == 100 and state.survival.thirst == 100 and state.survival.fatigue == 100
		and state.survival.stamina == 100 and state.health == 100, "player needs and health start at one hundred")
	state.advance(3600.0, 1.0)
	check.call(state.survival.hunger < 100 and state.survival.thirst < state.survival.hunger
		and state.survival.fatigue < 100 and state.survival.stamina < 100,
		"hunger thirst fatigue and sprint exertion use inverted reserve scales and deplete in game time")
	var walking := SurvivalSystem.new()
	walking.stamina = 50.0
	walking.advance(10.0, 0.0)
	var sprinting := SurvivalSystem.new()
	sprinting.stamina = 50.0
	sprinting.advance(10.0, 1.0)
	check.call(walking.stamina > 50.0 and sprinting.stamina < 50.0,
		"normal movement recovers stamina while sprint exertion consumes it")
	var depleted := SurvivalSystem.new()
	depleted.hunger = 0
	depleted.thirst = 0
	depleted.fatigue = 0
	depleted.stamina = 0
	state = fresh_state()
	state.survival = depleted
	state.advance(3600.0)
	check.call(state.health < 100 and not state.survival.can_sprint(), "zero hunger and thirst drain health while zero fatigue and stamina prevent sprinting")

	state = fresh_state()
	var overall := state.health
	state.add_wound("Laceration", "Left Leg", 25.0)
	check.call(state.body_health["Left Leg"] == 75 and state.health == overall and state.movement_multiplier() < 1.0,
		"direct hit damages only its body region and a leg injury penalizes movement")
	var perception := fresh_state()
	perception.add_wound("Laceration", "Head", 50.0)
	check.call(perception.perception_multiplier() < 1.0, "head injury reduces the authoritative perception multiplier")
	state.add_wound("Scratch", "Left Leg", 10.0)
	check.call(state.wounds_for_region("Left Leg").size() == 2, "one body region can hold multiple independent injuries")
	var head_state := fresh_state()
	head_state.add_wound("Bite", "Head", 100.0)
	check.call(head_state.is_dead(), "head health reaching zero kills the player")
	var limb_state := fresh_state()
	limb_state.add_wound("Fracture", "Right Arm", 100.0)
	check.call(not limb_state.is_dead() and limb_state.attack_performance() < 1.0, "limb health reaching zero restricts function without killing")

	var wound := state.wounds[0]
	wound["bleeding"] = 20.0
	var health_before := state.health
	state.advance(3600.0)
	check.call(state.health < health_before, "bleeding causes ongoing overall-health loss")
	state.treat_wound(wound["id"], "bandage")
	var severity_before := float(wound["severity"])
	state.advance(3600.0, 0.0, true)
	check.call(wound["bleeding"] == 0 and wound["severity"] < severity_before, "bandaging stops bleeding and allows gradual healing")
	var fracture := limb_state.wounds[0]
	fracture["bleeding"] = 0.0
	severity_before = fracture["severity"]
	limb_state.advance(3600.0)
	check.call(fracture["severity"] == severity_before, "fracture cannot heal before splinting")
	limb_state.treat_wound(fracture["id"], "splint")
	limb_state.advance(3600.0)
	check.call(fracture["severity"] < severity_before, "splinted fracture begins healing")

	for infection in [0.0, 1.0, 49.0, 50.0, 99.0]:
		wound["infection"] = infection
		var label := CharacterStatusPanel.infection_status(wound)
		check.call((infection == 0 and label == "Clean") or (infection > 0 and infection < 50 and label.begins_with("Infected"))
			or (infection >= 50 and label.begins_with("Severe")), "wound infection display threshold %.0f is correct" % infection)
	var infection_state := fresh_state()
	var infected_a := infection_state.add_wound("Scratch", "Left Arm", 10.0)
	var infected_b := infection_state.add_wound("Laceration", "Right Arm", 10.0)
	for infected in [infected_a, infected_b]:
		infected["bleeding"] = 0.0
		infected["bandaged"] = true
		infected["infection"] = 50.0
	infection_state.advance(3600.0)
	check.call(is_equal_approx(infection_state.health, 96.0), "multiple severe wound infections add their overall-health drain")
	infection_state.treat_wound(infected_a["id"], "antibiotic")
	check.call(infected_a["infection"] == 15.0, "antibiotics reduce established ordinary wound infection")
	var terminal := fresh_state()
	var terminal_wound := terminal.add_wound("Burn", "Torso", 5.0)
	terminal_wound["infection"] = 100.0
	terminal_wound["bleeding"] = 0.0
	terminal.advance(1.0)
	check.call(terminal.is_dead(), "ordinary wound infection at one hundred is immediately fatal")

	var dirty := fresh_state()
	var dirty_wound := dirty.add_wound("Scratch", "Left Hand", 20.0)
	dirty_wound["bleeding"] = 0.0
	dirty.advance(3600.0)
	var clean := fresh_state()
	var clean_wound := clean.add_wound("Scratch", "Left Hand", 20.0)
	clean_wound["bleeding"] = 0.0
	clean.treat_wound(clean_wound["id"], "disinfectant")
	clean.treat_wound(clean_wound["id"], "bandage")
	clean.advance(3600.0)
	check.call(dirty_wound["infection"] > clean_wound["infection"], "cleaning and bandaging prevent ordinary infection growth")
	var pain_before := dirty.pain
	dirty.treat_wound("", "painkiller")
	check.call(dirty.pain < pain_before and dirty_wound["severity"] > 0, "painkillers reduce global pain without healing injury")

	var clock_before := GameTime.elapsed_game_seconds
	GameTime.elapsed_game_seconds = 1000.0
	var virus := fresh_state()
	virus.add_wound("Bite", "Torso", 5.0, true, 0.99)
	check.call(virus.zombie_virus_exposure and virus.zombie_virus_deadline >= 1000.0 + StatusConfig.VIRUS_LATENT_MIN_SECONDS
		and virus.zombie_virus_deadline <= 1000.0 + StatusConfig.VIRUS_LATENT_MAX_SECONDS,
		"bite always transmits with a configurable one-to-two-week hidden deadline")
	var scratch_safe := fresh_state()
	scratch_safe.add_wound("Scratch", "Torso", 5.0, true, 0.5)
	var scratch_infected := fresh_state()
	scratch_infected.add_wound("Scratch", "Torso", 5.0, true, 0.0)
	var laceration := fresh_state()
	laceration.add_wound("Laceration", "Torso", 5.0, true, 0.0)
	check.call(not scratch_safe.zombie_virus_exposure and scratch_infected.zombie_virus_exposure and not laceration.zombie_virus_exposure,
		"scratch uses seven-percent transmission while laceration never transmits")
	var blocked := fresh_state()
	var helmet := ItemStack.new(ItemDefinition.clothing("test_helmet", "Helmet", "hat", ["Head"], {"Head": 100}, {}, {"Head": 20}, 1.0, Vector3.ONE, 1))
	blocked.inventory.contents("hat").append(helmet)
	blocked.receive_hit("Bite", "Head", 5.0, true, 0.0, 0.0)
	check.call(blocked.wounds.is_empty() and not blocked.zombie_virus_exposure, "fully clothing-blocked zombie hit cannot transmit virus")
	virus.zombie_virus_deadline = GameTime.elapsed_game_seconds + StatusConfig.VIRUS_LATENT_MIN_SECONDS * 0.1
	check.call(virus.symptom_text() == "Fever · weakness" and not "virus" in virus.visible_wound_summary().to_lower(),
		"late virus symptoms remain nonspecific and status text never confirms infection")
	virus.health = 0.0
	check.call(virus.should_reanimate(), "infected death requests immediate reanimation")
	virus.head_destroyed = true
	check.call(not virus.should_reanimate(), "head destruction prevents infected reanimation")
	GameTime.elapsed_game_seconds = clock_before

	var stable := fresh_state()
	var all_regions: Array[String] = []
	all_regions.assign(PlayerState.BODY_REGIONS)
	var thermal := ItemDefinition.clothing("thermal_test", "Thermal suit", "outer_top", all_regions,
		{}, _uniform_regions(100.0), _uniform_regions(100.0), 1.0, Vector3.ONE, 2)
	stable.inventory.contents("outer_top").append(ItemStack.new(thermal))
	stable.advance(3600.0)
	check.call(is_equal_approx(stable.core_temperature, StatusConfig.NORMAL_BODY_TEMPERATURE), "one hundred percent average warmth keeps core temperature stable")
	var cold := fresh_state()
	cold.advance(3600.0)
	var hot := fresh_state()
	thermal.clothing_warmth = _uniform_regions(200.0)
	hot.inventory.contents("outer_top").append(ItemStack.new(thermal))
	hot.advance(3600.0)
	check.call(cold.core_temperature < 37.0 and hot.core_temperature > 37.0, "warmth below and above one hundred drives cold and heat centrally")
	for tier in range(1, 5):
		cold.core_temperature = 37.0 - StatusConfig.TEMPERATURE_THRESHOLDS[tier - 1] - 0.01
		check.call(cold.temperature_tier() == tier, "temperature severity tier %d uses configured threshold" % tier)

	var emotions := fresh_state()
	emotions.advance(3600.0, 0.0, false, 2, false)
	check.call(emotions.panic > 0 and emotions.stress > 0 and emotions.boredom > 0, "danger raises panic and stress while prolonged inactivity raises boredom")
	var panic_before := emotions.panic
	emotions.advance(3600.0, 0.2, false, 0, true)
	check.call(emotions.panic < panic_before and emotions.boredom == 0, "safety recovers panic and exploration clears boredom")
	emotions.unhappiness = 100
	check.call(emotions.action_efficiency("search") < 1.0 and emotions.attack_performance() < 1.0,
		"emotional and physical status multipliers affect focused actions and combat")
	check.call(StatusConfig.severity_tier(100, true) == 0 and StatusConfig.severity_tier(0, true) == 4
		and StatusConfig.severity_tier(100, false) == 4, "HUD tiers invert needs but not adverse statuses")

	var old_mode := GameTime.speed_mode
	GameTime.set_speed(GameTime.SpeedMode.SLEEP)
	check.call(GameTime.simulation_scale() == StatusConfig.SLEEP_TIME_SCALE, "sleep uses unified configurable world-time fast-forward")
	GameTime.set_speed(old_mode)

	var baseline := QuickSave.snapshot(game)
	game.interactions.interrupt_action()
	for root in InventoryGrid.ROOTS: game.inventory.contents(root).clear()
	game.inventory.use_context.clear()
	var meal_def := ItemDefinition.new("status_meal", "Status meal", Vector3.ONE, 0.2, ["food"])
	meal_def.hunger_restore = 40.0
	meal_def.happiness_effect = 10.0
	var meal := ItemStack.new(meal_def)
	var meal_uid: String = meal.units[0]["uid"]
	game.inventory.contents("right_hand").append(meal)
	game.player_state.survival.hunger = 50.0
	game.player_state.unhappiness = 20.0
	game.interactions.request_use(meal_uid)
	game.interactions._update_active_action(5.0 / GameTime.GAME_SECONDS_PER_REAL_SECOND)
	check.call(is_equal_approx(game.player_state.survival.hunger, 60.0)
		and is_equal_approx(float(game.inventory.find_unit(meal_uid)["unit"]["remaining"]), 0.75)
		and is_equal_approx(game.player_state.unhappiness, 17.5),
		"item-specific hunger and happiness restore proportionally to the amount consumed")
	game.interactions.interrupt_action("Test")
	for root in InventoryGrid.ROOTS: game.inventory.contents(root).clear()
	game.inventory.use_context.clear()
	var treatment_state := game.player_state
	treatment_state.health = 100
	treatment_state.body_health["Left Arm"] = 100
	treatment_state.wounds.clear()
	var target := treatment_state.add_wound("Laceration", "Left Arm", 10.0)
	var bandage_def := ItemDefinition.new("status_bandage", "Bandage", Vector3.ONE, 0.1, ["medical"])
	bandage_def.medical_action = "bandage"
	var bandage := ItemStack.new(bandage_def)
	var bandage_uid: String = bandage.units[0]["uid"]
	game.inventory.loose.append(bandage)
	game.interactions.request_treatment(bandage_uid, target["id"])
	game.interactions._update_active_action(1.0)
	game.interactions.interrupt_action("Test")
	check.call(not target["bandaged"] and not game.inventory.find_unit(bandage_uid).is_empty(),
		"interrupted treatment consumes nothing and applies nothing")
	game.interactions.request_treatment(bandage_uid, target["id"])
	game.interactions._update_active_action(100.0)
	check.call(target["bandaged"] and game.inventory.find_unit(bandage_uid).is_empty(),
		"completed timed treatment consumes its item and updates the selected injury")
	QuickSave.restore(game, baseline)
	check.call(game.player_state.to_save_data() == baseline["player_status"],
		"save restore preserves regional health injuries pain emotions temperature and hidden virus scheduling")
	var legacy := baseline.duplicate(true)
	legacy["version"] = 4
	legacy.erase("player_status")
	check.call(QuickSave.validate(legacy, game), "version-four saves receive backward-compatible player-status defaults")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)

static func _uniform_regions(value: float) -> Dictionary:
	var result := {}
	for region in PlayerState.BODY_REGIONS: result[region] = value
	return result
