# Notes for further development

What the finished steps left for the ones not built yet: seams deliberately left in place,
limits the next implementer will hit, and decisions already taken that a later step should not
re-open.

This is the implementers' side of the plan. **The plan itself is
[prototype_goals.md](../prototype_goals.md), which belongs to the project owner — read it, never
edit it.** When a step is finished, its notes for the future go here instead, under the heading
of the step they are aimed at.

## Step 8 — Menu and game modes

**The points are already half there.** `Train.reached(point)` fires each time a train stands at a
station of its route and `Train.route_finished(completed)` when it leaves by its destination;
`TrainSpawner` counts `spawned_count`, `left_count` and `completed_count` and emits
`train_spawned` and `train_left(train, completed)`. A mode that scores one point per interest
point reached listens to those - there is nothing to add to the trains. Missing a station is not
an error: the stop is simply not made and `completed` ends false.

**A map's settings are on the spawner**: `max_trains`, `min_spawn_interval`, `initial_trains` and
`random_seed`. A menu that picks a map and a mode loads the scene and sets them before `_ready`
if a mode wants different ones (`TestCase.load_scene(path, prepare)` does exactly that).

The spawner has no end. A timed or target mode needs a way to stop it spawning and to say
"the round is over"; neither exists.

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

**Crossings join blocks.** The plan's rule implies it (trains that can collide share a block): two trains on the two rails of a
`Crossing` can meet, so both rails are one block there, even though no train can pass between
them. Every crossing is an attachment on both of its rails. It already reports its occupants, but
only for the crossing *point*: a train whose body ends a metre short is not "on" it, though it is
fouling it in any real sense. A fouling length either side belongs in the block logic, not here.

**Compound assemblies lock as one.** `CompoundTurnout.player_operable` is the switch — a click on
the widget or on any member marker goes through it — so locking an assembly's points under a
train is one flag, not four. Its members are already non-operable.

**Spawning already waits for a sector, not yet for a block.** `TrainSpawner.is_clear` wants no
train from 15 m behind the new one up to the first signal ahead of it (`sector_ahead`, a walk with
`any_aspect`) - the entry signal at a connection, the exit signal at a station. Past that signal
trains still do not look for each other, so a train let in and held at the next red with another
running up behind it is a collision waiting to happen. With blocks, the sector *is* the block
behind the entry signal and the spawner is the obvious caller of "is this block locked";
`sector_ahead` is where that question goes.

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

- **A spawned train just appears.** A connection puts a train down with its nose on its mark
  and the rest outside; where the exit tunnel is shorter than that (the desert's south-east gate)
  part of the train appears in view on its first frame, and there is no animation. A level whose
  exits want that to be invisible needs a tunnel reaching the mark from the rail's end.
- **Liveries are on the locomotive only**, as chosen: the wagons are all the same blue. Painting
  every car is a matter of `Train._rebuild_cars`, which already passes materials per car.
- **A train longer than its platform overhangs its near end** and nothing says so; nothing checks
  `platform_length` against the trains a route sends.
- **The route display is undecided**, like the turnout and signal ones: icons floating over each
  locomotive or a list ([ui.md](ui.md)). Whoever settles it deletes the loser.

- **Train models are still boxes**, now on bogies at standard gauge ([trains.md](trains.md)).
  Real models replace the body; they should keep the click collider and the collision box
  (`TrainCar.half_extents()`, which is what touching means), leave the bogies to the train, and
  keep the body clear of the wheels (`TrainCar.FLOOR_HEIGHT`). A wreck is drawn by turning each
  car a few degrees off its rail pose (`Train._wreck_pose`); models want the same, or better.
  Turnout markers and signal masts are boxes too.
- **The track's junctions are correct, not detailed** ([track.md](track.md)): the gaps are
  where a flange needs them and frogs have a nose and wing rails, but the nose is two rails
  meeting rather than a cast crossing, obtuse crossings have no point rails reaching in, and the
  blades are the rail profile planed thin. Each track lays its own ballast, so at a junction two beds overlap;
  it does not show, but a level with very different ground colours either side might.
- **Everything is rebuilt at once**, about 200 ms for 3.5 km of track. If levels grow several
  times bigger, the editor's rebuild wants to be per rail: the layout is already per rail except
  for the crossing and sleeper passes, which only need neighbours.
- **A structure covers one rail.** A turnout on a bridge would have its branch hanging in the
  air, and a tunnel under a junction would cut the ground over one track only. No level has
  either yet.
- **Inside a tunnel there is only the 14 m bore at each mouth**; beyond it the train is under
  the terrain. A camera that goes underground (none does) would see it hanging in the void.
- **The track's cut in the ground is as wide as the grid is coarse.** It keeps the ground under
  the bed for 1.8 m plus a cell diagonal either side, so a 3 m grid (the desert) gets a 6 m
  flat. Finer terrain, or terrain refined near the track, would let it be narrower.

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

## Step 10 — Simple editor

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

Step 7 added more: an interest point is a node with a child per track, and each track a rail and
a distance by number; routes are lists of node paths. An editor that places a station by clicking
a rail, or a gate at a rail's end, would remove most of it. The colours are picked for the level
as a whole (`InterestPoint.assign_colors`), so placing one more point re-spreads the rest.

Step 6 left two more things placed by hand: a `Bridge` or `Tunnel` is a rail and two distances,
and **Find Bridges & Tunnels** on the level's `TrackMesher` proposes them from the terrain. The
mesher already rebuilds the track by itself when anything it depends on changes
(`TrackMesher.signature()`), so whatever an editor moves - a point dragged, a turnout slid along
its rail - the track follows half a second later without being asked. A bridge or tunnel moving
with the rail under it does not happen yet: they are distances, so a rail that is lengthened at
its start leaves them where they were along it.
