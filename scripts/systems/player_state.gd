class_name PlayerState
extends RefCounted

signal died()

const MAX_HEALTH := 100.0
var health := MAX_HEALTH

## Medical language is deliberately split:
## - wound infection is visible per wound and can be treated in a later system.
## - zombie-virus infection is hidden from the player-facing state/UI.
var survival := SurvivalSystem.new()
var traits := TraitSet.new()
var wounds: Array[Dictionary] = []
var zombie_virus_infection_progress := 0.0
var zombie_virus_exposure := false


func add_wound(
		wound_type: String,
		location: String,
		severity: float,
		from_zombie: bool = false
	) -> void:
	if is_dead():
		return
	wounds.append({
		"type": wound_type,
		"location": location,
		"severity": severity,
		"wound_infection": false,
	})
	health = maxf(0.0, health - severity * 100.0)
	if is_dead():
		died.emit()
	if from_zombie:
		zombie_virus_exposure = true
		# The prototype keeps probability deterministic. The value remains hidden.
		zombie_virus_infection_progress = maxf(zombie_virus_infection_progress, severity * 0.35)


func advance(game_seconds: float) -> void:
	if is_dead():
		return
	if survival.hunger <= 0.0 or survival.thirst <= 0.0:
		health = maxf(0.0, health - game_seconds / 1800.0)
		if is_dead():
			died.emit()
	if zombie_virus_exposure:
		zombie_virus_infection_progress = minf(1.0, zombie_virus_infection_progress + game_seconds / 172800.0)
	for wound in wounds:
		# Full wound treatment is intentionally outside this MVP. This only preserves
		# the separate, observable wound-infection field in the data model.
		if wound["wound_infection"] and game_seconds > 0.0:
			wound["severity"] = minf(1.0, float(wound["severity"]) + game_seconds / 360000.0)


func visible_wound_summary() -> String:
	if wounds.is_empty():
		return "No wounds"
	var wound: Dictionary = wounds.back()
	var infection_label := "infected" if wound["wound_infection"] else "clean"
	return "%s, %s (%s)" % [wound["type"], wound["location"], infection_label]


func is_dead() -> bool:
	return health <= 0.0
