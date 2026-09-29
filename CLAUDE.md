# CLAUDE.md

Working notes for this repo: the facts, the commands, the architecture map and the engine traps.

- [README.md](README.md) — the game design.
- [prototype_goals.md](prototype_goals.md) — the implementation plan. **It belongs to the
  project owner: read it, never edit it.** Propose changes in conversation instead.
- [docs/](docs/) — the subsystems in detail, listed under "The rest of the notes" below.

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

# The whole regression suite (tests/README.md). Exits non-zero on failure.
tests/run.ps1                    # or: bash tests/run.sh
tests/run.ps1 driving passage    # only matching suites
tests/run.ps1 -List
tests/run.ps1 -Color always      # colour survives a pipe; -NoColor turns it off

# Same, plus the synthetic-click tests (3D pick and floating widget) - needs a window.
# That window opens on a private Windows desktop, so nothing of it reaches the screen
# and nothing takes the keyboard; clicks convert canvas -> window coordinates themselves,
# so its size and position are its own business.
tests/run.ps1 -Windowed
tests/run.ps1 -Window visible    # ... or on your own desktop, to watch a click test fail

# Open a scene in the editor without a human, to exercise @tool paths.
Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor res://scenes/main.tscn --quit-after 90
```

To eyeball a change without a human at the keyboard: run a throwaway `Node` scene
that instantiates `main.tscn`, `await RenderingServer.frame_post_draw` ~30 times, then
`get_viewport().get_texture().get_image().save_png("user://shot.png")`. Output lands in
`%APPDATA%\Godot\app_userdata\Train game prototype\`. Needs a real window — omit `--headless`.

## Architecture

```
scripts/rails/rail.gd             Rail        : Path3D   — a stretch of track
scripts/rails/turnout.gd          Turnout     : Node3D   — points joining two rails
scripts/rails/rail_signal.gd      RailSignal  : Node3D   — a one-directional stop signal
scripts/rails/track_walker.gd     TrackWalker : RefCounted — arc length across the network
scripts/rails/surface_snapper.gd  SurfaceSnapper        — ground raycasts
scripts/trains/train.gd           Train       : Node3D   — a box that drives the network
scripts/world/ground.gd           Ground      : MeshInstance3D — procedural terrain
scripts/ui/ui_scale.gd            UiScale     : Node (autoload) — picks the interface scale
scripts/ui/marker_overlay.gd      MarkerOverlay      : Control — lays out every floating marker
scripts/ui/track_marker_widget.gd TrackMarkerWidget  : Control — base: follow, collapse, click
scripts/ui/turnout_widget.gd      TurnoutWidget      : TrackMarkerWidget
scripts/ui/signal_widget.gd       SignalWidget       : TrackMarkerWidget
scripts/debug/camera_rig.gd       CameraRig   : Node3D   — orbit camera (debug)
scripts/debug/debug_panel.gd      DebugPanel  : PanelContainer — a collapsible HUD section
scripts/debug/train_debug_panel.gd            : DebugPanel — driving keys (debug)
scripts/debug/turnout_debug_panel.gd          : DebugPanel — turnout keys (debug)
scripts/debug/signal_debug_panel.gd           : DebugPanel — signal + presentation keys

tests/framework/test_case.gd      TestCase       : RefCounted — the base class suites extend
tests/framework/test_runner.gd                   : SceneTree — discovery, reporting, exit code
tests/support/turnout_demo_case.gd TurnoutDemoCase — fixture for the turnout demo layout
tests/support/signal_demo_case.gd  SignalDemoCase  — fixture for the signal demo layout
tests/*_test.gd                                  — the suites themselves
```

Scenes: `scenes/main.tscn` (the running prototype), `scenes/demos/turnouts.tscn` (flat ground,
a passing loop and a dead-end stub — every turnout case in one place) and
`scenes/demos/signals.tscn` (a straight 280 m main line with a siding: a back-to-back signal
pair, a cluster of three that forces the widgets apart, a signal past the points, and one on
the branch). All three are driven by the tests under `tests/`; keep them working.

The overlay is `scripts/ui/`, not `scripts/debug/`: clicking a signal or a turnout is the
player's actual interface, so it is gameplay UI that happens to still carry step 2's debug
presentation modes. The panels and the camera rig stay debug.

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
a rail end with no turnout attached. A rail end that connects onward hands the train over. It
stays a placeholder — real levels will want buffer stops and off-level connections there — but a
much smaller one than it was.

## The rest of the notes

One file per subsystem, under [docs/](docs/). Read the one you are about to touch — each is
the design record for its step, including the cases that look like bugs and are not.

| file | what is in it |
| --- | --- |
| [docs/turnouts.md](docs/turnouts.md) | the three legs, the passage table, refusal, what is authored vs. derived, the four presentation modes |
| [docs/signals.md](docs/signals.md) | which direction a signal governs, the stopping rule written from the nose, `signals_from`, the three widget styles |
| [docs/ui.md](docs/ui.md) | interface scale, the floating marker layer and its de-cluttering, the debug HUD's panels and keys |
| [docs/level_authoring.md](docs/level_authoring.md) | snapping rails to the terrain, and welding a branch onto a turnout (with and without the editor) |
| [docs/further_development.md](docs/further_development.md) | what finished steps left for the ones not built yet, per step |
| [tests/README.md](tests/README.md) | running and writing the suite, how fast to run the clock, the window a windowed run opens |
| [docs/naming_conventions.md](docs/naming_conventions.md) | what things are called |

Four rules from those files are worth having in front of you anyway, because breaking them
looks like it works:

- **A turnout refuses a trailing move against the points; it does not stop the train.** The
  train holds with its throttle still open and rolls on the instant the points are thrown.
  Same for a train at a red signal. `Train.blocking_turnout` / `blocking_signal` say which.
- **A signal is a property of a direction of travel, not of a place.** `governs` says which way
  the trains it applies to are going; a train going the other way never sees it. Two signals to
  stop both directions, and the side the mast stands on is derived from `governs`, not authored.
- **`TrackWalker.walk()` replaces arithmetic on `Train.distance`**, for driving *and* for body
  placement, because plain addition stops at a rail's own ends — exactly what turnouts exist to
  get past. Step 8's block locking is the same walk with the length turned up.
- **Left click is the only way to throw a turnout or change a signal** — the 3D model or the
  floating widget. There is no keyboard path and there should not be one.

**Two presentation questions are deliberately still open** and switchable rather than decided;
the cycle rows in the debug panels are where they live. See the end of [docs/ui.md](docs/ui.md).

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
- **The rail's own frame is no place to hang anything that stands on the ground.**
  `sample_transform` pitches with the gradient, banks with the curve's tilt, and is anchored
  to the railhead. A signal mast or a turnout's post built as a child of it therefore leans
  *and* floats: the ground two metres to the side of the track is not the ground under the
  track, and the railhead is another `surface_offset` above even that. Both models now hang
  off an internal `top_level` node placed by `Rail.ground_frame()` — upright, yawed along the
  track, standing on the ground — and their posts are *stretched* to reach it, so the lamps
  and the banner stay a fixed height above the railhead whatever the terrain does. Anything
  else that stands beside the track wants the same treatment.
- **`Rail.ground_height_at()` caches the baked ground, but never in the editor.** Collecting
  walks every triangle below `surface_root`, and everything standing beside the track asks;
  in the editor the terrain is still being edited, so a cache there would answer for a surface
  that has since moved.
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
- **The game window opens windowed at the default 1152x648**, and resizing or maximising it is
  handled at runtime rather than authored (`UiScale` reacts to `size_changed`). Anything the
  project says about window size is ignored anyway when the editor *embeds* the game: the
  embedded window is sized by the editor, and the Game workspace toolbar's rightmost
  **Game Window Options** menu -> **Embedded Window Sizing** decides — *Fixed Size* (the
  default, and the reason an embedded run sits at 1152x648 in the middle of a large window),
  *Keep Aspect Ratio* or *Stretch to Fit*.

- **`get_viewport().physics_object_picking` is off by default**, and without it a
  `CollisionObject3D.input_event` never fires. `Turnout` and `RailSignal` switch it on at runtime.
  A `Control` that calls `accept_event()` consumes the click before picking sees it, which is
  what stops the floating widget and the 3D collider under it both throwing the same points.
- **Any `Control` with the default `mouse_filter` eats clicks on the 3D world behind it**, and
  the debug readouts are big. A click on a signal that happened to be behind the signal panel
  silently did nothing — the raycast hit the collider, the event never got there. The panels,
  their column and every container `DebugPanel` builds are `mouse_filter = 2` for that reason;
  the fold header is the one deliberate exception (`Label` is already `IGNORE`). Cost an hour of
  suspecting the collider, the picking flag and Jolt in turn.
- **A `PanelContainer` grows past the offsets you authored**, because a container's minimum size
  wins. Two panels pinned with hand-picked offsets quietly overlapped once a level had enough
  trains to print. Panels that stack go in a `VBoxContainer` and size themselves — with
  `size_flags_horizontal = 0` (`SHRINK_BEGIN`), or the column stretches every folded header out
  to the width of the widest open readout.
- **Node order in a `CanvasLayer` is draw order**, and so is child order under a `Control`, with
  the parent drawing before every child. The overlay was authored before the panels and so was
  drawn *under* them: widgets present, clickable, invisible. `MarkerOverlay` is the last child
  of `DebugUi` in every scene, and orders its own children so dots land under badges — see
  [docs/ui.md](docs/ui.md).
- **Headless gives the root window 64x64 and will not be talked out of it.** `root.size = ...`
  holds until the first idle frame and is then snapped back, because the dummy display server
  reports no window at all (`--resolution` does not help either). With `window/stretch/mode`
  `disabled` that placeholder *is* the canvas, so anything that lays itself out on screen got a
  64 px screen to do it on and the overlay collapsed everything as hopelessly crowded — which is
  why two overlay tests started failing the moment the stretch mode changed, with nothing wrong
  in the overlay. `TestCase`'s runner therefore gives a headless run a fixed 1152x648 canvas
  (`content_scale_mode = CANVAS_ITEMS`, `ASPECT_IGNORE`, `content_scale_size` from the project),
  which is what the old stretch mode used to provide for free. A windowed run keeps the real
  window and the project's own settings — that is the configuration the click tests measure.
- **`Control.scale` scales drawing and input but not `position`/`size`**, so any rect maths has
  to be `size * scale` by hand, and anything drawn in `_draw()` is in *unscaled* coordinates -
  a leader line measured in screen pixels has to be divided by the scale to land on its marker.
- **Canvas coordinates and window coordinates are not the same thing.** The canvas is
  `window / content_scale_factor` — measured under both scale modes, so `window/stretch/mode`
  does not change the rule. `Camera3D.unproject_position` and `Control` layout are both in
  *canvas* space, so the overlay stays correct at any window size and any UI scale — but
  `Input.parse_input_event` wants *window* space, and feeding it a canvas point makes every
  synthetic click miss. Convert with `tree.root.get_screen_transform() * point`;
  `TestCase.click_at()` does, which is why the click tests survive a maximized window - or the
  off-screen one a windowed run actually gets.
  (This entry used to read "never pass `--resolution`"; that was a harness limitation, not an
  engine one.)
- **A synthetic mouse motion gives a `Control` a hover state but a collider only a pulse.**
  The GUI keeps its `mouse_over` until the next event arrives, so a widget hovered through
  `Input.parse_input_event` stays hovered and can be read at leisure. Physics picking does not:
  it re-picks from the *real* cursor on the following frame, and a `CollisionObject3D` the test
  never actually pointed at reports `mouse_exited` immediately after entering. So a 3D hover has
  to be watched for over the next few *physics* frames rather than read once —
  `TestCase.hover_probe()` — and never from frame zero, where the flag still holds whatever the
  previous position left it. A negative ("the pointer is *not* on this") wants a short watch for
  the same reason: the real cursor is loose in the window and picking keeps consulting it.
- **Nothing is ever rendered below native resolution.** `get_viewport().size` follows the
  window, so the 3D view is always native; `content_scale_factor` only divides the *2D*
  coordinate system, and glyphs are rasterized at the scaled size — verified crisp at 1:1 in a
  1440p capture. `CONTENT_SCALE_MODE_VIEWPORT` would be the one that renders small and upscales;
  the project does not use it.
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

