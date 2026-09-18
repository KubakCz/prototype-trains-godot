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

## Architecture (steps 1-3)

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

**How a turnout is presented is not settled**, so all four candidates are in and the turnout
panel's **overlay row** cycles them (`MarkerOverlay.Mode`):

| mode | on the track | floating |
| --- | --- | --- |
| `LEGS_3D` | coloured legs | — |
| `LEGS_AND_BADGE` | coloured legs | name + `N`/`R` pill |
| `LEGS_AND_SCHEMATIC` | coloured legs | miniature of the real layout |
| `SCHEMATIC_ONLY` | — | miniature only |

The 3D legs are stubs sampled along the real rails, so they curve with the track: the toe and
the set route in green, the dead leg in red with a cross on its end. The minimal box marker (a
post and a banner that swings onto the set route) is the turnout's *model*, not overlay, and
stays in every mode — it also carries the click collider. **Left click is the only way to throw
a turnout**: the marker, or the floating widget over it. There is no keyboard path and there
should not be one — see "The debug HUD".

## Signals (step 3)

A `RailSignal` lives at `distance` along `rail` and shows `DANGER` (red) or `CLEAR` (green).
`DANGER` is enum value 0, so a signal omitted from a `.tscn` or freshly added in the editor is
at stop, which is the rule the plan asks for.

**A signal is a property of a direction of travel, not of a place.** `governs`
(`TOWARDS_RAIL_END` / `TOWARDS_RAIL_START`) says which way the trains it applies to are going;
a train going the other way never sees it. Stopping both directions takes two signals, and
which *side* of the track the mast stands on is derived rather than authored — a signal is on
the right of the trains it governs, so `governs` alone places it.

**A cleared signal stays clear.** No automatic replacement after a train passes: the player is
the only thing that moves a signal until step 8's interlocking arrives.

**Held, not stopped.** A train meeting a red stops with its nose on the signal and keeps its
throttle open, exactly as at points set against it, and rolls on the instant it clears.
`Train.blocking_signal` says which one, for the readouts.

**The rule is written from the nose, and that is the whole subtlety.** `TrackWalker.walk()`
takes a `signals_from` argument — how far into the walk signals begin to count:

- `IGNORE_SIGNALS` (the default) — the walks that place a train's body. Where the body reaches
  is a question about *track*; a signal must never shorten it, or a train standing at a red
  would be drawn half-length.
- `body_length / 2` — what `Train._physics_process` passes for its probe. A signal nearer than
  that is one the nose is already past, so putting a signal back to danger under a moving train
  lets that train out instead of stranding it across the signal.
- `OBEY_ALL_SIGNALS` — everything, including one at the walk's own starting point. Tests use it.

A signal is never *crossed* by the walk: it either blocks (and the walk ends there) or it is
not a stop at all. So unlike a turnout it needs no `CLEARANCE` over-travel and no minimum
separation from its neighbours — two signals may stand at the same distance, which is exactly
what a back-to-back pair is.

**How a signal is presented is not settled either**, so all three candidates are in and the
signal panel's **widget row** cycles them (`SignalWidget.Style`). Every one of them has to answer "which direction is this
for", because a red badge that does not say whose red it is tells the player half the story:

| style | shape | direction shown by | collapsed |
| --- | --- | --- | --- |
| `ARROW` | a chevron | the badge itself points the governed way | an arrowhead |
| `PILL` | a plate | a small triangle beside the name | a dot |
| `SCHEMATIC` | a plate | a track stub with an arrowhead, lamp on the signal's own side | a dot |

The direction is projected through the camera (`signal_position()` → `ahead_position()`), so it
turns with the layout as the camera orbits and stays honest on a curve.

**Left click is the only way to change a signal**, as with a turnout: the mast, or the floating
widget over it. The 3D model is a mast, a head and two
lamps with the lit one emissive, plus a stop line across the track and an arrow down the
governed direction in the aspect's colour. The mast stands on the ground rather than on the
track — see `Rail.ground_frame()` under the gotchas — so `mast_position()` is a point on the
terrain and `mast_lift()` is how far the railhead is above it.

### Interface scale

`window/stretch/mode` is **`disabled`**, so the canvas is 1:1 with the window whatever size the
window is: the 3D view gets every pixel and the HUD does not grow just because the window did. `UiScale` then sets `Window.content_scale_factor` from the window *height* against a 1080p
reference, snapped to quarters and clamped to 1.0–3.0 — the usual game behaviour of picking a
size for the screen rather than stretching a fixed layout. Measured: 648 / 900 / 1009 / 1080 all
give 1.0, 1440 gives 1.25, 2160 gives 2.0. It reapplies on `size_changed`, and
`scale_for_height()` is static so the rule can be asked about a height without a window.

Deliberately *not* proportional. Base-size stretching (`canvas_items` + `expand`, what this was
before) scales the UI by exactly `window / 1152`, which made the readouts 1.557x on a 1920 window
— sharp, but eating half the screen for no extra information.

### The floating layer

`MarkerOverlay` owns **every** floating marker — signals and turnouts together. One overlay
rather than one each, because de-cluttering only works if it knows about every widget on
screen: two overlays would each lay its own markers out neatly and then draw over the other's.
Folding turnouts in is what fixed the overlap step 2 left behind.

`TrackMarkerWidget` is the base: follow the camera, collapse, hover, leader line, click.
A subclass supplies what it points at, how big it is, what colour it is, what a click does and
how to draw itself.

All three collapse rules are implemented and the signal panel's **collapse row** cycles them
(`MarkerOverlay.Collapse`):

| rule | behaviour |
| --- | --- |
| `WHEN_FAR` | full size inside `collapse_distance` metres, a point past it |
| `WITH_DISTANCE` | scales down with camera distance, collapses below `min_scale` |
| `WHEN_CROWDED` | distance is irrelevant; only what cannot be given a clear place collapses |

Hovering always opens a collapsed widget, whichever rule is in force.

Overlapping widgets are **stacked upwards**, lowest anchor first, so the nearest marker keeps
the place it asked for and the ones behind it climb above it; the leader lines are what stop
that reading as a scramble. **Collapsed widgets take no part in the layout** — a dot is already
the answer to "there is no room to show this properly", and moving it off its own marker to
make space for a badge would lose the one thing it still says. So the layout's promise is about
open badges: no two of those cover each other.

Which makes **draw order** the other half of that promise, and it is the overlay's to set:

- **Dots are drawn under badges.** A dot that stayed on its own marker while a badge was stacked
  over it used to be drawn on top of that badge, hiding its name and its aspect. The reverse
  costs nothing — a dot behind a badge still says everything a dot says. `_restack()` orders the
  children every frame (collapsed, then open, then whatever the pointer is on), because for a
  `Control` child order *is* draw order, and it is input order too: a badge now takes the click
  from a dot lying under it.
- **Leader lines belong to the overlay, not to the widgets.** A line drawn in a widget's own
  `_draw()` is drawn with that widget, so it crossed whatever badge happened to lie between the
  widget and its marker. `MarkerOverlay._draw()` draws all of them instead, and a parent draws
  before its children, so every line is behind every badge. The widget keeps only
  `leader_start()` / `leader_end()` / `leader_color()`, in the overlay's coordinates.

## The debug HUD

All three debug panels are sections of one top-left column (`DebugUi/Panels`, a `VBoxContainer`)
and all three **start folded**: a scene opens showing the track, and you open the section you
are working on. Three expanded readouts covered a good part of the screen, which is what folding
exists to fix.

`DebugPanel` is the base. A subclass supplies `_panel_title()`, `_panel_lines()` (the body, only
asked for while open), `_panel_controls()` / `_panel_control_pressed()` (its cycle rows) and
`_panel_key()` (return true if the key was used); the chrome, the fold, the numbering, the input
routing and the per-frame refresh live in the base. **The chrome is built in code**, not authored
per scene, which is what keeps a panel a single node in the `.tscn` with no `readout` node path
to get wrong.

Open a section by clicking its header or with its **number key**: `[1]` trains, `[2]` turnouts,
`[3]` signals. The numbers are read off the column (`DebugPanel.fold_key()` counts `DebugPanel`
siblings) rather than authored, so they always run down it in order and reordering the panels
renumbers them.

**The turnout and signal sections own no keys at all.** They used to: `[T]`/`[G]` selected a
turnout and threw it, `[N]`/`[C]` did the same for a signal. Clicking one is the player's actual
interface, so the keyboard path was a second way in that had to keep working and that nobody
used. What is left in those two sections is a readout and its cycle rows. The train section
keeps `[Tab] [Space] [R] [F] [E]`, because driving a train has no click path yet.

**No readout prints the mouse or the camera controls.** Left click, right-drag to orbit,
middle-drag or `WASD` to pan and the wheel to zoom are standard enough not to need saying, and
the lines saying them were three of the widest in the column. A readout lists state; the keys
still worth printing are the train section's, which are neither standard nor guessable.

Two consequences worth knowing:

- **The switches for the open presentation questions are rows, not keys.** `_panel_controls()`
  returns one label per row and the base builds a flat `Button` for each; a press calls
  `_panel_control_pressed(index)`. A `Button` consumes its click, which is what keeps a press on
  a row from also reaching the 3D picking behind the panel. The rows live in the body, so they
  fold with it and only exist once a section has been opened.
- **The `>` in the turnout and signal readouts marks whatever the mouse is on**, not a
  selection — with no select key there is nothing else it could mean. (The train readout's `>`
  is still a selection, because `[Tab]` still moves it.) Two things can be pointed at and either
  counts: the floating widget (`MarkerOverlay.hovered_subject()`, which reads
  `TrackMarkerWidget.is_pointer_over()`) and the 3D model under it (`Turnout.is_pointer_over()`,
  `RailSignal.is_pointer_over()`, both off the picker's `mouse_entered` / `mouse_exited`). The
  model has to answer for itself because the widget is not always what the pointer is on — in
  `LEGS_3D` there is no widget at all, and the mast or the marker is a target in every mode.

Two things the base has to get right, both of them bitten-once:

- **The header `Button` is `FOCUS_NONE`.** Otherwise it joins the GUI focus chain and `Tab` —
  the train panel's select key — moves focus between headers instead of selecting a train.
- **The panel stays `mouse_filter = IGNORE`; only its buttons stop clicks.** That keeps the
  "a `Control` eats clicks on the 3D world behind it" gotcha below confined to the header strip
  and the cycle rows, which are the places a click is meant to be a UI click.

`tests/debug_panel_test.gd` covers all of it: the fold, the numbering, a synthetic click on a
header, the cycle rows and the hover marker.

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

**"Unlimited" speed is not a thing — there's a real floor, and past it the number actively
hurts.** Each physics tick still costs whatever it costs regardless of `speed` (the delta is
always 1/60 s), so the total tick count for a fixed suite is fixed too; `speed` only controls
how many of them the engine is *allowed* to cram into one real second before it renders a
frame. Once `speed` is high enough that the engine is already CPU-bound and catching up every
frame, raising it further cannot shrink the floor — and measured, it does not stay flat, it
gets worse: the current suite floors around 23-24 s anywhere from `--speed 64` to `--speed
1024`, climbs back to 39 s at `--speed 8192`, and at `--speed 100000` it never even prints the
opening banner (killed after 120 s+). The default is **128** — comfortably inside the flat
band, nowhere near the cliff. Nobody has traced *why* it degrades rather than plateaus (likely
`max_physics_steps_per_frame`, set to `2 * speed`, making the per-frame catch-up burst itself
expensive once it runs into the thousands) — if that gets pinned down, this note should say so.

**A windowed run is for the display server, not for looking at**, and it happens where nobody
can see it. `-Windowed` exists so the click tests have somewhere to click, so
`tests/private_desktop.ps1` creates a **Windows desktop of its own** (`CreateDesktop`, then
`CreateProcess` with `STARTUPINFO.lpDesktop`) and starts the engine on it. A session can hold
many desktops and only one is composited, so the window opens at its normal size, draws,
picks and takes focus entirely within a desktop that is not on screen. Measured: nothing is
ever enumerated on the user's desktop and the foreground window never changes. Both wrappers
hand the launch to it; it relays the child's output line by line so piping `run.ps1` still
works, and exits 200 if the machine will not give it a desktop, which is the wrappers' cue to
fall back.

What it falls back to, and what `-Window minimized|offscreen|visible` select, all stay on the
user's desktop and none of them can hide the window entirely: Godot clamps the `--position`
given on its command line back onto the screen, so a window cannot be *created* out of sight
and is up for ~6 ms whatever we do. The wrappers therefore ask for `--resolution 1x1` - Windows
rounds it up to a 120x1 sliver - and `TestRunner._place_window()` restores the size, parks the
window below every screen and minimizes it, all in `_initialize()` before the first frame.
Minimizing is what gives the keyboard back (Windows returns focus on minimize; a parked window
keeps the focus it took), and doing it after the move keeps the minimize animation off screen.

Two things that did *not* work, so nobody tries them again: `--position` off the desktop (Godot
clamps it at startup - `--position 0,1200` landed at y=785) and `--wid <hwnd>`, which makes the
game window *owned* by the given window rather than a child of it, so it still opens at the
screen centre and still takes focus.

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
  of `DebugUi` in every scene, and orders its own children so dots land under badges — see the
  floating layer above.
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
* **Two presentation questions are open and switchable** rather than decided: which of the four
  turnout modes, which of the three signal widget styles and which of the three collapse rules.
  All three are cycle rows in the debug panels. Whoever settles them should delete the losers
  rather than leave the switches in — they exist to be tried against a real camera and a real
  human, not forever.
* **Step 7 (physics)** is where a signal stops being a wall. A train currently stops dead on the
  signal; with braking it needs to know the distance to it in advance, which is
  `TrackWalker.Step.travelled` on a walk that ends at one — no new machinery, just a longer walk
  and a deceleration curve. The `signals_from` rule is written from the nose, so it survives a
  train whose length changes when wagons are added.
* **Step 4 (compound turnouts)** should group existing `Turnout` nodes rather than extend them.
  Throw members through `throw_points()`, set `player_operable = false` so the group owns the
  clicks, and cycle positions in the group. Two limits to know about: `TrackWalker` needs two
  turnouts on one rail to be more than `EPSILON` apart, and a plain crossing (two rails meeting
  with no possibility of switching between them) has no representation yet — it is not a
  `Turnout`, and the walker has no notion of a rail end that simply continues into another rail.
* **Step 8 (block locking)** is mostly `TrackWalker.walk()` with the length turned up: walk
  ahead from a train and collect the rails, turnouts and signals it will reach. `Turnout`
  already reports refusal, which is the "train cannot be let into a block if it will reach an
  unconnected turnout" rule. What step 3 leaves for it: automatic replacement (a cleared signal
  currently stays clear forever), locking a signal to danger while its block is occupied, and
  locking points under an occupying train. The seams are in place — `RailSignal.aspect`'s setter
  is the single entry point whoever is changing it, `aspect_changed` reports every change, and
  `player_operable = false` takes a signal off the player without the player noticing a
  different code path. Putting a signal back to danger under a moving train is *deliberately*
  allowed and deliberately harmless: the train it is standing over keeps going, the next one up
  is held.