---
paths:
  - "tests/**"
---

# Gotchas: the test suite and headless runs

Traps for running and writing the suite. Found the hard way; keep new ones in the same voice, including what they cost. How the suite works is in tests/README.md; click-test coordinates are in .claude/rules/ui-and-input.md.

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
- **A synthetic mouse motion gives a `Control` a hover state but a collider only a pulse.**
  The GUI keeps its `mouse_over` until the next event arrives, so a widget hovered through
  `Input.parse_input_event` stays hovered and can be read at leisure. Physics picking does not:
  it re-picks from the *real* cursor on the following frame, and a `CollisionObject3D` the test
  never actually pointed at reports `mouse_exited` immediately after entering. So a 3D hover has
  to be watched for over the next few *physics* frames rather than read once —
  `TestCase.hover_probe()` — and never from frame zero, where the flag still holds whatever the
  previous position left it. A negative ("the pointer is *not* on this") wants a short watch for
  the same reason: the real cursor is loose in the window and picking keeps consulting it.
- **Godot writes terminal colour into pipes too.** Neither `print_rich` nor a raw ANSI escape
  is filtered when stdout is a file or a pipe — the engine does no tty detection, and GDScript
  has no `isatty` to do it with. So the caller decides: `tests/run.ps1` and `tests/run.sh` pass
  `--color never` when `[Console]::IsOutputRedirected` / `! -t 1` says nobody is watching, and
  the runner also honours `NO_COLOR`. Pad before painting, never after — the escapes count
  towards `%-4s` and friends.
- **Physics steps per real second are `Engine.physics_ticks_per_second`; the physics delta is
  `time_scale / physics_ticks_per_second`.** Measured, all four combinations: `time_scale` alone
  does *not* run a headless simulation faster, it makes each step cover more ground (at
  `time_scale = 8`, `delta` is 0.133 s and a train jumps 2 m per step, which is how you skip
  clean over a turnout). Raise **both** — `ticks = 60 * n`, `time_scale = n` — and the delta
  stays 1/60 s while the simulation runs `n` times faster than real time. That is the whole
  trick behind `tests/run.ps1` running at 128x real time.
- **`await physics_frame` is one step; `await process_frame` is however many steps fit.** So with
  the clock sped up, waiting on an idle frame advances the simulation by an unpredictable
  amount. Anything that needs a repeatable starting state waits on physics frames
  (`TestCase.load_scene` does).
- **`Script.get_script_method_list()` includes the base scripts' methods too**, derived first,
  each in declaration order — so an inherited method appears twice and the first sighting is the
  override. Fine for ordering tests by declaration, but it has to be de-duplicated.
- **PowerShell binds bare arguments to the first non-switch parameter declared.** A wrapper that
  wants pass-through arguments must declare its `ValueFromRemainingArguments` parameter *first*
  (`tests/run.ps1` does), or `run.ps1 driving` tries to parse `driving` as `-Speed`.
- **A train that frees itself cannot be captured by a lambda.** `drive_until(func(): return
  train.x)` over a train that has left the level prints "Lambda capture at index 0 was freed" on
  every frame after, and the test still passes. Ask by `get_instance_id()` and
  `is_instance_id_valid()` - see `spawner_test.gd`.
