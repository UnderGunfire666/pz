class_name SurvivalSystem
extends RefCounted

## Values are intentionally small and readable for the first playable build.
## Hunger/thirst/stamina are reserves (100 is good); fatigue is accumulated tiredness.
var hunger := 88.0
var thirst := 84.0
var fatigue := 12.0
var stamina := 100.0


func advance(game_seconds: float, exertion: float = 0.0, resting: bool = false) -> void:
	var game_hours := game_seconds / 3600.0
	hunger = clampf(hunger - game_hours * 2.2, 0.0, 100.0)
	thirst = clampf(thirst - game_hours * 3.4, 0.0, 100.0)

	if resting:
		fatigue = clampf(fatigue - game_hours * 24.0, 0.0, 100.0)
		stamina = clampf(stamina + game_seconds * 0.09, 0.0, 100.0)
	else:
		fatigue = clampf(fatigue + game_hours * (1.3 + exertion), 0.0, 100.0)
		var recovery := 0.035 if exertion <= 0.05 else -0.09 * exertion
		stamina = clampf(stamina + game_seconds * recovery, 0.0, 100.0)


func eat(nutrition: float) -> void:
	hunger = clampf(hunger + nutrition, 0.0, 100.0)


func drink(hydration: float) -> void:
	thirst = clampf(thirst + hydration, 0.0, 100.0)


func can_sprint() -> bool:
	return stamina > 10.0 and fatigue < 85.0
