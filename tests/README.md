# Tests

The regression suite for the prototype. It drives the real scenes — `scenes/main.tscn`
and `scenes/demos/turnouts.tscn` — so these are integration tests more than unit tests:
they instantiate a level, run the physics, and assert on what the trains and turnouts did.

## Running them

```powershell
tests\run.ps1                       # everything, headless
tests\run.ps1 driving               # one suite
tests\run.ps1 driving passage       # several
tests\run.ps1 driving::held         # tests whose name contains "held", in that suite
tests\run.ps1 ::spanning            # by test name, whichever suite it is in
tests\run.ps1 -List                 # what would run, as suite::test lines
tests\run.ps1 -Windowed             # keep a window, so the click tests run too
tests\run.ps1 -Json results.json    # machine-readable report as well
tests\run.ps1 -Speed 1              # real time instead of 16x
tests\run.ps1 -Color always         # colour even through a pipe (-NoColor for none)
```

`tests/run.sh` is the same thing for a POSIX shell (`--windowed`, `--json=path`, `--speed=4`).
Both find Godot at `C:\Godot\Godot_v4.7.2-stable_win64_console.exe` unless `$env:GODOT` /
`$GODOT` says otherwise, rebuild the script class cache if it has never been built, and exit
**0** when everything passed or skipped, **1** on a failure, **2** on a bad argument.

Filters match on substrings and `::` splits suite from test, so a filter can be as vague or as
exact as you like.

### Reading the output

Each test prints its name, the context lines it recorded, and a verdict:

```
=== tests/turnout_driving_test.gd ===
  - test_a_facing_move_puts_it_on_the_loop_and_the_far_points_hold_it
        after diverging: on LoopLine  @   18.1 /  126.0 m  nose along rail   throttle +1  clear
        at the far end:  on LoopLine  @  118.0 /  126.0 m  nose along rail   throttle +1  held by LoopEast
    PASS 9 assertions in 1494 ms
```

`PASS` is green, `FAIL` red, `SKIP` yellow, and everything that is context — the notes, the
assertion counts, the rules — is faint, so the verdicts are what the eye lands on. Colour is on
when the output is going to a console and off when it is piped, redirected, or `NO_COLOR` is
set; `-Color always` / `--color always` forces it back on for `| less -R`, and `-NoColor` off.
Godot itself cannot tell the difference, so it is the wrapper that decides — see
[run.ps1](run.ps1).

Failures repeat at the bottom under `FAILED`, and the run ends with one line meant to be
grepped:

```
RESULT ok=true tests=23 passed=23 failed=0 skipped=0 errors=0 duration_ms=13862
```

`--json` writes the same information with the notes and failures attached to each test, for
anything that wants to read a report rather than a log.

## Writing them

A suite is a `*_test.gd` file anywhere under `tests/` that extends
[`TestCase`](framework/test_case.gd); a test is a `test_*` method on it, run in declaration
order. Nothing needs registering, and no `class_name` is needed on the suite itself.

```gdscript
extends TestCase

var _demo: Node

func before_each() -> void:
    _demo = await load_scene("res://scenes/demos/turnouts.tscn")

func test_the_points_start_normal() -> void:
    var west: Turnout = _demo.get_node("Turnouts/LoopWest")
    note("LoopWest is %s" % Turnout.Position.keys()[west.turnout_position])
    assert_eq(west.turnout_position, Turnout.Position.NORMAL, "LoopWest starts normal")
```

Hooks: `before_all` / `after_all` per suite, `before_each` / `after_each` per test. Any of them,
and any test, may be a coroutine — `await` what you need.

Assertions: `assert_true`, `assert_false`, `assert_eq`, `assert_ne`, `assert_near`,
`assert_less`, `assert_greater`, `assert_between`, `assert_null`, `assert_not_null`, plus
`fail` and `succeed`. Each takes the claim as its last argument, phrased as a statement of fact
("the branch is welded to the points"), because that string is what the report prints.

Alongside them: `note()` for a line of context, `skip()` for a test that does not apply here,
`load_scene()` / `own()` for anything that should be freed afterwards, `frames()` and
`physics_frames()` for waiting, `has_display()` for tests that need a window.

Three things that are not like Python or TypeScript:

- **One suite instance, not one per test.** `before_all` can stash state in members; nothing is
  reset between tests, so per-test state goes in `before_each`.
- **A failed assertion does not abort the test.** GDScript has no exceptions, so assertions
  record their verdict and return it — the rest of the test still runs, which is usually what
  you want in a scene test. Bail out by hand where carrying on would be nonsense:
  `if not assert_not_null(x, "..."): return`.
- **Time is counted in frames, never in seconds of wall clock.** The runner speeds the clock up
  16x by stepping physics that much more often while leaving the physics delta at exactly
  1/60 s, so `await physics_frames(60)` is one second of game time at any `--speed`. Both are
  verified: the same run at `--speed 1` and `--speed 16` prints identical numbers.

Shared fixtures live in `tests/support/` and are not collected as suites, because they do not
end in `_test.gd`. [`TurnoutDemoCase`](support/turnout_demo_case.gd) is the one that exists: it
builds a fresh copy of the turnout demo for every test and exposes its rails, turnouts and the
shuttle.

## What is here

| suite | what it covers |
| --- | --- |
| `turnout_geometry_test.gd` | branches welded to the points, tangent departure, which hand a turnout is, configuration warnings |
| `turnout_passage_test.gd` | the passage table straight through `Turnout.traverse`, every leg in both positions |
| `turnout_driving_test.gd` | a train driving all of it: diverging, being held and released, the dead-end siding, a body spanning two rails, points thrown underneath |
| `main_scene_test.gd` | `scenes/main.tscn`: turnouts still welded after surface snapping, the freight train held at the junction, bodies at the arc position their distance says |
| `turnout_click_test.gd` | throwing points by clicking the 3D marker and the floating widget, through the real input path (needs `-Windowed`) |
