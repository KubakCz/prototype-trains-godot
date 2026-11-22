extends StationsDemoCase
## Interest points: the marker each one floats over its tracks, the colours they are
## given, the names beside them, and the warnings a level author gets for a point put
## together wrongly.


func after_each() -> void:
	InterestPoint.show_names = true


func _points() -> Array[InterestPoint]:
	var found: Array[InterestPoint] = []
	for node in tree.get_nodes_in_group(InterestPoint.GROUP):
		found.append(node as InterestPoint)
	return found


static func _hue_gap(a: float, b: float) -> float:
	var gap := absf(a - b)
	return minf(gap, 1.0 - gap)


func test_a_station_is_a_circle_and_a_connection_a_square() -> void:
	assert_false(central.is_square(), "a station is not square")
	assert_true(west_gate.is_square(), "a connection is")
	assert_true(central.marker_shape().mesh is SphereMesh, "so a station's marker is a sphere")
	assert_true(west_gate.marker_shape().mesh is BoxMesh, "and a connection's a box")


func test_the_marker_floats_over_the_middle_of_the_tracks_with_a_pole_down_to_each() -> void:
	var middle := central.anchor()
	note("anchor %s, marker %s" % [middle, central.marker_position()])
	assert_near(middle.x, 0.0, 0.01, "the middle of three tracks 5 m apart is the middle one, x")
	assert_near(middle.z, 0.0, 0.01, "and z")
	assert_near(central.marker_position().y - middle.y, InterestPoint.MARKER_HEIGHT, 0.01,
			"the marker is %.0f m up" % InterestPoint.MARKER_HEIGHT)
	var poles := central.get_node("Marker/Poles") as MeshInstance3D
	assert_eq((poles.mesh as ImmediateMesh).get_surface_count(), 1, "the poles are drawn")


func test_the_name_floats_beside_the_marker() -> void:
	assert_eq(central.name_label().text, "Central Station", "the display name")
	assert_eq(coal_mine.name_label().text, "Coal Mine", "of every point")
	var plain := Station.new()
	plain.name = "Platform"
	assert_eq(plain.label(), "Platform", "a point without one uses its node's name")
	plain.free()


func test_the_names_can_be_switched_off() -> void:
	InterestPoint.show_names = false
	await frames(2)
	for point in _points():
		assert_false(point.name_label().visible, "%s's name is hidden" % point.label())
	InterestPoint.show_names = true
	await frames(2)
	for point in _points():
		assert_true(point.name_label().visible, "%s's name is back" % point.label())


func test_every_point_gets_a_colour_of_its_own() -> void:
	await frames(2)
	var points := _points()
	assert_eq(points.size(), 5, "the demo has five points")
	var least := 1.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			least = minf(least, _hue_gap(points[i].color().h, points[j].color().h))
	note("the two closest hues are %.3f of a turn apart (an even spread is %.3f)" % [least, 0.2])
	assert_greater(least, 0.19, "no two are closer than an even spread of five")
	for point in points:
		assert_between(point.color().s, 0.5, 1.0, "%s's colour is saturated enough to tell" % point.label())


func test_hues_are_spread_as_far_as_their_number_allows() -> void:
	for count in range(1, 15):
		var hues := InterestPoint.auto_hues(count)
		assert_eq(hues.size(), count, "%d hues for %d points" % [count, count])
		var sorted := Array(hues)
		sorted.sort()
		var least := 1.0
		for i in count:
			least = minf(least, _hue_gap(sorted[i], sorted[(i + 1) % count]))
		if count > 1:
			assert_near(least, 1.0 / float(count), 1e-6, "%d hues are evenly spaced" % count)
		if count >= 3:
			for i in count - 1:
				assert_greater(_hue_gap(hues[i], hues[i + 1]), 0.19,
						"%d hues: listed neighbours are far apart" % count)


func test_a_colour_set_by_hand_is_kept_and_leaves_the_others_more_room() -> void:
	await frames(2)
	central.use_custom_color = true
	central.custom_color = Color(0.1, 0.6, 0.15)
	assert_eq(central.color(), Color(0.1, 0.6, 0.15), "the station keeps what it was given")
	await frames(2)
	assert_eq(central.marker_shape().material_override.albedo_color, central.color(),
			"and its marker is drawn in it")
	var others: Array[InterestPoint] = []
	for point in _points():
		if point != central:
			others.append(point)
	var least := 1.0
	for i in others.size():
		for j in range(i + 1, others.size()):
			least = minf(least, _hue_gap(others[i].color().h, others[j].color().h))
	assert_greater(least, 0.24, "the other four are spread over the wheel as four, not five")


func test_a_point_with_no_tracks_is_warned_about() -> void:
	var bare := Station.new()
	assert_false(bare._get_configuration_warnings().is_empty(), "a station with no tracks warns")
	var track := InterestTrack.new()
	assert_false(track._get_configuration_warnings().is_empty(), "a track with no rail, outside a point, warns")
	bare.free()
	track.free()


func test_the_demo_is_configured_without_warnings() -> void:
	var nodes: Array[Node] = [spawner]
	nodes.append_array(spawner.routes())
	for point in _points():
		nodes.append(point)
		nodes.append_array(point.tracks())
	for node in nodes:
		var warnings: PackedStringArray = node._get_configuration_warnings()
		if not warnings.is_empty():
			note("%s: %s" % [node.name, ", ".join(warnings)])
		assert_true(warnings.is_empty(), "%s: no configuration warnings" % node.name)


func test_a_route_that_does_not_end_by_leaving_is_warned_about() -> void:
	var route := TrainRoute.new()
	route.train_types = [express_type]
	route.entries = [west_gate]
	route.stops = [central]
	assert_false(route._get_configuration_warnings().is_empty(), "ending at a station warns")
	route.stops = [east_gate, central]
	assert_false(route._get_configuration_warnings().is_empty(), "leaving before the end warns")
	route.stops = [central, east_gate]
	assert_true(route._get_configuration_warnings().is_empty(), "stations then a gate is a route")
	route.entries = []
	assert_false(route._get_configuration_warnings().is_empty(), "no entry warns")
	route.free()


func test_a_connection_with_its_mark_on_the_end_of_the_rail_is_warned_about() -> void:
	var gate := OutsideConnection.new()
	var track := InterestTrack.new()
	track.rail = north_line
	track.distance = north_line.rail_length()
	gate.add_child(track)
	demo.add_child(gate)
	assert_false(gate._get_configuration_warnings().is_empty(), "no room outside the mark warns")
	gate.free()


func test_a_connections_outside_is_the_nearer_end_of_the_rail() -> void:
	assert_eq(OutsideConnection.outward(west_gate.tracks()[0]), -1, "the west gate's outside is the start")
	assert_eq(OutsideConnection.outward(east_gate.tracks()[0]), 1, "the east gate's the end")
	var pose := west_gate.spawn_pose(west_gate.tracks()[0], 48.0)
	assert_eq(pose["facing"], 1, "a train put on at the west gate faces east")
	assert_near(pose["distance"], 110.0 + 24.0 + OutsideConnection.SPAWN_INSET, 0.001,
			"with its tail just inside the mark")
	assert_true(west_gate.spawn_pose(west_gate.tracks()[0], 900.0).is_empty(),
			"a train longer than the rail does not fit")
