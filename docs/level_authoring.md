# Level authoring

How a level is built: snapping rails onto the terrain, welding a branch onto a turnout, and the
other way round - a terrain carved to fit the rails. What a turnout *is* is in
[turnouts.md](turnouts.md).

## Snapping rails to the ground

`Rail` snaps its curve points onto the ground:

- In the editor: the **Snap Points To Surface** inspector button.
- At runtime: `snap_on_ready` (on by default). It deliberately does *not* run automatically in
  the editor, so opening a scene never silently modifies it.
- `surface_root` points at the ground node; unset falls back to the `snap_surface` group.

Snapping only moves the points and their handles, so **point spacing must be finer than the
terrain's features** — the curve between two snapped points can still float over a dip.
On `main.tscn`, 15 points across 200 m keeps the main line within 0.22 m of its `surface_offset`;
5 points left it 1.5 m out in places.

## Authoring a turnout

1. Draw the branch rail so its start or end lands roughly on the main rail.
2. Add a `Turnout`, point it at both rails, and set `main_distance`, `diverge_towards` and
   `branch_end`. Placement is numeric — gizmo-drag placement belongs to step 5's editor.
3. Press **Align Branch To Turnout**. It welds the branch's attached end onto the points and
   turns its handle so the branch leaves **tangent to the main rail**. Tangency is what makes
   the handover smooth: a train crossing the points must not change direction abruptly, so the
   branch is expected to curve away over its *next* segment, not at the points.
4. Check `_get_configuration_warnings()` is clear — it flags a drifted branch, an impossible
   departure angle, a `main_distance` off the rail, and a toe leg with no length.

`align_branch_on_ready` (on by default, runtime only) re-runs step 3 when the level starts.
Surface snapping moves each rail onto the terrain independently, so without it a hand-aligned
branch drifts off the points and trains visibly jump on handover.

There is no editor button available to a headless agent. To weld a branch without the editor:
instantiate the scene, set `snap_on_ready = false` on the rails **before** adding it to the
tree, call `align_branch_to_turnout()`, then print the curve's `_data` and paste it back into
the `.tscn`.

`Rail`'s debug draw shows both running rails, sleepers, **cyan chevrons for the curve's own
direction** (trains may run against them), and a green start / red end marker. Rail direction
is level data, not cosmetic — turnouts are defined relative to it.


Snapping only moves curve points and handles, so point spacing has to be finer than the
terrain's features. If real levels get hillier, per-segment subdivision may be worth adding.

## Levels on a baked terrain

Snapping puts rails on whatever ground there is, which is fine on gentle hills and useless for a
tunnel or a bridge: a snapped rail runs over the ridge, and down into the gully. So a level with
either is built the other way round. The rails carry their own heights (`snap_on_ready = false`
on every one of them), and the ground is carved to fit them and baked into a heightmap.

`Ground.heightmap` is an `Image` in `FORMAT_RF`, one height in metres per grid vertex, spread
over `Ground.size`, first row at -Z. With it set, `subdivisions` and `hill_height` are ignored
and the image's resolution is the grid. `surface_root` still points at the ground, because the
turnout markers and signal masts stand on it through `Rail.ground_frame()`.

Carving follows three rules, and `tests/desert_level_test.gd` checks the result from the rails'
side:

- **Ordinary track** gets a flat bed 0.25 m (`surface_offset`) under the railhead, 3 m either
  side of the centre line, blending out into cuttings at 1:1 and banks at 1:1.6.
- **A tunnel** is any stretch where the natural ground stands more than 7 m over the railhead,
  grown from a rail's end (a way off the level, at most 90 m) or forced (under a hill). The ground
  over it is kept at least 6.5 m above the railhead. A heightfield can only rise from the bed to
  the roof across one grid cell, so every tunnel mouth is a few metres of ground in the loading
  gauge - the one place that is allowed.
- **A bridge** is left alone: no bank is filled under it, or within 30 m of its ends.

Two tracks side by side at different heights cannot both be carved for: a 4 m grid cell spans
the gap between them and interpolates one into the other's loading gauge. Where one line climbs
beside another, both climb.

### The desert level

`scenes/levels/desert.tscn` is a whole level rebuilt from a reference layout, track and terrain
only - no buildings, portals or bridge deck. Its terrain is a baked heightmap on a 3 m grid; the
carver that made it was a one-off and is not in the repo, so moving track means editing the
heightmap to match. Parallel tracks are 5 m apart, the steepest gradient is 5.2% (the north line
beside the ridge) and the tightest radius 28 m (on the loop).

| rail | from - to |
| --- | --- |
| `BottomLine` | the west exit to the east exit, straight along the south edge |
| `NorthLine` | the north-east exit west to `BridgeJunction`, straight along the north edge |
| `LoopLine` | `SouthJunction`, up through the wye, over the ridge, along the north line, over the bridge, round the lake, through the tunnel, back to `TunnelJunction` |
| `EastLine` | `WyeNorth`, round to the east exit |
| `WyeChord` | `WyeEast` to `WyeSouth`, the triangle's third side |
| `ScissorsDown` / `ScissorsUp` | the two diagonals of `LakeScissors` |

The loop round the lake is a **balloon**: out over the bridge, back through the tunnel, onto the
north line facing the other way. It is one rail from `SouthJunction` to `TunnelJunction` because
two rails only ever meet at a turnout; the alternative, the north line looping back onto itself,
works but draws a configuration warning. Where the loop touches the bottom line south of the
lake, `LakeScissors` (a double crossover, `LakeScissorsMiddle` its crossing) joins them; the
reference draws it as an X between two tracks a few pixels apart. The ridge line crosses the
tunnel line 8 m above it - the same rail twice, 1050 m apart along it.

Every junction is protected from every way into it, sixteen signals in all, and three trains come
out of the exit tunnels at the start and wait at the entry signals: `WestArrival` at `WestEntry`,
`NorthArrival` at `NorthEntry`, `EastArrival` at `EastEntry`. The exits are plain dead ends, so a
train sent into one turns round in the dark and comes back (`end_behavior`); see
[further_development.md](further_development.md).
