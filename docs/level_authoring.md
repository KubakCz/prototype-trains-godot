# Level authoring

How a level is built: snapping rails onto the terrain, and welding a branch onto a turnout.
What a turnout *is* is in [turnouts.md](turnouts.md).

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
