# Notes for further development

What the finished steps left for the ones not built yet: seams deliberately left in place,
limits the next implementer will hit, and decisions already taken that a later step should not
re-open.

This is the implementers' side of the plan. **The plan itself is
[prototype_goals.md](../prototype_goals.md), which belongs to the project owner — read it, never
edit it.** When a step is finished, its notes for the future go here instead, under the heading
of the step they are aimed at.

## Step 4 — Compound turnouts

Compound turnouts should **group** existing `Turnout` nodes rather than extend them: throw
members through `throw_points()`, set `player_operable = false` so the group owns the clicks, and
cycle positions in the group. `Turnout.throw_points()` is the single entry point for throwing,
whoever is throwing it, and `position_changed` fires whenever the points move — see
[turnouts.md](turnouts.md).

Two limits to know about:

- `TrackWalker` needs two turnouts on one rail to be more than `EPSILON` apart.
- A plain **crossing** — two rails meeting with no possibility of switching between them — has no
  representation yet. It is not a `Turnout`, and the walker has no notion of a rail end that
  simply continues into another rail.

## Step 5 — Simple editor

Placement is numeric on purpose: step 2 left gizmo-drag placement here, along with running
**Align Branch To Turnout** as part of editing rather than as a manual button press. What the
button does, and how to weld a branch without an editor at all, is in
[level_authoring.md](level_authoring.md).

## Step 7 — Trains with wagons and better physics

This is where a signal stops being a wall. A train currently stops dead on the signal; with
braking it needs to know the distance to it in advance, which is `TrackWalker.Step.travelled` on
a walk that ends at one — no new machinery, just a longer walk and a deceleration curve.

The `signals_from` rule is written from the nose, so it survives a train whose length changes
when wagons are added. See [signals.md](signals.md).

## Step 8 — Block locking

Mostly `TrackWalker.walk()` with the length turned up: walk ahead from a train and collect the
rails, turnouts and signals it will reach. `Turnout` already reports refusal, which is the "train
cannot be let into a block if it will reach an unconnected turnout" rule.

Still missing: automatic replacement (a cleared signal currently stays clear forever), locking a
signal to danger while its block is occupied, and locking points under an occupying train.

The seams are in place — `RailSignal.aspect`'s setter is the single entry point whoever is
changing it, `aspect_changed` reports every change, and `player_operable = false` takes a signal
off the player without the player noticing a different code path. Putting a signal back to danger
under a moving train is *deliberately* allowed and deliberately harmless: the train it is
standing over keeps going, the next one up is held.

## Not tied to a step

- **`Train.end_behavior` is a placeholder.** It now fires only at a genuine dead end, but real
  levels will want buffer stops and off-level connections there instead.
- **Two presentation questions are still open** — the turnout modes, the signal widget styles and
  the collapse rules are all switchable rather than decided. Whoever settles them should delete
  the losers; see the end of [ui.md](ui.md).
- **Surface snapping moves only curve points and handles**, so point spacing has to be finer than
  the terrain's features. If real levels get hillier, per-segment subdivision may be worth
  adding — see [level_authoring.md](level_authoring.md).
