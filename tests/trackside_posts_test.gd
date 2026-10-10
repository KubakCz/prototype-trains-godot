extends TestCase
## Signal masts and turnout marker posts on hilly ground: upright, and reaching it.
##
## A signal's mast and a turnout's marker post used to be built in their node's own
## frame, and that frame is the rail's: it pitches with the gradient, banks with the
## curve's tilt, and has its origin on the railhead. So on a slope the posts leaned,
## and since the ground a couple of metres to the side of the track is not the ground
## under it, they also floated clear of it or sank into it. They are built in
## [method Rail.ground_frame] now - upright, on the ground.
##
## Every level in the repo lies on a carved bed now, where the ground beside the
## track is the bed itself and every post stands on the same height. So the fixture
## is built here: the analytic hills of [Ground], a rail snapped across them, a branch
## off it, and signals along both.

var _posts: Array[Node3D] = []


func before_all() -> void:
	var hills := Node3D.new()
	hills.name = "Hills"
	var ground := Ground.new()
	ground.hill_height = 2.2
	hills.add_child(ground)

	var main := _rail("MainLine", ground, [Vector3(-100.0, 0.0, -20.0), Vector3(100.0, 0.0, -20.0)],
			20)
	var branch := _rail("BranchLine", ground, [Vector3(0.0, 0.0, -20.0), Vector3(40.0, 0.0, -10.0),
			Vector3(90.0, 0.0, 15.0)], 6)
	hills.add_child(main)
	hills.add_child(branch)

	var turnout := Turnout.new()
	turnout.name = "Junction"
	turnout.main_rail = main
	turnout.main_distance = 100.0
	turnout.diverge_towards = Turnout.DivergeTowards.RAIL_END
	turnout.branch_rail = branch
	turnout.branch_end = Turnout.RailEnd.START
	hills.add_child(turnout)
	_posts.append(turnout)

	var placements: Array[Array] = [[main, 20.0], [main, 55.0], [main, 80.0], [main, 130.0],
			[main, 165.0], [main, 190.0], [branch, 40.0], [branch, 75.0]]
	for i in placements.size():
		var rail_signal := RailSignal.new()
		rail_signal.name = "Signal%d" % i
		rail_signal.rail = placements[i][0]
		rail_signal.distance = placements[i][1]
		rail_signal.governs = (RailSignal.Governs.TOWARDS_RAIL_END if i % 2 == 0
				else RailSignal.Governs.TOWARDS_RAIL_START)
		hills.add_child(rail_signal)
		_posts.append(rail_signal)

	tree.root.add_child(own(hills))
	await physics_frames(2)


func test_every_post_beside_the_track_stands_upright_on_the_ground() -> void:
	for node: Node3D in _posts:
		var rail := _rail_of(node)
		var post := _post_of(node)
		if not assert_not_null(post, "%s has a post" % node.name):
			continue
		var height := (post.mesh as BoxMesh).size.y
		var foot := post.global_position - post.global_basis.y * (height * 0.5)
		var ground = rail.ground_height_at(foot)
		if not assert_not_null(ground, "%s stands over the terrain" % node.name):
			continue
		var lean := rad_to_deg(post.global_basis.y.angle_to(Vector3.UP))
		note("%-9s post %.2f m tall, foot %+.3f m from the ground, leaning %.2f deg"
				% [node.name, height, foot.y - float(ground), lean])
		assert_less(lean, 0.01, "%s stands upright" % node.name)
		assert_near(foot.y, float(ground), 0.01, "%s reaches the ground" % node.name)


## If every one of the posts happened to stand on level ground the test above would
## pass on a fixture that could not show the bug.
func test_the_terrain_under_the_posts_is_uneven_enough_to_be_worth_testing() -> void:
	var lowest := INF
	var highest := -INF
	for node: Node3D in _posts:
		var lift := 0.0
		if node is RailSignal:
			lift = (node as RailSignal).mast_lift()
		else:
			lift = (node as Turnout).marker_lift()
		lowest = minf(lowest, lift)
		highest = maxf(highest, lift)
	note("railhead stands %.2f - %.2f m above the ground at the posts" % [lowest, highest])
	assert_greater(highest - lowest, 0.1,
			"the posts stand on ground of visibly different heights")


## A rail through [param through], one curve point every [param segments]-th of the
## way between each pair - fine enough for snapping to follow the hills - and handles
## a third of the way to the neighbours, so it bends smoothly through them.
func _rail(rail_name: String, ground: Ground, through: Array[Vector3], segments: int) -> Rail:
	var points: Array[Vector3] = []
	for i in through.size() - 1:
		for step in segments:
			points.append(through[i].lerp(through[i + 1], float(step) / float(segments)))
	points.append(through[-1])
	var curve := Curve3D.new()
	for i in points.size():
		var before := points[maxi(i - 1, 0)]
		var after := points[mini(i + 1, points.size() - 1)]
		var handle := (after - before) / 6.0
		curve.add_point(points[i], -handle if i > 0 else Vector3.ZERO,
				handle if i < points.size() - 1 else Vector3.ZERO)
	var rail := Rail.new()
	rail.name = rail_name
	rail.curve = curve
	rail.surface_root = ground
	return rail


func _rail_of(node: Node3D) -> Rail:
	if node is RailSignal:
		return (node as RailSignal).rail
	return (node as Turnout).main_rail


## The post out of the generated model. Internal children, hence the `true`:
## these nodes are built at runtime and never saved into the scene.
func _post_of(node: Node3D) -> MeshInstance3D:
	for child: Node in node.get_children(true):
		if child.name != "Mast" and child.name != "Marker":
			continue
		for part: Node in child.get_children(true):
			if part is MeshInstance3D and part.name == "Post":
				return part as MeshInstance3D
	return null
