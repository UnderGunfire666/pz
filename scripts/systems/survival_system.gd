class_name SurvivalSystem
extends RefCounted

## All four values are reserves: 100 is healthy/rested/available.
var hunger := 100.0
var thirst := 100.0
var fatigue := 100.0
var stamina := 100.0


func advance(game_seconds: float, exertion: float = 0.0, resting: bool = false,
		overheating: float = 0.0, stamina_recovery_multiplier: float = 1.0) -> void:
	var game_hours := game_seconds / 3600.0
	hunger = clampf(hunger - game_hours * StatusConfig.HUNGER_PER_HOUR, 0.0, 100.0)
	thirst = clampf(thirst - game_hours * StatusConfig.THIRST_PER_HOUR * (1.0 + exertion * 0.35 + overheating * 0.5), 0.0, 100.0)

	if resting:
		fatigue = clampf(fatigue + game_hours * StatusConfig.SLEEP_RECOVERY_PER_HOUR, 0.0, 100.0)
		stamina = clampf(stamina + game_seconds * StatusConfig.STAMINA_RECOVERY_PER_SECOND * 2.5 * stamina_recovery_multiplier, 0.0, 100.0)
	else:
		fatigue = clampf(fatigue - game_hours * (StatusConfig.FATIGUE_PER_HOUR + exertion * StatusConfig.FATIGUE_EXERTION_PER_HOUR), 0.0, 100.0)
		var recovery := StatusConfig.STAMINA_RECOVERY_PER_SECOND * stamina_recovery_multiplier if exertion <= 0.05 else -StatusConfig.STAMINA_EXERTION_PER_SECOND * exertion * (1.0 + overheating)
		stamina = clampf(stamina + game_seconds * recovery, 0.0, 100.0)


func eat(nutrition: float) -> void:
	hunger = clampf(hunger + nutrition, 0.0, 100.0)


func drink(hydration: float) -> void:
	thirst = clampf(thirst + hydration, 0.0, 100.0)


func can_sprint() -> bool:
	return stamina > 10.0 and fatigue > 15.0
