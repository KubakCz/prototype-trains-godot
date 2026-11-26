---
paths:
  - "scripts/ui/**"
  - "scripts/debug/**"
  - "scripts/rails/turnout.gd"
  - "scripts/rails/compound_turnout.gd"
  - "scripts/rails/rail_signal.gd"
  - "scripts/trains/train_car.gd"
  - "tests/framework/**"
  - "tests/*click*"
  - "project.godot"
---

# Gotchas: the overlay, the HUD and input

Godot traps for `Control`s, picking, clicks and screen coordinates. Found the hard way; keep new ones in the same voice, including what they cost. The design is in docs/ui.md.

- **`MarkerOverlay` assigns `debug_draw` on every turnout and assembly every frame**, so that
  setter must return early when the value has not changed. Turnout's didn't, and rebuilt its
  `ImmediateMesh` sixty times a second unnoticed; `CompoundTurnout`'s re-walks every route on a
  rebuild and more than doubled the compound demo's frame time before the guard went in. Anything else the
  overlay drives per frame wants the same guard.
- **A schematic of a turnout has to exaggerate the divergence.** A real turnout diverges by
  about 6°; drawn to scale in a 44 px picture that is three collinear lines. `TurnoutWidget`
  amplifies the angle about its true sense (×5, clamped to 52°), so a right-hand turnout still
  reads as right-handed.
- **The game window opens windowed at the default 1152x648**, and resizing or maximising it is
  handled at runtime rather than authored (`UiScale` reacts to `size_changed`). Anything the
  project says about window size is ignored anyway when the editor *embeds* the game: the
  embedded window is sized by the editor, and the Game workspace toolbar's rightmost
  **Game Window Options** menu -> **Embedded Window Sizing** decides — *Fixed Size* (the
  default, and the reason an embedded run sits at 1152x648 in the middle of a large window),
  *Keep Aspect Ratio* or *Stretch to Fit*.
- **`get_viewport().physics_object_picking` is off by default**, and without it a
  `CollisionObject3D.input_event` never fires. `Turnout` and `RailSignal` switch it on at runtime.
  A `Control` that calls `accept_event()` consumes the click before picking sees it, which is
  what stops the floating widget and the 3D collider under it both throwing the same points.
- **Any `Control` with the default `mouse_filter` eats clicks on the 3D world behind it**, and
  the debug readouts are big. A click on a signal that happened to be behind the signal panel
  silently did nothing — the raycast hit the collider, the event never got there. The panels,
  their column and every container `DebugPanel` builds are `mouse_filter = 2` for that reason;
  the fold header is the one deliberate exception (`Label` is already `IGNORE`). Cost an hour of
  suspecting the collider, the picking flag and Jolt in turn.
- **A `PanelContainer` grows past the offsets you authored**, because a container's minimum size
  wins. Two panels pinned with hand-picked offsets quietly overlapped once a level had enough
  trains to print. Panels that stack go in a `VBoxContainer` and size themselves — with
  `size_flags_horizontal = 0` (`SHRINK_BEGIN`), or the column stretches every folded header out
  to the width of the widest open readout.
- **Node order in a `CanvasLayer` is draw order**, and so is child order under a `Control`, with
  the parent drawing before every child. The overlay was authored before the panels and so was
  drawn *under* them: widgets present, clickable, invisible. `MarkerOverlay` is the last child
  of `DebugUi` in every scene, and orders its own children so dots land under badges — see
  [docs/ui.md](docs/ui.md).
- **`Control.scale` scales drawing and input but not `position`/`size`**, so any rect maths has
  to be `size * scale` by hand, and anything drawn in `_draw()` is in *unscaled* coordinates -
  a leader line measured in screen pixels has to be divided by the scale to land on its marker.
- **Canvas coordinates and window coordinates are not the same thing.** The canvas is
  `window / content_scale_factor` — measured under both scale modes, so `window/stretch/mode`
  does not change the rule. `Camera3D.unproject_position` and `Control` layout are both in
  *canvas* space, so the overlay stays correct at any window size and any UI scale — but
  `Input.parse_input_event` wants *window* space, and feeding it a canvas point makes every
  synthetic click miss. Convert with `tree.root.get_screen_transform() * point`;
  `TestCase.click_at()` does, which is why the click tests survive a maximized window - or the
  off-screen one a windowed run actually gets.
  (This entry used to read "never pass `--resolution`"; that was a harness limitation, not an
  engine one.)
- **Nothing is ever rendered below native resolution.** `get_viewport().size` follows the
  window, so the 3D view is always native; `content_scale_factor` only divides the *2D*
  coordinate system, and glyphs are rasterized at the scaled size — verified crisp at 1:1 in a
  1440p capture. `CONTENT_SCALE_MODE_VIEWPORT` would be the one that renders small and upscales;
  the project does not use it.
- `Tab` is swallowed by the GUI focus system in `_unhandled_key_input`; the debug panel uses
  `_input` instead.
- **A `fixed_size` `Label3D` or `Sprite3D` ignores the UI scale.** It keeps a fraction of the
  *window* height, whatever `content_scale_factor` says, so station names drawn that way stayed
  small beside the scaled debug text - the reason the station badges moved onto the marker
  overlay. `RouteIcons` still uses fixed-size sprites and sets `pixel_size` every frame from the
  camera's `fov`, the window's native height and the scale factor; anything else that must match
  the interface in 3D needs the same sum.
