class_name CharacterAppearance
extends RefCounted

const BASE := "res://assets/Universal Base Characters[Standard]/"
const HAIR := ["original", "Hair_SimpleParted", "Hair_Long", "Hair_BuzzedFemale", "Hair_Buzzed", "Hair_Buns"]
const MALE := BASE + "Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"
const FEMALE := BASE + "Base Characters/Godot - UE/Superhero_Female_FullBody.gltf"
var gender := "male"
var hair := "original"

func randomize(rng: RandomNumberGenerator) -> void:
	gender = "male" if rng.randi_range(0, 1) == 0 else "female"
	hair = HAIR[rng.randi_range(0, HAIR.size() - 1)]

func to_save_data() -> Dictionary:
	return {"gender": gender, "hair": hair}

func load_save_data(data: Dictionary) -> void:
	gender = data["gender"]
	hair = data["hair"]

static func valid(data: Variant) -> bool:
	return data is Dictionary and data.get("gender") in ["male", "female"] and data.get("hair") in HAIR

func model_profile() -> CharacterBodyProfile:
	var result := ActorBody.PLAYER.duplicate() as CharacterBodyProfile
	result.model_path = FEMALE if gender == "female" else MALE
	result.model_scale = 1.8 / (1.775051 if gender == "female" else 1.819586)
	result.model_offset = Vector3(0, (0.008407 if gender == "female" else 0.00951) * result.model_scale, 0)
	return result
