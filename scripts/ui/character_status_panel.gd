class_name CharacterStatusPanel
extends PanelContainer

var title_label: Label
var summary_label: Label
var body_tree: Tree
var treatment_row: HBoxContainer
var character_summary_label: Label
var skill_tree: Tree
var trait_label: Label
var selected_wound_id := ""
var _game: MVPGameRoot
var _last_signature := ""

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.055, 0.94)
	style.set_content_margin_all(12.0)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	add_child(content)
	title_label = Label.new()
	title_label.text = "CHARACTER STATUS · C to close"
	title_label.add_theme_font_size_override("font_size", 18)
	content.add_child(title_label)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(900, 500)
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(tabs)
	var health_page := VBoxContainer.new()
	health_page.name = "Health"
	tabs.add_child(health_page)
	summary_label = Label.new()
	summary_label.add_theme_font_size_override("font_size", 14)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	health_page.add_child(summary_label)
	body_tree = Tree.new()
	body_tree.columns = 6
	body_tree.hide_root = true
	body_tree.column_titles_visible = true
	body_tree.custom_minimum_size = Vector2(900, 320)
	for index in range(6): body_tree.set_column_title(index, ["Body region / injury", "Health / status", "Bleeding", "Infection", "Protection / warmth", "Worn clothing"][index])
	body_tree.set_column_expand(0, true)
	for index in range(1, 6):
		body_tree.set_column_expand(index, false)
		body_tree.set_column_custom_minimum_width(index, [0, 130, 75, 100, 145, 190][index])
	body_tree.mouse_filter = Control.MOUSE_FILTER_STOP
	body_tree.item_selected.connect(_on_item_selected)
	health_page.add_child(body_tree)
	treatment_row = HBoxContainer.new()
	health_page.add_child(treatment_row)
	for action in ["bandage", "disinfectant", "antibiotic", "splint", "burn_dressing", "painkiller"]:
		var button := Button.new()
		button.text = action.capitalize().replace("_", " ")
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_request_treatment.bind(action))
		treatment_row.add_child(button)
	var character_page := VBoxContainer.new()
	character_page.name = "Skills & Traits"
	tabs.add_child(character_page)
	character_summary_label = Label.new()
	character_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_page.add_child(character_summary_label)
	skill_tree = Tree.new()
	skill_tree.columns = 4
	skill_tree.hide_root = true
	skill_tree.column_titles_visible = true
	skill_tree.custom_minimum_size = Vector2(900, 350)
	for index in range(4): skill_tree.set_column_title(index, ["Skill / attribute", "Level", "XP", "Starting XP rate"][index])
	skill_tree.set_column_expand(0, true)
	for index in range(1, 4): skill_tree.set_column_expand(index, false)
	character_page.add_child(skill_tree)
	trait_label = Label.new()
	trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_page.add_child(trait_label)

func refresh(game: MVPGameRoot) -> void:
	_game = game
	var state := game.player_state
	var character_data := state.character.to_save_data() if state.character != null else {}
	var signature := str(game.inventory.revision) + str(state.health) + str(state.body_health) + str(state.wounds) + str(character_data) + str([
		state.survival.hunger, state.survival.thirst, state.survival.fatigue, state.survival.stamina,
		state.pain, state.core_temperature, state.panic, state.stress, state.boredom, state.unhappiness])
	if signature == _last_signature: return
	_last_signature = signature
	var symptoms := " · Symptoms: %s" % state.symptom_text() if not state.symptom_text().is_empty() else ""
	summary_label.text = ("Health %.0f%% · Hunger %.0f · Thirst %.0f · Fatigue %.0f · Stamina %.0f\n" +
		"Pain %.0f · Temperature %.2f°C (%s) · Panic %.0f · Stress %.0f · Boredom %.0f · Unhappiness %.0f%s") % [
		state.health, state.survival.hunger, state.survival.thirst, state.survival.fatigue, state.survival.stamina,
		state.pain, state.core_temperature, temperature_label(state), state.panic, state.stress,
		state.boredom, state.unhappiness, symptoms]
	body_tree.clear()
	var root := body_tree.create_item()
	var warmth := state.clothing.warmth_by_region()
	for region in PlayerState.BODY_REGIONS:
		var row := body_tree.create_item(root)
		var data := region_data(game, region, warmth)
		row.set_text(0, region)
		row.set_text(1, "%.0f%% · %s" % [data["health"], data["status"]])
		row.set_text(4, "P %.0f%% · W %.1f%%" % [data["protection"], data["warmth"]])
		row.set_text(5, data["worn"])
		if data["injured"]: row.set_custom_color(1, Color(1.0, 0.48, 0.35))
		for wound in state.wounds_for_region(region):
			var injury := body_tree.create_item(row)
			injury.set_text(0, "↳ %s · severity %.0f" % [wound["type"], wound["severity"]])
			injury.set_text(1, treatment_status(wound))
			injury.set_text(2, "%.0f" % wound["bleeding"])
			injury.set_text(3, infection_status(wound))
			injury.set_metadata(0, wound["id"])
		row.collapsed = false
	_refresh_character_page(state)

func _refresh_character_page(state: PlayerState) -> void:
	skill_tree.clear()
	if state.character == null:
		character_summary_label.text = "Character progression is unavailable."
		trait_label.text = ""
		return
	var character := state.character
	var occupation := character.catalog.occupation(character.occupation_id)
	character_summary_label.text = "Occupation: %s · Unspent creation points: %d\nStrength and Fitness are physical attributes; needs and injuries remain on the Health tab." % [
		occupation.display_name, character.point_balance()]
	var root := skill_tree.create_item()
	var category_rows: Dictionary = {}
	for category in ["Attributes", "Combat", "Firearms", "Agility", "Crafting", "Survival", "Farming"]:
		var row := skill_tree.create_item(root)
		row.set_text(0, category)
		row.set_selectable(0, false)
		category_rows[category] = row
	var definitions: Array = character.catalog.skills.values()
	definitions.sort_custom(func(a: SkillDefinition, b: SkillDefinition) -> bool:
		return a.category < b.category or (a.category == b.category and a.display_name < b.display_name))
	for definition: SkillDefinition in definitions:
		var row := skill_tree.create_item(category_rows[definition.category])
		var level := int(character.skill_levels.get(definition.id, 0))
		var xp := float(character.skill_xp.get(definition.id, 0.0))
		var current_floor := CharacterProgression.total_xp_for_level(definition, level)
		var next_total := CharacterProgression.total_xp_for_level(definition, mini(level + 1, definition.max_level))
		row.set_text(0, definition.display_name)
		row.set_text(1, "%d / %d" % [level, definition.max_level])
		row.set_text(2, "MAX" if level >= definition.max_level else "%.0f / %.0f" % [xp - current_floor, next_total - current_floor])
		row.set_text(3, "—" if definition.physical_attribute else "×%.2f" % character.xp_multiplier(definition.id))
	var trait_names: Array[String] = []
	for trait_id in character.active_trait_ids():
		var definition := character.catalog.trait_definition(trait_id)
		if definition != null: trait_names.append(definition.display_name)
	trait_names.sort()
	trait_label.text = "Traits: %s" % (", ".join(trait_names) if not trait_names.is_empty() else "None")

func region_data(game: MVPGameRoot, region: String, warmth: Dictionary = {}) -> Dictionary:
	var garments := game.player_state.clothing.worn_for_region(region)
	var labels: Array[String] = []
	for entry in garments:
		var stack: ItemStack = entry["stack"]
		var unit: Dictionary = entry["unit"]
		labels.append("%s %.0f/%.0f" % [stack.definition.display_name,
			float(unit["clothing_durability"].get(region, 0)), float(stack.definition.clothing_max_durability.get(region, 0))])
	var wounds := game.player_state.wounds_for_region(region)
	var status := "Healthy" if wounds.is_empty() else "%d injury(s)" % wounds.size()
	return {"status": status, "injured": not wounds.is_empty(), "health": game.player_state.body_health[region],
		"protection": game.player_state.clothing.protection_percent(region),
		"warmth": float(warmth.get(region, game.player_state.clothing.warmth_by_region().get(region, 0.0))),
		"worn": ", ".join(labels) if not labels.is_empty() else "—"}

static func infection_status(wound: Dictionary) -> String:
	var value := float(wound["infection"])
	return "Severe %.0f" % value if value >= 50.0 else ("Infected %.0f" % value if value > 0.0 else "Clean")

func treatment_status(wound: Dictionary) -> String:
	var labels: Array[String] = []
	if float(wound["bleeding"]) > 0.0 and not wound["bandaged"]: labels.append("needs bandage")
	if float(wound["infection"]) > 0.0 and not wound["cleaned"]: labels.append("needs cleaning")
	if wound["type"] == "Fracture" and not wound["splinted"]: labels.append("needs splint")
	if wound["type"] == "Burn" and not wound["burn_dressed"]: labels.append("needs burn dressing")
	if wound["bandaged"]: labels.append("bandaged")
	if wound["cleaned"]: labels.append("cleaned")
	if wound["splinted"]: labels.append("splinted")
	if wound["burn_dressed"]: labels.append("dressed")
	if wound["healing"]: labels.append("healing")
	return ", ".join(labels) if not labels.is_empty() else "untreated"

func temperature_label(state: PlayerState) -> String:
	var tier := state.temperature_tier()
	if tier == 0: return "Stable"
	var direction := "Hot" if state.core_temperature > StatusConfig.NORMAL_BODY_TEMPERATURE else "Cold"
	return "%s %s" % [["", "Mild", "Moderate", "Severe", "Extreme"][tier], direction]

func _on_item_selected() -> void:
	var item := body_tree.get_selected()
	selected_wound_id = String(item.get_metadata(0)) if item != null and item.get_metadata(0) is String else ""

func _request_treatment(action: String) -> void:
	if _game == null: return
	var uid := _game.inventory.first_medical_action(action)
	if uid.is_empty():
		_game.show_notification("No %s available." % action.replace("_", " "))
		return
	_game.interactions.request_treatment(uid, selected_wound_id)
