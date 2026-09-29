# Turnouts

How the points work: the three legs, the passage rule, what is authored and what is derived,
and how a turnout is presented. Level-authoring steps are in
[level_authoring.md](level_authoring.md); the floating widget that sits over a turnout is in
[ui.md](ui.md). Engine traps that bite while working on this are in
[CLAUDE.md](../CLAUDE.md) — the turnout ones are that a rail distance exactly at the points is
ambiguous, and that a correctly aligned branch leaves *tangent* so the tangents cannot tell the
legs apart.


A `Turnout` lives at `main_distance` along `main_rail`, which runs straight through it, and
welds one end of `branch_rail` to that point. Three legs:

- **toe** — the main rail on the side the points face,
- **through** — the main rail carrying on past the points,
- **diverging** — the branch rail leaving the points.

`diverge_towards` (`RAIL_START` / `RAIL_END`) says which way along the main rail the diverging
move leads, and so which main-rail leg is the toe. Passage:

| arriving on | normal | reverse |
| --- | --- | --- |
| toe (facing move) | on down the main rail | switched onto the branch |
| through (trailing) | on to the toe | **refused** |
| diverging (trailing) | **refused** | on to the toe |

A refused train **holds with its throttle still open** and rolls on the instant the points are
thrown — it is waiting, not stopped. `Train.blocking_turnout` says which points, for the
readouts.

**`TrackWalker` replaces arithmetic on `Train.distance`.** Everything the train does is "move
this far from here", and plain addition stops at a rail's own ends — exactly what turnouts exist
to get past. So both driving and body placement go through `TrackWalker.walk()`, which crosses
every turnout on the way that admits the move. Two consequences fall out for free: a train
straddling the points has its two ends on two different rails and is drawn as the chord between
them, and a train is refused the moment its **leading end** touches the points rather than when
its middle does (`_physics_process` walks twice — once past the leading end to find the
obstruction, once to move the centre as far as that allows).

Step 8's block locking wants the same walk with the length turned up: look ahead and report
what the train will reach.

**Explicit vs. derived level data.** `diverge_towards` and `branch_end` are authored by hand.
Which *side* the branch leaves on is not: `branch_side()` reads it off the curves, which is what
lets one script be a left-hand turnout, a right-hand one, a turnout on a curve or a symmetric Y.

**Points can be thrown under a train**, deliberately, for now — the body visibly kinks onto the
other route. Step 8 makes occupancy lock them.

`Turnout.throw_points()` is the single entry point for throwing, whoever throws it; step 4's
compound assemblies should drive their members through it and set `player_operable = false` on
them. `position_changed` fires whenever the points move.

**How a turnout is presented is not settled**, so all four candidates are in and the turnout
panel's **overlay row** cycles them (`MarkerOverlay.Mode`):

| mode | on the track | floating |
| --- | --- | --- |
| `LEGS_3D` | coloured legs | — |
| `LEGS_AND_BADGE` | coloured legs | name + `N`/`R` pill |
| `LEGS_AND_SCHEMATIC` | coloured legs | miniature of the real layout |
| `SCHEMATIC_ONLY` | — | miniature only |

The 3D legs are stubs sampled along the real rails, so they curve with the track: the toe and
the set route in green, the dead leg in red with a cross on its end. The minimal box marker (a
post and a banner that swings onto the set route) is the turnout's *model*, not overlay, and
stays in every mode — it also carries the click collider. **Left click is the only way to throw
a turnout**: the marker, or the floating widget over it. There is no keyboard path and there
should not be one — see [the debug HUD](ui.md#the-debug-hud).

