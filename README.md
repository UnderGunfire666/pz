# Afterlight: Orangeville MVP

This repository contains a runnable Godot 4.7.2 3D greybox for a small, single-player zombie-survival MVP. It is deliberately a first playable build, not a full Project Zomboid clone: the goal is to prove the survival loop, visibility pressure, and one autonomous survivor before content production begins.

Run the project from Godot, or use:

```bash
flatpak run org.godotengine.Godot --path .
```

The prototype has no external art dependency. Its 3D terrain, multi-storey walls, actors, lighting, and camera are built from procedural meshes; the existing logical grid continues to drive survival and AI simulation.

## Demo route

1. Move north into the safehouse and approach the purple bed marker.
2. Travel east toward the grocery. The orange marker on the road is broken glass and deliberately gives a light wound.
3. Enter the grocery from its south door; approach the blue shelf and press `E`. Searching takes game time.
4. Watch the field of view and make space when a zombie is spotted. Zombies pursue and attack at close range; directional attacks show their remaining health and create noise.
5. Return to the safehouse bed, press `E`, then use `2` to fast-forward a rest.
6. Leave the house again to complete the demonstrable loop.

## Controls

| Input | Action |
| --- | --- |
| `WASD` | Move in screen-space up / down / left / right |
| `Shift` | Sprint while stamina permits |
| Hold right mouse | Aim / face the mouse without changing FOV |
| Hold middle mouse and drag horizontally | Rotate the 3D camera around the player; pitch stays fixed |
| Walk along the visible ramp | Move between floors inside multi-storey buildings |
| Left mouse | Directional melee attack; creates a noise event |
| `E` | Search a container or rest in the safehouse |
| `F` / `V` | Eat food / drink water from the pack |
| `R` | Sort inventory; this takes game time |
| `Space` | Pause world simulation |
| `1` / `2` | Normal speed / 3× fast-forward |
| Mouse wheel / HUD `+` and `-` | Zoom the world camera |
| HUD time buttons | Pause / normal / fast-forward |

Walls are thin face segments: actors can step onto the wall tile, but cannot cross the wall surface. Walls on the active floor are never hidden based on camera angle. Vision includes a short omnidirectional radius around the player, with the longer view still limited by facing and wall occlusion; the 3D fog boundary is a smooth, consistently shaded polygon and vision results are cached between changes. Interrupting a container search retains its completed game-time progress for the next attempt. Multi-storey buildings have walkable ramps; the player moves between floors physically and geometry on other floors is hidden. The 3D presentation and camera sit on top of the existing grid-based survival simulation.

`docs/MVP_BLUEPRINT.md` documents the architecture, solo-dev roadmap, boundaries, and launch acceptance criteria.

## Verification

The smoke test loads the complete scene and checks the map pressure model, FOV/LOS, medical-state separation, zombie seed population, and inventory data flow:

```bash
flatpak run org.godotengine.Godot --headless --path . res://tests/mvp_smoke_test.tscn
```
