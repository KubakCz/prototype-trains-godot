# Track meshes, bridges and tunnels

Step 6: the track is a generated mesh - steel rails, timber sleepers, a ballast bed - built from
the rails' curves, with real points and frogs at every junction, buffer stops at dead ends, and
bridges and tunnels where the authoring says so. The engine traps for meshes and the ground are
in [meshes-and-ground.md](../.claude/rules/meshes-and-ground.md).

| script | what it is |
| --- | --- |
| `scripts/track/track_mesher.gd` | `TrackMesher` - the one node per level that builds it all, and rebuilds it in the editor |
| `scripts/track/track_layout.gd` | `TrackLayout` - the geometry: running lines and their cuts, blades, check rails, sleepers, buffer stops |
| `scripts/track/track_mesh_builder.gd` | `TrackMeshBuilder` - layout to meshes: profiles swept along the lines, chunks, the blades' blend shape |
| `scripts/track/mesh_surface.gd` | `MeshSurface` - one surface being collected: quads, boxes, beams, strips |
| `scripts/track/track_materials.gd` | `TrackMaterials` - the shared steel, timber, ballast, stone and bore materials |
| `scripts/track/track_structure.gd` | `TrackStructure` - base of the two below: a stretch of one rail |
| `scripts/track/bridge.gd` | `Bridge` - stone arch viaduct, steel truss or timber trestle |
| `scripts/track/tunnel.gd` | `Tunnel` - portals, a dark bore in a stone shell, and the hole the shell fills in the `Ground` |

## One mesher per level, nothing saved

Every scene has a `Track` node (`TrackMesher`). It finds every `Rail`, `Bridge` and `Tunnel` in
the scene it was saved in (its `owner`) and builds; nothing it builds is saved, the same as
`Ground`'s mesh, so the track can never disagree with the rails. At runtime it builds once, a
frame after the level loads (`call_deferred`), after the rails have snapped and the turnouts have
welded their branches on.

It costs about 200 ms on the playground or the desert level (3-3.5 km of track, 200 000
vertices), 30 ms on the turnout demo. That is paid on every load - in the game, in the editor, in
every test that loads a scene.

**In the editor it rebuilds by itself** (`auto_rebuild`). Four times a second it hashes
everything a rebuild depends on - every curve point and handle, every rail transform, every
turnout's welding, every structure's span (`signature()`) - and rebuilds once that hash has
changed and then held still for `rebuild_delay` (0.5 s). So dragging a curve point costs nothing
until it is let go. Throwing points is deliberately not in the hash: the blades swing for that,
nothing is rebuilt. **Rebuild Track** forces a build.

The meshes are **chunks** 64 m square (`TrackMeshBuilder.CHUNK_SIZE`): everything whose middle
falls in a cell goes into that cell's one mesh, one surface per material, and long rails are cut
into runs of half a chunk so no chunk sprawls. The playground is 23 chunks, the desert 48 - a
few dozen draw calls for a whole level, and a camera looking at one corner culls the rest.

## The cross-section

Standard gauge, 1435 mm between the railheads' inner faces (`Rail.track_gauge`, which the
wheelsets use too). The railhead is `Rail.surface_offset` (0.25 m) above the ground, and
everything fits in that:

- **rail**: head 70 mm wide and 40 mm deep, web, foot; 130 mm railhead to foot. The head is
  bright steel, the rest rust (vertex colours on one metallic material).
- **sleeper**: 2.6 m x 0.24 m x 0.1 m, every 0.65 m, under the foot. Not all the same brown.
- **ballast**: a flat top 1.6 m either side of the centre line, a little below the sleeper tops,
  and sides at 1:1.5 down to wherever the ground is, buried 5 cm. The top takes on 42 % of the
  ground's colour and the toes all of it (`Ground.surface_color_at`), so the bed reads as stones
  half grown over and fades into grass in one level and into sand in the other. The sides are
  what hide sleeper ends over a dip or in a bump: a deep dip gets a tall bank (up to 6 m).

The grain on timber, ballast and stone is a noise texture mapped triplanar in world space, so
there are no UVs to generate and neighbouring chunks line up.

## The ground never shows through the track

Snapping puts the curve's points on the ground, but between them the terrain can bulge, and a
level's carving can leave its bed a little high: the desert's ground stood over the ballast at
almost a third of all the points along its track, by up to 1.2 m. So the track cuts its bed into
the ground. `TrackMesher` is in `Ground.SHAPER_GROUP` and answers `ground_cuts()`: every rail's
bed line, 0.25 m under the railhead, carried 2 m past its ends and left out in tunnels. The
ground lowers every grid vertex within 1.8 m **plus a cell diagonal** of a line to the line's
height - the margin because any point of a triangle is within a cell diagonal of all three of
its corners, so no triangle reaching under the bed can rise above it. The cut ends square at each
end of a line; at bends a segment covers the wedge outside the joint and nothing past the ends.

**Only the mesh and `surface_height_at()` are cut.** `terrain_height_at()` still answers the
ground as authored, and that is what rails snap to (`SurfaceSnapper.height_at(..., terrain =
true)`) and what **Find** looks at - otherwise each snap would follow the previous cut down.
Everything that stands on the ground (ballast toes, masts, markers, bridge piers, portals) reads
the cut surface.

The ground builds in its `_ready`, before the rails have snapped or the turnouts welded their
branches, and checks again once everything is ready (`refresh_shapes`, deferred). It rebuilds
only if a shape moved more than 5 cm - a welded branch moves millimetres - and then calls
`ground_changed()` on `Ground.STANDING_GROUP`, so signals and turnout markers measure the ground
again. Of the levels, only the turnout and compound demos rebuild, their saved rails being
0.25 m off the ground until they snap. `track_mesh_test.gd` checks the ground never rises above
the bed on any level.

## Running lines, and where they are cut

Every rail has **two running lines**, its centre line shifted half a gauge and half a railhead
either way. The whole of junction geometry is deciding where a line must *not* be drawn - its
**cuts** - and drawing what is left as pieces. Two rules make all the cuts.

**At the points**, the two routes share their first metres, so on each side two lines lie on
top of each other. One is the **stock rail** and runs on unbroken; the other is a **blade**.
With the branch leaving to the right of a facing train:

- the right stock rail is the main rail's right line up to the points and the branch's right
  line after them; the **straight blade** is the main rail's right line from the points on;
- the left stock rail is the main rail's left line throughout; the **curved blade** is the
  branch's left line.

A left-hand turnout is the mirror image. Each blade runs from the points to its **heel**, where
the two routes' centre lines have drawn 14.5 cm apart - a railhead, a flangeway and a little -
and is cut out of the static track over that length.

**Wherever one line crosses another**, both are cut. That is the frog of every turnout (the
curved blade's line crossing the main rail's line on the branch side), all four corners of a
diamond, and everything a double slip packs into its middle - found by intersecting every line
with every other (a spatial hash of their segments), never by knowing what kind of junction it
is. So compound turnouts needed no code of their own, and neither does `Crossing`: the track
does not read it. Two lines are crossing, not running alongside, only above 1° - which is what
keeps a stock rail and its blade, touching at an angle of zero at the points, from counting.

**Each line is cut on one side of the crossing only.** A wheel on the other line carries its
flange on that line's *gauge* side, towards the middle of its own track, so a line is taken
out only along the arm that lies there: a railhead plus a flangeway (115 mm) off the other
line, plus 10 % and 5 cm for lines that curve away more slowly than straight ones would (a slip
road inside a double slip does) - 1.3 m at a 6° frog. The arm on the other line's *field* side
carries no flange past it and runs on into the crossing, stopping where the two lines are
`NOSE_TIP` (12 mm) apart. The two such arms make the frog's V **nose**, generically: at a
turnout or the end of a diamond they meet at the acute angle and point back towards the throat;
in the middle of a diamond (an obtuse crossing) they meet nearly end-on and read as the knuckle.

**Wing rails**: at an acute nose, each line's cut arm carries on as a wing - from the knuckle,
where it reaches a check rail's offset off the other line, along that line's gauge side past the
nose, ending in a flare. It is laid along the other rail (`Piece.wing_of` names the line it
continues) and left out if it would stand in a third track's flangeway.

**Check rails** go on the opposite rail beside every cut under 30°, 115 mm inside it, running
0.8 m past the gap with flared ends. One is left out where that rail is cut too (the middle of a
diamond) or where it would stand within a flangeway of another track's rail (the next points
along, inside a double slip).

`track_mesh_test.gd` holds all of this to one rule, on every level: **no rail stands in another
track's flangeway** - within a railhead and a flangeway of its running rail, on the gauge side -
except where a stock rail passes from one rail onto another at the points, and a wing rail beside
the closure rail it continues. On the field side rails may meet: that is a nose. When the test
finds a clash, it says which rails and where.

## The blades move

Each turnout's two blades are one small mesh of their own, built in the normal position with
the reverse position as a **blend shape**; `TrackMesher` moves the weight towards wherever the
points are set, over `blade_throw_time` (0.6 s). A blade closed against its stock rail lies a
railhead's width inside it at the tip; open, it stands 11 cm further off, room for a flange.
From the tip to the heel it blends into its own line. The straight blade is closed when the
points are normal, the curved one when they are reverse - the one the train's wheel is guided
along is always closed.

The blades are polled rather than driven by `Turnout.position_changed`, so points thrown before
the track was built, or by the inspector, still end up right. The animation runs on the idle
frame, which is why a test steps it by hand: the sped-up test clock stretches an idle frame's
delta far past a whole throw.

## Sleepers where tracks share them

Where two tracks are too close for each to have its own sleepers - centre lines nearer than
3.2 m, along a sleeper's line - the **higher-ranked** track lays a long timber under both and the
other lays none. Rank: a rail that is the main rail of any turnout above one that is not, then
the longer. So at a turnout the main rail's timbers grow longer and longer under the branch
until there is room for two, and at a diamond one track carries the other across. A long timber
never reaches more than halfway to a track it does not cover, so the two mains of a crossover
meet in the middle under the link. The rule is generic in the same way the cuts are: a double
slip, a three-way and a scissors crossover all come out of it.

Where the tracks part, the branch's own first sleepers are laid at an angle to the main's last
long timbers and could cross them. Rails are laid highest rank first, and a sleeper whose
footprint in plan would cross another track's is dropped - a missing sleeper or two at the
handover, which reads fine. `track_mesh_test.gd` checks no two tracks' sleepers cross anywhere.

## Buffer stops

A rail end with no turnout welded to it is a **dead end**: the rails and sleepers run 1.4 m past
it and a buffer stop stands there, its face 0.3 m past the end - where a train braking for the
end comes to rest. A red beam on two posts, two buffers with yellow faces, braced back to the
rails. One inside a tunnel is not a buffer stop but a way off the level, and gets none.

## Bridges and tunnels

Both are `TrackStructure`s: a rail and a span along it, `from_distance` to `to_distance`,
authored in the inspector. A span ending within half a metre of its rail's end counts as running
off it (`END_TOLERANCE`), so a tunnel authored to "802.5" on a rail 802.51 m long still swallows
the dead end. Each builds its own mesh (internal, never saved), at runtime after the rails have
settled, in the editor when anything about it changes and whenever the mesher rebuilds. They are
**not** rail attachments: nothing walking the track needs them, and the mesher finds them in the
scene. **Find Bridges & Tunnels** on the mesher proposes them: a bridge wherever the railhead is
over 3 m above the ground, a tunnel wherever the ground is over 4 m above it, each widened out
until it meets the bank or the hillside, skipping stretches already covered. Stone under 40 m,
steel over, as a first draft.

A structure stands plumb: its frame is the rail's position with the rail's heading flattened
(`flat_frame`), not the rail's own banked, pitched frame.

### The three bridge styles

| style | how it handles length | deck |
| --- | --- | --- |
| `STONE_ARCH` | a viaduct of arches about 16 m each (`arch_spans`), piers to the ground between them with buttresses, solid abutments 3 m into each bank | filled: the ballast carries on between parapets (`Ballast.DECK`) |
| `STEEL_TRUSS` | a through truss per span, at most 40 m (`truss_joints`), stone piers between spans and abutments at the ends | no ballast: sleepers on a steel deck plate 2.2 m either side, two stringers under it on the cross girders |
| `WOODEN_TRESTLE` | a bent every 4.5 m along the whole length: two plumb posts, two raked ones, a cap, girts and cross-bracing in storeys of 6 m | no ballast: sleepers on planking 1.8 m either side, four stringers under it on the caps |

The decks of the truss and the trestle follow the track rather than the girders, so on a curve
the track never runs off its deck; `track_mesh_test.gd` checks there is deck right under the
sleepers, under both rails and between them, all the way across each bridge.

A stone arch is a segmental arch through both springings and a crown 0.9 m under the deck, its
rise limited by the ground under it - a shallow gully gets a flat arch, a deep one a near-
semicircle. The whole viaduct is one solid whose underside follows the arches and drops below
the ground under piers and abutments.

A truss is straight, so on a curve the track bows away from its centre line. `truss_joints`
takes more, shorter spans until that bow is at most 0.45 m, which with the trusses 2.7 m either
side keeps the widest train (3.1 m) clear; `structures_test.gd` checks it on a 60 m radius. The
top bracing is 5.6 m above the railhead, clear of the tallest thing on the rails - a
locomotive's roof marker, at 4.9 m.

### Tunnels

Each end that is not also the end of its rail is a **mouth**: a stone portal wall across the
track, 11 m wide, with a coping and a ring of voussoirs round a semicircular opening 4.8 m wide,
springing 3.6 m and crown 6 m above the railhead - clear of the widest and tallest stock. Behind
it a 14 m bore (walls, roof and floor, unshaded, fading from dim stone to black, closed with a
black wall) takes the light, inside a **shell**: stone side walls 2.9 m either side and a flat
roof 6.5 m above the railhead (`SHELL_HALF`, `SHELL_TOP`), closed at the far end. Trains carry on
through the hillside beyond, out of sight under the terrain.

**The terrain is a heightfield, so it has no tunnel in it**: across the one grid cell a mouth
spans, it rises from the bed straight through the loading gauge to the roof. A `Tunnel` is in
`Ground.SHAPER_GROUP` and answers `ground_holes()` with each mouth's shell, and the ground cuts
three things exactly - grid triangles near a mouth are clipped polygon by polygon
(`Ground._add_clipped`), not left out whole:

- **inside the shell**, the ground under its roof is cut out, and nothing else. Where the hill
  over the bore is deep, the shell is buried; where it is shallow, its roof and walls show,
  meeting the hillside along the cut's edge. There is never a hole to see into.
- **the apron**, two cell diagonals in front of the face and the shell's width: the ground there
  is levelled with the bed, every vertex within a cell of the face lowered - otherwise the cell
  straddling the face rises from the bed to the hillside right in front of the opening. Two
  **retaining walls** stand along the apron's sides, as high as the hillside beside them and
  never rising away from the portal, covering the step between the levelled apron and the
  ground outside it.
- **the portal wall** grows above its 7.6 m wherever the hillside within half a cell behind it
  is higher, so the steep climb of that cell is behind stone.

**Heights are still answered in the cut**, so anything standing beside the track keeps its
footing. `structures_test.gd` checks no ground is left in the shell and no column round a mouth
finds no ground.

A level carved for its tunnels (the desert, the playground) puts the mouth where the carved
ground starts to rise.

## The demos and the levels

- **`scenes/demos/structures.tscn`** - generated by `tools/build_structures_demo.gd`, like the
  playground: three straight lines side by side, one per bridge style (`StoneLine`, `SteelLine`,
  `TimberLine`), each crossing a 16 m, a 38 m and an 88 m gully and then tunnelling through a
  ridge, with a buffer stop at each end. A train shuttles up and down each (`end_behavior =
  REVERSE`). The 38 m gully is two arches but one truss; the 88 m one is six arches, three
  trusses or twenty bents.
- **The playground** - `tools/build_playground.gd` records, while carving, every stretch of track
  in a tunnel or on a bridge and writes a `Tunnel` and a `Bridge` (stone) for them.
- **The desert** - five tunnels (the four exits and the ridge) and a steel truss over the gully,
  authored by hand from what Find proposed.

## Things that look like bugs and are not

- **A check rail missing beside a frog** inside a double slip or a three-way: it would have stood
  in another track's flangeway, so it is left out.
- **A sleeper or two missing** where a branch's own sleepers take over from the main's long
  timbers: they would have crossed.
- **Two ballast beds overlapping** at every junction: each track lays its own. Their tops are the
  same height and nearly the same colour, so the overlap does not show.
- **No buffer stop at the end of an exit**: the end is in a tunnel, so it is a way off the level.
