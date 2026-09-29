---
name: prototype-step
description: Implement a step, sub-step, or bullet from prototype_goals.md in this Godot railway-dispatcher prototype. Use whenever the user asks to implement, start, continue, or finish any numbered step or section of the prototype plan (e.g. "implement step 2", "do the turnouts step", "let's do signals", "next step", "finish the compound turnouts"), or asks to extend prototype functionality described in that file.
---

# Implementing a prototype step

You are implementing a prototype of a game where the player is a railroad dispatcher.
Game design is in [README.md](../../../README.md); the implementation plan is in
[prototype_goals.md](../../../prototype_goals.md). **That plan belongs to the project owner —
read it, never edit it**, only allowed change is to tick a step off as done. If it needs changing, say so in
conversation and let them make the change. What earlier steps left for the one you are on is in
[docs/further_development.md](../../../docs/further_development.md), which *is* yours to write.

The working notes are split in two, and both matter before you write code:

- [CLAUDE.md](../../../CLAUDE.md) is already in your context — project facts, commands, the
  architecture map and the **gotchas**, which exist to stop you re-discovering the same Godot
  traps. Re-read the gotchas; they are the expensive ones.
- [docs/](../../../docs/) has one file per subsystem — `turnouts.md`, `signals.md`, `ui.md`,
  `level_authoring.md`, plus `further_development.md`, `naming_conventions.md`, and
  [tests/README.md](../../../tests/README.md) for the suite. **Open the ones your step touches**,
  and the ones it builds on — starting with `further_development.md`, which is where the last
  implementer wrote down what they left you. CLAUDE.md lists them all and summarises the four
  rules that cut across everything. A step that extends turnouts without reading
  `docs/turnouts.md` will re-litigate decisions that were already made.

## Scope

- **Implement only what the user asked for.** A step, a sub-step, or a single bullet. Do not
  start the next step because it seems natural, and do not implement the "later steps" the plan
  mentions.
- **Do leave seams for them.** The plan says explicitly where a feature gets extended.
  Design the data model so those extensions are additions, not rewrites — but don't build speculative abstractions for things the plan hasn't described yet.
- Existing behaviour marked as a placeholder in CLAUDE.md (e.g. `Train.end_behavior`) is fair
  game to replace when the step you're implementing supersedes it. Say so when you do.

## Clarify before building

The plan is deliberately loose. Where two readings would lead to materially different work,
**ask before writing it** — up front and batched, not drip-fed. Ask as many questions as the
ambiguity actually warrants; a long round of questions is welcome, a trickle of them mid-build
is not. `AskUserQuestion` takes at most 4 per call, so send several calls back to back and keep
each question self-contained.

**Gameplay design and UX questions matter most.** How the player interacts with the thing, what
they see, what the debug UI shows, how a mechanic should behave in the awkward cases, what
counts as "done" for a bullet in prototype terms. Ask these freely — they are the user's call,
not yours, and guessing wrong wastes a whole step.

**Implementation questions only when the answer outlives this step**: a data model that later
steps build on, something that constrains how a step the plan hasn't specified yet could work,
or how a feature gets authored in the editor. Ordinary code decisions — file layout, naming,
class structure, which Godot node to use — are yours to make; make them and move on.

Anything you can settle from README.md, prototype_goals.md, CLAUDE.md, `docs/`, or the existing
code, settle yourself. Don't ask permission to proceed.

## House rules (this repo)

- **Godot 4.7, GDScript only, warnings are errors.** Annotate types explicitly; `:=` fails on
  anything the analyser can't infer. See CLAUDE.md for the full list of traps —
  hand-written `.tscn` `node_paths`, row-major `Transform3D`, `Curve3D` `_data` layout,
  vertex colours as linear, `INTERNAL_MODE_BACK` for generated nodes.
- **Level data must be editable in the editor.** The plan asks for this repeatedly. That means
  `@tool` scripts, exported properties, inspector buttons for one-shot operations, and
  `_get_configuration_warnings()` for misconfigured nodes. Remember editor physics is not
  stepped — no raycasts from a `@tool` script.
- **Keep gameplay separate from debug.** Real gameplay input goes through the `InputMap`;
  debug controls use physical keycodes and live under `scripts/debug/`.
- Match the existing structure: `scripts/<area>/<thing>.gd` with a `class_name`, one concept per
  file, and the same comment density as the surrounding code.

## The output is always a playable scene

Every step ends with something a human can launch and drive that demonstrates **all** the new
functionality — including the failure cases the plan calls out (a train refused by a turnout set
against it, a signal at danger). Add the debug UI needed to see what the system is doing.

Extend `scenes/main.tscn` when the new feature belongs in the running prototype; add a focused
scene under `scenes/demos/` when the step needs a layout of its own (a yard, a crossover, a
double slip switch). Keep older demo scenes working — the suite under `tests/` drives them.

## Verify it, don't assume it

Before reporting done, actually run things (binary paths and flags are in CLAUDE.md):

1. `--headless --path . --import` after adding any `class_name`.
2. `--check-only --script res://…` on every script you touched or created.
3. `tests/run.ps1` — the whole suite, not just the part you touched. It drives both scenes, so
   it is how you find out you broke an earlier step.
4. Run the playable scene headlessly with `--quit-after` and read the output — no errors,
   no warnings, and the behaviour you expect actually printed.
5. Take a screenshot with the throwaway-scene recipe in CLAUDE.md and **look at it**, for
   anything visual. Godot fails visually in silence far more often than it errors.

**Leave tests behind for the step you just built.** Add a `tests/<thing>_test.gd` covering the
new rule and the failure cases the plan calls out — `tests/README.md` says how, and the existing
suites are the pattern to copy. A step's playable scene shows a human it works; the suite is
what keeps it working.

Report what you ran and what it said. If something is broken or unfinished, say that plainly.

## Afterwards

Writing the notes up is expected, not optional — but each kind goes in one place:

- **CLAUDE.md** gets only what every future session needs *before* it knows it needs it: new
  entries in the architecture map, and **anything you learned the hard way** — a Godot trap, a
  silent failure, an hour lost to something that looked like it worked. Keep the entry in the
  voice of the others, including what it cost; that is what makes it stick. Do not add a
  subsystem walkthrough here.
- **`docs/<subsystem>.md`** gets how the thing you just built actually works and *why it is that
  way*: the rules, the cases that look like bugs and are not, and the decisions you took.
  Extend the existing file if your step extended that subsystem; add a new one, and a row in
  CLAUDE.md's "The rest of the notes" table, if the step introduced a subsystem of its own.
- **`docs/further_development.md`** gets what your step leaves for a later one, under that
  step's heading: seams you deliberately left, limits the next implementer will hit, decisions
  already taken that they should not re-open. Delete the notes you have just made obsolete by
  building the thing they were about.
- **`prototype_goals.md` gets nothing.** It is the owner's plan and it is read-only to you —
  excluding only the *(done)* markers. If your step changed what a later step should be, write that
  in `docs/further_development.md` and mention it in conversation.
- **`tests/README.md`** gets anything new about running or writing the suite.

When a step supersedes something these files describe — a placeholder replaced, a rule changed —
**edit the old text out** rather than adding a note beside it. Two descriptions of one rule is
how a doc starts lying.
- Never run any git commands - this is handled manually.

## Subagents

Use them for read-only fan-out — surveying Godot 4.7 API options, reading how an existing
subsystem works, reviewing a finished implementation against the plan. Keep writing to one
agent: concurrent edits to the same `.tscn`, to CLAUDE.md or to a file under `docs/` will
clobber each other.
