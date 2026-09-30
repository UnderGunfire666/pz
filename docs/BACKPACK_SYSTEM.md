# Inventory, hands, and containment

InventoryGrid keeps its legacy class name, but capacity is exclusively external
volume in cubic centimeters. There is no grid, orientation, or shape packing.
Backpack exterior dimensions are its internal dimensions plus one centimeter on
each axis. Nested contents add weight but do not add external parent volume.

Every physical unit has a persistent UID, flavor, durability, acquisition time,
remaining fraction, and child stacks. Transfers move exact unit subtrees. The UI
groups equal definition IDs without merging identities. Independent food shrinks
its original longest dimension with the remaining fraction; ties prefer height,
then length, then width. Filled containers retain fixed exterior volume.

The inventory owns carried items, one equipped backpack, independent left/right/
two-hand slots, and world-container references. Only the equipped backpack reduces
its contents' effective carried weight; its own mass and all nested, handheld, or
unequipped containers remain unreduced. Zero durability prevents equipping but does
not alter mass, capacity, or reduction.

One-hand items must fit 5 × 5 cm and be below 100 cm tall, remain within the 25 kg
cap, and not require two hands. Two hands support 50 kg. Character-creation Strength
adds 5% per point, capped at 50%. Pickup prefers right then left and prevalidates the
complete displacement plan before committing individually timed ground drops.
Container operations and backpack equipment require a free hand; held-item dropping
is always available. Weapons in either hand replace the default shove attack.

Transfers take full weight in kg × external volume in cm³ / 100 game seconds;
ground drops use / 200. Equip and unequip use 2 × (full backpack mass / 100 + 1).
Starting a different timed action interrupts the old one. Completed steps and
partial consumption remain committed. Drinking runs at 50 mL/s and eating at
10 g/s, both stopping at satisfied needs.

The inventory UI is a two-pane authoritative view. PZ-style vertical labels on
the right edge of each pane replace container dropdowns. The player pane defaults
to an All carried aggregate. Each pane stores its selected container, sort
key/direction, expanded groups, and UI-only split groups in a ConfigFile. Single
items are leaf rows; only real stacks expand into individual identity rows. It
supports group/individual drag and drop, Ctrl-drag quantity choice,
context menus with disabled reasons, double-click defaults, and a delayed clamped
hover panel. Tab toggles it without pausing or cancelling actions. A separate HUD
progress row remains visible and offers an explicit cancel button.

The right pane lists aggregate Ground, reachable cabinets ordered by distance then
name, and actionable Nearby All. Nearby All merges equal item types but retains each
real source and resolves outbound transfers in container-list order. Range uses the
existing circular near-view radius plus simulation line-of-sight and room privacy.
Four deterministic whitebox cabinets exercise clear-near, clear-far, blocked, and
out-of-range states. Every cabinet has 50 × 50 × 100 cm capacity; ground is unbounded.
Viewing furniture is immediate while transfers and use remain timed.

QuickSave version 3 uses `user://afterlight_mvp_v3.save`. It stores complete item
trees, hands, Strength, equipped state, cabinet and ground contents, pending use,
and active/queued inventory steps. Load validates the entire candidate before
mutation. Version 2 remains untouched at its old path and is not migrated.

Run `tests/mvp_smoke_test.tscn` headlessly. Inventory tests cover volume boundaries,
weight reduction, hand caps and displacement, cabinet range/occlusion, Nearby All,
UI split/persistence, timing, interruption, partial consumption, and save/load.
