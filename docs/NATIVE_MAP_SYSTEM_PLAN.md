# Native map system implementation plan

## Confirmed integration points

- `scripts/world/world_map.gd` is the simulation authority for tiles, wall
  segments, stairs, navigation, area pressure and floor support.
- Runtime coordinates are logical `Vector2(x, y)` and `floor_level`; visual
  coordinates are `Vector3(x, elevation, y)`.
- `World3DView` creates independent floor, wall, roof and stair meshes from
  `WorldMap`, which is compatible with the existing building visibility system.
- `QuickSave` stores mutable actor, container, exploration and interaction
  state only. Static map content must stay outside it.
- The former 18 × 14 block has been migrated to the 64 × 64 typed Orangeville
  resource. `WorldMap` remains the runtime adapter and simulation authority.

## Delivery slices

1. Add typed `Resource` map definitions, a 64 × 64 cell resource and shared
   logical-to-world conversion. Load the current playable block from a map
   resource, retaining the existing runtime `FloorData` and systems as an
   adapter boundary.
2. Add static building, wall-edge, stair and spawn resources; make the sample
   map fully resource-authored and preserve the current multi-floor gameplay.
3. Add a native EditorPlugin shell with map selection, cell/layer/level tools,
   inspection, undo/redo and a 3D preview that uses the same adapter.
4. Add templates, room validation, roads, vegetation and semantic overlays.
5. Add validation, playtest launch and data-only mod manifests/packages.

## Static package boundary

- `MapModManifest` names a static package, version, dependencies and the map
  resource paths it contributes. It never contains actors, containers,
  exploration, doors or other mutable session data.
- `MapModRegistry.resolve_load_order()` validates stable IDs, missing
  dependencies and cycles, then produces deterministic dependency-first order.
- `resources/maps/mods/orangeville_base_mod.tres` is the initial base-content
  package. Discovery from user folders is intentionally deferred until a
  sandboxed package policy exists.

The first slice changes static authoring only. Doors, broken objects, moved
items, actors and exploration remain runtime/save data under `QuickSave`.

## Spatial queries

Simulation broad-phase queries use a four-tile spatial hash separated by floor.
Walls crossing several cells are deduplicated before exact tests, so sound
attenuation remains unchanged. Stair footprints are indexed on both landing
floors. FOV queries nearby walls once and reuses that set across its ray fan.
Map loads rebuild the index before navigation; `_add_wall` and `_add_stair`
invalidate it for lazy rebuilding. Bulk direct edits to `FloorData.wall_faces`
or the stair dictionary must call `rebuild_spatial_index()` explicitly. Rebuilding
the query index does not rebuild navigation or render geometry.

Navigation first creates the walkable nodes for every authored floor, then
connects each grid node once. This preserves the same within-floor edges and
explicit stair links while avoiding repeated scans of already completed floors
during multi-floor map loading.

## Save compatibility

Schema v8 binds saves to the map ID, format version and a deterministic hash of
exported static content, including nested terrain and building templates. A
mismatch is rejected before changing the live world. Exploration keys must
reference existing supported tiles and floors. The active runtime currently
loads one map resource, not a composed mod stack; that stack must become part of
the identity when runtime mod composition is introduced.

Versions 3–7 have no reliable historical content fingerprint. Their migration
assumes the bundled Orangeville map and still validates coordinates and state;
it cannot prove which historical edit of that map produced the save. New saves
use `afterlight_mvp_v8.save`, leaving older slots available as fallback.
