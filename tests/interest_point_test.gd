extends StationsDemoCase
## Interest points: the poles each one stands over its tracks, the badge on top of them
## on the floating marker layer, the colours they are given, their names, and the
## warnings a level author gets for a point put together wrongly.

var _overlay: MarkerOverlay


func before_each() -> void:
	await super.before_each()
	_overlay = demo.get_node("DebugUi/MarkerOverlay")


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


## Every node under [param node], internal children included.
static func _everything_under(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children(true):
		found.append(child)
		found.append_array(_everything_under(child))
	return found


func _badge(point: InterestPoint) -> InterestPointWidget:
	return _overlay.widget_for(point) as InterestPointWidget


func test_a_station_is_a_circle_and_a_connection_a_square() -> void:
	assert_false(central.is_square(), "a station is not square")
	assert_true(west_gate.is_square(), "a connection is")


func test_the_poles_meet_over_the_middle_of_the_tracks_with_one_down_to_each() -> void:
	var middle := Vector3.ZERO
	for track in central.tracks():
		middle += track.position()
	middle /= float(central.tracks().size())
	note("anchor %s, middle of the marks %s, marker %s" % [central.anchor(), middle,
			central.marker_position()])
	assert_true(central.anchor().is_equal_approx(middle), "the anchor is the middle of the three marks")
	assert_near(central.marker_position().y - middle.y, InterestPoint.MARKER_HEIGHT, 0.01,
			"the top of the poles is %.0f m up" % InterestPoint.MARKER_HEIGHT)
	assert_near(Vector2(central.marker_position().x, central.marker_position().z).distance_to(
			Vector2(middle.x, middle.z)), 0.0, 0.01, "straight over the middle")
	var poles := central.get_node("Marker/Poles") as MeshInstance3D
	if not assert_not_null(poles, "the poles are there"):
		return
	var mesh := poles.mesh as ImmediateMesh
	assert_eq(mesh.get_surface_count(), 1, "the poles are drawn")
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), 2 * central.tracks().size(),
			"one pole down to each of the three tracks")


func test_the_point_draws_no_shape_or_name_of_its_own_in_3d() -> void:
	for point in _points():
		var meshes: Array[String] = []
		for node in _everything_under(point):
			assert_false(node is Label3D, "%s has no 3D label (%s)" % [point.label(), node.name])
			assert_false(node is Sprite3D, "%s has no 3D sprite (%s)" % [point.label(), node.name])
			if node is MeshInstance3D:
				meshes.append(str(node.name))
		note("%s: meshes %s" % [point.label(), meshes])
		for mesh_name in meshes:
			assert_true(mesh_name in ["Poles", "Walls", "Roof"] or mesh_name.begins_with("PlatformPiece"),
					"%s's only meshes are its poles, its building and its platforms, not %s" % [
					point.label(), mesh_name])


func test_names_are_one_short_word() -> void:
	for point in _points():
		var label := point.label()
		assert_false(label.contains(" "), "%s is one word" % label)
		assert_less(float(label.length()), 10.5, "%s is short" % label)
	assert_eq(central.label(), "Central", "Central is called Central")
	assert_eq(west_gate.label(), "West", "and the west gate West")
	var plain := Station.new()
	plain.name = "Platform"
	assert_eq(plain.label(), "Platform", "a point without one uses its node's name")
	plain.free()


func test_every_point_gets_a_colour_of_its_own() -> void:
	await frames(2)
	var points := _points()
	assert_eq(points.size(), 6, "the demo has six points")
	var least := 1.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			least = minf(least, _hue_gap(points[i].color().h, points[j].color().h))
	var even := 1.0 / float(points.size())
	note("the two closest hues are %.3f of a turn apart (an even spread is %.3f)" % [least, even])
	assert_greater(least, even - 0.01, "no two are closer than an even spread of six")
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
	var badge := _badge(central)
	if assert_not_null(badge, "Central has a badge"):
		assert_eq(badge.accent_color(), central.color(), "and its badge is drawn in it")
	var others: Array[InterestPoint] = []
	for point in _points():
		if point != central:
			others.append(point)
	var least := 1.0
	for i in others.size():
		for j in range(i + 1, others.size()):
			least = minf(least, _hue_gap(others[i].color().h, others[j].color().h))
	assert_greater(least, 0.19, "the other five are spread over the wheel as five, not six")


#region The badge
func test_every_point_has_one_badge_on_the_marker_layer() -> void:
	await frames(3)
	var badges := 0
	for widget in _overlay.widgets():
		if widget is InterestPointWidget:
			badges += 1
	assert_eq(badges, _points().size(), "one badge per interest point")
	for point in _points():
		var badge := _badge(point)
		if not assert_not_null(badge, "%s has a badge" % point.label()):
			continue
		assert_eq(badge.point, point, "%s's badge is its own" % point.label())
		assert_eq(badge.accent_color(), point.color(), "%s's badge is in its colour" % point.label())


func test_the_badge_sits_on_top_of_the_poles() -> void:
	await frames(3)
	var camera: Camera3D = demo.get_node("CameraRig/Camera3D")
	var badge := _badge(central)
	if not assert_not_null(badge, "Central has a badge"):
		return
	var top := camera.unproject_position(central.marker_position())
	assert_true(badge.anchor_screen.is_equal_approx(top), "its anchor is the top of the poles on screen")
	var wanted := badge.desired_rect(_overlay.size)
	note("anchor %s, wanted %s" % [top, wanted])
	assert_near(wanted.get_center().distance_to(top), 0.0, 0.5, "and it is centred on it")


func test_the_name_is_inside_the_badge() -> void:
	await frames(3)
	var badge := _badge(central)
	if not assert_not_null(badge, "Central has a badge"):
		return
	var with_name := badge.expanded_size()
	note("Central's badge with its name: %s" % with_name)
	assert_eq(with_name.y, InterestPointWidget.HEIGHT, "the badge is %.0f px tall" % InterestPointWidget.HEIGHT)
	assert_greater(with_name.x, InterestPointWidget.HEIGHT, "and wider than tall, to hold the name")
	assert_eq(badge.size, with_name, "it is laid out at that size")
	central.display_name = "Centralissimo"
	var longer := badge.expanded_size()
	assert_greater(longer.x, with_name.x, "a longer name makes a wider badge")
	assert_eq(longer.y, with_name.y, "but not a taller one")
	await frames(2)
	assert_eq(badge.size, longer, "and the badge follows the rename")


func test_without_names_a_badge_is_a_bare_circle_or_square() -> void:
	InterestPoint.show_names = false
	await frames(3)
	for point in _points():
		var badge := _badge(point)
		if not assert_not_null(badge, "%s has a badge" % point.label()):
			continue
		var square := Vector2(InterestPointWidget.HEIGHT, InterestPointWidget.HEIGHT)
		assert_eq(badge.expanded_size(), square, "%s's badge is as wide as it is tall" % point.label())
		assert_eq(badge.size, square, "and laid out so")
	InterestPoint.show_names = true
	await frames(2)
	assert_greater(_badge(central).size.x, InterestPointWidget.HEIGHT, "with the names back it widens again")


func test_a_badge_never_collapses() -> void:
	# The demo's camera is ~400 m out: far past the distance at which signals collapse.
	for rule: MarkerOverlay.Collapse in [MarkerOverlay.Collapse.WHEN_FAR,
			MarkerOverlay.Collapse.WITH_DISTANCE, MarkerOverlay.Collapse.WHEN_CROWDED]:
		_overlay.collapse_rule = rule
		_overlay.collapse_distance = 10.0
		await frames(3)
		var signals_collapsed := 0
		for widget in _overlay.widgets():
			if widget is SignalWidget and widget.collapsed:
				signals_collapsed += 1
		note("%s: %d signal widgets collapsed" % [_overlay.collapse_label(), signals_collapsed])
		for point in _points():
			var badge := _badge(point)
			if not assert_not_null(badge, "%s has a badge" % point.label()):
				continue
			assert_false(badge.collapsible(), "%s's badge is not collapsible" % point.label())
			assert_false(badge.collapsed, "under %s, %s's badge %.0f m away is open" % [
					_overlay.collapse_label(), point.label(), badge.camera_distance])
			assert_eq(badge.scale, Vector2.ONE, "and full size")
	_overlay.collapse_rule = MarkerOverlay.Collapse.WHEN_FAR
	await frames(3)
	var signal_widget := _overlay.widget_for(signal_named("CentralWestEntryNorth"))
	if assert_not_null(signal_widget, "a signal has a widget"):
		assert_true(signal_widget.collapsed, "while a signal widget as far away is collapsed")


func test_a_badge_lets_clicks_through_to_the_world() -> void:
	await frames(3)
	for point in _points():
		var badge := _badge(point)
		if assert_not_null(badge, "%s has a badge" % point.label()):
			assert_eq(badge.mouse_filter, Control.MOUSE_FILTER_IGNORE,
					"%s's badge ignores the mouse" % point.label())
#endregion


#region Configuration
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
	track.rail = north_main
	track.distance = north_main.rail_length()
	gate.add_child(track)
	demo.add_child(gate)
	assert_false(gate._get_configuration_warnings().is_empty(), "no room outside the mark warns")
	gate.free()


func test_a_connections_outside_is_the_nearer_end_of_the_rail() -> void:
	var track := west_gate.tracks()[0]
	assert_eq(OutsideConnection.outward(track), -1, "the west gate's outside is the start")
	assert_eq(OutsideConnection.outward(east_gate.tracks()[0]), 1, "the east gate's the end")
	assert_near(OutsideConnection.room_outside(track), track.distance, 0.001,
			"the room outside the west gate's mark runs to the rail's start")
	var pose := west_gate.spawn_pose(track, 48.0)
	assert_eq(pose["facing"], 1, "a train put on at the west gate faces east")
	assert_near(pose["distance"], track.distance - 24.0, 0.001,
			"with its nose on the mark and the rest of it outside")
	assert_false(west_gate.spawn_pose(track, OutsideConnection.room_outside(track) - 0.5).is_empty(),
			"a train that just fits outside the mark has a pose")
	assert_true(west_gate.spawn_pose(track, OutsideConnection.room_outside(track) + 0.5).is_empty(),
			"one longer than the room outside the mark does not")
	var east := east_gate.tracks()[0]
	var east_pose := east_gate.spawn_pose(east, 48.0)
	assert_eq(east_pose["facing"], -1, "a train put on at the east gate faces west")
	assert_near(east_pose["distance"], east.distance + 24.0, 0.001, "with its nose on that mark")


#endregion
