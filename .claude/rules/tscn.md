---
paths:
  - "**/*.tscn"
  - "tools/**"
---

# Gotchas: hand-written scenes

Godot traps for writing `.tscn` text by hand or from a generator under `tools/`. Found the hard way; keep new ones in the same voice, including what they cost.

- **Hand-written `.tscn`: a typed array of a custom resource is typed by its *script*.**
  `wagons = Array[ExtResource("<wagon_type.gd>")]([ExtResource("<coach.tres>"), ...])` — the
  first id is the `WagonType` script's ext_resource, not a `.tres`. Learned by letting Godot save
  one (`PackedScene.pack` + `ResourceSaver.save` from a throwaway script) and reading it back,
  which is the quickest way to find any serialised form.
- **Hand-written `.tscn`: exported node references need `node_paths` on the node header**,
  or they silently arrive as `null`:
  ```
  [node name="PassengerTrain" type="Node3D" parent="Trains" groups=["trains"] node_paths=PackedStringArray("rail")]
  rail = NodePath("../../Rails/MainLine")
  ```
  Only the editor writes that attribute automatically. Same for `surface_root`, `camera`, `readout`.
  An exported *array* of nodes is the same, one entry in `node_paths` for the whole array:
  `members = [NodePath("NorthPoints"), NodePath("SouthPoints")]` fills an `Array[Turnout]`.
- **`Curve3D` in `.tscn`** stores `_data = {"points": PackedVector3Array(...), "tilts": ...}`
  with **three vectors per point, in the order `in`, `out`, `position`** (handles are relative
  to the point), plus a trailing `point_count`.
- **A `.tscn` `Transform3D(...)` lists the basis ROW-major**, i.e. the first three floats are
  the first *row*, not the x axis. Verified: `Transform3D(1,2,3, 4,5,6, 7,8,9, ...)` yields
  `basis.x == (1,4,7)`. Writing the three axes as consecutive columns silently stores the
  **transpose**, which stays orthonormal and right-handed, so nothing errors — it just
  quietly rotates the node wrong. Transpose before emitting:
  `rows = (x.x,y.x,z.x, x.y,y.y,z.y, x.z,y.z,z.z)`.
- **`DirectionalLight3D` shines along its basis `-Z`.** Combined with the row-major trap above,
  a hand-authored sun transform easily ends up lighting the scene *from below*; the symptom is
  flat, ambient-only terrain and unlit roofs. Assert the intended travel direction has a
  negative Y, then check in-engine that `-sun.global_basis.z` still does.
