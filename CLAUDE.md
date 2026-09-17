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

# The whole regression suite (see "Tests" below). Exits non-zero on failure.
tests/run.ps1                    # or: bash tests/run.sh
tests/run.ps1 driving passage    # only matching suites
tests/run.ps1 -List
tests/run.ps1 -Color always      # colour survives a pipe; -NoColor turns it off

# Same, plus the synthetic-click tests (3D pick and floating widget) - needs a window.
# Do NOT add --resolution: see the coordinate-space gotcha below.
tests/run.ps1 -Windowed

# Open a scene in the editor without a human, to exercise @tool paths.
Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor res://scenes/main.tscn --quit-after 90
```

To eyeball a change without a human at the keyboard: run a throwaway `Node` scene
that instantiates `main.tscn`, `await RenderingServer.frame_post_draw` ~30 times, then
`get_viewport().get_texture().get_image().save_png("user://shot.png")`. Output lands in
`%APPDATA%\Godot\app_userdata\Train game prototype\`. Needs a real window — omit `--headless`.

## Architecture (steps 1-2)

```
scripts/rails/rail.gd             Rail        : Path3D   — a stretch of track
scripts/rails/turnout.gd          Turnout     : Node3D   — points joining two rails
scripts/rails/track_walker.gd     TrackWalker : RefCounted — arc length across the network
scripts/rails/surface_snapper.gd  SurfaceSnapper        — ground raycasts
scripts/trains/train.gd           Train       : Node3D   — a box that drives the network
scripts/world/ground.gd           Ground      : MeshInstance3D — procedural terrain
scripts/debug/camera_rig.gd       CameraRig   : Node3D   — orbit camera (debug)
scripts/debug/train_debug_panel.gd            : PanelContainer — driving keys (debug)
scripts/debug/turnout_debug_panel.gd          : PanelContainer — turnout keys (debug)
scripts/debug/turnout_overlay.gd  TurnoutOverlay : Control — the four turnout presentations
scripts/debug/turnout_widget.gd   TurnoutWidget  : Control — one floating turnout marker

tests/framework/test_case.gd      TestCase       : RefCounted — the base class suites extend
tests/framework/test_runner.gd                   : SceneTree — discovery, reporting, exit code
tests/support/turnout_demo_case.gd TurnoutDemoCase — fixture for the turnout demo layout
tests/*_test.gd                                  — the suites themselves
```

Scenes: `scenes/main.tscn` (the running prototype) and `scenes/demos/turnouts.tscn`
(flat ground, a passing loop and a dead-end stub — every turnout case in one place).
Both are driven by the tests under `tests/`; keep them working.

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
box sits along a curve as a chord. Its centre therefore sits inside the arc — measured at
**1.39 m for the 14 m PassengerTrain** on `main.tscn`'s tighter bends, not the ~0.3 m an
earlier note claimed. That is correct, not drift: the invariant worth asserting is the *arc*
position (project the origin back onto the curve and you get the train's `distance` to within
0.2 m), because the chord midpoint is symmetric about it whatever the curvature.

`end_behavior` (`STOP` / `REVERSE` / `TURN_AROUND`) now fires **only at a genuine dead end** —
a rail end with no turnout attached. A rail end that connects onward hands the train over.

## Turnouts (step 2)

A `Turnout` lives at `main_distance` along `main_rail`, which runs straight through it, and
welds one end of `branch_rail` to that point. Three legs:

- **toe** — the main rail on the side the points face,
- **through** — the main rail carrying on past the points,
- **diverging** — the branch rail leaving the points.

`diverge_towards` (`RAIL_START` / `RAIL_END`) says which way along the main rail the diverging
move leads, and so which main-rail leg is the toe. Passage:

| arriving on | normal | reverse |
| --- | --- | --- |
| toe (facing move) | on down the main rail | switched onto the branch |
| through (trailing) | on to the toe | **refused** |
| diverging (trailing) | **refused** | on to the toe |

A refused train **holds with its throttle still open** and rolls on the instant the points are
thrown — it is waiting, not stopped. `Train.blocking_turnout` says which points, for the
readouts.

**`TrackWalker` replaces arithmetic on `Train.distance`.** Everything the train does is "move
this far from here", and plain addition stops at a rail's own ends — exactly what turnouts exist
to get past. So both driving and body placement go through `TrackWalker.walk()`, which crosses
every turnout on the way that admits the move. Two consequences fall out for free: a train
straddling the points has its two ends on two different rails and is drawn as the chord between
them, and a train is refused the moment its **leading end** touches the points rather than when
its middle does (`_physics_process` walks twice — once past the leading end to find the
obstruction, once to move the centre as far as that allows).

Step 8's block locking wants the same walk with the length turned up: look ahead and report
what the train will reach.

**Explicit vs. derived level data.** `diverge_towards` and `branch_end` are authored by hand.
Which *side* the branch leaves on is not: `branch_side()` reads it off the curves, which is what
lets one script be a left-hand turnout, a right-hand one, a turnout on a curve or a symmetric Y.

**Points can be thrown under a train**, deliberately, for now — the body visibly kinks onto the
other route. Step 8 makes occupancy lock them.

`Turnout.throw_points()` is the single entry point for throwing, whoever throws it; step 4's
compound assemblies should drive their members through it and set `player_operable = false` on
them. `position_changed` fires whenever the points move.

**How a turnout is presented is not settled**, so all four candidates are in and `[O]` cycles
them (`TurnoutOverlay.Mode`):

| mode | on the track | floating |
| --- | --- | --- |
| `LEGS_3D` | coloured legs | — |
| `LEGS_AND_BADGE` | coloured legs | name + `N`/`R` pill |
| `LEGS_AND_SCHEMATIC` | coloured legs | miniature of the real layout |
| `SCHEMATIC_ONLY` | — | miniature only |

The 3D legs are stubs sampled along the real rails, so they curve with the track: the toe and
the set route in green, the dead leg in red with a cross on its end. The minimal box marker (a
post and a banner that swings onto the set route) is the turnout's *model*, not overlay, and
stays in every mode — it also carries the click collider. Debug keys: `[T]` select, `[G]` throw,
`[O]` cycle presentation, left click throws whatever is under the cursor.

## Tests

`tests/` holds the regression suite; `tests/README.md` is the guide to writing one, and this is
just the shape of it. Run it with `tests/run.ps1` (or `bash tests/run.sh`), which finds Godot,
rebuilds the class cache if it has never been built, and exits 0 / 1 / 2 for pass / failure /
bad argument.

There is no third-party framework in here. GUT and gdUnit4 both exist and both would work, but
they are thousands of lines vendored into `addons/` for a prototype whose tests are all
"instantiate a level, run the physics, look at the trains" — `tests/framework/` is 440 lines of
code and produces exactly the report we want. If the suite ever outgrows it, that is the moment
to reconsider, not before.

The shape is the familiar one: a `*_test.gd` under `tests/` extending `TestCase`, `test_*`
methods run in declaration order, `before_all` / `after_all` / `before_each` / `after_each`,
and `assert_*` calls that take the claim as their last argument. Notes recorded with `note()`
print under the test and land in the `--json` report, which is where all the numbers the old
`turnout_checks.gd` printed have gone.

Three things specific to GDScript shaped it:

- **A failed assertion cannot abort the test** — no exceptions. So assertions record and return
  a bool, the test carries on, and a report lists every failure in the test rather than the
  first. `if not assert_not_null(x, "..."): return` where continuing would be nonsense.
- **One suite instance, not one per test.** `before_all` may stash state in members; nothing is
  reset between tests, so per-test state belongs in `before_each`. `load_scene()` frees what a
  test took but keeps what `before_all` took until the suite ends.
- **`await case.call(name)` covers coroutine and plain methods alike**, because a GDScript call
  that suspends hands back a signal to await and one that does not hands back its value. That
  is what lets a test `await` freely without declaring anything.

**Time is counted in physics frames, never in wall clock.** The runner sets
`Engine.physics_ticks_per_second = 60 * speed` *and* `Engine.time_scale = speed`, which leaves
the physics delta at exactly 1/60 s while stepping the simulation `speed` times faster than
real time. The default 16 took the suite from 87 s to 14 s, and `--speed 1` and `--speed 16`
print identical numbers — verified by diffing the runs.

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
- **A rail distance exactly at a turnout does not say which side of the points you are on.**
  The main rail runs *through* the points, so `main_distance` means both "about to arrive" and
  "just left". `TrackWalker` therefore never comes to rest in that zone: travel that would stop
  within `EPSILON` short of the points crosses them instead, and a crossing always carries the
  walk at least `CLEARANCE` (4 mm) past. Cost a real bug — a train restarting after being held
  sits exactly `body_length / 2` from the points, and `half / (speed * delta)` lands it in the
  1 mm blind spot of a naive "strictly ahead" test, where it saw no turnout, decided it was at a
  dead end and applied `end_behavior`. A few millimetres of over-travel per crossing buys the
  whole class of bug away.
- **A correctly aligned branch leaves *tangent* to the main rail, so the tangents at the points
  cannot tell the three legs apart.** Anything that wants to show or measure the shape of a
  turnout has to sample a few metres down the leg instead — that is what `Turnout.leg_position`,
  `leg_heading` and `branch_side` are for. Bit twice: `branch_side` returned "right" for every
  turnout, and the marker's banner never appeared to move when the points were thrown.
- **A schematic of a turnout has to exaggerate the divergence.** A real turnout diverges by
  about 6°; drawn to scale in a 44 px picture that is three collinear lines. `TurnoutWidget`
  amplifies the angle about its true sense (×5, clamped to 52°), so a right-hand turnout still
  reads as right-handed.
- **`get_viewport().physics_object_picking` is off by default**, and without it a
  `CollisionObject3D.input_event` never fires. `Turnout` switches it on at runtime.
  A `Control` that calls `accept_event()` consumes the click before picking sees it, which is
  what stops the floating widget and the 3D collider under it both throwing the same points.
- **Do not pass `--resolution` when feeding synthetic clicks.** With
  `window/stretch/mode = "canvas_items"` a resized window leaves the 2D canvas at the project's
  base size while the 3D render target follows the window, so `unproject_position` and
  `Input.parse_input_event` end up in different coordinate spaces and every click misses. Run at
  native resolution. (`--resolution` is fine for screenshots.)
- **Godot writes terminal colour into pipes too.** Neither `print_rich` nor a raw ANSI escape
  is filtered when stdout is a file or a pipe — the engine does no tty detection, and GDScript
  has no `isatty` to do it with. So the caller decides: `tests/run.ps1` and `tests/run.sh` pass
  `--color never` when `[Console]::IsOutputRedirected` / `! -t 1` says nobody is watching, and
  the runner also honours `NO_COLOR`. Pad before painting, never after — the escapes count
  towards `%-4s` and friends.
- **GDScript's `%` format has no `%g`.** Use `%f`/`%.Nf`/`%s`; `%g` raises "unsupported format
  character" at runtime, not parse time.
- **Array literals are `Variant`, so annotate the loop variable**: `for t: Turnout in [a, b]:`.
  Without it every `t.method()` is `Variant` and warnings-are-errors kills the next `var x :=`.
- **Physics steps per real second are `Engine.physics_ticks_per_second`; the physics delta is
  `time_scale / physics_ticks_per_second`.** Measured, all four combinations: `time_scale` alone
  does *not* run a headless simulation faster, it makes each step cover more ground (at
  `time_scale = 8`, `delta` is 0.133 s and a train jumps 2 m per step, which is how you skip
  clean over a turnout). Raise **both** — `ticks = 60 * n`, `time_scale = n` — and the delta
  stays 1/60 s while the simulation runs `n` times faster than real time. That is the whole
  trick behind `tests/run.ps1` finishing in 14 s instead of 87 s.
- **`await physics_frame` is one step; `await process_frame` is however many steps fit.** So with
  the clock sped up, waiting on an idle frame advances the simulation by an unpredictable
  amount. Anything that needs a repeatable starting state waits on physics frames
  (`TestCase.load_scene` does).
- **A `Variant` holding a bool or an int cannot be cast with `as`.** `value as Node` raises
  "Invalid cast: can't convert a non-object value to an object type" at runtime, where
  object-to-object casts merely give `null`. Test `if value is Object` before casting anything
  that came in as `Variant`.
- **`Script.get_script_method_list()` includes the base scripts' methods too**, derived first,
  each in declaration order — so an inherited method appears twice and the first sighting is the
  override. Fine for ordering tests by declaration, but it has to be de-duplicated.
- **PowerShell binds bare arguments to the first non-switch parameter declared.** A wrapper that
  wants pass-through arguments must declare its `ValueFromRemainingArguments` parameter *first*
  (`tests/run.ps1` does), or `run.ps1 driving` tries to parse `driving` as `-Speed`.
- `Tab` is swallowed by the GUI focus system in `_unhandled_key_input`; the debug panel uses
  `_input` instead.
- Debug controls use physical keycodes rather than `InputMap` actions, keeping the project's
  action list free for real gameplay. Throwing a turnout is *gameplay*, so it goes through the
  `interact` action (left mouse button) — the first entry in the project's action list, and the
  one step 3's signals should reuse.
- `Rail` stores its attachments as `Array[Node]`, not `Array[Turnout]`. `Turnout` has to name
  `Rail`, and naming it back would make the two scripts mutually dependent. `TrackWalker` casts.
  For the same reason `Turnout.Exit` is an inner class of `Turnout` rather than of the walker.

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

### Authoring a turnout

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

## Notes for further development

* `end_behavior` is now reached only at a genuine dead end. Real levels will want buffer stops
  and off-level connections there instead; it stays a placeholder, but a much smaller one.
* Snapping only moves curve points and handles, so point spacing has to be finer than the terrain's features. 5 points across the main line left it floating 1.5 m over dips; 15 points brought it to 0.22 m. If real levels get hillier, per-segment subdivision may be worth adding.
* **Step 3 (signals)** wants the same "lives at a distance along a rail" shape as `Turnout`, and
  a much better job of the floating UI than `TurnoutOverlay` does: collapsing when far away,
  shifting so neighbours do not overlap, and showing which direction a signal applies to. The
  turnout widgets already overlap each other when two turnouts are close, and nothing de-clutters
  them — that problem is step 3's to solve properly. Stopping a train is already possible without
  new machinery: hold it the way a turnout does, by capping how far the walk may carry its
  leading end.
* **Step 4 (compound turnouts)** should group existing `Turnout` nodes rather than extend them.
  Throw members through `throw_points()`, set `player_operable = false` so the group owns the
  clicks, and cycle positions in the group. Two limits to know about: `TrackWalker` needs two
  turnouts on one rail to be more than `EPSILON` apart, and a plain crossing (two rails meeting
  with no possibility of switching between them) has no representation yet — it is not a
  `Turnout`, and the walker has no notion of a rail end that simply continues into another rail.
* **Step 8 (block locking)** is mostly `TrackWalker.walk()` with the length turned up: walk
  ahead from a train and collect the rails and turnouts it will reach. `Turnout` already reports
  refusal, which is the "train cannot be let into a block if it will reach an unconnected
  turnout" rule. Locking points under an occupying train is the other half, and is deliberately
  *not* enforced yet.