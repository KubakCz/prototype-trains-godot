# Notes for further development

What the finished steps left for the ones not built yet: seams deliberately left in place,
limits the next implementer will hit, and decisions already taken that a later step should not
re-open.

This is the implementers' side of the plan. **The plan itself is
[prototype_goals.md](../prototype_goals.md), which belongs to the project owner — read it, never
edit it.** When a step is finished, its notes for the future go here instead, under the heading
of the step they are aimed at.

## Step 6 — Meshes

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
The playground (`scenes/main.tscn`) has one of each too, on the wye's tail: a 21 m bridge and a
44 m tunnel. Its generator classifies every sample of track as on its bed, in a tunnel or on a
bridge while carving, and throws the answer away; that is where it would get recorded.

**Train models.** A car is a `TrainCar`: boxes sized from its `CarType`, with the origin on the
railhead between its two ends and -Z towards the nose. Real models replace the boxes; they should
keep the click collider and the collision box (`TrainCar.half_extents()`, which is what touching
means), and match the gauge - the types' widths, 2.8-3.1 m, are already a plausible loading
gauge for 1435 mm. A wreck is drawn by turning each car a few degrees off its rail pose
(`Train._wreck_pose`); models want the same, or something better.

## Step 7 — Spawnpoints and stations

**Trains are made from types**: `locomotive`, `wagons` and `load_factor` are everything a
spawnpoint needs to make one, and the shared types under `rolling_stock/` are what it picks from.
Loading and unloading at a station is `load_factor` - deliberately on the train rather than a
"loaded" wagon type, so it can change in place. A train arriving from off the level wants
`Train.roll(speed)`: a rolling start, so it comes in at line speed instead of starting from rest
in a tunnel mouth.

**A spawned train can collide on its first frame.** Anything placed over another train touches
it and both derail, so a spawnpoint has to check that its stretch of track is clear first -
`Train.occupies()` and `occupied_spans()` answer that.

## Step 8 — Simple editor

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

## Step 9 — Block locking

Mostly `TrackWalker.walk()` with the length turned up: walk ahead from a train and collect the
rails, turnouts and signals it will reach. Every walk now records what it covered in
`Step.spans`, one `Span` per rail, and `Train.occupied_spans()` is the same for the stretch of
track a train's body stands on — which is block occupancy's input. `Turnout` already reports
refusal, which is the "train cannot be let into a block if it will reach an unconnected turnout"
rule.

**The playground is signalled for it.** Every way into every junction on `scenes/main.tscn` has a
signal, both directions on every track, and `main_scene_test.gd` checks that walking out from any
junction along any leg meets that signal before anything else. So the signals already bound the
blocks, and the junctions between them are what the blocks have to lock. The two diamonds on the
freight line are 5 m apart and protected as one, which is the "crossings join blocks" rule below
in miniature.

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
under a moving train is *deliberately* allowed and harmless: the train whose nose is past it
keeps going, the next one up is held.

**Since step 5, putting a signal back in front of a train is not harmless.** A train brakes for a
red from its own stopping distance out ([trains.md](trains.md)): put back inside that distance it
brakes harder, and put back too late even for full brakes it overruns the signal and waits,
tripped, for the player. So automatic replacement must only ever put a signal back *behind* a
train - once its nose is past, which is the moment the nose rule stops it applying - and
clearing a route should leave a signal clear while anything is inside its stopping distance.
`Train.stopping_distance()` and `obstruction_gap` are the numbers; a tripped train
(`Train.tripped`) is one that is somewhere it was not let into.

**Points thrown under a train derail it**, so locking points under an occupying train is not a
nicety: it is what stops the player wrecking one. A train also derails running into points set
against it - it never brakes for them, only for signals - which is the same lock seen from in
front: points on an approaching train's route want locking until a red protects them.

**Collisions now happen.** Any part of one train touching any part of another derails both, and
trains do not see each other: nothing brakes for a train ahead. Keeping two trains out of one
block is the only thing that prevents it - the README's "prevents two trains entering the same
block". `Train.derailment(reason)` fires for every derailment, which is the hook for a level's
"train collision" fail condition.

## Not tied to a step

- **`Train.end_behavior` is a placeholder.** It now fires only at a genuine dead end, once the
  train has braked to a stand there, but real levels will want buffer stops and off-level
  connections instead. The desert level's four exits are rails running into tunnels in the
  mountains and stopping there, which is where an off-level connection would go: a train sent
  into one turns round in the dark and comes back. With wagons, `TURN_AROUND` puts the
  locomotive at the other end in one frame.
- **No gradients and no speed limits.** A train starts and stops the same uphill as down, and
  takes a turnout at line speed. Either would go in `Train._drive`, where the rates are chosen.
- **Two presentation questions are still open** — the turnout modes and the schematic's caption,
  the signal widget styles and the collapse rules are all switchable rather than decided. A
  compound assembly's widget follows the turnout mode and caption, so settling those settles both. Whoever settles them should delete the
  losers; see the end of [ui.md](ui.md).
- **Surface snapping moves only curve points and handles**, so point spacing has to be finer than
  the terrain's features. If real levels get hillier, per-segment subdivision may be worth
  adding — see [level_authoring.md](level_authoring.md).
