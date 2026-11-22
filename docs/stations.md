# Stations, connections and the spawner

Step 7: the places trains are going, how they get on the level, what they do when they get
there and how that is shown. The track they run on is in [turnouts.md](turnouts.md), the train
itself in [trains.md](trains.md). The demo is `scenes/demos/stations.tscn`; the desert level
([level_authoring.md](level_authoring.md)) has the same nodes on a real map.

## Interest points

`InterestPoint` is the base: a `Node3D` that **spans one or more tracks** - its `InterestTrack`
children, each a `rail` and a `distance` - and is marked by a shape floating `MARKER_HEIGHT`
(16 m) over the middle of them, with a thin pole down to each track's mark. Two kinds:

| | shape | tracks mean | what a train does there |
| --- | --- | --- | --- |
| `Station` | circle (a sphere) | the mark is the middle of the platform | stops, dwells, moves its freight |
| `OutsideConnection` | square (a cube) | the mark is the line a train crosses to leave | is put on the level, or taken off it |

An `InterestTrack` is a plain `Node`, not spatial: the point draws itself and its tracks'
marks need no drawing of their own. Its `role` (`BOTH`, `IN`, `OUT`) only means something at a
connection: an `IN` track puts trains on the level and never takes one off it, an `OUT` track
takes them off and never puts one on. The demo's gates use it so that each of its three lines
runs one way - without block locking (step 9) two trains meeting on one line wreck each other,
and the spawner would otherwise produce that within seconds.

**Colours are picked for the whole level at once** (`InterestPoint.assign_colors`, run a frame
after any point enters or leaves the tree, and when one switches `use_custom_color`). Every
point without a colour of its own gets a hue from `auto_hues(n)`: `n` hues evenly spread round
the wheel, handed out so that each is as far as possible from the one before - points listed
next to each other in the scene are the ones likeliest to stand next to each other. Setting a
colour by hand (`use_custom_color`, `custom_color`) takes the point out of the spread and gives
the rest more room. The "three tints of green for the south corridor" the plan describes is
exactly that: three points with custom colours.

**Names** float beside the markers as fixed-size `Label3D`s. `InterestPoint.show_names` is
the debug switch, a row in the *Stations and connections* panel.

## Routes

A train's `route` is the list of points it is going through, **in order, the last an
`OutsideConnection`**: it always ends by leaving. `Train.route_index` is how many it has been
through, `next_stop()` the one it wants now, `remaining_stops()` what is left.

A level's list of routes is a `TrainRoute` node per line under the `TrainSpawner`: *these train
types, arriving at one of these entry points, go through these stops in this order*. A line
serves several types and entries at once, so "passenger trains from either end stop at the
central station and leave by the other end" is one or two lines. An entry may be a station: those
are where the trains placed at load can stand. The configuration warnings say what a line is
missing, and flag a stop list that does not end at a connection.

`TrainType` is a resource under `train_types/`: a locomotive, a wagon, how many of them (a
range), how full (a range) and a top speed. Four ship: `express`, `local`, `loaded_freight`,
`empty_freight` - the last two are the same consist at either end of a mine or a factory.

## What a train does at a station

When the next stop on its route is a `Station`, `Train._drive` treats the station's mark on the
rail ahead as a place to stop, the same way it treats a signal at danger or a dead end:

- It brakes along the service curve to stand with **its middle on the mark** - not its nose,
  so the same mark serves a train going either way and a train of any length. It lands to the
  millimetre, like every other stop.
- **A signal at clear does not matter**, and the station is stopped at even if it is on a line
  with signals either side. A signal at danger *before* the station still wins: the station is
  only stopped at when it is nearer than anything else the train would stop for.
- A train too fast for its brakes to make the mark **passes the station** and does not trip: a
  missed stop is not a fault, only a stop not made (and the route index does not advance).
- A station that is not the *next* stop is driven through at line speed. Stops are made in
  the order of the route.
- On standing, `reached(point)` fires, `route_index` advances, and the train **dwells**
  (`State.DWELLING`, cyan marker) for `Station.dwell_time`. It is `dwelling_at` the station,
  with no throttle and no brakes; if points are thrown under it or another train touches it it
  derails as usual.
- **Cargo.** `Station.cargo` is `NONE`, `LOAD` or `UNLOAD`. During the dwell the freight
  wagons' `load_factor` moves to full or empty in steps of 0.1 (so the wagons are rebuilt ten
  times, not every frame), and is exactly the target when the dwell ends. Coaches carry nothing,
  so they are not touched. A heavier train accelerates and brakes as its load says, as ever.

## Leaving the level

The destination connection takes a train off when **its tail has gone out past the mark** of
one of its tracks that can absorb (`OutsideConnection.has_left`). "Out" is the end of the rail
the mark is nearer to. The train emits `route_finished(completed)` - `completed` is whether it
went through every stop - and is freed.

- **A connection that is not a train's destination is nothing but the end of a rail**: it
  brakes and turns round there (`end_behavior`), as at any dead end. Only a train's own
  destination takes it off. A train that misses a station and reaches its destination leaves
  anyway, `completed = false`.
- **A train that cannot get its tail out** - the mark is within a train's length of the end of
  the rail, which is how the desert's short tunnels are - leaves anyway once it stands against the
  end of the line with either end past the mark. Without that rule it would turn round at the
  buffer for ever.
- An `IN` track does not take a train off, even its destination's.

Nothing here scores. `Train.reached` and `route_finished` are the hooks step 8's points are
built on.

## The spawner

One `TrainSpawner` per level, with the `TrainRoute`s as its children and the level's trains
added under `trains_parent` (a sibling called `Trains` unless set). Exports: `max_trains`,
`min_spawn_interval`, `initial_trains`, `random_seed` (0 is a different roll every run).

- **At load**, `initial_trains` trains are put down at random interest points - stations and
  connections alike (`spawn_random(true)`). A train put down at a station stands there, dwelling
  for the first time, facing whichever way leads to its route's stops (`_facing_towards` walks
  both ways from the mark and takes the one that reaches the route; a coin flip when neither
  or both do). A train put on at a connection is *rolling*: `Train.roll_safely` starts it at line
  speed, or slower if the first red signal ahead is too near to stop for at that speed.
- **While the level runs** only connections spawn trains (`spawn_random(false)`). The next is due
  between `min_spawn_interval` and twice it after the last, never while `max_trains` are
  on the level - wrecks count - and if nothing can be placed it tries again every second.
- **Choosing**: a route at random, a type of that route, an entry of it, a track of the entry.
  A spawn can be refused by the track: it has to be one that takes trains (`role != OUT` at a
  connection), the rail has to be long enough for the train, and no other train can be on the
  stretch the new one would take up plus `CLEAR_BEHIND` (15 m) behind and `CLEAR_AHEAD` (60 m)
  in front - `TrackWalker.Span.overlaps` against every train's `occupied_spans()`. The spawner
  tries the other tracks, entries and routes before giving up for now.
- **A spawn at a connection** puts the train's tail `SPAWN_INSET` (1 m) inside the mark, facing in.
  The desert's exit tunnels are short, so a long train has its nose out of the mouth the moment it
  appears; there is no animation to hide it.
- Each train is named for its type and a running number, painted a random `Livery`, and gets its
  route's stops. `train_spawned`, `train_left(train, completed)` and `spawned_count`,
  `left_count`, `completed_count` report what has happened.
- `spawn_at(route, entry, track, type)` places one train by hand - what the tests do - and
  `spawn_random` is nothing but a loop of dice that ends in it.

The spawner knows nothing of blocks: **a new train does not look for the ones ahead of it, and
trains do not look for each other.** The 60 m clear stretch only stops a train being put on top of
one. A train held at a red signal with another running up behind it is a collision waiting to
happen until step 9 ([further_development.md](further_development.md)).

## Liveries

`Livery` is how a locomotive is painted: a colour, optionally with a horizontal stripe round the
body (a thin band on the sides and both ends - `TrainCar`'s `Stripe`). Spawned trains get a random one,
half of them striped. The colours are the eight of `Livery.PALETTE` - red, orange, yellow, green,
blue, purple, pink, white: no two of a kind, so two engines never differ only by a shade - and a
stripe is only put on a colour it stands out from (`stands_out`): a WCAG contrast ratio of at
least 3 and a different part of the wheel. Orange and pink have no stripe in the palette to stand
out against, so `STRIPE_ONLY` adds black as a stripe - never as a body, since a black engine is
lost against the ground and the wrecks.

**The livery is on the locomotive only.** The wagons stay the blue they were, so selection is
still seen on them: a selected train's wagons go lighter blue as ever and its locomotive is
lightened by 30% (the stripe stays as it is). A wreck is grey all through, stripe too.
`Train.engine_color()` is what the locomotive shows, `body_color()` what the wagons do.

## Showing a route

Two ways, switchable; `RouteIcons.mode` and the first row of the *Routes* panel pick one. Both
want a decision from a human eventually - see "Two presentation questions" in [ui.md](ui.md).

- **Icons over the trains** (`RouteIcons`, an internal child of each train): a row of shapes
  floating 9 m over the train, a sphere for a station and a cube for a connection in the point's
  colour, **the next stop frontmost** (over the nose end, slightly bigger) and the last at the back.
  Hidden for a train with nothing left to do and for a wreck.
- **A list** (`RouteListPanel`, `RouteListView`): a section of the debug column with a line per
  train, **in the order the trains came on to the level** (`Train.arrival_index`, so a line
  never moves while it is read): the engine's colour with its stripe, the name, and the stops
  still to come as coloured circles and squares, the next first. Its second row adds the stops'
  names. The shapes are drawn with `_draw`, because the debug font has none.

The *Stations and connections* panel (`InterestDebugPanel`) lists every point and the spawner's
counts, and has the row that switches the names.

## Things that look like bugs and are not

- **A station's marker is a sphere, not a flat disc**, and a connection's a cube: from a camera
  that orbits, a sphere is a circle from every side and a cube a square from most.
- **Trains stand cyan, not red, at a station**, while braking up to it they are red like any other
  stop and "stopped by the player" yellow means what it always did.
- **`Train.route` on a train in a scene** is exported, so a hand-placed train can have a route
  too; one without a route is exactly what it was before this step.
- **A level with a spawner starts with no trains**: they come a frame later, so anything that
  looks at the train group in `_ready` finds it empty (the train panel's warning checks for a
  spawner first).
- **The same spawner seed gives the same trains** only until the player does something: a signal
  changed or a train derailed changes what is free and so what is rolled.
- **A station's gap is not measured the way a signal's is.** `Train._drive` compares them
  directly - both are how far the train may still travel - but an obstruction's `limit` is
  from the *leading end* (`ahead.travelled - half`, the walk starts at the middle) while a
  station's `_station_gap` is from the *middle*, straight along the walk to the mark. Taking
  `half` off the station's would stop every train half its length early.
