# CLAUDE.md

Working notes for this repo. See [README.md](README.md) for the game design and
[prototype_goals.md](prototype_goals.md) for the prototype plan.

## Project facts

- **Godot 4.7** (`config/features` in `project.godot` pins `"4.7"`), Forward+, D3D12 on Windows.
- Editor binary: **`C:\Godot\Godot_v4.7.2-stable_win64.exe`** — not on `PATH`.
  Use `Godot_v4.7.2-stable_win64_console.exe` when you want stdout.
  An old 4.4.1-mono under `~/Documents/Godot/` is unrelated; don't open the project with it.
- **GDScript**, no C#. Warnings are errors: untyped/`Variant` inference fails the parse,
  so annotate explicitly (`var x: float = a if c else b`) rather than using `:=` on
  anything the analyser can't type.
- Main scene: `scenes/main.tscn`.

## Commands

```bash
# Rebuild the import + global class-name cache. Do this after adding a class_name;
# --check-only cannot resolve cross-script class names until it has run.
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# Parse-check one script.
Godot_v4.7.2-stable_win64_console.exe --headless --path . --check-only --script res://scripts/rails/rail.gd

# Run a scene headlessly (harness scenes, smoke checks).
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://some/scene.tscn --quit-after 2000
```

To eyeball a change without a human at the keyboard: run a throwaway `Node` scene
that instantiates `main.tscn`, `await RenderingServer.frame_post_draw` ~30 times, then
`get_viewport().get_texture().get_image().save_png("user://shot.png")`. Output lands in
`%APPDATA%\Godot\app_userdata\Train game prototype\`. Needs a real window — omit `--headless`.

## Architecture (step 1)

```
scripts/rails/rail.gd             Rail        : Path3D   — a stretch of track
scripts/rails/surface_snapper.gd  SurfaceSnapper        — ground raycasts
scripts/trains/train.gd           Train       : Node3D   — a box that drives a rail
scripts/world/ground.gd           Ground      : MeshInstance3D — procedural terrain
scripts/debug/camera_rig.gd       CameraRig   : Node3D   — orbit camera (debug)
scripts/debug/train_debug_panel.gd            : PanelContainer — driving keys (debug)
```

**Rails are `Path3D` + `Curve3D`.** Free in-editor point/tangent gizmos, arc-length-accurate
`sample_baked`, and scene serialisation for nothing. `Rail` adds an arc-length sampling API
(`rail_length`, `sample_position/forward/up/transform`, all mirrored in `sample_local_*`).

**`PathFollow3D` is deliberately not used.** Trains keep their own `distance` along the rail,
because turnouts (step 2) need to hand a train from one rail to another mid-travel and to
refuse entry from an unconnected direction — neither fits `PathFollow3D`'s model.

**Train direction is two independent values**, and this is the crux of goal 1:
- `facing` (`ALONG_RAIL` / `AGAINST_RAIL`) — which way the nose points along the rail.
- `throttle` (`-1` / `0` / `1`) — drive nose-first, stand, or back up.

`distance += throttle * facing * speed * delta`. Driving forward always moves the nose
forward, whichever way the underlying curve was drawn. Never collapse these into a signed
speed — reversing a train and turning it around are different operations.

The body is placed from the rail positions under its two **ends**, not its centre, so a long
box sits along a curve as a chord. Its centre therefore sits slightly inside the arc
(~0.3 m for a 14 m body on these curves); that is correct, not drift.

`end_behavior` (`STOP` / `REVERSE` / `TURN_AROUND`) is a **placeholder** for "reached the end
of the line". Once turnouts exist, a rail end that connects onward should hand the train over
instead.

## Gotchas found the hard way

- **Hand-written `.tscn`: exported node references need `node_paths` on the node header**,
  or they silently arrive as `null`:
  ```
  [node name="PassengerTrain" type="Node3D" parent="Trains" groups=["trains"] node_paths=PackedStringArray("rail")]
  rail = NodePath("../../Rails/MainLine")
  ```
  Only the editor writes that attribute automatically. Same for `surface_root`, `camera`, `readout`.
- **`Curve3D` in `.tscn`** stores `_data = {"points": PackedVector3Array(...), "tilts": ...}`
  with **three vectors per point, in the order `in`, `out`, `position`** (handles are relative
  to the point), plus a trailing `point_count`.
- **Vertex colours are consumed as linear.** Set `vertex_color_is_srgb = true` on any material
  with `vertex_color_use_as_albedo`, or colours authored by eye render far darker and greyer.
  Cost me a long detour chasing phantom shadow bugs.
- **Procedural mesh winding**: get it backwards and the surface is invisible from above while
  still being solid to the snapper. `SurfaceTool.generate_normals()` won't warn — check that
  the normals point the way you expect.
- **A `.tscn` `Transform3D(...)` lists the basis ROW-major**, i.e. the first three floats are
  the first *row*, not the x axis. Verified: `Transform3D(1,2,3, 4,5,6, 7,8,9, ...)` yields
  `basis.x == (1,4,7)`. Writing the three axes as consecutive columns silently stores the
  **transpose**, which stays orthonormal and right-handed, so nothing errors — it just
  quietly rotates the node wrong. Transpose before emitting:
  `rows = (x.x,y.x,z.x, x.y,y.y,z.y, x.z,y.z,z.z)`.
- **`DirectionalLight3D` shines along its basis `-Z`.** Combined with the row-major trap above,
  a hand-authored sun transform easily ends up lighting the scene *from below*; the symptom is
  flat, ambient-only terrain and unlit roofs. Assert the intended travel direction has a
  negative Y, then check in-engine that `-sun.global_basis.z` still does.
- **Editor physics is not stepped**, so `PhysicsDirectSpaceState3D.intersect_ray` finds nothing
  from a `@tool` script. `SurfaceSnapper` intersects mesh triangles
  (`Geometry3D.ray_intersects_triangle`) instead, which behaves identically in editor and game.
- **Generated nodes use `INTERNAL_MODE_BACK`** (`Rail`'s debug lines, `Train`'s body boxes) so
  they never get saved into the scene or show up in the scene tree.
- `Tab` is swallowed by the GUI focus system in `_unhandled_key_input`; the debug panel uses
  `_input` instead.
- Debug controls use physical keycodes rather than `InputMap` actions, keeping the project's
  action list free for real gameplay.

## Level authoring

`Rail` snaps its curve points onto the ground:

- In the editor: the **Snap Points To Surface** inspector button.
- At runtime: `snap_on_ready` (on by default). It deliberately does *not* run automatically in
  the editor, so opening a scene never silently modifies it.
- `surface_root` points at the ground node; unset falls back to the `snap_surface` group.

Snapping only moves the points and their handles, so **point spacing must be finer than the
terrain's features** — the curve between two snapped points can still float over a dip.
On `main.tscn`, 15 points across 200 m keeps the main line within 0.22 m of its `surface_offset`;
5 points left it 1.5 m out in places.

`Rail`'s debug draw shows both running rails, sleepers, **cyan chevrons for the curve's own
direction** (trains may run against them), and a green start / red end marker. Rail direction
is level data, not cosmetic — turnouts are defined relative to it.

## Notes for further development

* `end_behavior` is a placeholder. With no turnouts there's nowhere to hand a train off, so it stops, backs up, or turns around. Step 2 should replace this where a rail end connects onward.
* Snapping only moves curve points and handles, so point spacing has to be finer than the terrain's features. 5 points across the main line left it floating 1.5 m over dips; 15 points brought it to 0.22 m. If real levels get hillier, per-segment subdivision may be worth adding.