# Notes for further development

What the finished steps left for the ones not built yet: seams deliberately left in place,
limits the next implementer will hit, and decisions already taken that a later step should not
re-open.

This is the implementers' side of the plan. **The plan itself is
[prototype_goals.md](../prototype_goals.md), which belongs to the project owner — read it, never
edit it.** When a step is finished, its notes for the future go here instead, under the heading
of the step they are aimed at.

## Step 5 — Simple editor

Placement is numeric on purpose: step 2 left gizmo-drag placement here, along with running
**Align Branch To Turnout** as part of editing rather than as a manual button press. What the
button does, and how to weld a branch without an editor at all, is in
[level_authoring.md](level_authoring.md).

Step 4 added more hand work in the same spirit: a compound assembly's members and connecting
rails are all placed one by one, and a `Crossing` has its own **Locate Crossing** button. An
editor that places a crossover as one thing — two turnouts, the link and both welds — would save
most of it. The assembly's configuration warnings already say what a correct one looks like; see
[compound_turnouts.md](compound_turnouts.md). `TrackWalker` needs two turnouts on one rail to be
more than `EPSILON` apart, so a three-way is staggered by a few metres, and an editor placing one
should keep it that way.

## Step 6 — Rail models

Where the running rails need gaps is all recorded already: at every turnout (the points), and at
every `Crossing` — `rail_a`/`distance_a` and `rail_b`/`distance_b` are the two rails and where
along each they cross, and `crossing_angle_degrees()` is the angle the frog needs. A double
crossover's middle is an ordinary `Crossing` (`ScissorsMiddle` in the demo), and so is a double
slip's diamond (`DoubleSlipMiddle`), so neither needs a special case. Crossings are attachments on
both rails, next to the turnouts and signals. A double slip is where it gets tight: four sets of
points within 14 m of a 12° diamond, so blades, frogs and check rails all overlap, and the slip
roads' sleepers have to merge with the diamond's.

The desert level (`scenes/levels/desert.tscn`) adds two things a rail model has to cope with that
no other scene has: a bridge, where the track is in the air over a gully with nothing under it,
and tunnel mouths, where the terrain rises from the bed to the roof across one 3 m grid cell.
Both are found by comparing the railhead with `Rail.ground_height_at()` - `desert_level_test.gd`
does exactly that - and neither is recorded on the rail; a deck and portals would want them to be.

## Step 7 — Trains with wagons and better physics

This is where a signal stops being a wall. A train currently stops dead on the signal; with
braking it needs to know the distance to it in advance, which is `TrackWalker.Step.travelled` on
a walk that ends at one — no new machinery, just a longer walk and a deceleration curve.

The `signals_from` rule is written from the nose, so it survives a train whose length changes
when wagons are added. See [signals.md](signals.md).

## Step 8 — Block locking

Mostly `TrackWalker.walk()` with the length turned up: walk ahead from a train and collect the
rails, turnouts and signals it will reach. Every walk now records what it covered in
`Step.spans`, one `Span` per rail, and `Train.occupied_spans()` is the same for the stretch of
track a train's body stands on — which is block occupancy's input. `Turnout` already reports
refusal, which is the "train cannot be let into a block if it will reach an unconnected turnout"
rule.

**Crossings join blocks.** The plan says so explicitly: two trains on the two rails of a
`Crossing` can meet, so both rails are one block there, even though no train can pass between
them. Every crossing is an attachment on both of its rails. It already reports its occupants, but
only for the crossing *point*: a train whose body ends a metre short is not "on" it, though it is
fouling it in any real sense. A fouling length either side belongs in the block logic, not here.

**Compound assemblies lock as one.** `CompoundTurnout.player_operable` is the switch — a click on
the widget or on any member marker goes through it — so locking an assembly's points under a
train is one flag, not four. Its members are already non-operable.

Still missing: automatic replacement (a cleared signal currently stays clear forever), locking a
signal to danger while its block is occupied, and locking points under an occupying train.

The seams are in place — `RailSignal.aspect`'s setter is the single entry point whoever is
changing it, `aspect_changed` reports every change, and `player_operable = false` takes a signal
off the player without the player noticing a different code path. Putting a signal back to danger
under a moving train is *deliberately* allowed and deliberately harmless: the train it is
standing over keeps going, the next one up is held.

## Not tied to a step

- **`Train.end_behavior` is a placeholder.** It now fires only at a genuine dead end, but real
  levels will want buffer stops and off-level connections there instead. The desert level's four
  exits are rails running into tunnels in the mountains and stopping there, which is where an
  off-level connection would go: a train sent into one turns round in the dark and comes back.
- **Two presentation questions are still open** — the turnout modes and the schematic's caption,
  the signal widget styles and the collapse rules are all switchable rather than decided. A
  compound assembly's widget follows the turnout mode and caption, so settling those settles both. Whoever settles them should delete the
  losers; see the end of [ui.md](ui.md).
- **Surface snapping moves only curve points and handles**, so point spacing has to be finer than
  the terrain's features. If real levels get hillier, per-segment subdivision may be worth
  adding — see [level_authoring.md](level_authoring.md).
