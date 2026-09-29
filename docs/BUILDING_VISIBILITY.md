# Building visibility and local occlusion

The logical player is `PlayerController` (Node2D); `World3DView` supplies its 3D
representation and orthographic camera. `WorldMap` owns building membership,
floor support and stair progress. Visibility never modifies that simulation.

At startup the existing independent meshes are registered and reparented under:

```text
World3DView
  <building>_Visibility (BuildingVisibilityController)
    Floor_01 (BuildingFloor)
      floor meshes, wall meshes, stair geometry
    Floor_02 ...
    roof mesh
```

`BuildingFloor` owns its geometry and caches `OccludableWall` handles. Controllers
expose `set_active_floor(index)`, `set_cutaway(enabled)` and `update_local_view`.
Floors are zero-indexed, matching WorldMap. Mesh transforms and original wall/roof
visibility are preserved; no materials are made transparent.

The view handles local-player movement events and camera orbit changes. A small
context comparison per frame also catches teleport/load and stair state changes.
Changed context uses the map's constant-time tile lookup. `BuildingOcclusionSystem`
queries an 8-unit spatial hash along the camera corridors for the player and
currently visible contents, updating nearby blocked
buildings/props and restoring previously blocked objects. There are no city-wide
frame scans, physics raycasts or NPC visibility inputs. `player_building_changed`,
`player_display_floor_changed` and controller `state_changed` expose transitions.
Area3D is unnecessary for the current logical movement architecture.

Interior mode hides the roof and parents of all floors above the displayed floor.
Lower floors remain rendered. A wall is cut when the player and camera
direction are on opposite sides of its plane, or when it obstructs currently
visible contents. The plane-side check keeps rear wall segments
visible even when the player stands near a corner. The earlier diagonal-depth
test could incorrectly remove far lateral segments of rear walls. Camera orbit
updates the plane-side rule without raycasting. Cached planes/bounds assume
static geometry.

Display floor changes at stair midpoint in both directions. Exiting restores
the architectural shell's original visibility, including direct moves
between buildings and load/teleport. Room-content privacy remains independent.

Room content is authorized by `WorldTileData.room_id`: indoor targets are only
revealed in the player's current room. This applies even through open doorways,
after exploration, and when exterior walls/roofs are cut away. Actors, health
bars, interaction markers and interaction prompts cannot disclose other rooms.
`BuildingFloor` masks foreign-room floors with an opaque neutral material and
hides static interior contents such as stairs. The active stair remains visible
during traversal. The current demo assigns one room per building floor; future
room layouts must give their tiles and registered static parts distinct IDs.

On FOV revision, the view intersects the actual wall-clipped visibility polygon
with allowed floor tiles and caches small content volumes. Unseen rooms never
produce targets. Building cutaway checks these volumes as well as the player's
body; turning the player can therefore change wall visibility without movement.
This does not extend gameplay LOS through hidden walls. Volume bounds are
conservative, with wall-contact insets and plane checks to preserve rear walls.

`EXTERIOR_FULL` is the default when a building does not obstruct the player or
currently visible content.
`OcclusionZone` tests the entire player envelope swept toward the orthographic
camera against cached bounds. The conservative expanded-box intersection catches
head/feet/edge occlusion rather than sampling a single center ray. Blocked exterior
buildings enter `EXTERIOR_CUTAWAY`: roof and floors above the displayed player floor
are hidden; remaining wall/stair/slab parts are cut only where they intersect the
view corridor. Other ground-floor parts remain opaque and visible. Neighboring
buildings can also cut away while the player is indoors. Zones emit
`occlusion_changed` on transitions; losing overlap, turning the camera or moving
away restores the original geometry. Entering a blocked building gives interior
rules priority. Zoom and camera-height changes refresh the context as well.

`SmallOccluder` is separate from building slicing. Register a prop's static meshes
with `register_mesh`, then register its `OcclusionZone` with the view's spatial
index. StandardMaterial3D base color/texture are supported. During occlusion a
dedicated opaque/discard shader dithers only an ellipse around the projected
player body; the rest of the prop stays opaque. Materials and shadow settings
restore when occlusion ends. Custom shader materials need a purpose-built adapter.
The demo road sign at (7.3, 7.0) and tree at (0.9, 7.5) are render-only placeholders
for this effect and do not add simulation collision. Prop bounds are registered
once; moving/destroying props or streamed buildings need index lifecycle support
before use. Procedural mesh cutting, arbitrary camera pitch/perspective and
animated occluders remain outside this fixed-pitch orthographic implementation.

Run `res://tests/mvp_smoke_test.tscn` for outside/entry, roof and floor slicing,
front/back walls at corners and after orbit, stair midpoint, NPC isolation,
exterior corridor cutaway, prop material restoration, spatial filtering, room
privacy through doorways and off-body visible-content wall occlusion checks,
plus existing combat, inventory, navigation and save regressions.
