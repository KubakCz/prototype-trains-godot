---
name: prototype-step
description: Implement a step, sub-step, or bullet from prototype_goals.md in this Godot railway-dispatcher prototype. Use whenever the user asks to implement, start, continue, or finish any numbered step or section of the prototype plan (e.g. "implement step 2", "do the turnouts step", "let's do signals", "next step", "finish the compound turnouts"), or asks to extend prototype functionality described in that file.
---

# Implementing a prototype step

You are implementing a prototype of a game where the player is a railroad dispatcher. The game
design is in [README.md](../../../README.md); the implementation plan is in
[prototype_goals.md](../../../prototype_goals.md). **That plan belongs to the project owner -
read it, never edit it**, except to tick a step off as *(done)*. If it needs changing, say so in
conversation and let them make the change.

**Your context is the scarce resource.** Reading, test-writing, verifying and reviewing go to
the subagents in `.claude/agents/`, which return short reports; you keep the design, the
questions to the user, the implementation, the fixes and the write-up. Never run git - the user
handles it.

## The flow

1. **Brief** - spawn `step-briefer` with the step as the user named it. Read README.md and the
   step in prototype_goals.md yourself (they are short and you need them first-hand); take the
   rest from the brief, and open a doc section yourself only where the brief leaves you unsure.
2. **Clarify** - ask the user what the brief's open questions and your own reading leave open
   (below), before writing code.
3. **Implement** - yourself. The `.claude/rules/` traps for each area load as you open its files.
4. **Test and verify, in parallel** - spawn `test-writer` and `step-verifier` in one message:
   - `test-writer`: the plan bullets with the user's decisions, the public API you built, the
     scene or fixture to use, and the failure cases the plan calls out. Do not hand it your
     implementation's reasoning - its tests are worth most when written to the spec.
   - `step-verifier`: the scripts you touched, whether a `class_name` was added, the playable
     scene and what it should print, and what each screenshot should show.
5. **Fix** - you fix what they report, then send the verifier a message (not a new spawn) to
   re-run. A test the test-writer reports failing is a finding about the feature until you have
   shown the test is wrong; if you change a test, say why in your final report.
6. **Review** - spawn `step-reviewer` with the step, the user's decisions and the changed files.
   Address what it finds, or say why not.
7. **Write the notes** - read [notes.md](notes.md) and follow it.
8. **Report** to the user: what was built, the verifier's final report (its `RESULT` line
   verbatim), the reviewer's open findings, and anything unfinished, plainly.

Skip a subagent only when the step is too small to need it (a one-bullet tweak) - and then do
that part yourself, including running the whole suite.

## Scope

- **Implement only what the user asked for.** A step, a sub-step, or a single bullet. Do not
  start the next step because it seems natural, and do not implement the "later steps" the plan
  mentions.
- **Do leave seams for them.** The plan says explicitly where a feature gets extended. Design the
  data model so those extensions are additions, not rewrites - but don't build speculative
  abstractions for things the plan hasn't described yet.
- Existing behaviour marked as a placeholder (e.g. `Train.end_behavior`) is fair game to replace
  when the step you're implementing supersedes it. Say so when you do.

## Clarify before building

The plan is deliberately loose. Where two readings would lead to materially different work,
**ask before writing it** - up front and batched, not drip-fed. Ask as many questions as the
ambiguity actually warrants; a long round of questions is welcome, a trickle of them mid-build
is not. `AskUserQuestion` takes at most 4 per call, so send several calls back to back and keep
each question self-contained.

**Gameplay design and UX questions matter most.** How the player interacts with the thing, what
they see, what the debug UI shows, how a mechanic should behave in the awkward cases, what
counts as "done" for a bullet in prototype terms. Ask these freely - they are the user's call,
not yours, and guessing wrong wastes a whole step.

**Implementation questions only when the answer outlives this step**: a data model that later
steps build on, something that constrains how a step the plan hasn't specified yet could work,
or how a feature gets authored in the editor. Ordinary code decisions - file layout, naming,
class structure, which Godot node to use - are yours to make; make them and move on.

Anything you can settle from the plan, the notes or the code, settle yourself. Don't ask
permission to proceed.

## House rules (this repo)

CLAUDE.md has the language rules and the traps that apply everywhere. On top of those:

- **Level data must be editable in the editor.** That means `@tool` scripts, exported
  properties, inspector buttons for one-shot operations, and `_get_configuration_warnings()` for
  misconfigured nodes.
- **Keep gameplay separate from debug.** Real gameplay input goes through the `InputMap`; debug
  controls use physical keycodes and live under `scripts/debug/`.
- Match the existing structure: `scripts/<area>/<thing>.gd` with a `class_name`, one concept per
  file, and the same comment density as the surrounding code.

## The output is always a playable scene

Every step ends with something a human can launch and drive that demonstrates **all** the new
functionality - including the failure cases the plan calls out (a train refused by a turnout set
against it, a signal at danger). Add the debug UI needed to see what the system is doing.

Extend the playground, `scenes/main.tscn`, when the new feature belongs in the running prototype.
It is generated: change `tools/build_playground.gd` and re-run it rather than editing the scene.
Add a focused scene under `scenes/demos/` when the step needs a layout of its own. Keep older
demo scenes working - the suite drives them.

## Subagents and writing

Only one agent writes to any given file. The test-writer owns `tests/`; you own everything else.
Concurrent edits to the same `.tscn`, to CLAUDE.md or to a file under `docs/` clobber each other,
so the briefer, the verifier and the reviewer are read-only, and for any other read-only fan-out
(Godot API questions, how a subsystem works) use the built-in `Explore` agent.
