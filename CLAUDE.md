# CLAUDE.md

Working notes for this repo: the facts, the commands, where everything else is written down, and
the rules and engine traps that apply to every change. **Kept short on purpose** - it is loaded
into every session, so anything that only matters for one subsystem lives with that subsystem.

- [README.md](README.md) — the game design.
- [prototype_goals.md](prototype_goals.md) — the implementation plan. **It belongs to the
  project owner: read it, never edit it.** Propose changes in conversation instead.
- [docs/](docs/) — the subsystems in detail, listed under "Where things are written down" below.

## Project facts

- **Godot 4.7** (`config/features` in `project.godot` pins `"4.7"`), Forward+ (D3D12 on Windows).
- **Linux is the primary platform** (the Fedora desktop, and the Ubuntu agent sandbox). Editor
  binary: **`godot`** on `PATH`, installed by `tools/setup_godot.sh` into
  `~/.local/opt/godot/<version>/` and linked as `~/.local/bin/godot`. One binary: stdout works
  as is. A fresh sandbox has no Godot (`$HOME` is not the user's, so a host install is not
  visible inside it): run the script once, it needs network access to github.com.
- Windowed runs (the click tests) need a display. The sandbox has none, so `tests/run.sh` goes
  through `xvfb-run`: `sudo apt-get install xvfb xauth mesa-vulkan-drivers libgl1 libxcursor1
  libxinerama1 libxi6 libxrandr2` (Ubuntu; software Vulkan is what Forward+ renders with there).
- **Windows** still works: **`C:\Godot\Godot_v4.7.2-stable_win64.exe`** — not on `PATH`; use
  `Godot_v4.7.2-stable_win64_console.exe` when you want stdout. `tests/run.ps1` is the
  Windows runner and `tests/run.sh` also works under Git Bash. An old 4.4.1-mono under
  `~/Documents/Godot/` is unrelated; don't open the project with it.
- **GDScript**, no C#. Warnings are errors: untyped/`Variant` inference fails the parse,
  so annotate explicitly (`var x: float = a if c else b`) rather than using `:=` on
  anything the analyser can't type.
- Main scene: `scenes/main.tscn`.

## Commands

Written for Linux; on Windows read `godot` as `Godot_v4.7.2-stable_win64_console.exe`.

```bash
# Rebuild the import + global class-name cache. Do this after adding a class_name;
# --check-only cannot resolve cross-script class names until it has run.
godot --headless --path . --import

# Parse-check one script.
godot --headless --path . --check-only --script res://scripts/rails/rail.gd

# Run a scene headlessly (harness scenes, smoke checks).
godot --headless --path . res://some/scene.tscn --quit-after 2000

# The whole regression suite (tests/README.md). Exits non-zero on failure.
tests/run.sh
tests/run.sh driving passage     # only matching suites
tests/run.sh --list
tests/run.sh --color always      # colour survives a pipe; --no-color turns it off

# Same, plus the synthetic-click tests (3D pick and floating widget) - needs a window.
# With no display (the sandbox) it runs under xvfb-run; on a desktop the window is
# minimized. Clicks convert canvas -> window coordinates themselves, so its size and
# position are its own business.
tests/run.sh --windowed
tests/run.sh --window visible    # ... or leave it where you can watch a click test fail

# Open a scene in the editor without a human, to exercise @tool paths.
godot --headless --path . --editor res://scenes/main.tscn --quit-after 90

# Regenerate the playground - scenes/main.tscn and its heightmap - from tools/build_playground.gd.
# Overwrites both; see docs/level_authoring.md.
godot --headless --path . --script res://tools/build_playground.gd

# Same for the bridges-and-tunnels demo, scenes/demos/structures.tscn; see docs/track.md.
godot --headless --path . --script res://tools/build_structures_demo.gd
# ... and the stations demo, scenes/demos/stations.tscn; see docs/level_authoring.md.
godot --headless --path . --script res://tools/build_stations_demo.gd
```

On Windows the suite is `tests/run.ps1` (`-List`, `-Color always`, `-Windowed`, `-Window visible`),
and a windowed run opens its window on a private Windows desktop, so nothing of it reaches the
screen and nothing takes the keyboard.

To eyeball a change without a human at the keyboard: run a throwaway `Node` scene
that instantiates `main.tscn`, `await RenderingServer.frame_post_draw` ~30 times, then
`get_viewport().get_texture().get_image().save_png("user://shot.png")`. Output lands in
`~/.local/share/godot/app_userdata/Train game prototype/` (Windows:
`%APPDATA%\Godot\app_userdata\Train game prototype\`). Needs a real window — omit
`--headless`; with no display (the sandbox), run it under `xvfb-run -a`.
The throwaway script need not live in the project: `--script C:/absolute/path/shot.gd` runs an
`extends SceneTree` script from anywhere, and `res://` paths inside it still resolve.

## Sandbox

The agent sandbox (`/etc/sandbox-persistent.sh` is sourced before every command) needs three
things remembered; the sandbox's own long notes are excluded from context on purpose:

- If `godot` or another tool is missing from `PATH`, run it through `bash -l -c "..."`.
- **Never put shell completion scripts into `/etc/sandbox-persistent.sh`** - it breaks every
  later command silently.
- Outbound network goes through a firewall. A blocked request answers **HTTP 403 with an
  explanation in the body**: read it and pass what it asks for on to the user rather than
  working around it.

## Layout

```
scripts/rails/    the track network: Rail, Turnout, CompoundTurnout, Crossing, RailSignal, TrackWalker
scripts/trains/   Train, TrainCar and the resource types (CarType, LocomotiveType, WagonType, Livery, TrainType)
scripts/traffic/  interest points, stations, outside connections, routes, the spawner
scripts/track/    the generated track meshes, bridges and tunnels
scripts/world/    Ground, the terrain
scripts/ui/       gameplay UI: the floating marker overlay and its widgets, the route list
scripts/debug/    the debug HUD panels and the camera rig
rolling_stock/    shared locomotive and wagon types (.tres); train_types/ the spawner's recipes
scenes/           main.tscn (generated), demos/, levels/
tools/            setup_godot.sh and the generators for the generated scenes
tests/            the suite: framework/, support/ fixtures, *_test.gd
```

The class-by-class map, every scene and what it is for, and the core model (rails as `Path3D`,
why `PathFollow3D` is not used, how a train's direction is held) are in
[docs/architecture.md](docs/architecture.md). **Read it before a change that adds a class or a
scene.** Three scenes are **generated** - `scenes/main.tscn`, `scenes/demos/structures.tscn` and
`scenes/demos/stations.tscn`: edit their `tools/build_*.gd` and re-run, never the `.tscn`.
Every scene is driven by the tests under `tests/`; keep them working.

## Where things are written down

One file per subsystem, under [docs/](docs/). Read the one you are about to touch — each is
the design record for its step, including the cases that look like bugs and are not. Read by
section: list a file's headings first (`grep -n '^#' docs/x.md`) and open the parts you need.

| file | what is in it |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | the class map, the scenes, rails as `Path3D`, train direction and consists in brief |
| [docs/turnouts.md](docs/turnouts.md) | the three legs, the passage table, refusal, what is authored vs. derived, the presentation modes and the schematic caption |
| [docs/compound_turnouts.md](docs/compound_turnouts.md) | assemblies of turnouts worked as one, their positions and single control, routes found by walking, crossings and their occupants |
| [docs/trains.md](docs/trains.md) | consists and rolling-stock types, acceleration and braking, what a train stops for, overrunning, derailment and collisions, the front marker, selection |
| [docs/stations.md](docs/stations.md) | interest points, stations and outside connections, routes, the spawner, what a train does at a station and on leaving, liveries, the two ways a route is shown |
| [docs/signals.md](docs/signals.md) | which direction a signal governs, the stopping rule written from the nose, `signals_from`, the three widget styles |
| [docs/ui.md](docs/ui.md) | interface scale, the floating marker layer and its de-cluttering, the debug HUD's panels and keys |
| [docs/level_authoring.md](docs/level_authoring.md) | snapping rails to the terrain, and welding a branch onto a turnout (with and without the editor) |
| [docs/track.md](docs/track.md) | the generated track: where the rails are cut and why, moving blades, check rails, shared timbers, ballast, buffer stops, chunks and editor rebuilds; bridges, tunnels and the holes they cut in the ground |
| [docs/further_development.md](docs/further_development.md) | what finished steps left for the ones not built yet, per step |
| [tests/README.md](tests/README.md) | running and writing the suite, how fast to run the clock, the window a windowed run opens |
| [docs/naming_conventions.md](docs/naming_conventions.md) | what things are called |

**Engine traps by area** are in `.claude/rules/`, and Claude Code loads each one automatically the
moment a matching file is read or written - so they are not repeated here:

| rule file | loaded for |
| --- | --- |
| `tscn.md` | hand-written `.tscn`, the generators under `tools/` |
| `meshes-and-ground.md` | `scripts/world/`, `scripts/track/`, `rail.gd`, `surface_snapper.gd`, levels |
| `track-network.md` | `scripts/rails/`, `scripts/trains/`, `scripts/traffic/` |
| `ui-and-input.md` | `scripts/ui/`, `scripts/debug/`, anything clickable, the click tests |
| `tests.md` | everything under `tests/` |

## Rules that cut across everything

Breaking any of these looks like it works:

- **Only a red signal (or the end of the line) stops a train; points set against it do not.**
  A turnout refuses a trailing move against the points, and the train runs into them and derails.
  At a red it brakes to stand `Train.STOP_SHORT` (3 m) short, holds with its throttle still open
  and goes the instant it clears (`Train.blocking_signal`). Found too late to stop for, a red is
  overrun; points thrown *under* a train derail it too — see [docs/trains.md](docs/trains.md).
- **A signal is a property of a direction of travel, not of a place.** `governs` says which way
  the trains it applies to are going; a train going the other way never sees it. Two signals to
  stop both directions, and the side the mast stands on is derived from `governs`, not authored.
- **`TrackWalker.walk()` replaces arithmetic on `Train.distance`**, for driving *and* for body
  placement, because plain addition stops at a rail's own ends — exactly what turnouts exist to
  get past. Step 9's block locking is the same walk with the length turned up.
- **Left click is the only way to throw a turnout or change a signal** — the 3D model or the
  floating widget. There is no keyboard path and there should not be one.

**Two presentation questions are deliberately still open** and switchable rather than decided;
the cycle rows in the debug panels are where they live. See the end of [docs/ui.md](docs/ui.md).
- **A train's direction is two values, never a signed speed.** `facing` (which way the nose
  points along the rail) and `throttle` (`-1` / `0` / `1`: nose-first, stand, back up), with
  `current_speed` never negative. Reversing a train and turning it round are different
  operations; see [docs/architecture.md](docs/architecture.md).

## Gotchas that apply everywhere

The traps every script can hit. Those that belong to one area are in `.claude/rules/` (above).

- **Editor physics is not stepped**, so `PhysicsDirectSpaceState3D.intersect_ray` finds nothing
  from a `@tool` script. `SurfaceSnapper` intersects mesh triangles
  (`Geometry3D.ray_intersects_triangle`) instead, which behaves identically in editor and game.
- **Generated nodes use `INTERNAL_MODE_BACK`** (`Rail`'s debug lines, `Train`'s cars) so
  they never get saved into the scene or show up in the scene tree.
- **`Vector2.angle_to` is signed** (`Vector3.angle_to` is not). Folding an angle into 0-90° with
  `minf(a, 180 - a)` then turns every crossing measured clockwise into a negative angle, and a
  "too shallow to be a crossing" filter dropped exactly half the frogs in every level - silently,
  since a turnout without its frog gap still draws. Take `absf` first.
- **GDScript's `%` format has no `%g`.** Use `%f`/`%.Nf`/`%s`; `%g` raises "unsupported format
  character" at runtime, not parse time.
- **Array literals are `Variant`, so annotate the loop variable**: `for t: Turnout in [a, b]:`.
  Without it every `t.method()` is `Variant` and warnings-are-errors kills the next `var x :=`.
- **A `Variant` holding a bool or an int cannot be cast with `as`.** `value as Node` raises
  "Invalid cast: can't convert a non-object value to an object type" at runtime, where
  object-to-object casts merely give `null`. Test `if value is Object` before casting anything
  that came in as `Variant`.
- Debug controls use physical keycodes rather than `InputMap` actions, keeping the project's
  action list free for real gameplay. Throwing a turnout is *gameplay*, so it goes through the
  `interact` action (left mouse button) — the first entry in the project's action list, and the
  one signals and selecting a train reuse.
- **A class that Train names cannot name Train back.** `OutsideConnection.spawn_pose` returns the
  facing as a bare `1` / `-1` rather than `Train.ALONG_RAIL`, for the same reason `Rail` holds
  `Array[Node]`: `Train` names `InterestPoint`, `Station` and `OutsideConnection`, and a cycle of
  class names between scripts is where the parser starts failing on things that look fine.

## Keeping these notes small

This file has a budget of about 15 000 characters (`wc -c CLAUDE.md`; it was 14 000 when the
budget was set) - over it, move something out before adding. A new trap goes into the `.claude/rules/` file for its
area (or a new rule file with its own `paths:`, plus a row in the table above); only a trap that
any script could hit goes here. A subsystem walkthrough goes into `docs/`, never here.
