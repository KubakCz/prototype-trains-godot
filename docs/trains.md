# Trains

Step 5: a locomotive and its wagons, getting going and stopping under their own power and their
own brakes, and the things that take a train off the rails. The track they run on is in
[turnouts.md](turnouts.md), the signals they stop for in [signals.md](signals.md), the train
panel in [ui.md](ui.md). The demo is `scenes/demos/trains.tscn`; the playground's four trains and
the desert level's three all have consists.

## A train is its consist

`Train.locomotive` leads, with the nose and the front marker; `Train.wagons` follow in order,
`COUPLING_GAP` (1 m) apart. Both are **shared types**, resources under `rolling_stock/`:

| type | class | length | mass | brakes | other |
| --- | --- | --- | --- | --- | --- |
| `passenger_locomotive` | `LocomotiveType` | 16 m | 80 t | 6.0 m/s² | 360 kN |
| `freight_locomotive` | `LocomotiveType` | 18 m | 110 t | 4.0 m/s² | 160 kN |
| `shunting_locomotive` | `LocomotiveType` | 10 m | 60 t | 5.0 m/s² | 150 kN |
| `coach` | `WagonType` | 15 m | 40 t | 6.0 m/s² | carries nothing |
| `freight_wagon` | `WagonType` | 12 m | 22 t | 4.0 m/s² | 60 t when full |

`CarType` is the base: size, empty mass, `brake_rate`. A `LocomotiveType` adds `traction`, a
`WagonType` adds `capacity`. **How full the wagons are is the train's**, `Train.load_factor` from
0 to 1, not a separate "loaded" type: loading is something that happens *to* a train - at a
station, in step 7 - so an empty and a full freight are one consist with a different load.

Authoring is all inspector: pick a locomotive, add wagon slots, pick a type in each, set the
load. Editing a shared type rebuilds every train that uses it (each setter emits `changed`).
The configuration warnings catch a missing locomotive (a 16 m stand-in is drawn), an empty slot,
and a train whose nose or tail runs off the end of its rail - the thing to check after making a
train longer. A hand-written `.tscn` writes the list as a typed array whose type is the *script*:
`wagons = Array[ExtResource("<wagon_type.gd>")]([ExtResource("<coach.tres>"), ...])`.

`Train.distance` is still the **middle of the whole train**. Not the nose: a train held with its
nose on points would then have its own position in the ambiguous zone at them (see the gotcha in
[CLAUDE.md](../CLAUDE.md)). Changing the consist keeps the nose put and moves the middle instead
(`add_wagon`, `remove_wagon`).

**Placement.** The `Train` node itself sits on the rail at its distance - exactly on the arc,
`main_scene_test.gd` checks it. Each car (`TrainCar`, an internal `top_level` child) is the
chord between the rail positions under *its own* two ends, found on the two walks out from the
centre with `TrackWalker.Step.locate()`. So every wagon follows the one in front through every
set of points it took, and a car's middle sits inside a bend by `L² / 8R` - for a 16 m car round
the playground's 32 m balloon, a metre - and no more. A single long box used to bulge 1.9 m.

## Getting going and stopping

One speed, `current_speed`, never negative. The direction of travel (nose-first or backing) is
separate and **only changes at a standstill**: reversing a train at speed brakes it first. The
throttle (`-1` / `0` / `1`) is still what the train is told; it no longer is how fast it goes.

- **Acceleration** = locomotive traction / total mass. A kilonewton over a tonne is a m/s².
- **Full brake** (100%) = every car's `mass × brake_rate` / total mass. Brakes are sized for the
  empty car, so a load adds weight and no brakes: a loaded freight stops longer than an empty
  one, while adding identical coaches makes a train slower to start and no worse to stop.
- **Service brake** - a normal stop - is `SERVICE_BRAKE` (60%) of the full brake.

With the shipped types ("moderate", as the owner picked):

| train | mass | to top speed | normal stop from it | shortest stop |
| --- | --- | --- | --- | --- |
| express: passenger loco + 2 coaches, 18 m/s | 160 t | 8 s | 5 s, 45 m | 27 m |
| regional: passenger loco + coach, 12 m/s | 120 t | 4 s | 3.3 s, 20 m | 12 m |
| freight: freight loco + 4 wagons full, 12 m/s | 438 t | 33 s | 11 s, 66 m | 40 m |
| the same empty | 198 t | 15 s | 5 s, 30 m | 18 m |

A frame is integrated as constant acceleration over it, so a train braking at exactly the rate it
needs lands exactly on what it is braking for - to the millimetre, which the tests rely on.

`Train.roll(speed)` is a **rolling start**: the train is moving the moment it appears. The test
fixtures use it so the older passage tests stay about the points rather than about the time it
takes to get going, and step 7's arrivals will want it.

## What a train stops for

Every frame the train looks ahead from its centre out past its leading end, as far as its normal
stopping distance plus this frame's travel plus `STOP_SHORT` plus 2 m, for a signal at danger (from
the nose on - the rule in [signals.md](signals.md)), points set against it, or a dead end.

**Only a signal at danger and the end of the line are stopped for.** Points set against the train
are not braked for at all: it runs into them at whatever speed it has and derails there ("ran into
..."). Protecting a junction is the signals' job - the player sets a red in front of points before
setting them against a train, as on a real railway.

**It means to stop `STOP_SHORT` (3 m) short** of a signal or a buffer, not with its nose on it:
`stop_gap` is that point, `obstruction_gap` the obstruction itself. If even full brakes cannot stop
it that short but can still stop it before the obstruction, it uses the margin rather than tripping
and stands somewhere in between. With `g` the gap to where it means to stop and `needed = v² / 2g`:

- `needed` below the service rate: no braking, but **never faster than the service curve**
  `√(2 · service · g)` - so it starts braking exactly its stopping distance short.
- `needed` at or above the service rate: brake at `needed`, up to 100%. A signal put back late,
  inside the normal stopping distance, is stopped for *harder*, and short of it - not past it. Red
  marker, steady.
- Not even 100% is enough (it would arrive faster than 0.5 m/s): the train is **tripped**.

Brought to a stand where it meant to stop, throttle open, it is **held** - `blocking_signal` or
`at_dead_end` - and goes by itself the moment the way clears. Those are set only while standing
there, not while braking towards it. `blocking_turnout` is the one degenerate case left of holding
at points: a train that *starts* with its nose on points set against it can only creep up to them,
and arriving at 0.5 m/s or less holds rather than derails.

**Tripped** is the overrun, and the train stays tripped until the player lets it go:

- A **signal** it cannot stop for is *excused* - `TrackWalker.walk()` takes an `excused` list -
  so the train runs past it at full brake and stands beyond it, as soon as it can. It blinks red
  there until `release()`, which is **Space** on the selected train: "let go" is the train's own
  go control, and the signal behind it stays red. Released while still braking, it takes the
  brakes off and carries on through. An excused signal is forgotten once the train is past it,
  or once it stands untripped - so a train that never got past it is held by it again.
- **The end of the line** cannot be run past: it brakes flat out and, if it still reaches it
  faster than 0.5 m/s, derails there ("ran off the end of ...").

**The player's stop** (throttle cut, Space) is a normal stop: blinking yellow while braking,
steady yellow standing. If a red signal turns up that needs harder braking than that, the train
brakes for the signal instead - red - and stands at it, still yellow once stopped because its
throttle is shut.

The brake onset has a tolerance: `needed >= service × (1 − 1e-6)`. Without it, a train riding the
service curve computed `needed` a hair under the service rate once near the end, coasted a frame,
and then had to brake at 3.8 instead of 3.6 to make up for it.

## Derailment

Final, as the plan says: the train stops dead, every car is knocked a few degrees askew and
greyed, the marker goes black, and nothing - throttle, release, a rolling start, the panel's keys
- moves it again. `derail_reason` says why. Three things do it:

- **Points thrown under the train.** "Under" is more than 5 cm inside both ends (`_UNDER_MARGIN`):
  a train held at points stands with its leading end on them, and throwing them is how the player
  lets it through. The margin was 0.25 m first, and a throw 0.2 m after a nose had crossed the
  points re-routed the nose onto the other leg instead of derailing it. The check compares the
  points under the body after each move with how they are set next frame, so a train standing
  still is caught too; a train that is *teleported* (any setter) forgets what was under it.
- **Any part of one train touching any part of another.** Every car's body box against every
  car of every other train within reach, an exact oriented-box test in 3D (so a train on a bridge
  does not touch one in the tunnel under it). Both trains derail. Trains do not see each other,
  so nothing brakes for a train ahead - keeping them apart is step 9's blocks.
- **Running into points set against it**, at any speed above a crawl, or **into a buffer it found
  too late** - above.

A wreck is knocked askew **from where each car stands**, not walked out again: with points just
thrown under it, walking would put half of the wreck on the other route. (`Train.nose()` still
walks, so a wreck's readout can name the other route; the wreck itself has not moved.) A wreck
still occupies whatever it lies on, crossings included, and another train touching it derails.

## The front marker

| state | when | marker |
| --- | --- | --- |
| `DRIVING` | under power, running, or about to go | green |
| `BRAKING` | braking for a red signal or a dead end | red |
| `HELD` | standing at one of those, throttle open | red |
| `STOPPING` | braking because the throttle was cut (or reversed) | blinking yellow |
| `STOPPED` | standing with the throttle cut | yellow |
| `TRIPPED` | could not stop in time; waiting to be let go | blinking red |
| `DERAILED` | off the rails | black |

`Train.state` is worked out every frame from the physics, never set. The colours are
`Train.state_color()` and `Train.state_blinks()`; the marker is emissive so it reads from afar.

## Selection

A left click on any car selects the train (`TrainCar` carries a click collider), and the selected
train is drawn lighter blue. Selection is static on `Train` - `select()`, `selected_train()`,
`clear_selection()` - because there is only ever one. A click on nothing clears it: the selected
train hears the unhandled click and, on the next physics frame, casts the same ray; if it hits
nothing clickable, it deselects. A click on a signal or a turnout leaves the selection alone,
and one on a widget or a panel never reaches it.

Selecting replaces `[Tab]`, and is what the train panel's keys act on - see [ui.md](ui.md).
Space, reverse, turn round, the consist keys and restart stay debug keys: in the game proper the
player drives trains only through signals and points.

## Debug aids

- **Stopping strip** - the selected train's stopping distance, drawn down the track ahead of its
  leading end in the marker's colour, with a bar where it would stand: out to the obstruction
  while braking for one, else at the rate it is braking at, else at the service rate.
- **Collision boxes** - every car's box, as a magenta wireframe through everything.
- **Consist keys** - `[+]` couples another of the last wagon on (a coach if there is none),
  `[-]` takes the last one off, `[L]` empties or fills the wagons.
- **Restart** - `[Backspace]` reloads the scene, because a wreck is otherwise permanent.

Both drawings are rows in the train panel.

## Cost

A crossing asks every train every frame whether it is over it, and the points check wants the
same answer, so a train keeps the two walks it was placed with (`_front`, `_rear`) and answers
`occupied_spans()` from them at runtime. That halved the compound demo's frame time (9 trains,
3.3 ms -> 1.7 ms per physics frame, of which 0.85 ms is everything else). Per moving train and
frame there are four walks: the look ahead, the move, and the two that place it.

## The demo

`scenes/demos/trains.tscn`: three straight lines 5 m apart, 500 m long.

- The **express**, a **loaded freight** and the **same freight empty** start abreast, from rest,
  and run up to a red signal each at the far end: the express is away and stopped while the full
  freight is still gathering speed, and the strip shows how much longer it needs to stop.
- **NorthOverrun**, clear, stands part way along the north line: put it back in front of the
  express to see a harder stop, or an overrun if left too late, and Space to let it go.
- A **crossover** from the north line onto the middle one: throw it under a train to derail it,
  set it against the freight late to watch it run into the points, or send the express across
  into the freight.
- A **stalled** shunter stands beyond the south line's signal, facing west: clear the signal to
  run the empty freight into it.

Nothing about the old demos needed changing except where trains now collide. The compound demo
used to set its diamond and double-slip pairs crossing at the same moment, to show a crossing's
occupants; they now crash, so one of each pair starts parked (Space starts it, and the crash).
The signal demo's goods train grew a wagon and moved 7 m east, clear of the signal its neighbour
is held at.

## Things that look like bugs and are not

- **A train held at points set against it fouls the other route.** Its nose is on the points, and
  a train using the other route there touches it. That is a collision, deliberately; the
  playground's signals stand clear of every junction, which is what keeps it from happening. Only a
  train that started there can be held at points at all - any other runs into them.
- **A train stands up to 3 m short of a red, not on it.** `STOP_SHORT`. One that found the red too
  late to stop that short stands nearer, not tripped.
- **`TURN_AROUND` puts the locomotive at the other end in a single frame.** The placeholder flips
  `facing`, and the consist is laid out from the nose. Turning round on the debug key waits for a
  standstill for the same reason.
- **A tripped train can end up held at a later signal**, still blinking: it stopped for one it
  *could* stop for at full brake. Letting it go leaves it held there, red.
- **No gradients, no speed limits.** A train climbs and brakes the same uphill and down, and takes
  a turnout at line speed.
