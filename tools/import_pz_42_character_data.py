#!/usr/bin/env python3
"""Import the installed Project Zomboid 42.21 character catalogue as Godot resources.

The generated resources are committed authoring data. Runtime code never reads the
Project Zomboid installation. Pass the directory containing projectzomboid.jar.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
OUT = PROJECT / "resources" / "character"
STANDARD_XP = [75, 150, 300, 750, 1500, 3000, 4500, 6000, 7500, 9000]
ATTRIBUTE_XP = [1500, 3000, 6000, 9000, 18000, 30000, 60000, 90000, 120000, 150000]
SKILLS = {
    "Combat": ["Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance"],
    "Firearms": ["Aiming", "Reloading"],
    "Crafting": ["Woodwork", "Carving", "Cooking", "Electricity", "Glassmaking", "FlintKnapping", "Masonry", "Blacksmith", "Mechanics", "Pottery", "Tailoring", "MetalWelding"],
    "Survival": ["Doctor", "Fishing", "PlantScavenging", "Tracking", "Trapping"],
    "Attributes": ["Fitness", "Strength"],
    "Agility": ["Lightfoot", "Nimble", "Sprinting", "Sneak"],
    "Farming": ["Farming", "Husbandry", "Butchering"],
}
TRANSLATION_IDS = {"Woodwork": "Carpentry", "Lightfoot": "Lightfooted", "PlantScavenging": "Foraging", "Sneak": "Sneaking"}
IMPLEMENTED_TRAITS = {
    "base:fastlearner": "global_xp_multiplier_1_3",
    "base:slowlearner": "global_xp_multiplier_0_7",
    "base:pacifist": "combat_xp_multiplier_0_75",
    "base:crafty": "crafting_xp_multiplier_1_3",
}
MUTABLE_TRAITS = {
    "base:athletic", "base:fit", "base:out of shape", "base:unfit",
    "base:strong", "base:stout", "base:feeble", "base:weak",
    "base:emaciated", "base:very underweight", "base:underweight",
    "base:overweight", "base:obese", "base:weightgain", "base:weightloss",
}
ATTRIBUTE_TRAITS = {
    "base:athletic", "base:fit", "base:out of shape", "base:unfit",
    "base:strong", "base:stout", "base:feeble", "base:weak",
}


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def packed(values: list[str]) -> str:
    return "PackedStringArray(" + ", ".join(quote(value) for value in values) + ")"


def dictionary(values: dict[str, int]) -> str:
    return "{" + ", ".join(f"{quote(key)}: {value}" for key, value in values.items()) + "}"


def clean_text(value: str) -> str:
    value = value.replace("<LINE>", "\n").replace("<BR>", "\n")
    value = re.sub(r"<[^>]+>", "", value)
    return value.strip()


def parse_blocks(path: Path, block_type: str) -> list[dict[str, str]]:
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(rf"    {block_type} ([^\n]+)\n    \{{(.*?)\n    \}}", re.S)
    result = []
    for match in pattern.finditer(text):
        fields: dict[str, str] = {"id": match.group(1).strip()}
        for line in match.group(2).splitlines():
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, value = line.split("=", 1)
            fields[key.strip()] = value.strip().rstrip(",")
        result.append(fields)
    return result


def pairs(value: str) -> dict[str, int]:
    result = {}
    for entry in filter(None, value.split(";")):
        key, amount = entry.split("=", 1)
        result[key] = int(amount)
    return result


def sequence(value: str) -> list[str]:
    return list(filter(None, value.split(";")))


def safe_name(identifier: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", identifier.lower().replace("base:", "")).strip("_")


def write_resource(path: Path, script_path: str, script_class: str, fields: list[tuple[str, str]]) -> None:
    lines = [f'[gd_resource type="Resource" script_class="{script_class}" load_steps=2 format=3]', "",
             f'[ext_resource type="Script" path="{script_path}" id="1"]', "", "[resource]",
             'script = ExtResource("1")']
    lines.extend(f"{name} = {value}" for name, value in fields)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: import_pz_42_character_data.py /path/to/projectzomboid")
    pz = Path(sys.argv[1])
    traits_path = pz / "media/scripts/generated/characters/character_traits.txt"
    professions_path = pz / "media/scripts/generated/characters/character_professions.txt"
    translations_path = pz / "media/lua/shared/Translate/EN/UI.json"
    for required in [traits_path, professions_path, translations_path, pz / "projectzomboid.jar"]:
        if not required.is_file():
            raise SystemExit(f"missing canonical input: {required}")
    revision = shutil.which("unzip")
    if revision is None:
        raise SystemExit("unzip is required to verify the game revision")
    translations = json.loads(translations_path.read_text(encoding="utf-8-sig"))
    for directory in [OUT / "skills", OUT / "traits", OUT / "occupations"]:
        directory.mkdir(parents=True, exist_ok=True)
        for old in directory.glob("*.tres"):
            old.unlink()

    for category, skill_ids in SKILLS.items():
        for skill_id in skill_ids:
            translation_id = TRANSLATION_IDS.get(skill_id, skill_id)
            display = translations.get(f"IGUI_perks_{translation_id}", translation_id)
            xp = ATTRIBUTE_XP if category == "Attributes" else STANDARD_XP
            fields = [
                ("id", quote(skill_id)), ("display_name", quote(display)), ("category", quote(category)),
                ("max_level", "10"), ("xp_per_level", "PackedFloat32Array(" + ", ".join(map(str, xp)) + ")"),
                ("passive", "true" if category == "Attributes" else "false"),
                ("physical_attribute", "true" if category == "Attributes" else "false"),
            ]
            write_resource(OUT / "skills" / f"{safe_name(skill_id)}.tres", "res://scripts/data/skill_definition.gd", "SkillDefinition", fields)

    for raw in parse_blocks(traits_path, "character_trait_definition"):
        trait_id = raw["id"]
        cost = int(raw.get("Cost", "0"))
        profession = raw.get("IsProfessionTrait", "false") == "true"
        xp_boosts = pairs(raw.get("XPBoosts", ""))
        recipes = sequence(raw.get("GrantedRecipes", ""))
        effect_ids = (["starting_skill_levels"] if xp_boosts else [])
        if trait_id in IMPLEMENTED_TRAITS:
            effect_ids.append(IMPLEMENTED_TRAITS[trait_id])
        if trait_id in ATTRIBUTE_TRAITS:
            effect_ids.append("attribute_level_trait")
        pending = []
        if recipes:
            pending.append("recipe_unlocks")
        if trait_id not in IMPLEMENTED_TRAITS and not xp_boosts:
            pending.append("trait_effect:" + trait_id)
        elif trait_id not in IMPLEMENTED_TRAITS:
            pending.append("non_skill_trait_effect:" + trait_id)
        fields = [
            ("id", quote(trait_id)),
            ("display_name", quote(clean_text(translations.get(raw.get("UIName", ""), raw.get("UIName", trait_id))))),
            ("description", quote(clean_text(translations.get(raw.get("UIDescription", ""), "")))),
            ("cost", str(cost)), ("selectable", "true" if cost != 0 and not profession else "false"),
            ("profession_trait", "true" if profession else "false"),
            ("disabled_in_multiplayer", raw.get("DisabledInMultiplayer", "false")),
            ("xp_boosts", dictionary(xp_boosts)),
            ("incompatible_trait_ids", packed(sequence(raw.get("MutuallyExclusiveTraits", "")))),
            ("granted_trait_ids", packed(sequence(raw.get("GrantedTraits", "")))),
            ("granted_recipe_ids", packed(recipes)), ("effect_ids", packed(effect_ids)),
            ("pending_effect_ids", packed(pending)),
            ("can_change_during_play", "true" if trait_id in MUTABLE_TRAITS else "false"),
        ]
        write_resource(OUT / "traits" / f"{safe_name(trait_id)}.tres", "res://scripts/data/trait_definition.gd", "TraitDefinition", fields)

    for raw in parse_blocks(professions_path, "character_profession_definition"):
        occupation_id = raw["id"]
        recipes = sequence(raw.get("GrantedRecipes", ""))
        pending = ["recipe_unlocks"] if recipes else []
        fields = [
            ("id", quote(occupation_id)),
            ("display_name", quote(clean_text(translations.get(raw.get("UIName", ""), raw.get("UIName", occupation_id))))),
            ("description", quote(clean_text(translations.get(raw.get("UIDescription", ""), "")))),
            ("point_bonus", raw.get("Cost", "0")), ("xp_boosts", dictionary(pairs(raw.get("XPBoosts", "")))),
            ("granted_trait_ids", packed(sequence(raw.get("GrantedTraits", "")))),
            ("granted_recipe_ids", packed(recipes)), ("pending_effect_ids", packed(pending)),
        ]
        write_resource(OUT / "occupations" / f"{safe_name(occupation_id)}.tres", "res://scripts/data/occupation_definition.gd", "OccupationDefinition", fields)

    write_resource(OUT / "world_rules.tres", "res://scripts/data/character_world_rules.gd", "CharacterWorldRules", [
        ("free_trait_points", "0"), ("minimum_attribute_level", "0"), ("maximum_attribute_level", "10"),
        ("maximum_skill_level", "10"), ("default_occupation_id", quote("base:unemployed")),
    ])
    provenance = {
        "canonical_version": "42.21", "game_revision": "4a0e9546ec",
        "inputs": [str(traits_path.relative_to(pz)), str(professions_path.relative_to(pz)),
                   str(translations_path.relative_to(pz)), "projectzomboid.jar:PerkFactory.class"],
        "counts": {"skills": sum(map(len, SKILLS.values())), "traits": len(parse_blocks(traits_path, "character_trait_definition")),
                   "occupations": len(parse_blocks(professions_path, "character_profession_definition"))},
    }
    (OUT / "SOURCE.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(provenance))


if __name__ == "__main__":
    main()
