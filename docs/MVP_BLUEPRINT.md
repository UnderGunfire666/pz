# Godot 4.7.2 MVP Blueprint — Afterlight: Orangeville

## Outcome and scope

Build a small, single-player, oblique top-down survival sandbox set in an Orangeville-inspired neighbourhood at the beginning of an outbreak. The first playable build proves a cautious loop: enter a safehouse, scavenge food, suffer a light wound, use sight and sound to avoid zombies, return to rest, and continue exploring.

The differentiator is an individual-survivor NPC simulation, but it is fifth in MVP priority. The player’s survival pressure and readable environment must be solid before the NPC layer grows.

This repository implements a greybox version of that loop. It intentionally uses procedural 3D meshes and compact data objects so a solo developer can validate feel before investing in art assets, animation, complex UI, or a large map.

## Product decisions

- Engine: Godot 4.7.2, Windows-first, single player.
- Presentation: a procedural 3D world over a logical 2D simulation grid. The oblique orbit camera supports middle-mouse rotation; multi-storey buildings cull geometry outside the player's active floor.
- Time: one in-game day per real-time hour at normal speed; pause and 3× fast-forward use a simulation scale rather than freezing the HUD.
- Zombies: ordinary zombies only. Rural/road cells are low pressure; the grocery is high pressure. No special variants or global horde simulation.
- Perception: distance + wall-face line of sight + ambient light first; player vision uses a facing fan plus a small omnidirectional near-field radius. Entities outside that view are not rendered.
- Medical terminology: **wound infection** is an observable field on an individual wound. **Zombie-virus infection** is a separate hidden state. The UI must never use the former term to reveal the latter.

## Recommended project layout

```text
res://
├── scenes/
│   └── main.tscn                    # first-playable composition root
├── scripts/
│   ├── actors/
│   │   ├── player_controller.gd
│   │   ├── zombie.gd
│   │   └── survivor_npc.gd
│   ├── data/
│   │   ├── world tile, building, room, trait data
│   │   └── item, stack, container data
│   ├── game/game_root.gd
│   ├── systems/
│   │   ├── game_time.gd, noise_bus.gd, visibility_system.gd
│   │   ├── survival_system.gd, player_state.gd
│   │   ├── inventory_grid.gd, interaction_system.gd, npc_brain.gd
│   ├── ui/mvp_hud.gd
│   └── world/world_map.gd, zombie_spawner.gd
├── tests/mvp_smoke_test.tscn
└── docs/MVP_BLUEPRINT.md
```

When content production begins, replace hard-coded `WorldTileData` and item definitions with `.tres` resources or imported map data. Keep runtime systems consuming interfaces/query methods rather than direct scene paths.

## Core scene and node hierarchy

The current `main.tscn` starts small and composes the greybox runtime in `MVPGameRoot`:

```text
Autoloads
├── GameTime                 # clock, pause/normal/fast simulation scale
└── NoiseBus                 # decoupled sound events

AfterlightMVP (MVPGameRoot)
├── WorldMap                 # logical tiles, buildings, LOS and pressure data
├── World3DViewport          # procedural 3D terrain, floors, walls, actors and orbit camera
├── Actors
│   ├── Player               # PlayerController
│   ├── Zombie*              # ZombieActor instances from pressure seed
│   └── SurvivorNPC          # one autonomous B-level survivor
├── VisibilitySystem
├── InteractionSystem        # search, rest, hazard, sorting duration
├── ZombieSpawner
└── HUD
```

Split this later into `world.tscn`, `player.tscn`, `zombie.tscn`, `survivor_npc.tscn`, and reusable interaction scenes only after the greybox contracts stabilize. Premature scene fragmentation is not valuable for this MVP.

## Runtime data flow

```text
Input ──> PlayerController ──> NoiseBus ──> zombies / NPC
   │              │
   │              └──> PlayerState + SurvivalSystem
   │
   └──> InteractionSystem ──> InventoryGrid / ContainerData / rest

GameTime ──> player survival, NPC needs, zombies, search/rest durations
WorldMap ──> LOS + pressure + ambient light ──> VisibilitySystem
VisibilitySystem ──> map darkening + zombie/NPC hidden state
```

This is intentionally event/query based. For example, a zombie hears a `NoiseBus` event rather than reaching into player code; later firearms, alarms, or NPC actions can emit the same event.

## Core classes and contracts

| Area | Classes | MVP responsibility | Deliberately deferred |
| --- | --- | --- | --- |
| Player | `PlayerController`, `PlayerState` | WASD motion, RMB mouse-facing aim, directional melee, state ownership | animation tree, weapon families, multiplayer prediction |
| World | `WorldMap`, `WorldTileData`, `BuildingData`, `RoomData`, `World3DView` | grid queries, procedural 3D geometry, ramp traversal, floor culling, camera orbit, collision, LOS, safehouse and pressure/stress metadata | streaming map, navmesh bake, full Orangeville import |
| Visibility | `VisibilitySystem` | fan FOV, lighting-adjusted range, dark/grey unknown map, hide NPC/zombies outside FOV | movement/stance/eye-condition modifiers, multiplayer visibility |
| Zombies | `ZombieSpawner`, `ZombieActor` | density by local pressure, ordinary chase, visual/noise response, basic melee threat | migration simulation, meta-population, variants, large-horde optimisation |
| Items | `ItemDefinition`, `ItemStack`, `ContainerData`, `InventoryGrid` | grid footprint, weight cap, container contents, tag consumption, sorting API | drag UI, equipment paper doll, crafting, nested containers |
| Survival | `SurvivalSystem` | hunger, thirst, fatigue, stamina; rest/eat/drink effects | full health panel and body-part treatment |
| NPC | `SurvivorNPC`, `NPCBrain`, `TraitSet` | needs, danger check, flee/rest/scavenge goal, shared traits, local memory/relationship save hooks | factions, rumours, settlements, global social simulation |
| Interaction | `InteractionSystem` | nearby search/rest, deliberate search duration, known-content shortcut, glass hazard | generic action UI, locking, full looting UX |

### Medical-state boundary

`PlayerState.wounds` stores wound type, location, severity, and `wound_infection`. The HUD is allowed to show, for example, `Glass cut, left calf (clean)` and later `(... infected)`.

`zombie_virus_exposure` and `zombie_virus_infection_progress` are separate internal fields. A zombie scratch can set exposure, but no player-facing display exposes the virus state. Full body parts, treatment, bite lethality tuning, latent-infection progression, and reanimation belong to a later medical slice.

## MVP implementation order

1. **Movement, vision, noise, attacks** — complete first. If aiming, facing, FOV hiding, LOS, and noise do not feel tense, do not add more content.
2. **Survival and time** — hunger, thirst, fatigue, stamina, rest, pause, normal speed, and fast-forward must all advance consistently.
3. **Map pressure** — a compact block with rural/residential/commercial metadata, a safehouse, and a high-pressure grocery.
4. **Inventory and looting** — grid size, carry weight, containers, search/sort time cost, and simple food/water consumption.
5. **One autonomous NPC** — urgent needs → local threat assessment → flee, rest, or scavenge; preserve trait/memory/relationship hooks.

The checked-in prototype follows this order. It does not hide the fact that visual content, UI polish, and long-session balancing remain future work.

## Solo-developer roadmap

| Milestone | Scope | Exit criterion |
| --- | --- | --- |
| 0. Greybox foundation (2–4 days) | current map, controls, FOV, time, HUD | player can traverse and read the space without art assets |
| 1. Combat/perception feel (1–2 weeks) | hit timing, zombie pathing, basic sound occlusion, tuning tools | a group of 1–3 zombies is manageable; a cluster is scary |
| 2. Survival/loot vertical slice (1–2 weeks) | clear inventory panel, containers, food/water, rest, saves | the full loop survives save/load and is understandable without developer notes |
| 3. NPC vertical slice (2–3 weeks) | one to five persistent NPCs, local memory, traits, claimed-home logic | NPCs independently satisfy needs and react believably to a nearby threat |
| 4. Content pass (2–4 weeks) | one polished neighbourhood, audio, tiles, UI/art pass, balance | 20–30 minute repeatable first-playable session |
| 5. Early-access hardening | options, telemetry/debug tools, save migration, performance pass | feature freeze on core loop before wider map/content expansion |

These are sequencing estimates, not commitments; finish each exit criterion before moving down the list. Keep debug overlays for FOV, pressure, NPC goal, sound radius, and path intent from day one.

## Explicitly out of scope for this MVP

- Multiplayer/co-op implementation or networking architecture beyond clean ownership boundaries.
- Colony simulation, factions, leadership, settlements, broad reputation, rumours, or a world-scale social graph.
- D-level world evolution, global event director, guaranteed scripted outbreak arc, or a mandatory campaign.
- Full body-part injuries, wound treatment, visible zombie-virus diagnosis, advanced reanimation, and medical crafting.
- Special zombies, boss encounters, elaborate migration, and high-scale horde simulation.
- Large-map streaming, production Orangeville geography, vehicles, farming, electricity/water utilities, crafting depth, or mod support.
- Final grid drag/drop UX, equipment slots, deep nested containers, and full item taxonomy.

## First playable launch plan

Package only the compact neighbourhood and verify the following before sharing a build:

- Start outside the safehouse at outbreak morning; no forced story sequence is required.
- Enter the house, reach the grocery, search food, trigger the light glass wound, see/avoid zombies, rest at home, then leave again.
- RMB changes facing to the mouse; standard facing follows motion; actor visibility obeys the fan FOV.
- MMB drag rotates the 3D camera; walkable ramps connect floors, and only the player's current floor is rendered.
- A melee strike creates a basic sound event and nearby zombies/NPCs react only through the common noise path.
- Pause, normal, and fast-forward affect clock, NPC/zombie thinking, search/rest durations, and needs consistently.
- Grocery pressure visibly produces more ordinary zombies than rural/residential space.
- A wound display can distinguish clean from wound-infected injuries without disclosing zombie-virus infection.
- Run `tests/mvp_smoke_test.tscn` headlessly and manually complete the route once at normal speed and once with fast-forward.

If any criterion fails, fix the vertical slice rather than adding map size or social systems.
