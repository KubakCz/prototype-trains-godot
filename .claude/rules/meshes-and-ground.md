---
paths:
  - "scripts/world/**"
  - "scripts/track/**"
  - "scripts/rails/rail.gd"
  - "scripts/rails/surface_snapper.gd"
  - "scenes/levels/**"
  - "tools/**"
---

# Gotchas: procedural meshes and the ground

Godot traps for building meshes, the `Ground` terrain and anything that measures it. Found the hard way; keep new ones in the same voice, including what they cost. How the ground and track work is in docs/track.md and docs/level_authoring.md.

- **Vertex colours are consumed as linear.** Set `vertex_color_is_srgb = true` on any material
  with `vertex_color_use_as_albedo`, or colours authored by eye render far darker and greyer.
  Cost me a long detour chasing phantom shadow bugs.
- **Procedural mesh winding**: get it backwards and the surface is invisible from above while
  still being solid to the snapper. `SurfaceTool.generate_normals()` won't warn — check that
  the normals point the way you expect.
- **`Rail.ground_height_at()` caches the baked ground, but never in the editor.** Collecting
  walks every triangle below `surface_root`, and everything standing beside the track asks;
  in the editor the terrain is still being edited, so a cache there would answer for a surface
  that has since moved.
- **A `Ground` answers heights for itself; any other mesh is walked.** `SurfaceSnapper` asks
  `Ground.surface_height_at()`, which reads its grid and the diagonal each quad is split along,
  instead of ray-testing every triangle - on the desert level's 100 000 triangles that is the
  difference between a lookup and seconds of load time. It is the *more* exact of the two: the
  snapper's ray starts 10 km up, where a float resolves to about a millimetre. `ground_test.gd`
  holds them together.
- **A `Ground` answers two heights.** `surface_height_at()` is the mesh, with the track's bed
  and the tunnel mouths cut into it; `terrain_height_at()` is the ground as authored. Snapping
  (and Find) must read the terrain - `SurfaceSnapper.height_at(..., true)` - or every snap
  follows the last cut down; everything that stands on the ground reads the surface. The ground
  is shaped before the rails settle and checks again once everything is ready; anything that
  measures it to stand on it joins `Ground.STANDING_GROUP` to be told. See
  [docs/track.md](docs/track.md).
- **`Ground` never saves its mesh, and only rebuilds inside the tree.** `_validate_property`
  strips `mesh`'s storage, or an editor save would write every vertex of a baked terrain into the
  scene. And loading a scene assigns every export in turn, so a setter that rebuilt outside the
  tree built the terrain once per property before `_ready` built it again.
- **A heightfield cannot hold a wall between two tracks.** Two parallel tracks 5 m apart at
  different heights share grid cells, and the terrain between them interpolates straight into the
  lower one's loading gauge: the desert level's north line was buried 0.7 m beside the ridge line
  climbing next to it. Where one line climbs beside another, both climb;
  `desert_level_test.gd` checks the ground never rises into a passing train.
