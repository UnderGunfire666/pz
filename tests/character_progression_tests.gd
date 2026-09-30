class_name CharacterProgressionTests
extends RefCounted


static func run(game: MVPGameRoot, check: Callable) -> void:
	var catalog := game.character_catalog
	check.call(catalog.skills.size() == 35 and catalog.occupations.size() == 25 and catalog.traits.size() == 97,
		"Build 42.21 character catalog has all 35 skills, 25 occupations and 97 trait definitions")
	check.call(catalog.validate().is_empty(), "character resource catalog has unique valid IDs and references")
	check.call(catalog.rules.free_trait_points == 0 and catalog.occupation("base:unemployed").point_bonus == 8,
		"Build 42.21 uses zero sandbox free points and eight points from Custom Occupation")

	var character := CharacterProgression.new()
	character.setup(catalog)
	check.call(character.skill_levels["Strength"] == 5 and character.skill_levels["Fitness"] == 5,
		"physical attributes start at Build 42.21 level five")
	check.call(not character.has_trait("base:stout") and not character.has_trait("base:fit"),
		"level-five attributes do not expose an attribute-level trait")
	character.add_skill_xp("Strength", catalog.skill("Strength").xp_per_level[5])
	character.add_skill_xp("Fitness", catalog.skill("Fitness").xp_per_level[5])
	check.call(character.has_trait("base:stout") and character.has_trait("base:fit"),
		"level-six attributes dynamically expose the verified Stout and Fit traits")
	character.add_skill_xp("Strength", catalog.skill("Strength").xp_per_level[6]
		+ catalog.skill("Strength").xp_per_level[7]
		+ catalog.skill("Strength").xp_per_level[8])
	check.call(character.has_trait("base:strong") and not character.has_trait("base:stout"),
		"level-nine Strength replaces Stout with Strong")
	character.rebuild_starting_state()
	check.call(character.point_balance(["base:deaf"]) == 20,
		"negative traits can raise the balance beyond the occupation starting budget")
	check.call(not character.selection_errors(["base:athletic"], "base:unemployed").is_empty(),
		"positive traits cannot overspend the available point balance")
	check.call(not character.selection_errors(["base:athletic", "base:unfit", "base:deaf"], "base:unemployed").is_empty(),
		"Build 42.21 mutual exclusions reject incompatible trait combinations")

	var errors := character.select_build("base:nurse", [])
	check.call(errors.is_empty() and character.has_trait("base:nightowl")
		and character.skill_levels["Doctor"] == 3 and character.skill_levels["Fitness"] == 6,
		"occupation grants free traits and exact starting skill and attribute levels")
	var carpentry := catalog.skill("Woodwork")
	check.call(carpentry.xp_per_level == PackedFloat32Array([75, 150, 300, 750, 1500, 3000, 4500, 6000, 7500, 9000]),
		"regular skills use the Build 42.21 XP curve")
	var strength := catalog.skill("Strength")
	check.call(strength.xp_per_level == PackedFloat32Array([1500, 3000, 6000, 9000, 18000, 30000, 60000, 90000, 120000, 150000]),
		"Strength and Fitness use the Build 42.21 passive XP curve")

	character = CharacterProgression.new()
	character.setup(catalog)
	check.call(is_equal_approx(character.xp_multiplier("Axe"), 0.25),
		"a skill with no starting level earns XP at the Build 42.21 quarter rate")
	errors = character.select_build("base:unemployed", ["base:fastlearner", "base:asthmatic"])
	check.call(errors.is_empty() and is_equal_approx(character.xp_multiplier("Axe"), 0.325),
		"Fast Learner applies its verified 1.3 multiplier after the starting-skill rate")
	var awarded := character.add_skill_xp("Axe", 100.0)
	check.call(is_equal_approx(awarded, 32.5) and character.skill_levels["Axe"] == 0,
		"skill XP is multiplied and retained independently from static definitions")
	check.call(is_equal_approx(character.xp_multiplier("Cooking"), 0.325),
		"pending Asthmatic effects do not silently alter unrelated systems")

	var saved := character.to_save_data()
	var restored := CharacterProgression.new()
	restored.setup(catalog)
	check.call(restored.load_save_data(saved) and restored.to_save_data() == saved,
		"occupation traits skill levels and XP survive runtime save/load")
	check.call(not restored.select_build("base:unemployed", []).is_empty(),
		"occupation and selectable traits are fixed after character creation")
	check.call(catalog.trait_definition("base:fastlearner").cost == 6 and catalog.skill("Axe").xp_per_level[0] == 75,
		"save/load never mutates shared definition resources")
	var corrupt := saved.duplicate(true)
	corrupt["skill_levels"]["Axe"] = 10
	check.call(not CharacterProgression.valid_save_data(corrupt, catalog),
		"save validation rejects skill levels inconsistent with authoritative XP")
	var legacy := QuickSave.snapshot(game)
	legacy["version"] = 5
	legacy.erase("character")
	legacy["traits"] = {}
	check.call(QuickSave.validate(legacy, game), "version-five saves migrate to the default 42.21 character build")
