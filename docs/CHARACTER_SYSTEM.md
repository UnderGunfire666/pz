# Character System

The player character model is split into three layers:

- Immutable authoring data: individual typed resources under `resources/character/`.
- Runtime progression: `CharacterProgression`, referenced by `PlayerState.character`.
- Temporary survival condition: the existing `SurvivalSystem` and `PlayerState` health, wounds, pain, temperature, and emotions.

## Canonical data

The catalog was imported from the locally installed Project Zomboid 42.21 Stable data, revision `4a0e9546ec`:

- `media/scripts/generated/characters/character_traits.txt`
- `media/scripts/generated/characters/character_professions.txt`
- `media/lua/shared/Translate/EN/UI.json`
- `projectzomboid.jar`, `PerkFactory.class` and `IsoGameCharacter$XP.class`

`resources/character/SOURCE.json` records the version, revision, inputs, and counts. The importer is `tools/import_pz_42_character_data.py`; it is an authoring tool and is never used at runtime.

The imported catalog contains 35 skill definitions (including Strength and Fitness as separately flagged physical attributes), 25 occupations, and 97 traits. Of the traits, 81 are selectable and 16 are free occupation traits.

## Implemented rules

- Default sandbox free trait points: 0.
- Custom Occupation point bonus: 8.
- Positive and negative trait costs, including balances above the initial budget.
- Trait mutual exclusions, including occupation-granted traits.
- Occupation and trait starting skill/attribute levels without double charging granted traits.
- Ten-level regular and passive-attribute XP curves from 42.21.
- Starting-skill XP factors and verified Fast Learner, Slow Learner, Pacifist, and Crafty multipliers.
- Strength/Fitness level traits update from the authoritative current level: 0–1 Weak/Unfit, 2–4 Feeble/Out of Shape, 5 none, 6–8 Stout/Fit, and 9–10 Strong/Athletic.
- Versioned runtime save data containing only occupation/trait IDs and mutable level/XP values.

## Pending integrations

Every unsupported effect has a `pending_effect_ids` entry in its `.tres`. Recipe/knowledge unlocks are retained as stable IDs but remain inactive because this project has no recipe system. Strength/Fitness level-trait transitions are active. Weight-driven trait transitions remain marked `can_change_during_play` but inactive until the project has an authoritative nutrition/weight system; other traits are not generally learnable or removable.

Combat, movement, foraging, vehicles, hearing, sleep, illness, nutrition, panic, transfer speed, healing, and other detailed trait effects are not approximated. They must be connected only after their exact 42.21 behavior and matching local gameplay system are available.
