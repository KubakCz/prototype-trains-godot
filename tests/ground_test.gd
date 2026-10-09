extends TestCase
## Ground: the height it reports for itself against a ray cast onto its triangles.
##
## SurfaceSnapper asks a Ground for its height instead of walking its mesh, which
## on the desert level's baked terrain is the difference between one lookup and
## some hundred thousand ray tests per question. That is only allowed because the
## two answers are the same; this is where that is checked, on the analytic hills
## of main.tscn and on the baked heightmap of the desert level.

const SCENES := ["res://scenes/main.tscn", "res://scenes/levels/desert.tscn"]
## Points per scene. Few, because the reference answer walks every triangle.
const SAMPLES := 24
## The ray cast is the less exact of the two: it starts 10 km up, where a float
## only resolves to about a millimetre.
const TOLERANCE := 0.005


func test_the_ground_answers_exactly_what_a_ray_cast_onto_its_mesh_finds() -> void:
	for path: String in SCENES:
		var scene := await load_scene(path)
		var ground: Ground = scene.get_node("Ground")
		if not assert_true(ground.answers_heights(), "%s: the ground answers for itself" % path):
			continue
		var faces := ground.mesh.get_faces()
		for i in faces.size():
			faces[i] = ground.global_transform * faces[i]
		var walked: Array[SurfaceSnapper.Surface] = [SurfaceSnapper.Surface.new(faces)]
		var answered := SurfaceSnapper.collect([ground])
		assert_eq(answered.size(), 1, "%s: collected as one surface" % path)
		assert_true(answered[0].triangles.is_empty(),
				"%s: without baking its triangles" % path)

		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		var half := ground.size * 0.49
		var worst := 0.0
		for sample in SAMPLES:
			var x := rng.randf_range(-half.x, half.x)
			var z := rng.randf_range(-half.y, half.y)
			var expected = SurfaceSnapper.height_at(walked, x, z)
			var actual = SurfaceSnapper.height_at(answered, x, z)
			if not assert_not_null(actual, "%s: an answer at (%.1f, %.1f)" % [path, x, z]):
				continue
			worst = maxf(worst, absf(float(actual) - float(expected)))
		note("%s: %d triangles, worst difference over %d points %.6f m"
				% [path, faces.size() / 3, SAMPLES, worst])
		assert_less(worst, TOLERANCE, "%s: the same height as the ray cast" % path)
		assert_null(SurfaceSnapper.height_at(answered, ground.size.x, 0.0),
				"%s: nothing off the edge" % path)
