# Compound turnouts and crossings

Step 4: assemblies of simple turnouts that the player works as one — the three-way, the
crossover, the double crossover and the double slip — and the plain crossing, which the player cannot work at
all. The simple turnout they are all built from is in [turnouts.md](turnouts.md); the widget
layer is in [ui.md](ui.md). The demo is `scenes/demos/compound_turnouts.tscn`, and the playground, `main.tscn`,
has one of each kind on its oval and in its yard.

## An assembly groups turnouts, it does not replace them

`CompoundTurnout` holds a list of ordinary `Turnout` **members** and a list of **positions**, each
position being a setting for every member. That is all it adds. The members stay the only thing
a train deals with: `TrackWalker` has no idea an assembly exists, and walks through a crossover
as two sets of points in a row. So none of the passage rules changed, and a train refused by an
assembly is refused by one particular member — `Train.blocking_turnout` is that member, and the
readout names it through its assembly (`held by Crossover/SouthPoints`), because the assembly is
what the player has to change.

The assembly throws members through `Turnout.throw_points()`, the single entry point, and at
runtime sets `player_operable = false` on each of them and `assembly` to itself. Members are
authored as **children** of the assembly and listed in its `members` array. Children are not
required, but they keep the tree legible, and a parent's `_ready` runs after its children's, so
the assembly starts after its members have welded their branches.

| kind | members | positions, in cycle order | what each sets |
| --- | --- | --- | --- |
| `THREE_WAY` | 2, same main rail, same `diverge_towards`, a few metres apart | `STRAIGHT` → `LEFT` → `RIGHT` | straight: both normal. A branch: its member reverse, the other normal |
| `CROSSOVER` | 2, on two parallel rails, sharing one connecting rail as their branch | `PARALLEL` ↔ `CROSS` | parallel: both normal. Cross: both reverse |
| `DOUBLE_CROSSOVER` | 4, two per rail, two connecting rails that cross in an X | `PARALLEL` ↔ `CROSS` | the same, over four |
| `DOUBLE_SLIP` | 4, two on each of two crossing rails, two slip roads | `STRAIGHT` ↔ `SLIP` | straight: all normal, both straight routes open. Slip: all reverse, both slip roads open — [below](#the-double-slip) |

- **Which three-way member is the left branch is read off the curves** (`Turnout.branch_side()`),
  not off the member order, the same way a single turnout's hand is derived rather than
  authored. If both branch to the same side the level is odd but drivable, and the members are
  then told apart by order; the configuration warning says so.
- **The three-way is staggered, not symmetric.** Two sets of points at the same distance on one
  rail break `TrackWalker`, which needs them more than `EPSILON` apart. The demo has them 4 m apart.
- **A crossover only lets trains switch in one direction** — that is what it is. Set to cross, the
  two moves it stands in the way of are refused by a member, exactly as a single turnout refuses
  a trailing move against it. The double crossover is two crossovers facing opposite ways, so set
  to cross it switches every one of its four ways in.
- **"Double crossover" is the plan's "double crossing / slip switch".** The plan describes a
  scissors crossover — two parallel tracks, four sets of points, an X in the middle — and that is
  what `DOUBLE_CROSSOVER` is. The true double slip was added after, as its own kind.

## The double slip

Two tracks crossing at a shallow angle (12° in the demo), with a slip road on each side of the
diamond joining one track to the other. Four members, all within a few metres of the crossing:
on each track one set of points either side of the diamond, and each slip road is the branch of
one member on each track. The diamond itself is an ordinary `Crossing` beside the assembly, as
with the scissors. **Track 1** is the first member's main rail and **slip 1** is its branch —
that is all the numbering means, so reorder `members` to renumber.

Topologically it is the same as a double crossover — two rails, two members on each, two links
each shared by one member of each rail. Only the geometry differs, so the configuration warnings
cannot tell a double slip authored as a `DOUBLE_CROSSOVER` from the real thing.

It is **worked in pairs**, like the double crossover: `STRAIGHT` opens both straight routes,
`SLIP` both slip roads. That is `PARALLEL`/`CROSS` under other names — every member normal, or
every member reverse — so it needs no code of its own, and it never holds anyone: every entry
always has somewhere to go.

It used to be switchable against a second way, **one route at a time** (`S1 → X1 → S2 → X2`), how
a real double slip with a lever at each end behaves; pairs won and the other was deleted. Worth
knowing if it ever comes back: worked that way, a train on a closed entry is held *inside* the
slip rather than at its edge. Every entry is a facing move at the first set of points, and a
facing move is never refused, so the train rolls in and waits at the far points over part of the
diamond, until step 8's signals keep it out.

**Someone else may throw a member.** A test, a level script, step 8's interlocking. The assembly
does not fight it: it listens to its members' `position_changed`, looks the combination up in its
positions, and reads `MIXED` (-1) when none matches. The next click goes to the first position.
`position_changed` on the assembly fires once per change of the assembly, however many members
moved.

## One control element

The plan asks for a single control per assembly. How the player reaches it:

- **The floating widget** (`CompoundTurnoutWidget`) is the one control the overlay shows. Members
  get no widget of their own: `MarkerOverlay` skips any turnout whose `assembly` is set.
- **Every member keeps its 3D marker** — the post and the banner — because the points really are
  there, and a click on any of them cycles the whole assembly. `Turnout` emits `clicked` on a
  click whether or not it throws itself; the assembly listens, and its members being
  non-operable is what stops the click also throwing the one member directly.
  `CompoundTurnout.player_operable` is the assembly's own switch, for step 8.

The widget is a **schematic**, shown or hidden by the same overlay mode as a single turnout's:
the assembly's whole track, dead pieces red and the set routes green, drawn in the assembly's own
frame and then turned to match the camera. Not projected point by point like the single-turnout
schematic: two tracks 4.5 m apart over a 40 m crossover are a 10:1 sliver at any honest scale, so
the across-track axis is stretched (up to 6x) until the X shows, and an independent stretch needs
a frame in which "across" means something.

Its caption follows the same `MarkerOverlay.turnout_caption` as a single turnout's (see
[turnouts.md](turnouts.md)); the position it writes is the assembly's own — `STRAIGHT`, `CROSS`,
`SLIP`, `MIXED` — never a member's.

## Routes are walks, not member states

An assembly draws its own 3D legs, and a member of one draws none (`Turnout._refresh_debug_mesh`
checks `assembly`). Drawn one member at a time, a three-way set to one branch paints its second
set of points' toe green straight over the first set's dead leg: the toe is always connected
*from that member's point of view*, even when no train from outside can get there.

So `CompoundTurnout.route_spans()` finds the routes by walking. It lets a train in from every
**outer leg** — a member leg that does not lead to another member — walks it through with
`TrackWalker`, and keeps only the walks that come out of the far side. `track_pieces()` is the
assembly's track for drawing: every outer leg out to `leg_length`, every stretch between two
members in full, once. The 3D draw and the schematic both draw these, red pieces first and green
routes over them, so the two always agree with each other and with where a train actually goes —
`compound_passage_test.gd` checks the last of those directly.

This needed `TrackWalker.Step.spans`: every walk now records the stretches of rail it covered,
one `Span` per rail.

## Crossings

A `Crossing` is two rails crossing with no way from one to the other — a diamond. It changes
nothing about driving: both rails run straight through it, and `TrackWalker` never stops there
(it only ever casts a rail's attachments to `Turnout` and `RailSignal`). What it is for is being
known about:

- `rail_a` / `distance_a` and `rail_b` / `distance_b` — where along each rail they meet.
  **Locate Crossing** (inspector button) finds that in plan, and `locate_on_ready` re-runs it at
  runtime after the rails have snapped to the ground, because snapping changes arc lengths. It
  works in plan rather than 3D because two rails crossing on a slope need not meet to the
  centimetre in height; a height gap over 1 m is warned about as a bridge rather than a crossing.
- It registers as an **attachment on both rails**, like a turnout or a signal, so anything walking
  the network finds it.
- It knows **which trains are over it**: `occupants()`, `is_occupied()`, `occupancy_changed`,
  from `Train.occupies()` — which reads the body's own spans, so a train half over some points is
  on both of the rails its halves are on. Only the crossing point counts, not a clearance around
  it; see [further_development.md](further_development.md).

It is drawn as a diamond lying along both tracks — yellow, orange while occupied — and listed in
the turnout panel with its rails, its angle and who is on it. There is no widget: nothing about
it is the player's to change.

**A double crossover's middle is a separate `Crossing`**, authored beside the assembly
(`ScissorsMiddle` in the demo) rather than owned by it. The assembly does not need it, and the
steps that do — 6's rail meshes, 8's blocks — want every crossing, not just the ones inside an
assembly.

## Authoring

1. Draw the rails. For a crossover, the connecting rail runs from one parallel rail to the other,
   leaving and arriving tangent — two points with their handles along the track is enough.
2. Add the members as plain `Turnout`s, welded as usual ([level_authoring.md](level_authoring.md)).
3. Add a `CompoundTurnout`, set `kind`, make the members its children and list them in `members`.
   Put it in the `compound_turnouts` group, which is what the overlay and the turnout panel look
   for. Its configuration warnings check the shape: member count, a three-way's shared main rail
   and facing, a crossover's connecting rails each shared by exactly two members.
4. `compound_position` picks the starting position; the inspector lists the names for the chosen
   kind. Setting it in the editor throws the members, so their saved positions follow.
5. For a crossing, add a `Crossing` in the `crossings` group, set the two rails and press
   **Locate Crossing**.

In a hand-written `.tscn`, the member list is an array of node paths with `members` in the
node's `node_paths`: `members = [NodePath("NorthPoints"), NodePath("SouthPoints")]`.
