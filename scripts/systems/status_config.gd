class_name StatusConfig
extends RefCounted

## Central tuning for player status gameplay. Rates use unified in-game seconds.
const HUNGER_PER_HOUR := 1.25
const THIRST_PER_HOUR := 2.0
const FATIGUE_PER_HOUR := 1.5
const FATIGUE_EXERTION_PER_HOUR := 2.5
const SLEEP_RECOVERY_PER_HOUR := 18.0
const STAMINA_RECOVERY_PER_SECOND := 0.035
const STAMINA_EXERTION_PER_SECOND := 0.09
const STARVATION_HEALTH_PER_HOUR := 2.0
const DEHYDRATION_HEALTH_PER_HOUR := 4.0
const HEALTH_RECOVERY_PER_HOUR := 0.6
const BLEED_HEALTH_PER_HOUR := 0.12
const INFECTION_HEALTH_PER_HOUR := 0.04
const BASE_HEALING_PER_HOUR := 0.35

const NORMAL_BODY_TEMPERATURE := 37.0
static var AMBIENT_TEMPERATURE := 20.0
const TEMPERATURE_CHANGE_PER_HOUR := 0.22
const TEMPERATURE_THRESHOLDS := [0.5, 1.0, 1.8, 2.7]
const STATUS_THRESHOLDS := [25.0, 50.0, 75.0]

const SLEEP_FATIGUE_THRESHOLD := 70.0
static var SLEEP_TIME_SCALE := 20.0
static var BITE_INFECTION_CHANCE := 1.0
static var SCRATCH_INFECTION_CHANCE := 0.07
static var VIRUS_LATENT_MIN_SECONDS := 7.0 * 86400.0
static var VIRUS_LATENT_MAX_SECONDS := 14.0 * 86400.0
const VIRUS_SYMPTOM_FRACTION := 0.8

const WOUND_TYPES := ["Scratch", "Laceration", "Bite", "Fracture", "Burn", "Deep Wound"]
const BLEEDING_FACTOR := {"Scratch": 0.25, "Laceration": 0.7, "Bite": 0.55, "Fracture": 0.0, "Burn": 0.15, "Deep Wound": 0.9}
const PAIN_FACTOR := {"Scratch": 0.35, "Laceration": 0.65, "Bite": 0.7, "Fracture": 1.0, "Burn": 0.9, "Deep Wound": 1.0}

const MONTHLY_AMBIENT_TEMPERATURES := [-7.5, -6.5, -2.1, 5.3, 11.7, 16.9, 19.4, 18.4, 14.3, 7.8, 2.0, -4.1]

static func ambient_temperature_at(game_seconds: float) -> float:
	var day := game_seconds / 86400.0
	var year_fraction := fposmod(day, 365.0) / 365.0 * 12.0
	var index := int(floor(year_fraction)) % 12
	var next := (index + 1) % 12
	return lerpf(MONTHLY_AMBIENT_TEMPERATURES[index], MONTHLY_AMBIENT_TEMPERATURES[next], year_fraction - floor(year_fraction))

static func severity_tier(value: float, inverse: bool = false) -> int:
	var severity := 100.0 - value if inverse else value
	if severity <= 0.0001: return 0
	if severity < STATUS_THRESHOLDS[0]: return 1
	if severity < STATUS_THRESHOLDS[1]: return 2
	if severity < STATUS_THRESHOLDS[2]: return 3
	return 4

## Warming retains the agreed 1 C/hour at 0 C, +/-2% per ambient degree.
## Cooling is a separate process: colder surroundings must not slow cooling.
static func item_temperature_after(current: float, environment: float, seconds: float) -> float:
	if seconds <= 0.0: return current
	var rate := maxf(0.0, 1.0 + environment * 0.02) if current < environment else 1.0 + maxf(0.0, -environment) * 0.02
	return move_toward(current, environment, rate * seconds / 3600.0)
