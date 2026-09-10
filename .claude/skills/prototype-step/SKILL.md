---
name: prototype-step
description: Implement a step, sub-step, or bullet from prototype_goals.md in this Godot railway-dispatcher prototype. Use whenever the user asks to implement, start, continue, or finish any numbered step or section of the prototype plan (e.g. "implement step 2", "do the turnouts step", "let's do signals", "next step", "finish the compound turnouts"), or asks to extend prototype functionality described in that file.
---

# Implementing a prototype step

You are implementing a prototype of a game where the player is a railroad dispatcher.
Game design is in [README.md](../../../README.md), the implementation plan is in
[prototype_goals.md](../../../prototype_goals.md), and working notes / engine gotchas are in
[CLAUDE.md](../../../CLAUDE.md). Read the relevant sections of all three before writing code —
CLAUDE.md especially, it exists to stop you re-discovering the same Godot traps.

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

Anything you can settle from README.md, prototype_goals.md, CLAUDE.md, or the existing code,
settle yourself. Don't ask permission to proceed.

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
double slip switch). Keep older demo scenes working — they're the regression suite.

## Verify it, don't assume it

Before reporting done, actually run things (binary paths and flags are in CLAUDE.md):

1. `--headless --path . --import` after adding any `class_name`.
2. `--check-only --script res://…` on every script you touched or created.
3. Run the playable scene headlessly with `--quit-after` and read the output — no errors,
   no warnings, and the behaviour you expect actually printed.
4. Take a screenshot with the throwaway-scene recipe in CLAUDE.md and **look at it**, for
   anything visual. Godot fails visually in silence far more often than it errors.

Report what you ran and what it said. If something is broken or unfinished, say that plainly.

## Afterwards

- **Update CLAUDE.md**: new architecture entries, anything you learned the hard way, and notes
  for whoever implements the next step. This is expected, not optional.
- Update `prototype_goals.md` only to record progress or fold in decisions made with the user —
  it's their plan, so don't rewrite its intent.
- Never run any git commands - this is handled manually.

## Subagents

Use them for read-only fan-out — surveying Godot 4.7 API options, reading how an existing
subsystem works, reviewing a finished implementation against the plan. Keep writing to one
agent: concurrent edits to the same `.tscn` or to CLAUDE.md will clobber each other.
