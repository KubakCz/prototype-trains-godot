# Interface, overlay and HUD

Everything drawn on the canvas: how the interface picks its scale, the floating marker layer
that both signals and turnouts share, and the debug HUD's fold-out panels. What the markers
point *at* is in [turnouts.md](turnouts.md) and [signals.md](signals.md).

The `Control` traps that shaped all of this — a `Control` eating clicks on the 3D world behind
it, `Control.scale` not moving `position`/`size`, canvas vs. window coordinates, child order
being draw order — are in [CLAUDE.md](../CLAUDE.md), because they bite anything that touches the
canvas, not just this.

## Interface scale

`window/stretch/mode` is **`disabled`**, so the canvas is 1:1 with the window whatever size the
window is: the 3D view gets every pixel and the HUD does not grow just because the window did. `UiScale` then sets `Window.content_scale_factor` from the window *height* against a 1080p
reference, snapped to quarters and clamped to 1.0–3.0 — the usual game behaviour of picking a
size for the screen rather than stretching a fixed layout. Measured: 648 / 900 / 1009 / 1080 all
give 1.0, 1440 gives 1.25, 2160 gives 2.0. It reapplies on `size_changed`, and
`scale_for_height()` is static so the rule can be asked about a height without a window.

Deliberately *not* proportional. Base-size stretching (`canvas_items` + `expand`, what this was
before) scales the UI by exactly `window / 1152`, which made the readouts 1.557x on a 1920 window
— sharp, but eating half the screen for no extra information.

## The floating layer

`MarkerOverlay` owns **every** floating marker — signals and turnouts together. One overlay
rather than one each, because de-cluttering only works if it knows about every widget on
screen: two overlays would each lay its own markers out neatly and then draw over the other's.
Folding turnouts in is what fixed the overlap step 2 left behind.

`TrackMarkerWidget` is the base: follow the camera, collapse, hover, leader line, click.
A subclass supplies what it points at, how big it is, what colour it is, what a click does and
how to draw itself.

All three collapse rules are implemented and the signal panel's **collapse row** cycles them
(`MarkerOverlay.Collapse`):

| rule | behaviour |
| --- | --- |
| `WHEN_FAR` | full size inside `collapse_distance` metres, a point past it |
| `WITH_DISTANCE` | scales down with camera distance, collapses below `min_scale` |
| `WHEN_CROWDED` | distance is irrelevant; only what cannot be given a clear place collapses |

Hovering always opens a collapsed widget, whichever rule is in force.

Overlapping widgets are **stacked upwards**, lowest anchor first, so the nearest marker keeps
the place it asked for and the ones behind it climb above it; the leader lines are what stop
that reading as a scramble. **Collapsed widgets take no part in the layout** — a dot is already
the answer to "there is no room to show this properly", and moving it off its own marker to
make space for a badge would lose the one thing it still says. So the layout's promise is about
open badges: no two of those cover each other.

Which makes **draw order** the other half of that promise, and it is the overlay's to set:

- **Dots are drawn under badges.** A dot that stayed on its own marker while a badge was stacked
  over it used to be drawn on top of that badge, hiding its name and its aspect. The reverse
  costs nothing — a dot behind a badge still says everything a dot says. `_restack()` orders the
  children every frame (collapsed, then open, then whatever the pointer is on), because for a
  `Control` child order *is* draw order, and it is input order too: a badge now takes the click
  from a dot lying under it.
- **Leader lines belong to the overlay, not to the widgets.** A line drawn in a widget's own
  `_draw()` is drawn with that widget, so it crossed whatever badge happened to lie between the
  widget and its marker. `MarkerOverlay._draw()` draws all of them instead, and a parent draws
  before its children, so every line is behind every badge. The widget keeps only
  `leader_start()` / `leader_end()` / `leader_color()`, in the overlay's coordinates.


## The debug HUD

All three debug panels are sections of one top-left column (`DebugUi/Panels`, a `VBoxContainer`)
and all three **start folded**: a scene opens showing the track, and you open the section you
are working on. Three expanded readouts covered a good part of the screen, which is what folding
exists to fix.

`DebugPanel` is the base. A subclass supplies `_panel_title()`, `_panel_lines()` (the body, only
asked for while open), `_panel_controls()` / `_panel_control_pressed()` (its cycle rows) and
`_panel_key()` (return true if the key was used); the chrome, the fold, the numbering, the input
routing and the per-frame refresh live in the base. **The chrome is built in code**, not authored
per scene, which is what keeps a panel a single node in the `.tscn` with no `readout` node path
to get wrong.

Open a section by clicking its header or with its **number key**: `[1]` trains, `[2]` turnouts,
`[3]` signals. The numbers are read off the column (`DebugPanel.fold_key()` counts `DebugPanel`
siblings) rather than authored, so they always run down it in order and reordering the panels
renumbers them.

**The turnout and signal sections own no keys at all.** They used to: `[T]`/`[G]` selected a
turnout and threw it, `[N]`/`[C]` did the same for a signal. Clicking one is the player's actual
interface, so the keyboard path was a second way in that had to keep working and that nobody
used. What is left in those two sections is a readout and its cycle rows. The train section
keeps `[Tab] [Space] [R] [F] [E]`, because driving a train has no click path yet.

**No readout prints the mouse or the camera controls.** Left click, right-drag to orbit,
middle-drag or `WASD` to pan and the wheel to zoom are standard enough not to need saying, and
the lines saying them were three of the widest in the column. A readout lists state; the keys
still worth printing are the train section's, which are neither standard nor guessable.

Two consequences worth knowing:

- **The switches for the open presentation questions are rows, not keys.** `_panel_controls()`
  returns one label per row and the base builds a flat `Button` for each; a press calls
  `_panel_control_pressed(index)`. A `Button` consumes its click, which is what keeps a press on
  a row from also reaching the 3D picking behind the panel. The rows live in the body, so they
  fold with it and only exist once a section has been opened.
- **The `>` in the turnout and signal readouts marks whatever the mouse is on**, not a
  selection — with no select key there is nothing else it could mean. (The train readout's `>`
  is still a selection, because `[Tab]` still moves it.) Two things can be pointed at and either
  counts: the floating widget (`MarkerOverlay.hovered_subject()`, which reads
  `TrackMarkerWidget.is_pointer_over()`) and the 3D model under it (`Turnout.is_pointer_over()`,
  `RailSignal.is_pointer_over()`, both off the picker's `mouse_entered` / `mouse_exited`). The
  model has to answer for itself because the widget is not always what the pointer is on — in
  `LEGS_3D` there is no widget at all, and the mast or the marker is a target in every mode.

Two things the base has to get right, both of them bitten-once:

- **The header `Button` is `FOCUS_NONE`.** Otherwise it joins the GUI focus chain and `Tab` —
  the train panel's select key — moves focus between headers instead of selecting a train.
- **The panel stays `mouse_filter = IGNORE`; only its buttons stop clicks.** That keeps the
  "a `Control` eats clicks on the 3D world behind it" gotcha (in [CLAUDE.md](../CLAUDE.md))
  confined to the header strip and the cycle rows, which are the places a click is meant to be a
  UI click.

`tests/debug_panel_test.gd` covers all of it: the fold, the numbering, a synthetic click on a
header, the cycle rows and the hover marker.


## Two presentation questions are still open

They are deliberately unsettled, and switchable rather than decided: which of the four turnout
modes, which of the three signal widget styles, and which of the three collapse rules. All three
are cycle rows in the debug panels. Whoever settles them should **delete the losers** rather
than leave the switches in — they exist to be tried against a real camera and a real human, not
forever.
