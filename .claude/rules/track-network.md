---
paths:
  - "scripts/rails/**"
  - "scripts/trains/**"
  - "scripts/traffic/**"
  - "tools/**"
---

# Gotchas: rails, turnouts, trains and traffic

Traps in the track network and what drives on it. Found the hard way; keep new ones in the same voice, including what they cost. The design itself is in docs/turnouts.md, docs/trains.md, docs/stations.md and docs/level_authoring.md.

- **The rail's own frame is no place to hang anything that stands on the ground.**
  `sample_transform` pitches with the gradient, banks with the curve's tilt, and is anchored
  to the railhead. A signal mast or a turnout's post built as a child of it therefore leans
  *and* floats: the ground two metres to the side of the track is not the ground under the
  track, and the railhead is another `surface_offset` above even that. Both models now hang
  off an internal `top_level` node placed by `Rail.ground_frame()` — upright, yawed along the
  track, standing on the ground — and their posts are *stretched* to reach it, so the lamps
  and the banner stay a fixed height above the railhead whatever the terrain does. Anything
  else that stands beside the track wants the same treatment.
- **Something that registers itself on a `Rail` from a property setter must only do it inside the
  tree.** A node built with `.new()`, configured and freed without ever entering the tree never
  runs `_exit_tree`, so it stays in `Rail.attachments()` as a freed instance and the next walk
  over that rail casts it. `Crossing` attaches in `_enter_tree` and guards its setters;
  `Turnout`'s setters still attach unconditionally, which is harmless only because nothing
  builds a turnout outside a scene yet.
- **A rail distance exactly at a turnout does not say which side of the points you are on.**
  The main rail runs *through* the points, so `main_distance` means both "about to arrive" and
  "just left". `TrackWalker` therefore never comes to rest in that zone: travel that would stop
  within `EPSILON` short of the points crosses them instead, and a crossing always carries the
  walk at least `CLEARANCE` (4 mm) past. Cost a real bug — a train restarting after being held
  sits exactly half its length from the points, and `half / (speed * delta)` lands it in the
  1 mm blind spot of a naive "strictly ahead" test, where it saw no turnout, decided it was at a
  dead end and applied `end_behavior`. A few millimetres of over-travel per crossing buys the
  whole class of bug away.
- **A correctly aligned branch leaves *tangent* to the main rail, so the tangents at the points
  cannot tell the three legs apart.** Anything that wants to show or measure the shape of a
  turnout has to sample a few metres down the leg instead — that is what `Turnout.leg_position`,
  `leg_heading` and `branch_side` are for. Bit twice: `branch_side` returned "right" for every
  turnout, and the marker's banner never appeared to move when the points were thrown.
- **Two rails only ever meet at a turnout, so every closed loop of track has to be cut at one.**
  A turnout welds one rail's *end* onto a rail running through the points; there is no
  end-to-end join, and a rail welded to itself works but warns (and the level tests forbid
  warnings). So a loop is cut where something else leaves it - the loop as the *diverging*
  route, the main rail carrying on to the other thing - and that takes junctions with somewhere
  to go and some care over which rail runs through which. The playground's oval only closes
  through its balloon and its wye; the working is in
  [docs/level_authoring.md](docs/level_authoring.md).
- `Rail` stores its attachments as `Array[Node]`, not `Array[Turnout]`. `Turnout` has to name
  `Rail`, and naming it back would make the two scripts mutually dependent. `TrackWalker` casts.
  For the same reason `Turnout.Exit` is an inner class of `Turnout` rather than of the walker,
  and `Turnout.assembly` is typed `Node3D` rather than `CompoundTurnout`.
- **A level with a `TrainSpawner` has no trains in `_ready`.** The initial ones are placed a frame
  later (`_spawn_initial.call_deferred()`), because the rails have to have settled first. Anything
  that looked at the `trains` group at start - the train panel's "No trains" warning did, and the
  level tests forbid warnings - has to check for a spawner too.
