class_name PlayerState
extends RefCounted

signal died()
signal rags_requested(count: int)

const MAX_HEALTH := 100.0
const BODY_REGIONS := ["Head", "Torso", "Left Arm", "Right Arm", "Left Hand", "Right Hand",
	"Left Leg", "Right Leg", "Left Foot", "Right Foot"]

var health := MAX_HEALTH
var body_health := {"Head": 100.0, "Torso": 100.0, "Left Arm": 100.0, "Right Arm": 100.0,
	"Left Hand": 100.0, "Right Hand": 100.0, "Left Leg": 100.0, "Right Leg": 100.0,
	"Left Foot": 100.0, "Right Foot": 100.0}
var survival := SurvivalSystem.new()
var character: CharacterProgression
var wounds: Array[Dictionary] = []
var pain := 0.0
var pain_relief := 0.0
var panic := 0.0
var stress := 0.0
var boredom := 0.0
var unhappiness := 0.0
var core_temperature := StatusConfig.NORMAL_BODY_TEMPERATURE
var zombie_virus_exposure := false
var zombie_virus_deadline := -1.0
var head_destroyed := false
var _death_emitted := false
var inventory: InventoryGrid
var clothing: ClothingSystem
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func setup_inventory(value: InventoryGrid) -> void:
	inventory = value
	clothing = ClothingSystem.new(value)

func setup_character(catalog: CharacterCatalog) -> void:
	character = CharacterProgression.new()
	character.setup(catalog)

func receive_hit(wound_type: String, region: String, damage: float, from_zombie: bool = false,
		forced_roll: float = -1.0, forced_virus_roll: float = -1.0) -> Dictionary:
	region = canonical_region(region)
	var result := clothing.resolve_hit(region, damage, forced_roll) if clothing != null else {
		"player_damage": damage, "rag_count": 0, "protected": false}
	if int(result.get("rag_count", 0)) > 0: rags_requested.emit(result["rag_count"])
	var passed := float(result.get("player_damage", damage))
	if passed > 0.0: add_wound(wound_type, region, passed, from_zombie, forced_virus_roll)
	return result

func add_wound(wound_type: String, location: String, severity: float, from_zombie: bool = false,
		forced_virus_roll: float = -1.0) -> Dictionary:
	if is_dead(): return {}
	var region := canonical_region(location)
	var normalized_type := wound_type.capitalize()
	if normalized_type not in StatusConfig.WOUND_TYPES:
		normalized_type = "Laceration" if "cut" in wound_type.to_lower() else "Scratch"
	if severity <= 1.0: severity *= 100.0 # v4 compatibility
	severity = clampf(severity, 0.0, 100.0)
	var wound := {"id": ItemStack.new_uid(), "type": normalized_type, "region": region,
		"location": region, "severity": severity,
		"bleeding": severity * float(StatusConfig.BLEEDING_FACTOR.get(normalized_type, 0.25)),
		"infection": 0.0, "wound_infection": false, "bandaged": false, "cleaned": false,
		"splinted": false, "burn_dressed": false, "healing": false}
	wounds.append(wound)
	body_health[region] = maxf(0.0, float(body_health.get(region, 100.0)) - severity)
	if from_zombie: _try_virus_transmission(normalized_type, forced_virus_roll)
	_recalculate_pain()
	if region in ["Head", "Torso"] and body_health[region] <= 0.0: _kill()
	return wound

func _try_virus_transmission(wound_type: String, forced_roll: float = -1.0) -> void:
	var chance := StatusConfig.BITE_INFECTION_CHANCE if wound_type == "Bite" else (StatusConfig.SCRATCH_INFECTION_CHANCE if wound_type == "Scratch" else 0.0)
	if chance <= 0.0 or zombie_virus_exposure: return
	var roll := rng.randf() if forced_roll < 0.0 else clampf(forced_roll, 0.0, 1.0)
	if roll < chance:
		zombie_virus_exposure = true
		zombie_virus_deadline = GameTime.elapsed_game_seconds + rng.randf_range(StatusConfig.VIRUS_LATENT_MIN_SECONDS, StatusConfig.VIRUS_LATENT_MAX_SECONDS)

func advance(game_seconds: float, exertion: float = 0.0, sleeping: bool = false,
		nearby_zombies: int = 0, exploring: bool = false) -> void:
	if is_dead() or game_seconds <= 0.0: return
	var heat := maxf(0.0, float(temperature_tier(true)) / 4.0)
	survival.advance(game_seconds, exertion, sleeping, heat, stamina_recovery_multiplier())
	_advance_temperature(game_seconds, exertion)
	_advance_wounds(game_seconds, sleeping)
	_advance_emotions(game_seconds, nearby_zombies, exploring)
	_advance_virus()
	var hours := game_seconds / 3600.0
	var health_loss := 0.0
	if survival.hunger <= 0.0: health_loss += StatusConfig.STARVATION_HEALTH_PER_HOUR * hours
	if survival.thirst <= 0.0: health_loss += StatusConfig.DEHYDRATION_HEALTH_PER_HOUR * hours
	if temperature_tier() >= 4: health_loss += 3.0 * hours
	for wound in wounds:
		health_loss += float(wound["bleeding"]) * StatusConfig.BLEED_HEALTH_PER_HOUR * hours
		if float(wound["infection"]) >= 50.0: health_loss += float(wound["infection"]) * StatusConfig.INFECTION_HEALTH_PER_HOUR * hours
		if float(wound["infection"]) >= 100.0: health_loss = MAX_HEALTH
	if health_loss > 0.0:
		health = maxf(0.0, health - health_loss)
	elif survival.hunger >= 60.0 and survival.thirst >= 60.0 and pain < 60.0:
		health = minf(MAX_HEALTH, health + StatusConfig.HEALTH_RECOVERY_PER_HOUR * hours * (2.0 if sleeping else 1.0))
	if health <= 0.0: _kill()

func _advance_wounds(game_seconds: float, sleeping: bool) -> void:
	var hours := game_seconds / 3600.0
	pain_relief = maxf(0.0, pain_relief - hours * 8.0)
	for wound in wounds:
		_normalize_wound(wound)
		if not wound["bandaged"] and not wound["cleaned"]:
			wound["infection"] = minf(100.0, float(wound["infection"]) + hours * float(wound["severity"]) * 0.025)
		elif wound["cleaned"]:
			wound["infection"] = maxf(0.0, float(wound["infection"]) - hours * 0.5)
		wound["wound_infection"] = float(wound["infection"]) > 0.0
		var blocked: bool = (wound["type"] == "Fracture" and not wound["splinted"]) or (wound["type"] == "Burn" and not wound["burn_dressed"])
		wound["healing"] = not blocked and float(wound["bleeding"]) <= 0.0
		if wound["healing"]:
			var wellness := clampf((survival.hunger + survival.thirst + survival.fatigue + health) / 400.0, 0.2, 1.0)
			var healed := StatusConfig.BASE_HEALING_PER_HOUR * hours * wellness * maxf(0.1, 1.0 - float(wound["infection"]) / 125.0) * (1.5 if sleeping else 1.0)
			wound["severity"] = maxf(0.0, float(wound["severity"]) - healed)
			body_health[wound["region"]] = minf(100.0, float(body_health[wound["region"]]) + healed)
	wounds = wounds.filter(func(wound: Dictionary) -> bool: return float(wound["severity"]) > 0.0001)
	_recalculate_pain()

func _advance_temperature(game_seconds: float, exertion: float) -> void:
	var warmth := clothing.total_warmth() if clothing != null else 0.0
	var hours := game_seconds / 3600.0
	core_temperature += ((warmth - 100.0) / 100.0 + (StatusConfig.AMBIENT_TEMPERATURE - 20.0) * 0.02 + exertion * 0.7) * StatusConfig.TEMPERATURE_CHANGE_PER_HOUR * hours
	if absf(warmth - 100.0) < 0.001 and exertion <= 0.001:
		core_temperature = move_toward(core_temperature, StatusConfig.NORMAL_BODY_TEMPERATURE, StatusConfig.TEMPERATURE_CHANGE_PER_HOUR * hours)
	core_temperature = clampf(core_temperature, 30.0, 43.0)

func _advance_emotions(game_seconds: float, nearby_zombies: int, exploring: bool) -> void:
	var hours := game_seconds / 3600.0
	if nearby_zombies > 0:
		panic = minf(100.0, panic + hours * nearby_zombies * 80.0 * (1.0 + stress / 100.0))
		stress = minf(100.0, stress + hours * nearby_zombies * 18.0)
	else:
		panic = maxf(0.0, panic - hours * 35.0 * (1.0 - stress / 150.0))
		stress = maxf(0.0, stress - hours * 3.0)
	if late_virus_symptoms():
		stress = minf(100.0, stress + hours * 6.0)
		unhappiness = minf(100.0, unhappiness + hours * 2.0)
	boredom = maxf(0.0, boredom - hours * 24.0) if exploring else minf(100.0, boredom + hours * 2.0)
	unhappiness = clampf(unhappiness + hours * (maxf(0.0, boredom - 50.0) * 0.05 + maxf(0.0, pain - 60.0) * 0.04) - hours * 0.5, 0.0, 100.0)

func _advance_virus() -> void:
	if not zombie_virus_exposure or zombie_virus_deadline <= 0.0: return
	if GameTime.elapsed_game_seconds >= zombie_virus_deadline: _kill()

func treat_wound(wound_id: String, treatment: String) -> bool:
	if treatment == "painkiller":
		pain_relief = minf(100.0, pain_relief + 30.0)
		_recalculate_pain()
		return true
	var wound := wound_by_id(wound_id)
	if wound.is_empty(): return false
	match treatment:
		"bandage": wound["bandaged"] = true; wound["bleeding"] = 0.0
		"disinfectant": wound["cleaned"] = true; wound["infection"] = maxf(0.0, float(wound["infection"]) - 20.0)
		"antibiotic": wound["infection"] = maxf(0.0, float(wound["infection"]) - 35.0)
		"splint":
			if wound["type"] != "Fracture": return false
			wound["splinted"] = true
		"burn_dressing":
			if wound["type"] != "Burn": return false
			wound["burn_dressed"] = true
		_: return false
	wound["wound_infection"] = float(wound["infection"]) > 0.0
	return true

func wound_by_id(id: String) -> Dictionary:
	for wound in wounds:
		if wound.get("id", "") == id: return wound
	return {}

func movement_multiplier() -> float:
	var carry := 1.0 / (1.0 + 0.8 * inventory.encumbrance()) if inventory != null else 1.0
	var legs := (float(body_health["Left Leg"]) + float(body_health["Right Leg"]) + float(body_health["Left Foot"]) + float(body_health["Right Foot"])) / 400.0
	return carry * lerpf(0.3, 1.0, legs) * lerpf(0.5, 1.0, 1.0 - pain / 100.0) * temperature_performance()

func exertion_multiplier() -> float:
	return 1.0 + (2.0 * inventory.encumbrance() if inventory != null else 0.0)

func attack_performance() -> float:
	var arms := (float(body_health["Left Arm"]) + float(body_health["Right Arm"]) + float(body_health["Left Hand"]) + float(body_health["Right Hand"])) / 400.0
	return clampf(arms * lerpf(0.35, 1.0, 1.0 - pain / 100.0) * lerpf(0.4, 1.0, survival.stamina / 100.0) * (1.0 - panic * 0.004) * temperature_performance(), 0.15, 1.0)

func perception_multiplier() -> float:
	return lerpf(0.45, 1.0, float(body_health["Head"]) / 100.0)

func action_efficiency(kind: String = "") -> float:
	if kind in ["use", "sleep"]: return 1.0
	var effective_pain := maxf(0.0, pain - 25.0)
	return clampf(lerpf(0.5, 1.0, float(body_health["Torso"]) / 100.0) * (1.0 - effective_pain * 0.005) * (1.0 - unhappiness * 0.003) * temperature_performance(), 0.2, 1.0)

func stamina_recovery_multiplier() -> float:
	return clampf(float(body_health["Torso"]) / 100.0 * (1.0 - maxf(0.0, float(temperature_tier()) - 1.0) * 0.15), 0.2, 1.0)

func temperature_tier(overheating_only: bool = false) -> int:
	var delta := core_temperature - StatusConfig.NORMAL_BODY_TEMPERATURE
	if overheating_only and delta <= 0.0: return 0
	var magnitude := absf(delta)
	for index in range(StatusConfig.TEMPERATURE_THRESHOLDS.size()):
		if magnitude < StatusConfig.TEMPERATURE_THRESHOLDS[index]: return index
	return 4

func temperature_performance() -> float:
	return [1.0, 1.0, 0.9, 0.72, 0.5][temperature_tier()]

func late_virus_symptoms() -> bool:
	var symptom_window := StatusConfig.VIRUS_LATENT_MIN_SECONDS * (1.0 - StatusConfig.VIRUS_SYMPTOM_FRACTION)
	return zombie_virus_exposure and zombie_virus_deadline > 0.0 and GameTime.elapsed_game_seconds >= zombie_virus_deadline - symptom_window

func symptom_text() -> String:
	return "Fever · weakness" if late_virus_symptoms() else ""

func should_reanimate() -> bool:
	return is_dead() and zombie_virus_exposure and not head_destroyed

func destroy_head() -> void:
	head_destroyed = true
	body_health["Head"] = 0.0
	_kill()

func _kill() -> void:
	health = 0.0
	if not _death_emitted:
		_death_emitted = true
		died.emit()

func is_dead() -> bool:
	return health <= 0.0

func _recalculate_pain() -> void:
	var total := 0.0
	for wound in wounds: total += float(wound.get("severity", 0.0)) * float(StatusConfig.PAIN_FACTOR.get(wound.get("type", "Scratch"), 0.4))
	pain = clampf(total - pain_relief, 0.0, 100.0)

func visible_wound_summary() -> String:
	if wounds.is_empty(): return "No wounds"
	var wound: Dictionary = wounds.back()
	var infection := float(wound.get("infection", 0.0))
	var infection_label := "severe infection" if infection >= 50.0 else ("infected" if infection > 0.0 else "clean")
	return "%s, %s (%s)" % [wound["type"], wound["region"], infection_label]

func wounds_for_region(region: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for wound in wounds:
		_normalize_wound(wound)
		if wound["region"] == region: result.append(wound)
	return result

func canonical_region(location: String) -> String:
	var lower := location.to_lower()
	for region in BODY_REGIONS:
		if lower == region.to_lower(): return region
	if lower in ["face", "neck", "head"]: return "Head"
	if lower in ["chest", "abdomen", "back", "torso"]: return "Torso"
	if "left" in lower:
		if "hand" in lower: return "Left Hand"
		if "foot" in lower: return "Left Foot"
		if "leg" in lower or "thigh" in lower or "calf" in lower: return "Left Leg"
		return "Left Arm"
	if "hand" in lower: return "Right Hand"
	if "foot" in lower: return "Right Foot"
	if "leg" in lower or "thigh" in lower or "calf" in lower: return "Right Leg"
	return "Right Arm"

func _normalize_wound(wound: Dictionary) -> void:
	if not wound.has("id"): wound["id"] = ItemStack.new_uid()
	if not wound.has("region"): wound["region"] = canonical_region(wound.get("location", "Torso"))
	wound["location"] = wound["region"]
	var value := float(wound.get("severity", 0.0))
	if value <= 1.0: value *= 100.0
	wound["severity"] = clampf(value, 0.0, 100.0)
	var old_infection: Variant = wound.get("infection", wound.get("wound_infection", false))
	wound["infection"] = 1.0 if old_infection is bool and old_infection else (0.0 if old_infection is bool else clampf(float(old_infection), 0.0, 100.0))
	wound["wound_infection"] = float(wound["infection"]) > 0.0
	if not wound.has("bleeding"): wound["bleeding"] = float(wound["severity"]) * float(StatusConfig.BLEEDING_FACTOR.get(wound.get("type", "Scratch"), 0.25))
	for key in ["bandaged", "cleaned", "splinted", "burn_dressed", "healing"]:
		if not wound.has(key): wound[key] = false

func to_save_data() -> Dictionary:
	return {"body_health": body_health.duplicate(true), "wounds": wounds.duplicate(true), "pain": pain,
		"pain_relief": pain_relief, "panic": panic, "stress": stress, "boredom": boredom,
		"unhappiness": unhappiness, "core_temperature": core_temperature,
		"virus_infected": zombie_virus_exposure, "virus_deadline": zombie_virus_deadline,
		"head_destroyed": head_destroyed}

func load_save_data(data: Dictionary) -> void:
	body_health = data.get("body_health", body_health).duplicate(true)
	wounds.assign(data.get("wounds", []))
	for wound in wounds: _normalize_wound(wound)
	for key in ["pain", "pain_relief", "panic", "stress", "boredom", "unhappiness", "core_temperature"]: set(key, data.get(key, get(key)))
	zombie_virus_exposure = data.get("virus_infected", false)
	zombie_virus_deadline = data.get("virus_deadline", -1.0)
	head_destroyed = data.get("head_destroyed", false)
	_death_emitted = is_dead()
	_recalculate_pain()

static func valid_status_data(data: Variant) -> bool:
	if not data is Dictionary or not data.get("body_health") is Dictionary or not data.get("wounds") is Array: return false
	for region in BODY_REGIONS:
		var value: Variant = data["body_health"].get(region)
		if not (value is float or value is int) or float(value) < 0.0 or float(value) > 100.0: return false
	for key in ["pain", "pain_relief", "panic", "stress", "boredom", "unhappiness"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or float(value) < 0.0 or float(value) > 100.0: return false
	if not (data.get("core_temperature") is float or data.get("core_temperature") is int): return false
	if not data.get("virus_infected") is bool or not data.get("head_destroyed") is bool: return false
	if not (data.get("virus_deadline") is float or data.get("virus_deadline") is int): return false
	for wound in data["wounds"]:
		if not wound is Dictionary or not wound.has_all(["id", "type", "region", "severity", "bleeding", "infection"]): return false
		if wound["region"] not in BODY_REGIONS or wound["type"] not in StatusConfig.WOUND_TYPES: return false
		for key in ["severity", "bleeding", "infection"]:
			if not (wound[key] is float or wound[key] is int) or float(wound[key]) < 0.0 or float(wound[key]) > 100.0: return false
	return true
