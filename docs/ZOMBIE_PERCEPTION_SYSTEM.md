# Zombie Perception and Local Pressure

## Runtime model

The Orangeville MVP creates its finite zombie population once when the world is initialized. The authored cap remains seven. Death removes an actor permanently; neither elapsed time, noise nor area pressure can spawn a replacement. Migration assigns an existing idle zombie a reachable destination and lets the shared `LocalNavigation` move it there normally.

Visual, auditory and group observations are separate runtime states:

- A visible player or NPC updates an exact last-observed position. Loss of sight preserves only that position until visual memory expires.
- `NoiseStimulus` contains position, range, loudness, floor, type and world timestamp, but no actor reference. Hearing therefore cannot track an emitter after the event.
- Reaching an unreacquired visual or auditory location starts a short local search. Search ends against the unified world clock.
- A nearby zombie may receive the last observed position from another zombie. This is loose convergence only: there is no leader, formation, entity creation or global director.

Sight uses the existing light level, floor/stair state and `WorldMap.has_line_of_sight`. It adds a forward cone plus near-peripheral radius. Player and NPC nodes belong to the same `zombie_targets` group and pass through the same query. Sound continues to use `WorldMap.sound_cost`, including wall and stair attenuation.

Perception runs at an authored game-time interval. Migration runs at a much slower local interval. Pause freezes both; other speed modes advance them through `GameTime`.

## Static resources

`resources/zombie/world_rules.tres` stores the local sight, memory, search, migration and convergence tuning. `resources/zombie/areas/*.tres` stores stable area IDs, pressure, legal population points and real-map adjacency. `ZombieAreaCatalog` validates duplicate/missing references and stand points. `BuildingData.pressure` and tile pressure are initialized from these definitions rather than competing hard-coded values.

The numeric perception and migration defaults are project tuning values selected for this small map. They are not presented as undocumented Project Zomboid Build 42.21 constants.

Loaded resources remain immutable. Current awareness, last positions, deadlines, migration destination and the finite population ledger are runtime/save state. Save version 7 restores them without reseeding.

## Current limits

The map has open door tiles but no authored open/closed door or window state yet. Zombies only use existing legal navigation and cannot cross wall faces or unsupported floors; destruction and forced entry are not implemented. Actual closed-door/window behavior can only be tested after those barrier states exist.

The system is deliberately local: five authored Orangeville areas, no off-map simulation, respawn, factions, special infected or horde director.
