extends TestCase
## The generated track: where the rails are cut, the blades, the sleepers, the
## buffer stops and the chunks, on every scene that has turnouts or crossings.
##
## Most of it is checked from the [TrackLayout] the meshes are built from, which
## is the geometry itself; the meshes are only checked for being there and being
## cut into chunks. The rule that matters most is
## [method test_no_two_tracks_rails_come_within_a_flangeway_of_each_other]: a
## wheel's flange has room to pass everywhere, in every direction, at every
## junction in every level - which is the plan's "correct gaps".

const SCENES := [
	"res://scenes/demos/turnouts.tscn",
	"res://scenes/demos/compound_turnouts.tscn",
	"res://scenes/main.tscn",
	"res://scenes/levels/desert.tscn",
]

## One copy of each scene for the whole suite, and no other scene loaded while
## they are: the marker overlay collects turnouts from the whole tree, so a scene
## freed under another one's overlay leaves it holding freed widgets.
var _scenes: Dictionary[String, Node] = {}


func before_all() -> void:
	for path: String in SCENES:
		_scenes[path] = await load_scene(path)


func _mesher(path: String) -> TrackMesher:
	for node in _scenes[path].get_children():
		if node is TrackMesher:
			return node as TrackMesher
	return null


func test_every_scene_builds_its_track_as_it_loads() -> void:
	for path: String in SCENES:
		var mesher := _mesher(path)
		if not assert_not_null(mesher, "%s has a TrackMesher" % path.get_file()):
			continue
		assert_not_null(mesher.layout, "%s has been built" % path.get_file())
		assert_false(mesher.chunks().is_empty(), "%s has track meshes" % path.get_file())
		note("%-24s %d rails, %d chunks, %d sleepers, built in %.0f ms" % [path.get_file(),
				mesher.layout.rails.size(), mesher.chunks().size(), mesher.layout.sleepers.size(),
				mesher.last_build_msec])
		# Generous: it is ~200 ms on the largest level here. A regression to
		# seconds would make loading, the tests and the editor all crawl.
		assert_less(mesher.last_build_msec, 2000.0, "%s builds in under two seconds"
				% path.get_file())


## The plan asks for big chunks, not one mesh per rail or per sleeper, but still
## small enough for the camera to cull: every chunk is one mesh of at most three
## surfaces, and none sprawls far beyond its cell.
func test_the_track_is_cut_into_square_chunks() -> void:
	var mesher := _mesher("res://scenes/levels/desert.tscn")
	var chunks := mesher.chunks()
	assert_greater(float(chunks.size()), 4.0, "a large level is cut into many chunks")
	var widest := 0.0
	for cell in chunks:
		var mesh := chunks[cell].mesh as ArrayMesh
		assert_between(float(mesh.get_surface_count()), 1.0, 3.0,
				"chunk %s is one mesh with a surface per material" % cell)
		var box := mesh.get_aabb()
		widest = maxf(widest, maxf(box.size.x, box.size.z))
	note("%d chunks, the widest %.0f m across" % [chunks.size(), widest])
	assert_less(widest, TrackMeshBuilder.CHUNK_SIZE * 2.5,
			"no chunk spreads much past its own %.0f m cell" % TrackMeshBuilder.CHUNK_SIZE)


## Wherever a running rail is drawn, no other track's rail stands in its
## flangeway - within a railhead and a flangeway of it on the gauge side, where
## its wheels' flanges run - except where one rail carries straight on into
## another's at the points, which is a joint, not a clash. On the field side
## rails may meet: that is a frog's nose. That one rule is the frog gaps, the
## wing rails, the diamond gaps, the blades being cut out of the static track
## and everything a double slip packs into its middle.
func test_no_two_tracks_rails_come_within_a_flangeway_of_each_other() -> void:
	var clearance := TrackLayout.HEAD_WIDTH + TrackLayout.FLANGEWAY - 0.005
	for path: String in SCENES:
		var layout := _mesher(path).layout
		var samples := _piece_samples(layout)
		var points: PackedVector3Array = samples[0]
		var owners: PackedInt32Array = samples[1]
		var alongs: PackedFloat64Array = samples[2]
		var grid := {}
		for i in points.size():
			var cell := Vector2i(floori(points[i].x), floori(points[i].z))
			if not grid.has(cell):
				grid[cell] = PackedInt32Array()
			grid[cell].append(i)
		var clashes := 0
		var worst := INF
		var where := ""
		for i in points.size():
			var home := Vector2i(floori(points[i].x), floori(points[i].z))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for j: int in grid.get(home + Vector2i(dx, dz), PackedInt32Array()):
						if j <= i:
							continue
						var a := layout.pieces[owners[i]]
						var b := layout.pieces[owners[j]]
						if a.rail == b.rail or _continues(a, b) or _continues(b, a):
							continue
						var gap := points[i].distance_to(points[j])
						if gap >= clearance or _at_a_joint(a, b, points[i]):
							continue
						if not (_in_flangeway(points[i], b, alongs[j])
								or _in_flangeway(points[j], a, alongs[i])):
							continue
						clashes += 1
						if gap < worst:
							worst = gap
							where = "%s%s %+.2f @ %.2f m and %s%s %+.2f @ %.2f m" % [
									a.rail.name, " check" if a.is_check else "", a.lateral, alongs[i],
									b.rail.name, " check" if b.is_check else "", b.lateral, alongs[j]]
		note("%-24s %d samples of rail, closest clash: %s" % [path.get_file(), points.size(),
				"none" if clashes == 0 else "%.3f m, %s" % [worst, where]])
		assert_eq(clashes, 0, "%s: rails of different tracks keep a flangeway apart"
				% path.get_file())


## Every piece of running or check rail, sampled every 20 cm: (positions, index
## of the piece each came from, distance along its rail).
func _piece_samples(layout: TrackLayout) -> Array:
	var points := PackedVector3Array()
	var owners := PackedInt32Array()
	var alongs := PackedFloat64Array()
	for index in layout.pieces.size():
		var piece := layout.pieces[index]
		var at := piece.from
		while at <= piece.to:
			var frame := TrackLayout.frame_at(piece.rail, at)
			var lateral := piece.lateral - signf(piece.lateral) * TrackMeshBuilder._flare_at(piece, at)
			points.append(frame.origin + frame.basis.x * lateral)
			owners.append(index)
			alongs.append(at)
			at += 0.2
	return [points, owners, alongs]


## Whether [param wing] is a wing rail bent off [param piece]'s own line.
func _continues(wing: TrackLayout.Piece, piece: TrackLayout.Piece) -> bool:
	return (wing.wing_of != null and wing.wing_of.rail == piece.rail
			and is_equal_approx(wing.wing_of.lateral, piece.lateral))


## Whether [param point] lies on the gauge side of [param piece] at [param at],
## where its wheels' flanges run. A check or wing rail carries no wheels, so has
## no flangeway of its own.
func _in_flangeway(point: Vector3, piece: TrackLayout.Piece, at: float) -> bool:
	if piece.is_check:
		return false
	var frame := TrackLayout.frame_at(piece.rail, at)
	var gauge_side := frame.basis.x * -signf(piece.lateral)
	return (point - (frame.origin + frame.basis.x * piece.lateral)).dot(gauge_side) > 0.005


## Where one rail's line runs on into another's: two pieces that both end at
## [param point], on the same side and heading the same way - a stock rail
## passing from the main rail onto the branch at the points.
func _at_a_joint(a: TrackLayout.Piece, b: TrackLayout.Piece, point: Vector3) -> bool:
	for a_end: float in [a.from, a.to]:
		for b_end: float in [b.from, b.to]:
			var pa := TrackLayout.frame_at(a.rail, a_end)
			var pb := TrackLayout.frame_at(b.rail, b_end)
			var end_a := pa.origin + pa.basis.x * a.lateral
			var end_b := pb.origin + pb.basis.x * b.lateral
			if end_a.distance_to(end_b) < 0.02 and point.distance_to(end_a) < 0.6:
				return true
	return false


## Every turnout gets two blades - the straight one on the main rail, the curved
## one on the branch - running from the points to a heel, and a frog where the
## curved blade's line crosses the main rail's.
func test_every_turnout_has_two_blades_and_a_frog() -> void:
	for path: String in SCENES:
		var layout := _mesher(path).layout
		for turnout in layout.turnouts:
			var own: Array[TrackLayout.Blade] = []
			for blade in layout.blades:
				if blade.turnout == turnout:
					own.append(blade)
			if not assert_eq(own.size(), 2, "%s has two blades" % turnout.name):
				continue
			assert_eq(own[0].line.rail, turnout.main_rail, "the straight blade is on the main rail")
			assert_eq(own[1].line.rail, turnout.branch_rail, "the curved blade is on the branch")
			assert_between(own[0].heel, TrackLayout.MIN_HEEL, TrackLayout.MAX_HEEL,
					"%s's blades end at a heel" % turnout.name)
			var frog := false
			for gap in layout.gaps:
				if gap.line == own[1].line and gap.other.rail == turnout.main_rail:
					frog = true
			assert_true(frog, "%s's curved blade line is cut where it crosses the main rail"
					% turnout.name)


## A plain diamond: two lines each crossed by two, so eight cuts, all at the
## crossing's own angle.
func test_a_diamond_is_cut_at_all_four_corners() -> void:
	var path := "res://scenes/demos/compound_turnouts.tscn"
	var layout := _mesher(path).layout
	var diamond := _scenes[path].get_node("Crossings/Diamond") as Crossing
	var cuts := 0
	for gap in layout.gaps:
		if ((gap.line.rail == diamond.rail_a and gap.other.rail == diamond.rail_b)
				or (gap.line.rail == diamond.rail_b and gap.other.rail == diamond.rail_a)):
			cuts += 1
			assert_near(gap.angle_degrees, diamond.crossing_angle_degrees(), 1.0,
					"each corner is cut at the crossing's angle")
	note("diamond at %.1f deg: %d cuts" % [diamond.crossing_angle_degrees(), cuts])
	assert_eq(cuts, 8, "both rails of each track are cut where both rails of the other cross")


## The blades swing across when the points are thrown - in the time
## [member TrackMesher.blade_throw_time] says, not at once - and, lying closed,
## sit a railhead's width inside their stock rail.
func test_the_blades_follow_the_points() -> void:
	var scene := _scenes["res://scenes/demos/turnouts.tscn"]
	var mesher: TrackMesher = scene.get_node("Track")
	var turnout: Turnout = scene.get_node("Turnouts/LoopWest")
	assert_not_null(mesher.blade_instance(turnout), "the turnout has a blade mesh")
	assert_eq(mesher.blade_instance(turnout).mesh.get_blend_shape_count(), 1,
			"its second position is a blend shape")
	var start := mesher.blade_weight(turnout)
	# Stepped by hand: the blades swing on the idle frame, whose delta the sped-up
	# test clock stretches far past a whole throw.
	mesher.set_process(false)
	turnout.throw_points()
	mesher._swing_blades(mesher.blade_throw_time * 0.25)
	var moving := mesher.blade_weight(turnout)
	mesher._swing_blades(mesher.blade_throw_time)
	var after := mesher.blade_weight(turnout)
	note("blade weight %.2f -> %.2f a quarter of the way through the throw -> %.2f"
			% [start, moving, after])
	assert_near(start, 0.0, 1e-3, "normal: the blades lie at weight 0")
	assert_near(moving, 0.25, 0.01, "they swing across rather than jumping")
	assert_near(after, 1.0, 1e-3, "reverse: they have swung over to weight 1")
	assert_eq(mesher.blade_instance(turnout).get_blend_shape_value(0), 1.0,
			"and the mesh shows it")

	for blade in mesher.layout.blades:
		if blade.turnout != turnout:
			continue
		var stock := TrackLayout.line_point(blade.stock, blade.stock_start)
		var closed := TrackLayout.blade_point(blade, 0.0, true).distance_to(stock)
		var open := TrackLayout.blade_point(blade, 0.0, false).distance_to(stock)
		assert_near(closed, TrackLayout.HEAD_WIDTH, 0.01, "a closed blade's tip lies against its stock rail")
		assert_greater(open - closed, 0.08, "an open one stands off it, room for a flange")


## Sleepers of two tracks never lie across each other. Where tracks share their
## timbers, the higher-ranked one lays them long and the other lays none.
func test_sleepers_never_cross_and_turnouts_have_long_timbers() -> void:
	for path: String in SCENES:
		var layout := _mesher(path).layout
		var crossings := 0
		var grid := {}
		for sleeper in layout.sleepers:
			var cell := Vector2i(floori(sleeper.frame.origin.x / 8.0), floori(sleeper.frame.origin.z / 8.0))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for other: TrackLayout.Sleeper in grid.get(cell + Vector2i(dx, dz), []):
						if other.rail != sleeper.rail and _sleepers_cross(sleeper, other):
							crossings += 1
			if not grid.has(cell):
				grid[cell] = []
			grid[cell].append(sleeper)
		assert_eq(crossings, 0, "%s: no two tracks' sleepers cross" % path.get_file())

		# Whichever track ranks higher lays them - usually the main rail, but in a
		# double slip it can be the other track through the diamond.
		for turnout in layout.turnouts:
			var long_ones := 0
			var points := turnout.points_position()
			for sleeper in layout.sleepers:
				if sleeper.frame.origin.distance_to(points) < 12.0 \
						and sleeper.hi - sleeper.lo > TrackLayout.SLEEPER_LENGTH + 0.3:
					long_ones += 1
			assert_greater(float(long_ones), 2.0,
					"%s: long timbers carry both routes beyond the points" % turnout.name)


static func _sleepers_cross(a: TrackLayout.Sleeper, b: TrackLayout.Sleeper) -> bool:
	var footprint := func(s: TrackLayout.Sleeper) -> Array:
		var across := Vector3(s.frame.basis.x.x, 0.0, s.frame.basis.x.z).normalized()
		var centre := s.frame.origin + across * ((s.lo + s.hi) * 0.5)
		return [Vector2(centre.x, centre.z), Vector2(across.x, across.z), (s.hi - s.lo) * 0.5]
	return TrackLayout._footprints_cross(footprint.call(a), footprint.call(b))


## A rail end with nothing welded to it is a dead end, and gets a buffer stop;
## one inside a tunnel is a way off the level, and does not.
func test_dead_ends_get_buffer_stops_unless_a_tunnel_swallows_them() -> void:
	var turnouts := _mesher("res://scenes/demos/turnouts.tscn").layout
	var ends := 0
	for rail in turnouts.rails:
		for end: float in [0.0, rail.rail_length()]:
			if not turnouts._is_welded(rail, end):
				ends += 1
	note("turnout demo: %d dead ends, %d buffer stops" % [ends, turnouts.buffer_stops.size()])
	assert_greater(float(ends), 0.0, "the turnout demo has dead ends")
	assert_eq(turnouts.buffer_stops.size(), ends, "every one of them has a buffer stop")
	for stop in turnouts.buffer_stops:
		var end := stop.rail.sample_position(stop.distance)
		assert_near(stop.frame.origin.distance_to(end), TrackLayout.BUFFER_FACE, 0.01,
				"the stop's face is just past the end of %s" % stop.rail.name)
		var outward := -stop.frame.basis.z
		var inward := stop.rail.sample_position(stop.rail.clamp_distance(
				stop.distance + (5.0 if stop.distance == 0.0 else -5.0))) - end
		assert_less(outward.dot(inward.normalized()), -0.9, "and it faces back down the track")

	var desert := _mesher("res://scenes/levels/desert.tscn")
	note("desert: %d buffer stops, every exit in a tunnel" % desert.layout.buffer_stops.size())
	assert_eq(desert.layout.buffer_stops.size(), 0, "the desert's dead ends are all in tunnels")


## The bed meets the ground: its toes lie on the terrain either side wherever the
## track is on ordinary ground, so no sleeper end hangs over a dip.
func test_the_ballast_runs_down_to_the_ground() -> void:
	var path := "res://scenes/main.tscn"
	var mesher := _mesher(path)
	var surfaces := mesher.layout.rails[0].ground_surfaces()
	var builder := TrackMeshBuilder.new()
	builder.ground_height = func(point: Vector3) -> Variant:
		return SurfaceSnapper.height_at(surfaces, point.x, point.z)
	var worst := 0.0
	var checked := 0
	for rail in mesher.layout.rails:
		var at := 5.0
		while at < rail.rail_length() - 5.0:
			var covered := false
			for structure in mesher.structures():
				if structure.covers(rail, at):
					covered = true
			if not covered:
				var frame := TrackLayout.frame_at(rail, at)
				var top := frame.origin - frame.basis.y * (TrackLayout.RAIL_HEIGHT
						+ TrackLayout.SLEEPER_HEIGHT * 0.6)
				var flat := Vector3(frame.basis.x.x, 0.0, frame.basis.x.z).normalized()
				for side: float in [-1.0, 1.0]:
					var shoulder := top + frame.basis.x * 1.6 * side
					var toe := builder._toe(top, shoulder, flat * side, TrackMeshBuilder.Ballast.BED)
					var ground = SurfaceSnapper.height_at(surfaces, toe.x, toe.z)
					if ground != null:
						worst = maxf(worst, toe.y - float(ground))
						checked += 1
			at += 25.0
	note("%d toes checked, the highest %.2f m over the ground" % [checked, worst])
	assert_greater(float(checked), 50.0, "toes checked all over the playground")
	assert_less(worst, 0.05, "no toe of the bed stands above the ground")


## The ground never shows through the track: wherever a rail runs on the ground,
## the ground across its bed lies at or under the bed, 0.25 m below the
## railhead - however the terrain between two snapped curve points bulges, and
## however coarse the grid is (the desert's 3 m cells). The track cuts its bed
## into the mesh for that; the terrain as authored, which rails snap to, is left
## as it was.
func test_the_ground_never_rises_into_the_track() -> void:
	for path: String in SCENES:
		var mesher := _mesher(path)
		var surfaces := mesher.layout.rails[0].ground_surfaces()
		var worst := -INF
		var where := ""
		var checked := 0
		var cut := 0
		for rail in mesher.layout.rails:
			var at := 0.0
			while at <= rail.rail_length():
				var covered := false
				for structure in mesher.structures():
					if structure is Tunnel and structure.covers(rail, at):
						covered = true
				if not covered:
					var frame := TrackLayout.frame_at(rail, at)
					var bed := frame.origin.y - rail.surface_offset
					for across: float in [-1.6, -0.8, 0.0, 0.8, 1.6]:
						var point := frame.origin + frame.basis.x * across
						var ground = SurfaceSnapper.height_at(surfaces, point.x, point.z)
						var terrain = SurfaceSnapper.height_at(surfaces, point.x, point.z, true)
						if ground == null:
							continue
						checked += 1
						if float(terrain) > float(ground) + 1e-3:
							cut += 1
						if float(ground) - bed > worst:
							worst = float(ground) - bed
							where = "%s @ %.1f m, %.1f m across" % [rail.name, at, across]
				at += 1.0
		note("%s: %d points, %d of them cut down; ground at most %.3f m over the bed (%s)"
				% [path.get_file(), checked, cut, worst, where])
		assert_less(worst, 0.02, "%s: the ground never rises above the bed" % path.get_file())


## Steel and timber bridges carry no ballast, so they carry a deck instead: under
## the rails, between the sleepers, there is a plate or planking right under the
## sleepers - never a drop to the gully.
func test_an_open_bridge_has_a_deck_under_its_rails() -> void:
	var demo: Node = await load_scene("res://scenes/demos/structures.tscn")
	var sleeper_bottom := TrackLayout.RAIL_HEIGHT + TrackLayout.SLEEPER_HEIGHT
	for node in demo.get_node("Structures").get_children():
		var bridge := node as Bridge
		if bridge == null or bridge.style == Bridge.Style.STONE_ARCH:
			continue
		var faces := bridge.mesh_instance().mesh.get_faces()
		var to_global := bridge.mesh_instance().global_transform
		var triangles := PackedVector3Array()
		for face in faces:
			triangles.append(to_global * face)
		var deepest := 0.0
		var at := bridge.start_distance() + 0.5
		while at < bridge.end_distance() - 0.5:
			var frame := TrackLayout.frame_at(bridge.rail, at)
			for across: float in [-0.75, 0.0, 0.75]:
				var from := frame.origin + frame.basis.x * across + Vector3.DOWN * (sleeper_bottom - 0.05)
				var nearest := INF
				for i in range(0, triangles.size(), 3):
					var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN,
							triangles[i], triangles[i + 1], triangles[i + 2])
					if hit != null:
						nearest = minf(nearest, from.y - (hit as Vector3).y)
				deepest = maxf(deepest, nearest)
			at += 1.3
		note("%s: the deck is at most %.2f m under the sleepers' undersides"
				% [bridge.name, deepest - 0.05])
		assert_less(deepest, 0.1, "%s: a deck right under the sleepers all the way across"
				% bridge.name)
	demo.queue_free()


## Only rails and timbers count as track; the structures a level has tell it how
## the bed crosses them - over a stone bridge it is held between the parapets,
## over steel and timber there is none.
func test_bridges_say_how_the_ballast_crosses_them() -> void:
	for style: Bridge.Style in [Bridge.Style.STONE_ARCH, Bridge.Style.STEEL_TRUSS,
			Bridge.Style.WOODEN_TRESTLE]:
		var bridge := Bridge.new()
		bridge.style = style
		var expected := (TrackMeshBuilder.Ballast.DECK if style == Bridge.Style.STONE_ARCH
				else TrackMeshBuilder.Ballast.NONE)
		assert_eq(bridge.ballast_mode(), expected, "%s: %s" % [Bridge.Style.keys()[style],
				TrackMeshBuilder.Ballast.keys()[expected]])
		bridge.free()


## What a rebuild depends on: moving a rail changes it, throwing points does not
## - the blades swing for that - and so does moving a structure.
func test_the_signature_follows_the_rails_and_not_the_points() -> void:
	# The suite's own copy, and the last test to use it: this one bends a rail.
	var scene := _scenes["res://scenes/demos/turnouts.tscn"]
	var mesher: TrackMesher = scene.get_node("Track")
	var rail: Rail = scene.get_node("Rails/StubLine")
	var turnout: Turnout = scene.get_node("Turnouts/StubPoints")
	var before := mesher.signature()
	turnout.throw_points()
	assert_eq(mesher.signature(), before, "throwing the points changes nothing to rebuild")
	var last := rail.curve.point_count - 1
	rail.curve.set_point_position(last, rail.curve.get_point_position(last) + Vector3(0.0, 0.0, 3.0))
	var moved := mesher.signature()
	assert_ne(moved, before, "moving a curve point does")
	var sleepers_before := mesher.layout.sleepers.size()
	mesher.rebuild()
	note("sleepers %d -> %d after moving the stub's end" % [sleepers_before,
			mesher.layout.sleepers.size()])
	assert_eq(mesher.signature(), moved, "a rebuild catches up with it")
