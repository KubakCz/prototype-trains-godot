# Signals

What a signal is, which trains it applies to, and the stopping rule — which is written from the
nose, and that is the whole subtlety. The floating widget styles that present a signal are in
[ui.md](ui.md); step 8 will change several of the rules below, and what it inherits is recorded
in [further_development.md](further_development.md).


A `RailSignal` lives at `distance` along `rail` and shows `DANGER` (red) or `CLEAR` (green).
`DANGER` is enum value 0, so a signal omitted from a `.tscn` or freshly added in the editor is
at stop, which is the rule the plan asks for.

**A signal is a property of a direction of travel, not of a place.** `governs`
(`TOWARDS_RAIL_END` / `TOWARDS_RAIL_START`) says which way the trains it applies to are going;
a train going the other way never sees it. Stopping both directions takes two signals, and
which *side* of the track the mast stands on is derived rather than authored — a signal is on
the right of the trains it governs, so `governs` alone places it.

**A cleared signal stays clear.** No automatic replacement after a train passes: the player is
the only thing that moves a signal until step 8's interlocking arrives.

**Held, not stopped.** A train meeting a red stops with its nose on the signal and keeps its
throttle open, exactly as at points set against it, and rolls on the instant it clears.
`Train.blocking_signal` says which one, for the readouts.

**The rule is written from the nose, and that is the whole subtlety.** `TrackWalker.walk()`
takes a `signals_from` argument — how far into the walk signals begin to count:

- `IGNORE_SIGNALS` (the default) — the walks that place a train's body. Where the body reaches
  is a question about *track*; a signal must never shorten it, or a train standing at a red
  would be drawn half-length.
- `body_length / 2` — what `Train._physics_process` passes for its probe. A signal nearer than
  that is one the nose is already past, so putting a signal back to danger under a moving train
  lets that train out instead of stranding it across the signal.
- `OBEY_ALL_SIGNALS` — everything, including one at the walk's own starting point. Tests use it.

A signal is never *crossed* by the walk: it either blocks (and the walk ends there) or it is
not a stop at all. So unlike a turnout it needs no `CLEARANCE` over-travel and no minimum
separation from its neighbours — two signals may stand at the same distance, which is exactly
what a back-to-back pair is.

**How a signal is presented is not settled either**, so all three candidates are in and the
signal panel's **widget row** cycles them (`SignalWidget.Style`). Every one of them has to answer "which direction is this
for", because a red badge that does not say whose red it is tells the player half the story:

| style | shape | direction shown by | collapsed |
| --- | --- | --- | --- |
| `ARROW` | a chevron | the badge itself points the governed way | an arrowhead |
| `PILL` | a plate | a small triangle beside the name | a dot |
| `SCHEMATIC` | a plate | a track stub with an arrowhead, lamp on the signal's own side | a dot |

The direction is projected through the camera (`signal_position()` → `ahead_position()`), so it
turns with the layout as the camera orbits and stays honest on a curve.

**Left click is the only way to change a signal**, as with a turnout: the mast, or the floating
widget over it. The 3D model is a mast, a head and two lamps with the lit one emissive, plus a
stop line across the track and an arrow down the governed direction in the aspect's colour. The
mast stands on the ground rather than on the track — see `Rail.ground_frame()` under the gotchas
in [CLAUDE.md](../CLAUDE.md) — so `mast_position()` is a point on the terrain and `mast_lift()`
is how far the railhead is above it.

